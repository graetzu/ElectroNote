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
    private var receiveBuffer = Data()
    private var isHandshakeDone: Bool = false
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
        DispatchQueue.main.async { [weak self] in
            self?.onDiscoveredRoomsChanged?([])
        }
    }

    // MARK: - Connect via RFC 6455 over TCP NWConnection

    func connect(endpoint: NWEndpoint, localPeer: CollabPeer, documentType: CollabDocumentType) {
        disconnect()
        self.localPeer = localPeer
        self.receiveBuffer = Data()
        self.isHandshakeDone = false

        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let conn = NWConnection(to: endpoint, using: parameters)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self = self, let conn = conn else { return }
            switch state {
            case .ready:
                self.startHandshake(connection: conn, endpoint: endpoint, documentType: documentType)
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
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? 8765
        )
        connect(endpoint: endpoint, localPeer: localPeer, documentType: documentType)
    }

    private func startHandshake(connection: NWConnection, endpoint: NWEndpoint, documentType: CollabDocumentType) {
        var hostStr = "localhost"
        switch endpoint {
        case .hostPort(let host, let port):
            hostStr = "\(host):\(port)"
        case .service(let name, _, _, _):
            hostStr = name
        default:
            break
        }

        // Generate 16 random bytes for Sec-WebSocket-Key
        var randomBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &randomBytes)
        let secKey = Data(randomBytes).base64EncodedString()

        let request = "GET / HTTP/1.1\r\n" +
            "Host: \(hostStr)\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            "Sec-WebSocket-Key: \(secKey)\r\n" +
            "Sec-WebSocket-Version: 13\r\n\r\n"

        guard let reqData = request.data(using: .utf8) else {
            disconnect()
            return
        }

        connection.send(content: reqData, isComplete: false, completion: .contentProcessed({ [weak self, weak connection] error in
            guard let self = self, let conn = connection, error == nil else {
                self?.disconnect()
                return
            }
            self.receiveHandshakeResponse(connection: conn, documentType: documentType)
        }))
    }

    private func receiveHandshakeResponse(connection: NWConnection, documentType: CollabDocumentType) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak connection] data, _, isComplete, error in
            guard let self = self, let conn = connection else { return }
            if error != nil || isComplete {
                self.disconnect()
                return
            }

            guard let data = data, !data.isEmpty else {
                if conn.state == .ready {
                    self.receiveHandshakeResponse(connection: conn, documentType: documentType)
                }
                return
            }

            self.receiveBuffer.append(data)

            // Check if HTTP header complete
            if let range = self.receiveBuffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = self.receiveBuffer.subdata(in: 0..<range.upperBound)
                self.receiveBuffer.removeSubrange(0..<range.upperBound)

                if let headerStr = String(data: headerData, encoding: .utf8),
                   headerStr.contains("101 Switching Protocols") {
                    self.isHandshakeDone = true
                    self.isConnected = true
                    print("[CollabClient] WebSocket handshake successful!")

                    DispatchQueue.main.async {
                        self.onConnectedChanged?(true)
                    }

                    // Send JOIN message
                    if let peer = self.localPeer {
                        let joinMsg = CollabMessage(
                            type: .join,
                            senderId: peer.id,
                            senderName: peer.name,
                            documentType: documentType,
                            peer: peer
                        )
                        self.send(message: joinMsg)
                    }

                    // Process any remaining frames in buffer
                    if !self.receiveBuffer.isEmpty {
                        let messages = self.parseWebSocketFrames(buffer: &self.receiveBuffer, connection: conn)
                        for msgData in messages {
                            self.handleIncomingData(msgData)
                        }
                    }

                    // Start message receiving loop
                    self.receiveNextWebSocketBytes(from: conn)
                } else {
                    print("[CollabClient] Handshake rejected or invalid response")
                    self.disconnect()
                }
            } else {
                // Keep reading until header is complete
                if conn.state == .ready {
                    self.receiveHandshakeResponse(connection: conn, documentType: documentType)
                }
            }
        }
    }

    private func receiveNextWebSocketBytes(from conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak conn] data, _, isComplete, error in
            guard let self = self, let connection = conn else { return }
            if error != nil || isComplete {
                self.disconnect()
                return
            }

            if let data = data, !data.isEmpty {
                self.receiveBuffer.append(data)
                let messages = self.parseWebSocketFrames(buffer: &self.receiveBuffer, connection: connection)
                for msgData in messages {
                    self.handleIncomingData(msgData)
                }
            }

            if connection.state == .ready {
                self.receiveNextWebSocketBytes(from: connection)
            }
        }
    }

    // MARK: - RFC 6455 Frame Parser & Builder

    private func parseWebSocketFrames(buffer: inout Data, connection: NWConnection) -> [Data] {
        var payloadList: [Data] = []

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

            if opcode == 0x08 { // Close frame
                disconnect()
                return payloadList
            } else if opcode == 0x09 { // Ping frame -> reply with masked Pong (0x0A)
                let pongFrame = makeClientFrame(payload: payload, opcode: 0x0A)
                connection.send(content: pongFrame, isComplete: false, completion: .contentProcessed({ _ in }))
            } else if opcode == 0x01 || opcode == 0x02 { // Text or Binary frame
                payloadList.append(payload)
            }
        }

        return payloadList
    }

    private func makeClientFrame(payload: Data, opcode: UInt8 = 0x01) -> Data {
        var frame = Data()
        frame.reserveCapacity(payload.count + 14)
        // FIN bit (0x80) | opcode
        frame.append(0x80 | opcode)

        let len = payload.count
        // Client frames MUST be masked (0x80 bit set on length byte)
        if len < 126 {
            frame.append(0x80 | UInt8(len))
        } else if len <= 0xFFFF {
            frame.append(0x80 | 126)
            var beLen = UInt16(len).bigEndian
            withUnsafeBytes(of: &beLen) { frame.append(contentsOf: $0) }
        } else {
            frame.append(0x80 | 127)
            var beLen = UInt64(len).bigEndian
            withUnsafeBytes(of: &beLen) { frame.append(contentsOf: $0) }
        }

        // 4-byte random masking key
        let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
        frame.append(contentsOf: mask)

        var maskedPayload = payload
        for i in 0..<maskedPayload.count {
            maskedPayload[i] ^= mask[i % 4]
        }
        frame.append(maskedPayload)

        return frame
    }

    func disconnect() {
        let wasConnected = isConnected
        isConnected = false
        isHandshakeDone = false
        receiveBuffer.removeAll()

        if wasConnected, let peer = localPeer {
            let leaveMsg = CollabMessage(
                type: .leave,
                senderId: peer.id,
                senderName: peer.name,
                documentType: .note,
                peer: peer
            )
            send(message: leaveMsg)
        }

        connection?.cancel()
        connection = nil

        if wasConnected {
            DispatchQueue.main.async { [weak self] in
                self?.onConnectedChanged?(false)
            }
        }
    }

    func send(message: CollabMessage) {
        guard let conn = connection, let data = try? JSONEncoder().encode(message) else { return }
        let frame = makeClientFrame(payload: data, opcode: 0x01)
        conn.send(content: frame, isComplete: false, completion: .contentProcessed({ error in
            if let error = error {
                print("[CollabClient] Send error: \(error)")
            }
        }))
    }

    private func handleIncomingData(_ data: Data) {
        guard let message = try? JSONDecoder().decode(CollabMessage.self, from: data) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onMessageReceived?(message)
        }
    }
}
