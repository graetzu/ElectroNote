import Foundation
import CoreGraphics
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class NoteSearchDatabase {
    static let shared = NoteSearchDatabase()

    private var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "de.graetz.electronote.searchdb", qos: .userInitiated)

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = appSupport.appendingPathComponent("ElectroNote", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.dbPath = folder.appendingPathComponent("search_index.sqlite").path

        openAndSetupDatabase()
    }

    deinit {
        queue.sync {
            if let db = db {
                sqlite3_close(db)
            }
        }
    }

    // MARK: - Setup

    private func openAndSetupDatabase() {
        queue.sync {
            if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
                print("[NoteSearchDatabase] Failed to open database at \(dbPath)")
                return
            }

            // Enable Write-Ahead-Logging for concurrency and performance
            execute(sql: "PRAGMA journal_mode = WAL;")
            execute(sql: "PRAGMA synchronous = NORMAL;")

            // Documents table
            let createDocsTable = """
            CREATE TABLE IF NOT EXISTS indexed_documents (
                doc_path TEXT PRIMARY KEY,
                doc_type TEXT NOT NULL,
                last_modified REAL NOT NULL,
                index_version INTEGER NOT NULL DEFAULT 1
            );
            """
            execute(sql: createDocsTable)

            // Chunk hashes for dirty tracking
            let createChunksTable = """
            CREATE TABLE IF NOT EXISTS chunk_hashes (
                doc_path TEXT NOT NULL,
                chunk_id TEXT NOT NULL,
                chunk_hash TEXT NOT NULL,
                PRIMARY KEY(doc_path, chunk_id)
            );
            """
            execute(sql: createChunksTable)

            // FTS5 Full Text Index
            let createFTS5Table = """
            CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
                doc_path UNINDEXED,
                doc_name,
                content_type UNINDEXED,
                text_content,
                canvas_x UNINDEXED,
                canvas_y UNINDEXED,
                canvas_w UNINDEXED,
                canvas_h UNINDEXED,
                page_idx UNINDEXED,
                chunk_id UNINDEXED,
                tokenize='unicode61 remove_diacritics 2'
            );
            """
            execute(sql: createFTS5Table)
        }
    }

    private func execute(sql: String) {
        guard let db = db else { return }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let err = errMsg {
                print("[NoteSearchDatabase] SQL exec error: \(String(cString: err)) in: \(sql)")
                sqlite3_free(errMsg)
            }
        }
    }

    // MARK: - Query Sanitization

    func sanitizeQuery(_ raw: String) -> String {
        let clean = raw.replacingOccurrences(of: "\"", with: "")
        let tokens = clean.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return "" }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }

    // MARK: - Search (Async)

    func search(query: String, inDocument docPath: String? = nil, limit: Int = 100) async -> [SearchResultItem] {
        await withCheckedContinuation { continuation in
            queue.async {
                let items = self.performSearchSync(query: query, inDocument: docPath, limit: limit)
                continuation.resume(returning: items)
            }
        }
    }

    private func performSearchSync(query: String, inDocument docPath: String?, limit: Int) -> [SearchResultItem] {
        guard let db = db else { return [] }
        let ftsQuery = sanitizeQuery(query)
        guard !ftsQuery.isEmpty else { return [] }

        var results: [SearchResultItem] = []
        let sql: String
        if let _ = docPath {
            sql = """
            SELECT doc_path, doc_name, content_type, text_content, canvas_x, canvas_y, canvas_w, canvas_h, page_idx,
                   snippet(search_index, 3, '«', '»', '…', 12) AS match_snippet
            FROM search_index
            WHERE search_index MATCH ? AND doc_path = ?
            ORDER BY rank
            LIMIT ?;
            """
        } else {
            sql = """
            SELECT doc_path, doc_name, content_type, text_content, canvas_x, canvas_y, canvas_w, canvas_h, page_idx,
                   snippet(search_index, 3, '«', '»', '…', 12) AS match_snippet
            FROM search_index
            WHERE search_index MATCH ?
            ORDER BY rank
            LIMIT ?;
            """
        }

        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, ftsQuery, -1, SQLITE_TRANSIENT)
            if let docPath = docPath {
                sqlite3_bind_text(stmt, 2, docPath, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 3, Int32(limit))
            } else {
                sqlite3_bind_int(stmt, 2, Int32(limit))
            }

            while sqlite3_step(stmt) == SQLITE_ROW {
                let path = String(cString: sqlite3_column_text(stmt, 0))
                let name = String(cString: sqlite3_column_text(stmt, 1))
                let rawType = String(cString: sqlite3_column_text(stmt, 2))
                let text = String(cString: sqlite3_column_text(stmt, 3))
                let x = sqlite3_column_double(stmt, 4)
                let y = sqlite3_column_double(stmt, 5)
                let w = sqlite3_column_double(stmt, 6)
                let h = sqlite3_column_double(stmt, 7)
                let pageIdx = Int(sqlite3_column_int(stmt, 8))
                let snippet = String(cString: sqlite3_column_text(stmt, 9))

                let contentType = SearchContentType(rawValue: rawType) ?? .handwriting
                let rect = CGRect(x: x, y: y, width: w, height: h)

                let item = SearchResultItem(
                    documentPath: path,
                    documentName: name,
                    contentType: contentType,
                    textContent: text,
                    canvasRect: rect,
                    pageIndex: pageIdx,
                    snippet: snippet
                )
                results.append(item)
            }
            sqlite3_finalize(stmt)
        } else {
            print("[NoteSearchDatabase] Search prepare error: \(String(cString: sqlite3_errmsg(db)))")
        }

        return results
    }

    // MARK: - Chunk Tracking & Index Updates (Async)

    func getChunkHash(docPath: String, chunkId: String) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let db = self.db else {
                    continuation.resume(returning: nil)
                    return
                }
                let sql = "SELECT chunk_hash FROM chunk_hashes WHERE doc_path = ? AND chunk_id = ?;"
                var stmt: OpaquePointer?
                var hash: String? = nil
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, docPath, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, chunkId, -1, SQLITE_TRANSIENT)
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        hash = String(cString: sqlite3_column_text(stmt, 0))
                    }
                    sqlite3_finalize(stmt)
                }
                continuation.resume(returning: hash)
            }
        }
    }

    func updateChunk(
        docPath: String,
        docName: String,
        chunkId: String,
        chunkHash: String,
        entries: [IndexEntry]
    ) async {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let db = self.db else {
                    continuation.resume()
                    return
                }

                // 1. Delete old FTS5 records for this chunk
                let delSql = "DELETE FROM search_index WHERE doc_path = ? AND chunk_id = ?;"
                var delStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, delSql, -1, &delStmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(delStmt, 1, docPath, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(delStmt, 2, chunkId, -1, SQLITE_TRANSIENT)
                    sqlite3_step(delStmt)
                    sqlite3_finalize(delStmt)
                }

                // 2. Insert new entries
                if !entries.isEmpty {
                    let insertSql = """
                    INSERT INTO search_index (
                        doc_path, doc_name, content_type, text_content,
                        canvas_x, canvas_y, canvas_w, canvas_h, page_idx, chunk_id
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                    """
                    var insStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, insertSql, -1, &insStmt, nil) == SQLITE_OK {
                        for entry in entries {
                            sqlite3_bind_text(insStmt, 1, docPath, -1, SQLITE_TRANSIENT)
                            sqlite3_bind_text(insStmt, 2, docName, -1, SQLITE_TRANSIENT)
                            sqlite3_bind_text(insStmt, 3, entry.contentType.rawValue, -1, SQLITE_TRANSIENT)
                            sqlite3_bind_text(insStmt, 4, entry.textContent, -1, SQLITE_TRANSIENT)
                            sqlite3_bind_double(insStmt, 5, Double(entry.canvasRect.origin.x))
                            sqlite3_bind_double(insStmt, 6, Double(entry.canvasRect.origin.y))
                            sqlite3_bind_double(insStmt, 7, Double(entry.canvasRect.width))
                            sqlite3_bind_double(insStmt, 8, Double(entry.canvasRect.height))
                            sqlite3_bind_int(insStmt, 9, Int32(entry.pageIndex))
                            sqlite3_bind_text(insStmt, 10, entry.chunkId, -1, SQLITE_TRANSIENT)

                            sqlite3_step(insStmt)
                            sqlite3_reset(insStmt)
                        }
                        sqlite3_finalize(insStmt)
                    }
                }

                // 3. Update chunk_hashes table
                let hashSql = "INSERT OR REPLACE INTO chunk_hashes (doc_path, chunk_id, chunk_hash) VALUES (?, ?, ?);"
                var hashStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, hashSql, -1, &hashStmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(hashStmt, 1, docPath, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(hashStmt, 2, chunkId, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(hashStmt, 3, chunkHash, -1, SQLITE_TRANSIENT)
                    sqlite3_step(hashStmt)
                    sqlite3_finalize(hashStmt)
                }

                continuation.resume()
            }
        }
    }

    func removeMissingChunks(docPath: String, validChunkIds: Set<String>) async {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let db = self.db else {
                    continuation.resume()
                    return
                }

                // Find all chunks recorded for this doc
                let listSql = "SELECT chunk_id FROM chunk_hashes WHERE doc_path = ?;"
                var existingChunks: [String] = []
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, listSql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, docPath, -1, SQLITE_TRANSIENT)
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        let cId = String(cString: sqlite3_column_text(stmt, 0))
                        existingChunks.append(cId)
                    }
                    sqlite3_finalize(stmt)
                }

                for cId in existingChunks where !validChunkIds.contains(cId) {
                    let delFts = "DELETE FROM search_index WHERE doc_path = ? AND chunk_id = ?;"
                    var delFtsStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, delFts, -1, &delFtsStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(delFtsStmt, 1, docPath, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(delFtsStmt, 2, cId, -1, SQLITE_TRANSIENT)
                        sqlite3_step(delFtsStmt)
                        sqlite3_finalize(delFtsStmt)
                    }

                    let delHash = "DELETE FROM chunk_hashes WHERE doc_path = ? AND chunk_id = ?;"
                    var delHashStmt: OpaquePointer?
                    if sqlite3_prepare_v2(db, delHash, -1, &delHashStmt, nil) == SQLITE_OK {
                        sqlite3_bind_text(delHashStmt, 1, docPath, -1, SQLITE_TRANSIENT)
                        sqlite3_bind_text(delHashStmt, 2, cId, -1, SQLITE_TRANSIENT)
                        sqlite3_step(delHashStmt)
                        sqlite3_finalize(delHashStmt)
                    }
                }

                continuation.resume()
            }
        }
    }

    func deleteDocument(docPath: String) async {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let db = self.db else {
                    continuation.resume()
                    return
                }

                let del1 = "DELETE FROM search_index WHERE doc_path = ?;"
                var s1: OpaquePointer?
                if sqlite3_prepare_v2(db, del1, -1, &s1, nil) == SQLITE_OK {
                    sqlite3_bind_text(s1, 1, docPath, -1, SQLITE_TRANSIENT)
                    sqlite3_step(s1)
                    sqlite3_finalize(s1)
                }

                let del2 = "DELETE FROM chunk_hashes WHERE doc_path = ?;"
                var s2: OpaquePointer?
                if sqlite3_prepare_v2(db, del2, -1, &s2, nil) == SQLITE_OK {
                    sqlite3_bind_text(s2, 1, docPath, -1, SQLITE_TRANSIENT)
                    sqlite3_step(s2)
                    sqlite3_finalize(s2)
                }

                let del3 = "DELETE FROM indexed_documents WHERE doc_path = ?;"
                var s3: OpaquePointer?
                if sqlite3_prepare_v2(db, del3, -1, &s3, nil) == SQLITE_OK {
                    sqlite3_bind_text(s3, 1, docPath, -1, SQLITE_TRANSIENT)
                    sqlite3_step(s3)
                    sqlite3_finalize(s3)
                }

                continuation.resume()
            }
        }
    }

    func setDocumentIndexed(docPath: String, docType: String, lastModified: Double) async {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let db = self.db else {
                    continuation.resume()
                    return
                }
                let sql = "INSERT OR REPLACE INTO indexed_documents (doc_path, doc_type, last_modified, index_version) VALUES (?, ?, ?, 1);"
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, docPath, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, docType, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_double(stmt, 3, lastModified)
                    sqlite3_step(stmt)
                    sqlite3_finalize(stmt)
                }
                continuation.resume()
            }
        }
    }

    func getDocumentLastIndexed(docPath: String) async -> Double? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let db = self.db else {
                    continuation.resume(returning: nil)
                    return
                }
                let sql = "SELECT last_modified FROM indexed_documents WHERE doc_path = ?;"
                var stmt: OpaquePointer?
                var date: Double? = nil
                if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, docPath, -1, SQLITE_TRANSIENT)
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        date = sqlite3_column_double(stmt, 0)
                    }
                    sqlite3_finalize(stmt)
                }
                continuation.resume(returning: date)
            }
        }
    }
}
