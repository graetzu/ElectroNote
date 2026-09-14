import Foundation
import Network
import Combine

struct DiscoveredRoom: Identifiable, Hashable {
    let id: String
    let name: String
    let endpoint: NWEndpoint

    var displayName: String {
        switch endpoint {
        case .service(let n, _, _, _):
            return n
        case .hostPort(let host, let port):
            return "\(host):\(port)"
        default:
            return name
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DiscoveredRoom, rhs: DiscoveredRoom) -> Bool {
        lhs.id == rhs.id
    }
}

final class LiveCollabClient {
    private(set) var isConnected: Bool = false
    var onMessageReceived: ((CollabMessage) -> Void)?
    var onConnectedChanged: ((Bool) -> Void)?
    var onDiscoveredRoomsChanged: (([DiscoveredRoom]) -> Void)?

    private var connection: NWConnection?
    private var browser: NWBrowser?
    private var discoveredRooms: [String: DiscoveredRoom] = [:]
    private var localPeer: CollabPeer?
    private let queue = DispatchQueue(label: "de.graetz.electronote.collab.client", qos: .userInitiated)

    // MARK: - Bonjour Room Discovery (mDNS)

    func startBrowsing() {
        stopBrowsing()
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_electronote-collab._tcp", domain: nil), using: parameters)

        browser.browseResultsChangedHandler = { [weak self] results, changes in
            guard let self = self else { return }
            var rooms: [String: DiscoveredRoom] = [:]
            for result in results {
                let id = "\(result.endpoint)"
                let name: String
                switch result.endpoint {
                case .service(let n, _, _, _):
                    name = n
                default:
                    name = "ElectroNote Raum"
                }
                rooms[id] = DiscoveredRoom(id: id, name: name, endpoint: result.endpoint)
            }
            self.discoveredRooms = rooms
            DispatchQueue.main.async {
                self.onDiscoveredRoomsChanged?(Array(rooms.values))
            }
        }

        browser.start(queue: queue)
        self.browser = browser
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        discoveredRooms.removeAll()
        onDiscoveredRoomsChanged?([])
    }

    // MARK: - Connect via WebSocket NWConnection

    func connect(endpoint: NWEndpoint, localPeer: CollabPeer, documentType: CollabDocumentType) {
        disconnect()
        self.localPeer = localPeer

        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let conn = NWConnection(to: endpoint, using: parameters)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self = self, let conn = conn else { return }
            switch state {
            case .ready:
                self.isConnected = true
                DispatchQueue.main.async {
                    self.onConnectedChanged?(true)
                }
                // Send JOIN message
                let joinMsg = CollabMessage(
                    type: .join,
                    senderId: localPeer.id,
                    senderName: localPeer.name,
                    documentType: documentType,
                    peer: localPeer
                )
                self.send(message: joinMsg)
                self.receiveNextMessage(from: conn)

            case .failed(let error):
                print("[CollabClient] Connection failed: \(error)")
                self.disconnect()

            case .cancelled:
                self.disconnect()

            default:
                break
            }
        }

        conn.start(queue: queue)
    }

    func connect(host: String, port: UInt16, localPeer: CollabPeer, documentType: CollabDocumentType) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 8765)
        connect(endpoint: endpoint, localPeer: localPeer, documentType: documentType)
    }

    func disconnect() {
        if isConnected, let peer = localPeer {
            let leaveMsg = CollabMessage(
                type: .leave,
                senderId: peer.id,
                senderName: peer.name,
                documentType: .note,
                peer: peer
            )
            send(message: leaveMsg)
        }
        isConnected = false
        connection?.cancel()
        connection = nil
        DispatchQueue.main.async { [weak self] in
            self?.onConnectedChanged?(false)
        }
    }

    func send(message: CollabMessage) {
        guard let conn = connection, let data = try? JSONEncoder().encode(message) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])
        conn.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed({ error in
            if let error = error {
                print("[CollabClient] Send error: \(error)")
            }
        }))
    }

    private func receiveNextMessage(from conn: NWConnection) {
        conn.receiveMessage { [weak self, weak conn] data, context, isComplete, error in
            guard let self = self, let conn = conn else { return }
            if let error = error {
                print("[CollabClient] Receive error: \(error)")
                self.disconnect()
                return
            }

            if let data = data, !data.isEmpty,
               let message = try? JSONDecoder().decode(CollabMessage.self, from: data) {
                DispatchQueue.main.async {
                    self.onMessageReceived?(message)
                }
            }

            if conn.state == .ready {
                self.receiveNextMessage(from: conn)
            }
        }
    }
}
