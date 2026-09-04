import SwiftUI
import Network
import UIKit
import CoreImage.CIFilterBuiltins
import CryptoKit

// MARK: - Live Cast Server (Echtzeit-Stream über lokales WLAN)

@MainActor
final class LiveCastServer: ObservableObject {
    static let shared = LiveCastServer()

    @Published var isStreaming: Bool = false
    @Published var viewerCount: Int = 0
    @Published var serverURL: String = ""
    @Published var localIP: String = ""
    @Published var port: UInt16 = 8080
    @Published var targetFPS: Int = 20
    @Published var streamQuality: CGFloat = 0.70

    private var listener: NWListener?
    private var webSocketConnections: [NWConnection] = []
    private var streamConnections: [NWConnection] = []
    private var activeSendingIds = Set<ObjectIdentifier>()
    private var captureTask: Task<Void, Never>?
    private let queue = DispatchQueue(label: "de.graetz.electronote.livecast", qos: .userInteractive)

    private init() {
        refreshIP()
    }

    func refreshIP() {
        if let ip = getLocalIPAddress() {
            localIP = ip
            serverURL = "http://\(ip):\(port)"
        } else {
            localIP = "127.0.0.1"
            serverURL = "http://127.0.0.1:\(port)"
        }
    }

    // MARK: - Start / Stop

    func toggleStreaming() {
        if isStreaming {
            stopStreaming()
        } else {
            startStreaming()
        }
    }

