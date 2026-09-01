import Foundation

// Nextcloud Login Flow v2
// https://docs.nextcloud.com/server/latest/developer_manual/client_apis/LoginFlow/index.html
//
// User enters only their server URL. The app opens an in-app browser at the Nextcloud
// login page, then polls until Nextcloud hands back an app-password.

@MainActor
final class NextcloudLoginFlow: ObservableObject {
    @Published var loginURL: URL?
    @Published var isLoading  = false
    @Published var errorMessage: String?

    var onSuccess: ((NextcloudCredentials) -> Void)?
    private var pollTask: Task<Void, Never>?

    // MARK: - Public API

    func start(serverURL raw: String) {
        var server = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !server.lowercased().hasPrefix("http") { server = "https://" + server }
        server = server.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        isLoading    = true
        errorMessage = nil

        Task {
            do {
                let (pollEndpoint, token, loginURL) = try await initiateFlow(server: server)
                self.loginURL = loginURL
                self.isLoading = false
                self.pollTask  = Task { await self.poll(endpoint: pollEndpoint, token: token) }
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading    = false
            }
        }
    }

    func cancel() {
        pollTask?.cancel()
        pollTask  = nil
        loginURL  = nil
        isLoading = false
    }

    // MARK: - Private

    private func initiateFlow(server: String) async throws -> (URL, String, URL) {
        guard let endpoint = URL(string: "\(server)/index.php/login/v2") else {
            throw NextcloudError.invalidURL
        }
        var req = URLRequest(url: endpoint, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("ElectroNote iOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw NextcloudError.serverError(
                "Server antwortet nicht (HTTP \(status)). Ist die URL korrekt?"
            )
        }

        struct V2Response: Decodable {
            struct Poll: Decodable { let token: String; let endpoint: String }
            let poll: Poll
            let login: String
        }
        let decoded = try JSONDecoder().decode(V2Response.self, from: data)
        guard let pollURL  = URL(string: decoded.poll.endpoint),
              let loginURL = URL(string: decoded.login) else { throw NextcloudError.invalidURL }
        return (pollURL, decoded.poll.token, loginURL)
    }

    private func poll(endpoint: URL, token: String) async {
        var comps   = URLComponents()
        comps.queryItems = [URLQueryItem(name: "token", value: token)]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.httpBody   = comps.query?.data(using: .utf8)
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("ElectroNote iOS",                   forHTTPHeaderField: "User-Agent")

        struct PollResponse: Decodable { let server, loginName, appPassword: String }

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }

            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let decoded = try? JSONDecoder().decode(PollResponse.self, from: data)
            else { continue }

            var srv = decoded.server
            if srv.hasSuffix("/") { srv = String(srv.dropLast()) }
            let creds = NextcloudCredentials(serverURL: srv,
                                             loginName: decoded.loginName,
                                             appPassword: decoded.appPassword)
            creds.save()
            await MainActor.run {
                self.loginURL = nil
                self.onSuccess?(creds)
            }
            return
        }
    }
}

enum NextcloudError: LocalizedError {
    case invalidURL
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "Ungültige Server-URL."
        case .serverError(let msg): return msg
        }
    }
}
