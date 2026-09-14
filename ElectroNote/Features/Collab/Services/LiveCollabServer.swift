import Foundation
import Network
import Combine

final class LiveCollabServer {
    var port: UInt16 = 8765
    private(set) var isRunning: Bool = false
    private(set) var localIP: String = "127.0.0.1"

    var onMessageReceived: ((CollabMessage) -> Void)?
    var onPeerListChanged: (([CollabPeer]) -> Void)?
    var onSnapshotNeeded: (() -> (docJson: String?, drawingJson: String?))?

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var peers: [ObjectIdentifier: CollabPeer] = [:]
    private let queue = DispatchQueue(label: "de.graetz.electronote.collab.server", qos: .userInitiated)
    private var hostPeer: CollabPeer?

    func start(hostPeer: CollabPeer, documentType: CollabDocumentType, roomName: String = "ElectroNote Live") throws {
        stop()
        self.hostPeer = hostPeer
        self.localIP = getLocalIPAddress() ?? "127.0.0.1"

        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        // Try preferred port or next available
        var currentPort = port
        var newListener: NWListener? = nil
        for attempt in 0..<10 {
            let p = NWEndpoint.Port(rawValue: currentPort + UInt16(attempt))!
            do {
                newListener = try NWListener(using: parameters, on: p)
                self.port = p.rawValue
                break
            } catch {
                continue
            }
        }

        guard let listener = newListener else {
            throw NSError(domain: "LiveCollabServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Konnte keinen freien Port finden."])
        }

        listener.service = NWListener.Service(name: roomName, type: "_electronote-collab._tcp")
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
            case .failed(let error):
                self?.isRunning = false
                print("[CollabServer] Failed with error: \(error)")
            case .cancelled:
                self?.isRunning = false
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }

        listener.start(queue: queue)
        self.listener = listener
        self.isRunning = true
        print("[CollabServer] Started on port \(self.port), IP: \(self.localIP)")
    }

    func stop() {
        isRunning = false
        listener?.cancel()
        listener = nil

        for (_, conn) in connections {
            conn.cancel()
        }
        connections.removeAll()
        peers.removeAll()
        notifyPeersChanged()
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let conn = connection else { return }
            switch state {
            case .ready:
                self.receiveNextMessage(from: conn)
            case .failed, .cancelled:
                self.removeConnection(id: id)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveNextMessage(from connection: NWConnection) {
        connection.receiveMessage { [weak self, weak connection] data, context, isComplete, error in
            guard let self = self, let conn = connection else { return }
            if let error = error {
                print("[CollabServer] Receive error: \(error)")
                self.removeConnection(id: ObjectIdentifier(conn))
                return
            }

            if let data = data, !data.isEmpty {
                self.handleIncomingData(data, from: conn)
            }

            if connection?.state == .ready {
                self.receiveNextMessage(from: conn)
            }
        }
    }

    private func handleIncomingData(_ data: Data, from connection: NWConnection) {
        guard let message = try? JSONDecoder().decode(CollabMessage.self, from: data) else {
            return
        }

        let connId = ObjectIdentifier(connection)

        switch message.type {
        case .join:
            if let peer = message.peer {
                peers[connId] = peer
                notifyPeersChanged()

                // Send current room state to all
                broadcastRoomState()

                // Send initial snapshot to joining peer
                if let snapshots = onSnapshotNeeded?() {
                    let snapshotMsg = CollabMessage(
                        type: .snapshotResponse,
                        senderId: hostPeer?.id ?? "host",
                        senderName: hostPeer?.name ?? "Host",
                        documentType: message.documentType,
                        documentSnapshotJson: snapshots.docJson,
                        drawingSnapshotJson: snapshots.drawingJson
                    )
                    send(message: snapshotMsg, to: connection)
                }
            }

        case .snapshotRequest:
            if let snapshots = onSnapshotNeeded?() {
                let snapshotMsg = CollabMessage(
                    type: .snapshotResponse,
                    senderId: hostPeer?.id ?? "host",
                    senderName: hostPeer?.name ?? "Host",
                    documentType: message.documentType,
                    documentSnapshotJson: snapshots.docJson,
                    drawingSnapshotJson: snapshots.drawingJson
                )
                send(message: snapshotMsg, to: connection)
            }

        case .leave:
            removeConnection(id: connId)

        default:
            // Delta event from client: notify local host AND broadcast to other clients
            onMessageReceived?(message)
            broadcast(message: message, excluding: connId)
        }
    }

    func broadcast(message: CollabMessage, excluding excludeId: ObjectIdentifier? = nil) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        for (id, conn) in connections {
            if let exclude = excludeId, id == exclude { continue }
            sendRaw(data: data, to: conn)
        }
    }

    private func send(message: CollabMessage, to connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        sendRaw(data: data, to: connection)
    }

    private func sendRaw(data: Data, to connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed({ error in
            if let error = error {
                print("[CollabServer] Send error: \(error)")
            }
        }))
    }

    private func broadcastRoomState() {
        var allPeers: [CollabPeer] = []
        if let host = hostPeer { allPeers.append(host) }
        allPeers.append(contentsOf: peers.values)

        let msg = CollabMessage(
            type: .roomState,
            senderId: hostPeer?.id ?? "host",
            senderName: hostPeer?.name ?? "Host",
            documentType: .note,
            peers: allPeers
        )
        broadcast(message: msg)
    }

    private func removeConnection(id: ObjectIdentifier) {
        if let conn = connections.removeValue(forKey: id) {
            conn.cancel()
        }
        peers.removeValue(forKey: id)
        notifyPeersChanged()
        broadcastRoomState()
    }

    private func notifyPeersChanged() {
        var allPeers: [CollabPeer] = []
        if let host = hostPeer { allPeers.append(host) }
        allPeers.append(contentsOf: peers.values)
        DispatchQueue.main.async { [weak self] in
            self?.onPeerListChanged?(allPeers)
        }
    }

    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let addr = ptr.pointee.ifa_addr.pointee

            if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING) {
                if addr.sa_family == UInt8(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                                   &hostname, socklen_t(hostname.count),
                                   nil, 0, NI_NUMERICHOST) == 0 {
                        let ip = String(cString: hostname)
                        let name = String(cString: ptr.pointee.ifa_name)
                        if name.hasPrefix("en") || name.hasPrefix("wlan") || name.hasPrefix("ap") {
                            return ip
                        }
                        if address == nil { address = ip }
                    }
                }
            }
        }
        return address
    }
}
