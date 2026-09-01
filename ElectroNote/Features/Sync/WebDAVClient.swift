import Foundation

// MARK: - DAVFile

struct DAVFile {
    let name: String
    let davPath: String     // path relative to user's WebDAV root (e.g. "ElectroNote/Note.enote/drawing.pkdrawing")
    let lastModified: Date
    let isDirectory: Bool

    var pathExtension: String { (name as NSString).pathExtension.lowercased() }
    var isPDF:  Bool { pathExtension == "pdf" }
    var isNote: Bool { name.hasSuffix(".enote") }
    var isOfficeDoc: Bool {
        let ext = pathExtension
        return ["docx", "doc", "xlsx", "xls", "pptx", "ppt", "rtf", "txt", "pages", "numbers", "keynote"].contains(ext)
    }
    var isImportable: Bool { isPDF || isOfficeDoc }

    var systemImage: String {
        if isDirectory { return isNote ? "note.text" : "folder.fill" }
        if isPDF       { return "doc.richtext.fill" }
        switch pathExtension {
        case "docx", "doc": return "doc.text.fill"
        case "xlsx", "xls": return "tablecells.fill"
        case "pptx", "ppt": return "rectangle.inset.filled.and.person.filled"
        case "rtf", "txt":  return "doc.plaintext.fill"
        default:            return "doc"
        }
    }
}

// MARK: - Client

final class WebDAVClient {
    let credentials: NextcloudCredentials

    private let session: URLSession = .shared

    private let rfc1123: DateFormatter = {
        let f = DateFormatter()
        f.locale     = Locale(identifier: "en_US_POSIX")
        f.timeZone   = TimeZone(identifier: "GMT")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    init(credentials: NextcloudCredentials) {
        self.credentials = credentials
    }

    // MARK: - Auth

    private var authHeader: String {
        let s = "\(credentials.loginName):\(credentials.appPassword)"
        return "Basic " + Data(s.utf8).base64EncodedString()
    }

    func davURL(path: String) -> URL {
        path.isEmpty ? credentials.webdavBase
                     : credentials.webdavBase.appendingPathComponent(path)
    }

    private func makeRequest(_ url: URL, method: String) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 30)
        r.httpMethod = method
        r.setValue(authHeader,        forHTTPHeaderField: "Authorization")
        r.setValue("ElectroNote iOS", forHTTPHeaderField: "User-Agent")
        return r
    }

    // MARK: - PROPFIND

    func propfind(path: String, depth: String = "1") async throws -> [DAVFile] {
        let url = davURL(path: path)
        var req = makeRequest(url, method: "PROPFIND")
        req.setValue(depth,            forHTTPHeaderField: "Depth")
        req.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        req.httpBody = """
            <?xml version="1.0"?>
            <d:propfind xmlns:d="DAV:">
              <d:prop><d:displayname/><d:getlastmodified/><d:resourcetype/></d:prop>
            </d:propfind>
            """.data(using: .utf8)

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return [] }
        guard status == 207 else { throw WebDAVError.http(status, "PROPFIND \(path)") }

        return PropfindParser(
            data: data,
            userRootPath: credentials.webdavBase.path,
            rfc1123: rfc1123
        ).parse()
    }

    // MARK: - GET

    func get(path: String) async throws -> Data {
        let (data, response) = try await session.data(for: makeRequest(davURL(path: path), method: "GET"))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw WebDAVError.http(status, "GET \(path)") }
        return data
    }

    // MARK: - PUT

    func put(path: String, data: Data) async throws {
        var req = makeRequest(davURL(path: path), method: "PUT")
        req.httpBody = data
        let (_, response) = try await session.upload(for: req, from: data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else { throw WebDAVError.http(status, "PUT \(path)") }
    }

    // MARK: - MKCOL

    func mkcol(path: String) async throws {
        let (_, response) = try await session.data(for: makeRequest(davURL(path: path), method: "MKCOL"))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) || status == 405 else {
            throw WebDAVError.http(status, "MKCOL \(path)")
        }
    }

    // MARK: - Helpers

    func ensureDirectories(for filePath: String) async throws {
        let components = filePath.split(separator: "/").map(String.init).dropLast()
        var current = ""
        for component in components {
            current = current.isEmpty ? component : "\(current)/\(component)"
            try await mkcol(path: current)
        }
    }
}

enum WebDAVError: LocalizedError {
    case http(Int, String)
    var errorDescription: String? {
        if case .http(let code, let op) = self { return "\(op) fehlgeschlagen (HTTP \(code))" }
        return "WebDAV-Fehler"
    }
}

// MARK: - XML Parser (DAV:multistatus)

private final class PropfindParser: NSObject, XMLParserDelegate {
    let data: Data
    let userRootPath: String    // e.g. "/remote.php/dav/files/username/"
    let rfc1123: DateFormatter

    private var results: [DAVFile] = []
    private var currentHref    = ""
    private var currentLastMod: Date?
    private var currentIsDir   = false
    private var currentText    = ""
    private var inResponse     = false

    init(data: Data, userRootPath: String, rfc1123: DateFormatter) {
        self.data = data; self.userRootPath = userRootPath; self.rfc1123 = rfc1123
    }

    func parse() -> [DAVFile] {
        let p = XMLParser(data: data)
        p.shouldProcessNamespaces = true
        p.delegate = self
        p.parse()
        return results
    }

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        currentText = ""
        if el == "response"   { inResponse = true; currentHref = ""; currentLastMod = nil; currentIsDir = false }
        if el == "collection" { currentIsDir = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { currentText += string }

    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?,
                qualifiedName: String?) {
        switch el {
        case "href":
            let raw = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            currentHref = raw.removingPercentEncoding ?? raw
        case "getlastmodified":
            currentLastMod = rfc1123.date(from: currentText.trimmingCharacters(in: .whitespacesAndNewlines))
        case "response":
            guard inResponse, !currentHref.isEmpty else { return }
            var davPath = currentHref
            if davPath.hasPrefix(userRootPath) {
                davPath = String(davPath.dropFirst(userRootPath.count))
            }
            davPath = davPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !davPath.isEmpty else { return }

            let name = (davPath as NSString).lastPathComponent
            results.append(DAVFile(name: name, davPath: davPath,
                                   lastModified: currentLastMod ?? .distantPast,
                                   isDirectory: currentIsDir))
            inResponse = false
        default: break
        }
        currentText = ""
    }
}
