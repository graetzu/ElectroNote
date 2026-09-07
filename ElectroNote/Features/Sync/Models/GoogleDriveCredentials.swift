import Foundation

struct GoogleDriveCredentials {
    var accessToken: String
    var refreshToken: String?
    var userEmail: String?
    var userName: String?
    var folderId: String?

    // MARK: - Keychain Persistence

    static func load() -> GoogleDriveCredentials? {
        guard let token = KeychainHelper.load(key: "gdrive_access_token"),
              !token.isEmpty else {
            return nil
        }
        let refresh = KeychainHelper.load(key: "gdrive_refresh_token")
        let email   = KeychainHelper.load(key: "gdrive_user_email")
        let name    = KeychainHelper.load(key: "gdrive_user_name")
        let folder  = KeychainHelper.load(key: "gdrive_folder_id")
        return GoogleDriveCredentials(
            accessToken: token,
            refreshToken: refresh,
            userEmail: email,
            userName: name,
            folderId: folder
        )
    }

    func save() {
        KeychainHelper.save(accessToken, key: "gdrive_access_token")
        if let refresh = refreshToken {
            KeychainHelper.save(refresh, key: "gdrive_refresh_token")
        }
        if let email = userEmail {
            KeychainHelper.save(email, key: "gdrive_user_email")
        }
        if let name = userName {
            KeychainHelper.save(name, key: "gdrive_user_name")
        }
        if let folder = folderId {
            KeychainHelper.save(folder, key: "gdrive_folder_id")
        }
    }

    static func logout() {
        KeychainHelper.delete(key: "gdrive_access_token")
        KeychainHelper.delete(key: "gdrive_refresh_token")
        KeychainHelper.delete(key: "gdrive_user_email")
        KeychainHelper.delete(key: "gdrive_user_name")
        KeychainHelper.delete(key: "gdrive_folder_id")
    }
}
