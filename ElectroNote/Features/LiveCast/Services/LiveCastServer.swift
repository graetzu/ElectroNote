import SwiftUI
import Network
import UIKit
import CoreImage.CIFilterBuiltins

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
    private var streamConnections: [NWConnection] = []
    private var captureTimer: Timer?
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
        captureTimer?.invalidate()
        captureTimer = nil

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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak connection] data, context, isComplete, error in
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

            let path = parts[1]

            Task { @MainActor in
                if path == "/stream" || path == "/live.mjpg" {
                    self.serveMJPEGStream(connection: connection)
                } else if path == "/snapshot.jpg" {
                    self.serveSnapshot(connection: connection)
                } else if path == "/api/status" {
                    self.serveStatus(connection: connection)
                } else {
                    self.serveHTMLViewer(connection: connection)
                }
            }
        }
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
        Connection: close\r
        \r
        """
        var responseData = header.data(using: .utf8) ?? Data()
        responseData.append(jpeg)
        connection.send(content: responseData, completion: .contentProcessed({ _ in
            connection.cancel()
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
            connection.send(content: data, completion: .contentProcessed({ _ in
                connection.cancel()
            }))
        }
    }

    private func serveMJPEGStream(connection: NWConnection) {
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: multipart/x-mixed-replace; boundary=--frame\r
        Cache-Control: no-cache, no-store, must-revalidate\r
        Pragma: no-cache\r
        Expires: 0\r
        Access-Control-Allow-Origin: *\r
        Connection: keep-alive\r
        \r
        """
        guard let headerData = header.data(using: .utf8) else {
            connection.cancel()
            return
        }

        connection.send(content: headerData, completion: .contentProcessed({ [weak self, weak connection] error in
            guard let self = self, let connection = connection, error == nil else {
                connection?.cancel()
                return
            }
            Task { @MainActor in
                self.streamConnections.append(connection)
                self.viewerCount = self.streamConnections.count

                // Send immediate first frame
                if let frame = self.captureCurrentFrame() {
                    self.sendFrame(frame, to: connection)
                }
            }
        }))
    }

    // MARK: - Frame Broadcast

    private func startCaptureLoop() {
        captureTimer?.invalidate()
        let interval = 1.0 / Double(targetFPS)
        captureTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.broadcastNextFrame()
            }
        }
    }

    private func broadcastNextFrame() {
        guard isStreaming && !streamConnections.isEmpty else { return }
        guard let jpegData = captureCurrentFrame() else { return }

        var active: [NWConnection] = []
        for connection in streamConnections {
            if connection.state == .ready {
                sendFrame(jpegData, to: connection)
                active.append(connection)
            } else if connection.state != .cancelled && connection.state != .failed(NWError.posix(.ECANCELED)) {
                active.append(connection)
            }
        }
        if streamConnections.count != active.count {
            streamConnections = active
            viewerCount = active.count
        }
    }

    private func sendFrame(_ jpegData: Data, to connection: NWConnection) {
        let frameHeader = """
        --frame\r
        Content-Type: image/jpeg\r
        Content-Length: \(jpegData.count)\r
        \r
        """
        guard let headerData = frameHeader.data(using: .utf8) else { return }
        var fullData = headerData
        fullData.append(jpegData)
        fullData.append("\r\n".data(using: .utf8)!)

        connection.send(content: fullData, completion: .contentProcessed({ [weak self, weak connection] error in
            if error != nil, let conn = connection {
                Task { @MainActor in
                    self?.streamConnections.removeAll(where: { $0 === conn })
                    self?.viewerCount = self?.streamConnections.count ?? 0
                }
            }
        }))
    }

    // MARK: - High Performance Screen Capture

    private func captureCurrentFrame() -> Data? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else {
            return nil
        }

        let bounds = window.bounds
        guard bounds.width > 0 && bounds.height > 0 else { return nil }

        // Scale down high-DPI retina display to standard 1080p width for ultra-smooth 60ms latency streaming over Wi-Fi
        let scale: CGFloat = bounds.width > 1200 ? 0.70 : 0.85
        let targetSize = CGSize(width: floor(bounds.width * scale), height: floor(bounds.height * scale))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let image = renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .medium
            ctx.cgContext.scaleBy(x: scale, y: scale)
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
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
                    background-color: #0d1117;
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
                    padding: 14px 20px;
                    display: flex;
                    align-items: center;
                    justify-content: space-between;
                    background: rgba(22, 27, 34, 0.85);
                    backdrop-filter: blur(12px);
                    border-bottom: 1px solid rgba(255,255,255,0.1);
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
                    font-size: 18px;
                    box-shadow: 0 2px 8px rgba(0,122,255,0.4);
                }
                .logo-title {
                    font-size: 18px;
                    font-weight: 700;
                    letter-spacing: -0.5px;
                }
                .live-badge {
                    display: inline-flex;
                    align-items: center;
                    gap: 6px;
                    background: rgba(235, 59, 90, 0.2);
                    color: #ff4757;
                    border: 1px solid rgba(255, 71, 87, 0.4);
                    padding: 4px 10px;
                    border-radius: 20px;
                    font-size: 12px;
                    font-weight: 700;
                    letter-spacing: 0.5px;
                }
                .live-dot {
                    width: 8px;
                    height: 8px;
                    background: #ff4757;
                    border-radius: 50%;
                    animation: pulse 1.4s infinite;
                }
                @keyframes pulse {
                    0% { transform: scale(0.9); opacity: 0.8; }
                    50% { transform: scale(1.3); opacity: 1; box-shadow: 0 0 10px #ff4757; }
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
                    max-width: 1200px;
                    background: #000;
                    border-radius: 12px;
                    overflow: hidden;
                    box-shadow: 0 12px 40px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,255,255,0.1);
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
                }
                footer {
                    width: 100%;
                    padding: 12px 20px;
                    text-align: center;
                    font-size: 12px;
                    color: #8b949e;
                    border-top: 1px solid rgba(255,255,255,0.06);
                }
                :fullscreen .stream-wrapper {
                    max-width: 100vw;
                    height: 100vh;
                    border-radius: 0;
                }
                :fullscreen #stream {
                    max-height: 100vh;
                }
            </style>
        </head>
        <body>
            <header>
                <div class="logo-group">
                    <div class="logo-icon">Σ</div>
                    <div class="logo-title">ElectroNote</div>
                    <div class="live-badge">
                        <div class="live-dot"></div>
                        LIVE
                    </div>
                </div>
                <div class="actions">
                    <button onclick="takeSnapshot()">📷 Schnappschuss</button>
                    <button onclick="toggleFullscreen()">⛶ Vollbild</button>
                </div>
            </header>

            <div class="stream-container">
                <div class="stream-wrapper" id="wrapper">
                    <img id="stream" src="/stream" alt="Live Übertragung lädt..." onerror="retryStream()">
                </div>
            </div>

            <footer>
                Übertragen über lokales WLAN • ElectroNote Live Cast • Ohne Apple TV kompatibel mit allen Browsern
            </footer>

            <script>
                function toggleFullscreen() {
                    const el = document.getElementById("wrapper");
                    if (!document.fullscreenElement) {
                        el.requestFullscreen().catch(err => {
                            alert("Vollbild nicht unterstützt: " + err.message);
                        });
                    } else {
                        document.exitFullscreen();
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

                function retryStream() {
                    setTimeout(() => {
                        document.getElementById("stream").src = "/stream?t=" + Date.now();
                    }, 1000);
                }
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
