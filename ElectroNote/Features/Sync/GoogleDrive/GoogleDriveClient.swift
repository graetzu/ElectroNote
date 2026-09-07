import Foundation

struct GoogleDriveFile: Identifiable, Codable {
    let id: String
    let name: String
    let mimeType: String
    let modifiedTime: String?
    let size: String?

    var isFolder: Bool {
        mimeType == "application/vnd.google-apps.folder"
    }

    var lastModifiedDate: Date {
        guard let modifiedTime = modifiedTime else { return Date() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: modifiedTime) ?? ISO8601DateFormatter().date(from: modifiedTime) ?? Date()
    }

    var sizeFormatted: String {
        guard let s = size, let bytes = Int64(s) else { return "" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct GoogleDriveFileListResponse: Codable {
    let files: [GoogleDriveFile]
}

private struct GoogleDriveAboutResponse: Codable {
    struct User: Codable {
        let displayName: String?
        let emailAddress: String?
    }
    let user: User?
}

final class GoogleDriveClient {
    let credentials: GoogleDriveCredentials
    private let session: URLSession

    init(credentials: GoogleDriveCredentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    // MARK: - User Info

    func getUserInfo() async throws -> (name: String, email: String) {
        let url = URL(string: "https://www.googleapis.com/drive/v3/about?fields=user")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, res) = try await session.data(for: req)
        try validateResponse(res, data: data)

        let decoded = try JSONDecoder().decode(GoogleDriveAboutResponse.self, from: data)
        let name = decoded.user?.displayName ?? "Google Nutzer"
        let email = decoded.user?.emailAddress ?? "Google Drive"
        return (name, email)
    }

    // MARK: - Folders & Files

    func findOrCreateFolder(name: String, parentId: String? = nil) async throws -> String {
        let escapedName = name.replacingOccurrences(of: "'", with: "\\'")
        var query = "mimeType = 'application/vnd.google-apps.folder' and name = '\(escapedName)' and trashed = false"
        if let parentId = parentId {
            query += " and '\(parentId)' in parents"
        }

        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://www.googleapis.com/drive/v3/files?q=\(encodedQuery)&fields=files(id,name)")
        else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: searchURL)
        req.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, res) = try await session.data(for: req)
        try validateResponse(res, data: data)

        let list = try JSONDecoder().decode(GoogleDriveFileListResponse.self, from: data)
        if let existing = list.files.first {
            return existing.id
        }

        // Create folder
        let createURL = URL(string: "https://www.googleapis.com/drive/v3/files")!
        var createReq = URLRequest(url: createURL)
        createReq.httpMethod = "POST"
        createReq.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        createReq.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder"
        ]
        if let parentId = parentId {
            body["parents"] = [parentId]
        }
        createReq.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (cData, cRes) = try await session.data(for: createReq)
        try validateResponse(cRes, data: cData)

        let created = try JSONDecoder().decode(GoogleDriveFile.self, from: cData)
        return created.id
    }

    func listFiles(inFolderId folderId: String? = nil) async throws -> [GoogleDriveFile] {
        var query = "trashed = false"
        if let fid = folderId, !fid.isEmpty {
            query += " and '\(fid)' in parents"
        }

        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.googleapis.com/drive/v3/files?q=\(encodedQuery)&fields=files(id,name,mimeType,modifiedTime,size)&pageSize=100")
        else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, res) = try await session.data(for: req)
        try validateResponse(res, data: data)

        let list = try JSONDecoder().decode(GoogleDriveFileListResponse.self, from: data)
        return list.files
    }

    // MARK: - Upload / Download / Delete

    func uploadFile(name: String, data: Data, mimeType: String, folderId: String, existingFileId: String? = nil) async throws -> GoogleDriveFile {
        let boundary = "Boundary-\(UUID().uuidString)"

        var url: URL
        var httpMethod: String
        if let existingId = existingFileId {
            url = URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(existingId)?uploadType=multipart")!
            httpMethod = "PATCH"
        } else {
            url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!
            httpMethod = "POST"
        }

        var req = URLRequest(url: url)
        req.httpMethod = httpMethod
        req.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var metadata: [String: Any] = ["name": name]
        if existingFileId == nil {
            metadata["parents"] = [folderId]
        }
        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataJSON)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        req.httpBody = body

        let (resData, res) = try await session.data(for: req)
        try validateResponse(res, data: resData)

        return try JSONDecoder().decode(GoogleDriveFile.self, from: resData)
    }

    func downloadFile(fileId: String) async throws -> Data {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, res) = try await session.data(for: req)
        try validateResponse(res, data: data)
        return data
    }

    func deleteFile(fileId: String) async throws {
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")

        let (_, res) = try await session.data(for: req)
        guard let http = res as? HTTPURLResponse, (200...299).contains(http.statusCode) || http.statusCode == 404 else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Validation

    private func validateResponse(_ res: URLResponse, data: Data) throws {
        guard let http = res as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errObj = json["error"] as? [String: Any],
               let message = errObj["message"] as? String {
                throw NSError(domain: "GoogleDrive", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
            throw NSError(domain: "GoogleDrive", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP-Fehler \(http.statusCode)"])
        }
    }
}
