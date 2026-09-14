import Foundation
import Network
import Combine
import CryptoKit

final class LiveCollabServer {
    var port: UInt16 = 8765
    private(set) var isRunning: Bool = false
    private(set) var localIP: String = "127.0.0.1"
    private(set) var documentType: CollabDocumentType = .note

    var onMessageReceived: ((CollabMessage) -> Void)?
    var onPeerListChanged: (([CollabPeer]) -> Void)?
    var onSnapshotNeeded: (() -> (docJson: String?, drawingJson: String?))?

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var peers: [ObjectIdentifier: CollabPeer] = [:]
    private var buffers: [ObjectIdentifier: Data] = [:]
    private var handshakeDone: [ObjectIdentifier: Bool] = [:]
    private let queue = DispatchQueue(label: "de.graetz.electronote.collab.server", qos: .userInitiated)
    private var hostPeer: CollabPeer?

    func start(hostPeer: CollabPeer, documentType: CollabDocumentType, roomName: String = "ElectroNote Live") throws {
        stop()
        self.hostPeer = hostPeer
        self.documentType = documentType
        self.localIP = getLocalIPAddress() ?? "127.0.0.1"

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        parameters.allowLocalEndpointReuse = true

        // Try preferred port or next available
        var currentPort = port
        var newListener: NWListener? = nil
        for attempt in 0..<10 {
            guard let p = NWEndpoint.Port(rawValue: currentPort + UInt16(attempt)) else { continue }
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
                print("[CollabServer] Listener failed: \(error)")
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
        buffers.removeAll()
        handshakeDone.removeAll()
        notifyPeersChanged()
    }

    private func handleNewConnection(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        buffers[id] = Data()
        handshakeDone[id] = false

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let conn = connection else { return }
            switch state {
            case .ready:
                self.receiveNextBytes(from: conn)
            case .failed, .cancelled:
                self.removeConnection(id: id)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveNextBytes(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, isComplete, error in
            guard let self = self, let conn = connection else { return }
            let id = ObjectIdentifier(conn)

            if error != nil || isComplete {
                self.removeConnection(id: id)
                return
            }

            guard let data = data, !data.isEmpty else {
                if conn.state == .ready {
                    self.receiveNextBytes(from: conn)
                }
                return
            }

            self.handleData(data, from: conn)

            if conn.state == .ready {
                self.receiveNextBytes(from: conn)
            }
        }
    }

    private func handleData(_ data: Data, from connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        guard var buf = buffers[id] else { return }
        buf.append(data)

        if handshakeDone[id] != true {
            // Check if HTTP header is complete
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buf.subdata(in: 0..<range.upperBound)
                buf.removeSubrange(0..<range.upperBound)
                buffers[id] = buf

                if let headerStr = String(data: headerData, encoding: .utf8) {
                    processHandshake(headerStr, connection: connection)
                }
            } else {
                buffers[id] = buf
                return
            }
        }

        // Process WebSocket frames if handshake is complete
        if handshakeDone[id] == true {
            guard var remainingBuf = buffers[id] else { return }
            let messages = parseWebSocketFrames(buffer: &remainingBuf, connection: connection)
            buffers[id] = remainingBuf

            for msgData in messages {
                handleIncomingMessageData(msgData, from: connection)
            }
        }
    }

    private func processHandshake(_ headers: String, connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        guard let key = extractWebSocketKey(from: headers) else {
            let badResp = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            connection.send(content: badResp.data(using: .utf8), completion: .contentProcessed({ _ in
                self.removeConnection(id: id)
            }))
            return
        }

        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data((key + magic).utf8))
        let accept = Data(digest).base64EncodedString()

        let response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(accept)\r\n\r\n"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed({ [weak self, weak connection] error in
            guard let self = self, let conn = connection else { return }
            if error != nil {
                self.removeConnection(id: id)
                return
            }
            self.handshakeDone[id] = true
            print("[CollabServer] WebSocket handshake complete with client")

            // If buffered data remains, process it now
            if var rem = self.buffers[id], !rem.isEmpty {
                let messages = self.parseWebSocketFrames(buffer: &rem, connection: conn)
                self.buffers[id] = rem
                for msgData in messages {
                    self.handleIncomingMessageData(msgData, from: conn)
                }
            }
        }))
    }

    private func extractWebSocketKey(from headers: String) -> String? {
        for line in headers.components(separatedBy: "\r\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("sec-websocket-key:") {
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }

    // MARK: - RFC 6455 Frame Parser & Builder

    private func parseWebSocketFrames(buffer: inout Data, connection: NWConnection) -> [Data] {
        var payloadList: [Data] = []
        let id = ObjectIdentifier(connection)

        while buffer.count >= 2 {
            let b0 = buffer[0]
            let b1 = buffer[1]
            let opcode = b0 & 0x0F
            let isMasked = (b1 & 0x80) != 0
            var payloadLen = Int(b1 & 0x7F)
            var offset = 2

            if payloadLen == 126 {
                guard buffer.count >= 4 else { break }
                payloadLen = Int(buffer[2]) << 8 | Int(buffer[3])
                offset = 4
            } else if payloadLen == 127 {
                guard buffer.count >= 10 else { break }
                payloadLen = Int(buffer[2]) << 56 | Int(buffer[3]) << 48 | Int(buffer[4]) << 40 | Int(buffer[5]) << 32 |
                             Int(buffer[6]) << 24 | Int(buffer[7]) << 16 | Int(buffer[8]) << 8 | Int(buffer[9])
                offset = 10
            }

            let maskLen = isMasked ? 4 : 0
            let totalFrameLen = offset + maskLen + payloadLen
            guard buffer.count >= totalFrameLen else { break }

            let mask: [UInt8]
            if isMasked {
                mask = [buffer[offset], buffer[offset+1], buffer[offset+2], buffer[offset+3]]
                offset += 4
            } else {
                mask = []
            }

            var payload = Data(buffer[offset..<(offset+payloadLen)])
            if isMasked && !mask.isEmpty {
                for i in 0..<payload.count {
                    payload[i] ^= mask[i % 4]
                }
            }

            buffer.removeSubrange(0..<totalFrameLen)

            // Handle Control frames
            if opcode == 0x08 { // Close frame
                removeConnection(id: id)
                return payloadList
            } else if opcode == 0x09 { // Ping frame -> reply with Pong (0x0A)
                let pongFrame = makeFrame(payload: payload, opcode: 0x0A)
                connection.send(content: pongFrame, completion: .contentProcessed({ _ in }))
            } else if opcode == 0x01 || opcode == 0x02 { // Text or Binary frame
                payloadList.append(payload)
            }
        }

        return payloadList
    }

    private func makeFrame(payload: Data, opcode: UInt8 = 0x01) -> Data {
        var frame = Data()
        frame.reserveCapacity(payload.count + 10)
        // FIN bit (0x80) | opcode
        frame.append(0x80 | opcode)

        let len = payload.count
        if len < 126 {
            frame.append(UInt8(len))
        } else if len <= 0xFFFF {
            frame.append(126)
            var beLen = UInt16(len).bigEndian
            withUnsafeBytes(of: &beLen) { frame.append(contentsOf: $0) }
        } else {
            frame.append(127)
            var beLen = UInt64(len).bigEndian
            withUnsafeBytes(of: &beLen) { frame.append(contentsOf: $0) }
        }

        frame.append(payload)
        return frame
    }

    // MARK: - Collab Message Dispatch

    private func handleIncomingMessageData(_ data: Data, from connection: NWConnection) {
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

                // Send initial snapshot with host documentType
                if let snapshots = onSnapshotNeeded?() {
                    let snapshotMsg = CollabMessage(
                        type: .snapshotResponse,
                        senderId: hostPeer?.id ?? "host",
                        senderName: hostPeer?.name ?? "Host",
                        documentType: self.documentType,
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
                    documentType: self.documentType,
                    documentSnapshotJson: snapshots.docJson,
                    drawingSnapshotJson: snapshots.drawingJson
                )
                send(message: snapshotMsg, to: connection)
            }

        case .leave:
            removeConnection(id: connId)

        default:
            // Delta event: notify local host and forward to other clients
            onMessageReceived?(message)
            broadcast(message: message, excluding: connId)
        }
    }

    func broadcast(message: CollabMessage, excluding excludeId: ObjectIdentifier? = nil) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        let frame = makeFrame(payload: data, opcode: 0x01)
        for (id, conn) in connections {
            if let exclude = excludeId, id == exclude { continue }
            conn.send(content: frame, completion: .contentProcessed({ _ in }))
        }
    }

    private func send(message: CollabMessage, to connection: NWConnection) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        let frame = makeFrame(payload: data, opcode: 0x01)
        connection.send(content: frame, completion: .contentProcessed({ _ in }))
    }

    private func broadcastRoomState() {
        var allPeers: [CollabPeer] = []
        if let host = hostPeer { allPeers.append(host) }
        allPeers.append(contentsOf: peers.values)

        let msg = CollabMessage(
            type: .roomState,
            senderId: hostPeer?.id ?? "host",
            senderName: hostPeer?.name ?? "Host",
            documentType: self.documentType,
            peers: allPeers
        )
        broadcast(message: msg)
    }

    private func removeConnection(id: ObjectIdentifier) {
        if let conn = connections.removeValue(forKey: id) {
            conn.cancel()
        }
        peers.removeValue(forKey: id)
        buffers.removeValue(forKey: id)
        handshakeDone.removeValue(forKey: id)
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