    func startStreaming() {
        guard !isStreaming else { return }
        refreshIP()

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            listener = try NWListener(using: parameters, on: nwPort)

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleNewConnection(connection)
                }
            }

            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    switch state {
                    case .ready:
                        self?.isStreaming = true
                    case .failed(let error):
                        print("[LiveCast] Listener failed: \(error)")
                        self?.stopStreaming()
                    case .cancelled:
                        self?.isStreaming = false
                    default:
                        break
                    }
                }
            }

            listener?.start(queue: queue)
            isStreaming = true
            startCaptureLoop()
            print("[LiveCast] Server gestartet auf \(serverURL)")
        } catch {
            print("[LiveCast] Start-Fehler: \(error)")
            isStreaming = false
        }
    }

    func stopStreaming() {
        captureTask?.cancel()
        captureTask = nil
        activeSendingIds.removeAll()

        for conn in webSocketConnections {
            conn.cancel()
        }
        webSocketConnections.removeAll()

        for conn in streamConnections {
            conn.cancel()
        }
        streamConnections.removeAll()
        viewerCount = 0

        listener?.cancel()
        listener = nil
        isStreaming = false
        print("[LiveCast] Server gestoppt.")
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection)
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak connection] data, _, _, _ in
            guard let self = self, let connection = connection, let data = data, !data.isEmpty else {
                return
            }

            let requestString = String(decoding: data, as: UTF8.self)
            let firstLine = requestString.components(separatedBy: "\r\n").first ?? ""
            let parts = firstLine.components(separatedBy: " ")

            guard parts.count >= 2 else {
                connection.cancel()
                return
            }

            let rawPath = parts[1]
            let path = rawPath.components(separatedBy: "?").first ?? rawPath

            Task { @MainActor in
                if self.isWebSocketUpgrade(headers: requestString) || path == "/ws" {
                    self.handleWebSocketUpgrade(connection: connection, requestString: requestString)
                } else if path == "/stream" || path == "/live.mjpg" {
                    self.serveMJPEGStream(connection: connection)
                } else if path == "/snapshot.jpg" {
                    self.serveSnapshot(connection: connection)
                } else if path == "/api/status" {
                    self.serveStatus(connection: connection)
                } else if path == "/favicon.ico" {
                    let resp = "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    if let d = resp.data(using: .utf8) {
                        connection.send(content: d, completion: .contentProcessed({ _ in connection.cancel() }))
                    }
                } else {
                    self.serveHTMLViewer(connection: connection)
                }
            }
        }
    }

    // MARK: - WebSocket Protocol Support (RFC 6455)

    private func isWebSocketUpgrade(headers: String) -> Bool {
        return headers.lowercased().contains("upgrade: websocket")
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

    private func computeWebSocketAccept(key: String) -> String {
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let combined = key + magic
        let digest = Insecure.SHA1.hash(data: Data(combined.utf8))
        return Data(digest).base64EncodedString()
    }

    private func handleWebSocketUpgrade(connection: NWConnection, requestString: String) {
        guard let key = extractWebSocketKey(from: requestString) else {
            let badRequest = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            if let data = badRequest.data(using: .utf8) {
                connection.send(content: data, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            }
            return
        }

        let acceptKey = computeWebSocketAccept(key: key)
        let response = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: \(acceptKey)\r\n\r\n"

        guard let data = response.data(using: .utf8) else { return }
        connection.send(content: data, completion: .contentProcessed({ [weak self, weak connection] error in
            guard error == nil, let conn = connection else { return }
            Task { @MainActor [weak self] in
                self?.addWebSocketClient(conn)
            }
        }))
    }

    private func addWebSocketClient(_ connection: NWConnection) {
        guard isStreaming else {
            connection.cancel()
            return
        }
        webSocketConnections.append(connection)
        updateViewerCount()

        listenWebSocket(on: connection)

        // Send initial frame immediately
        if let firstFrame = captureCurrentFrame() {
            let wsFrame = makeWebSocketBinaryFrame(payload: firstFrame)
            connection.send(content: wsFrame, completion: .contentProcessed({ _ in }))
        }
    }

    private func listenWebSocket(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self, weak connection] data, _, isComplete, error in
            guard let self = self, let conn = connection else { return }
            if error != nil || isComplete {
                Task { @MainActor in
                    self.removeWebSocketClient(conn)
                }
                return
            }

            if let data = data, !data.isEmpty {
                let opcode = data[0] & 0x0F
                if opcode == 0x08 { // Close frame
                    Task { @MainActor in
                        self.removeWebSocketClient(conn)
                    }
                    return
                } else if opcode == 0x09 { // Ping frame -> respond with Pong (0x0A)
                    let pongData = Data([0x8A, 0x00])
                    conn.send(content: pongData, completion: .contentProcessed({ _ in }))
                }
            }

            self.listenWebSocket(on: conn)
        }
    }

    private func removeWebSocketClient(_ connection: NWConnection) {
        let connId = ObjectIdentifier(connection)
        activeSendingIds.remove(connId)
        webSocketConnections.removeAll(where: { $0 === connection })
        connection.cancel()
        updateViewerCount()
    }

    private func makeWebSocketBinaryFrame(payload: Data) -> Data {
        var frame = Data()
        frame.reserveCapacity(payload.count + 10)
        // FIN bit (0x80) + Binary Opcode (0x02) = 0x82
        frame.append(0x82)

        let length = payload.count
        if length < 126 {
            frame.append(UInt8(length))
        } else if length <= 0xFFFF {
            frame.append(126)
            var len = UInt16(length).bigEndian
            withUnsafeBytes(of: &len) { frame.append(contentsOf: $0) }
        } else {
            frame.append(127)
            var len = UInt64(length).bigEndian
            withUnsafeBytes(of: &len) { frame.append(contentsOf: $0) }
        }

        frame.append(payload)
        return frame
    }

    private func updateViewerCount() {
        viewerCount = webSocketConnections.count + streamConnections.count
    }

    private var hasActiveClients: Bool {
        return !webSocketConnections.isEmpty || !streamConnections.isEmpty
    }

    // MARK: - HTTP Endpoints

    private func serveHTMLViewer(connection: NWConnection) {
        let html = buildHTMLViewer()
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        \(html)
        """
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }
    }

    private func serveSnapshot(connection: NWConnection) {
        guard let jpeg = captureCurrentFrame() else {
            connection.cancel()
            return
        }
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: image/jpeg\r
        Content-Length: \(jpeg.count)\r
        Access-Control-Allow-Origin: *\r
        Cache-Control: no-cache, no-store, must-revalidate\r
        Connection: close\r
        \r
        """
        var responseData = header.data(using: .utf8) ?? Data()
        responseData.append(jpeg)
        connection.send(content: responseData, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                connection.cancel()
            }
        }))
    }

    private func serveStatus(connection: NWConnection) {
        let json = "{\"streaming\": true, \"viewers\": \(viewerCount), \"fps\": \(targetFPS)}"
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(json.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        \(json)
        """
        if let data = response.data(using: .utf8) {
            connection.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed({ _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    connection.cancel()
                }
            }))
        }
    }

    private func serveMJPEGStream(connection: NWConnection) {
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: multipart/x-mixed-replace; boundary=frame\r
        Cache-Control: no-cache, no-store, must-revalidate, max-age=0\r
        Pragma: no-cache\r
        Expires: 0\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        """
        guard let data = header.data(using: .utf8) else { return }
        connection.send(content: data, completion: .contentProcessed({ [weak self, weak connection] error in
            guard error == nil, let conn = connection else { return }
            Task { @MainActor [weak self] in
                guard let self = self, self.isStreaming else {
                    conn.cancel()
                    return
                }
                self.streamConnections.append(conn)
                self.updateViewerCount()
                if let firstFrame = self.captureCurrentFrame() {
                    self.sendMJPEGFrame(firstFrame, to: conn)
                }
            }
        }))
    }

    // MARK: - Non-blocking Frame Broadcast (Immune to Touch & Apple Pencil Tracking)

    private func startCaptureLoop() {
        captureTask?.cancel()
        captureTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self, self.isStreaming else { break }
                if self.hasActiveClients {
                    self.broadcastNextFrame()
                }
                let fps = max(10, min(30, self.targetFPS))
                let delayNs = UInt64(1_000_000_000 / UInt64(fps))
                try? await Task.sleep(nanoseconds: delayNs)
            }
        }
    }

    private func broadcastNextFrame() {
        guard isStreaming && hasActiveClients else { return }
        guard let jpegData = captureCurrentFrame() else { return }

        // 1. Broadcast via WebSocket (Zero latency, smooth 30 FPS in Safari & Chrome)
        if !webSocketConnections.isEmpty {
            let wsFrame = makeWebSocketBinaryFrame(payload: jpegData)
            for connection in webSocketConnections {
                let connId = ObjectIdentifier(connection)
                if activeSendingIds.contains(connId) {
                    continue // Drop frame if client network buffer is busy
                }
                if connection.state == .ready {
                    activeSendingIds.insert(connId)
                    connection.send(content: wsFrame, completion: .contentProcessed({ [weak self, weak connection] error in
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            self.activeSendingIds.remove(connId)
                            if let error = error, let conn = connection {
                                print("[LiveCast] WebSocket send error: \(error)")
                                self.removeWebSocketClient(conn)
                            }
                        }
                    }))
                }
            }
        }

        // 2. Broadcast via MJPEG Multipart (VLC player / legacy fallback)
        if !streamConnections.isEmpty {
            for connection in streamConnections {
                let connId = ObjectIdentifier(connection)
                if activeSendingIds.contains(connId) {
                    continue
                }
                if connection.state == .ready {
                    activeSendingIds.insert(connId)
                    sendMJPEGFrame(jpegData, to: connection)
                }
            }
        }
    }

    private func sendMJPEGFrame(_ jpegData: Data, to connection: NWConnection) {
        let connId = ObjectIdentifier(connection)
        let frameHeader = "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpegData.count)\r\n\r\n"
        guard let headerData = frameHeader.data(using: .utf8) else {
            activeSendingIds.remove(connId)
            return
        }
        var fullData = headerData
        fullData.append(jpegData)
        fullData.append("\r\n".data(using: .utf8)!)

        connection.send(content: fullData, completion: .contentProcessed({ [weak self, weak connection] error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.activeSendingIds.remove(connId)
                if let error = error, let conn = connection {
                    print("[LiveCast] MJPEG connection send error: \(error)")
                    self.streamConnections.removeAll(where: { $0 === conn })
                    self.updateViewerCount()
                }
            }
        }))
    }

    // MARK: - High Performance Screen Capture

    private func captureCurrentFrame() -> Data? {
        let scenes = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
        let windows = scenes.flatMap({ $0.windows })

        guard let window = windows.first(where: { $0.isKeyWindow && $0.bounds.width > 0 })
                ?? windows.first(where: { $0.bounds.width > 0 }) else {
            return nil
        }

        let bounds = window.bounds
        guard bounds.width > 0 && bounds.height > 0 else { return nil }

        // Optimize scale to max 1280px width for blazing fast 10ms frame capture and smooth 25 FPS over Wi-Fi
        let targetWidth: CGFloat = min(1280, bounds.width)
        let scale = targetWidth / bounds.width
        let targetSize = CGSize(width: floor(targetWidth), height: floor(bounds.height * scale))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let image = renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .low
            ctx.cgContext.scaleBy(x: scale, y: scale)
            let drawn = window.drawHierarchy(in: bounds, afterScreenUpdates: false)
            if !drawn {
                window.layer.render(in: ctx.cgContext)
            }
        }

        return image.jpegData(compressionQuality: streamQuality)
    }

    // MARK: - QR Code Generator

    func generateQRCode(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: transform)

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - HTML5 Web Viewer Template

    private func buildHTMLViewer() -> String {
        return """
        <!DOCTYPE html>
        <html lang="de">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <title>ElectroNote — Live-Übertragung</title>
            <style>
                * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
                body {
                    background-color: #0b0e14;
                    color: #f0f6fc;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    min-height: 100vh;
                    overflow-x: hidden;
                }
                header {
                    width: 100%;
                    max-width: 1400px;
                    padding: 12px 20px;
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    background: rgba(18, 22, 31, 0.88);
                    backdrop-filter: blur(16px);
                    border-bottom: 1px solid rgba(255,255,255,0.08);
                    position: sticky;
                    top: 0;
                    z-index: 100;
                }
                .logo-group {
                    display: flex;
                    align-items: center;
                    gap: 12px;
                }
                .logo-icon {
                    width: 32px;
                    height: 32px;
                    background: linear-gradient(135deg, #007aff, #5856d6);
                    border-radius: 8px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    font-weight: 900;
                    color: white;
                    font-size: 17px;
                    box-shadow: 0 2px 10px rgba(0,122,255,0.4);
                }
                .logo-title {
                    font-size: 18px;
                    font-weight: 700;
                    letter-spacing: -0.4px;
                }
                .status-container {
                    display: flex;
                    align-items: center;
                    gap: 10px;
                }
                .live-badge {
                    display: inline-flex;
                    align-items: center;
                    gap: 6px;
                    background: rgba(235, 59, 90, 0.15);
                    color: #ff4757;
                    border: 1px solid rgba(255, 71, 87, 0.35);
                    padding: 4px 10px;
                    border-radius: 20px;
                    font-size: 12px;
                    font-weight: 700;
                    letter-spacing: 0.5px;
                    transition: all 0.3s ease;
                }
                .live-badge.connecting {
                    background: rgba(255, 177, 66, 0.15);
                    color: #eccc68;
                    border-color: rgba(255, 177, 66, 0.35);
                }
                .live-dot {
                    width: 8px;
                    height: 8px;
                    background: currentColor;
                    border-radius: 50%;
                    animation: pulse 1.4s infinite;
                }
                .fps-badge {
                    font-size: 12px;
                    font-family: ui-monospace, Menlo, monospace;
                    color: #8b949e;
                    background: rgba(255,255,255,0.06);
                    padding: 4px 8px;
                    border-radius: 6px;
                }
                @keyframes pulse {
                    0% { transform: scale(0.9); opacity: 0.8; }
                    50% { transform: scale(1.3); opacity: 1; }
                    100% { transform: scale(0.9); opacity: 0.8; }
                }
                .actions {
                    display: flex;
                    gap: 10px;
                }
                button {
                    background: #21262d;
                    border: 1px solid rgba(255,255,255,0.15);
                    color: #c9d1d9;
                    padding: 8px 14px;
                    border-radius: 6px;
                    font-size: 13px;
                    font-weight: 600;
                    cursor: pointer;
                    display: flex;
                    align-items: center;
                    gap: 6px;
                    transition: all 0.2s ease;
                }
                button:hover {
                    background: #30363d;
                    color: white;
                    border-color: rgba(255,255,255,0.3);
                }
                .stream-container {
                    flex: 1;
                    width: 100%;
                    max-width: 1400px;
                    padding: 16px;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                }
                .stream-wrapper {
                    position: relative;
                    width: 100%;
                    max-width: 1240px;
                    background: #000;
                    border-radius: 14px;
                    overflow: hidden;
                    box-shadow: 0 16px 48px rgba(0,0,0,0.7), 0 0 0 1px rgba(255,255,255,0.08);
                    display: flex;
                    justify-content: center;
                    align-items: center;
                }
                #stream {
                    width: 100%;
                    height: auto;
                    max-height: 85vh;
                    object-fit: contain;
                    display: block;
                    transition: opacity 0.2s ease;
                }
                footer {
                    width: 100%;
                    padding: 12px 20px;
                    text-align: center;
                    font-size: 12px;
                    color: #8b949e;
                    border-top: 1px solid rgba(255,255,255,0.06);
                }
                :fullscreen .stream-wrapper, :-webkit-full-screen .stream-wrapper {
                    max-width: 100vw;
                    height: 100vh;
                    border-radius: 0;
                }
                :fullscreen #stream, :-webkit-full-screen #stream {
                    max-height: 100vh;
                }
            </style>
        </head>
        <body>
            <header>
                <div class="logo-group">
                    <div class="logo-icon">Σ</div>
                    <div class="logo-title">ElectroNote</div>
                    <div class="status-container">
                        <div class="live-badge" id="status-badge">
                            <div class="live-dot"></div>
                            <span id="status-text">VERBINDET...</span>
                        </div>
                        <div class="fps-badge" id="fps-badge">-- FPS</div>
                    </div>
                </div>
                <div class="actions">
                    <button onclick="takeSnapshot()">📷 Screenshot</button>
                    <button onclick="toggleFullscreen()">⛶ Vollbild</button>
                </div>
            </header>

            <div class="stream-container">
                <div class="stream-wrapper" id="wrapper">
                    <img id="stream" alt="Live-Übertragung lädt...">
                </div>
            </div>

            <footer>
                Echtzeitübertragung über lokales WLAN • Kompatibel mit Mac Safari, Chrome, Edge, iPad & PC
            </footer>

            <script>
                const streamImg = document.getElementById("stream");
                const statusBadge = document.getElementById("status-badge");
                const statusText = document.getElementById("status-text");
                const fpsBadge = document.getElementById("fps-badge");
                const wrapper = document.getElementById("wrapper");

                let ws = null;
                let currentBlobUrl = null;
                let frameCount = 0;
                let lastFpsCheck = performance.now();
                let reconnectTimer = null;
                let fallbackTimer = null;
                let firstFrameReceived = false;

                function startStream() {
                    if (fallbackTimer) { clearInterval(fallbackTimer); fallbackTimer = null; }
                    const protocol = (location.protocol === "https:") ? "wss:" : "ws:";
                    const wsUrl = protocol + "//" + location.host + "/ws";

                    try {
                        ws = new WebSocket(wsUrl);
                        ws.binaryType = "blob";
                    } catch (e) {
                        console.warn("[LiveCast] WebSocket init error, fallback to polling", e);
                        startPollingFallback();
                        return;
                    }

                    ws.onopen = () => {
                        console.log("[LiveCast] WebSocket verbunden.");
                        statusBadge.className = "live-badge";
                        statusText.innerText = "LIVE";
                    };

                    ws.onmessage = (event) => {
                        firstFrameReceived = true;
                        const newBlobUrl = URL.createObjectURL(event.data);
                        const oldBlobUrl = currentBlobUrl;
                        currentBlobUrl = newBlobUrl;
                        streamImg.src = newBlobUrl;

                        if (oldBlobUrl) {
                            setTimeout(() => URL.revokeObjectURL(oldBlobUrl), 100);
                        }

                        // FPS Calculation
                        frameCount++;
                        const now = performance.now();
                        if (now - lastFpsCheck >= 1000) {
                            const fps = Math.round((frameCount * 1000) / (now - lastFpsCheck));
                            fpsBadge.innerText = fps + " FPS";
                            frameCount = 0;
                            lastFpsCheck = now;
                        }
                    };

                    ws.onerror = (e) => {
                        console.warn("[LiveCast] WebSocket Verbindungswarnung:", e);
                    };

                    ws.onclose = () => {
                        console.log("[LiveCast] WebSocket getrennt, verbinde neu...");
                        statusBadge.className = "live-badge connecting";
                        statusText.innerText = "VERBINDET...";
                        fpsBadge.innerText = "-- FPS";

                        if (!reconnectTimer) {
                            reconnectTimer = setTimeout(() => {
                                reconnectTimer = null;
                                startStream();
                            }, 1000);
                        }
                    };
                }

                // If after 2.5 seconds no frame received via WebSocket, start fallback polling
                setTimeout(() => {
                    if (!firstFrameReceived) {
                        startPollingFallback();
                    }
                }, 2500);

                function startPollingFallback() {
                    if (fallbackTimer) return;
                    console.log("[LiveCast] Starte Snapshot-Polling Fallback...");
                    fallbackTimer = setInterval(() => {
                        const testImg = new Image();
                        testImg.onload = () => {
                            streamImg.src = testImg.src;
                            statusBadge.className = "live-badge";
                            statusText.innerText = "LIVE (HTTP)";
                        };
                        testImg.src = "/snapshot.jpg?t=" + Date.now();
                    }, 65);
                }

                function toggleFullscreen() {
                    if (!document.fullscreenElement && !document.webkitFullscreenElement) {
                        if (wrapper.requestFullscreen) {
                            wrapper.requestFullscreen();
                        } else if (wrapper.webkitRequestFullscreen) {
                            wrapper.webkitRequestFullscreen();
                        }
                    } else {
                        if (document.exitFullscreen) {
                            document.exitFullscreen();
                        } else if (document.webkitExitFullscreen) {
                            document.webkitExitFullscreen();
                        }
                    }
                }

                function takeSnapshot() {
                    const a = document.createElement("a");
                    a.href = "/snapshot.jpg?t=" + Date.now();
                    a.download = "ElectroNote_Live_" + new Date().toISOString().slice(0,19).replace(/[:T]/g, "-") + ".jpg";
                    document.body.appendChild(a);
                    a.click();
                    document.body.removeChild(a);
                }

                // Initial start
                startStream();
            </script>
        </body>
        </html>
        """
    }
}

// MARK: - Local IP Resolver

func getLocalIPAddress() -> String? {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
    defer { freeifaddrs(ifaddr) }

    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let flags = Int32(ptr.pointee.ifa_flags)
        let addr = ptr.pointee.ifa_addr.pointee

        // Check for running IPv4 interface that is NOT loopback
        if (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING),
           (flags & IFF_LOOPBACK) == 0,
           addr.sa_family == UInt8(AF_INET) {
            let name = String(cString: ptr.pointee.ifa_name)
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(ptr.pointee.ifa_addr, socklen_t(addr.sa_len),
                           &hostname, socklen_t(hostname.count),
                           nil, socklen_t(0), NI_NUMERICHOST) == 0 {
                let ip = String(cString: hostname)
                if name == "en0" {
                    return ip // Primary iOS Wi-Fi interface
                } else if address == nil {
                    address = ip
                }
            }
        }
    }
    return address
}
