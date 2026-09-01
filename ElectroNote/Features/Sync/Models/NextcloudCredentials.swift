import Foundation

struct NextcloudCredentials {
    var serverURL: String       // https://cloud.example.com  (no trailing slash)
    var loginName: String
    var appPassword: String

    var webdavBase: URL {
        let enc = loginName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? loginName
        return URL(string: "\(serverURL)/remote.php/dav/files/\(enc)/")!
    }

    var displayHost: String { URL(string: serverURL)?.host ?? serverURL }

    // MARK: - Keychain persistence

    static func load() -> NextcloudCredentials? {
        guard let server = KeychainHelper.load(key: "nc_server"),
              let login  = KeychainHelper.load(key: "nc_login"),
              let pwd    = KeychainHelper.load(key: "nc_password"),
              !server.isEmpty, !login.isEmpty, !pwd.isEmpty
        else { return nil }
        return NextcloudCredentials(serverURL: server, loginName: login, appPassword: pwd)
    }

    func save() {
        KeychainHelper.save(serverURL,   key: "nc_server")
        KeychainHelper.save(loginName,   key: "nc_login")
        KeychainHelper.save(appPassword, key: "nc_password")
    }

    static func logout() {
        KeychainHelper.delete(key: "nc_server")
        KeychainHelper.delete(key: "nc_login")
        KeychainHelper.delete(key: "nc_password")
    }
}
