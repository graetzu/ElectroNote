import SwiftUI
import CoreImage

struct LiveCollabSheetView: View {
    let documentName: String
    let documentType: CollabDocumentType
    var initialTab: Int = 1

    @ObservedObject private var collab = LiveCollabSessionManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Int
    @State private var manualHost: String = ""
    @State private var manualPortText: String = "8765"

    init(documentName: String, documentType: CollabDocumentType, initialTab: Int = 1) {
        self.documentName = documentName
        self.documentType = documentType
        self.initialTab = initialTab
        self._selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch collab.sessionState {
                case .hosting:
                    activeHostingView
                case .connected:
                    activeConnectedView
                case .idle, .error:
                    preSessionView
                }
            }
            .navigationTitle("Live-Zusammenarbeit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 520)
        .onAppear {
            collab.startBrowsingRooms()
            if manualHost.isEmpty {
                let ip = collab.hostIP.isEmpty ? (getLocalIPAddress() ?? "") : collab.hostIP
                if !ip.isEmpty && ip.contains(".") {
                    let parts = ip.split(separator: ".")
                    if parts.count >= 3 {
                        manualHost = "\(parts[0]).\(parts[1]).\(parts[2])."
                    } else {
                        manualHost = ip
                    }
                } else {
                    manualHost = "10.100.72."
                }
            }
        }
    }

    // MARK: - Pre-Session View (Host or Join)

    private var preSessionView: some View {
        VStack(spacing: 16) {
            if case .error(let message) = collab.sessionState {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding()
                .background(Color.red.opacity(0.12))
                .cornerRadius(10)
                .padding(.horizontal)
            }

            // Big, prominent tab switcher (Beitreten / Hosten)
            HStack(spacing: 12) {
                Button {
                    selectedTab = 1
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Sitzung beitreten")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(selectedTab == 1 ? Color.blue : Color(uiColor: .tertiarySystemFill))
                    .foregroundColor(selectedTab == 1 ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                Button {
                    selectedTab = 0
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.2.wave.2.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Sitzung hosten")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(selectedTab == 0 ? Color.green : Color(uiColor: .tertiarySystemFill))
                    .foregroundColor(selectedTab == 0 ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 12)

            if selectedTab == 0 {
                hostTabContent
            } else {
                joinTabContent
            }
        }
    }

    // MARK: - Host Tab

    private var hostTabContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.wave.2")
                        .font(.system(size: 44))
                        .foregroundColor(.accentColor)

                    Text("Dokument im lokalen Netzwerk teilen")
                        .font(.headline)

                    Text("Erlaube iPads, Macs, Android-Tablets und Smartboards im selben WLAN oder Hotspot, synchron und in Echtzeit an diesem Dokument mitzuarbeiten. Kein externer Server erforderlich!")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 12)

                VStack(spacing: 12) {
                    HStack {
                        Label("Dokument:", systemImage: "doc.text")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(documentName)
                            .fontWeight(.semibold)
                    }

                    Divider()

                    HStack {
                        Label("Typ:", systemImage: "square.grid.2x2")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(documentTypeLabel(documentType))
                            .fontWeight(.semibold)
                    }

                    Divider()

                    HStack {
                        Label("Dein Gerätename:", systemImage: "laptopcomputer.and.iphone")
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: collab.myPeer.colorHex))
                                .frame(width: 12, height: 12)
                            Text(collab.myPeer.name)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                Button {
                    collab.startHosting(documentName: documentName, documentType: documentType)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                        Text("Live-Sitzung starten")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Join Tab

    private var joinTabContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Section: Discovered Rooms via Bonjour
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.blue)
                        Text("Gefundene Sitzungen (WLAN/Bonjour)")
                            .font(.headline)
                        Spacer()
                    }

                    if collab.discoveredRooms.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Suche nach aktiven ElectroNote-Sitzungen...")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        ForEach(collab.discoveredRooms) { room in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(room.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text("Im lokalen Netzwerk gefunden")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Beitreten") {
                                    collab.joinSession(endpoint: room.endpoint, documentType: documentType)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                            }
                            .padding(10)
                            .background(Color(uiColor: .tertiarySystemFill))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // Section: Manual IP Connection
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.orange)
                        Text("Manuelle Verbindung")
                            .font(.headline)
                    }

                    Text("IP-Adresse des Hosts oder Smartboards eingeben:")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        TextField("Host-IP (z.B. 192.168.1.50)", text: $manualHost)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        TextField("Port", text: $manualPortText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 75)
                            .keyboardType(.numberPad)
                    }

                    Button {
                        var targetHost = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
                        var targetPort = UInt16(manualPortText.filter { $0.isNumber }) ?? 8765
                        if targetHost.contains(":") {
                            let parts = targetHost.split(separator: ":")
                            if let h = parts.first { targetHost = String(h) }
                            if parts.count > 1, let p = UInt16(parts[1].filter { $0.isNumber }) {
                                targetPort = p
                            }
                        }
                        collab.joinSession(host: targetHost, port: targetPort, documentType: documentType)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Mit Host verbinden")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.plain)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Active Hosting View

    private var activeHostingView: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 14, height: 14)
                    Text("Du hostest diese Sitzung live")
                        .font(.headline)
                        .foregroundColor(.green)
                    Spacer()
                }
                .padding()
                .background(Color.green.opacity(0.12))
                .cornerRadius(12)
                .padding(.horizontal)

                // Host Connection Details
                VStack(spacing: 12) {
                    HStack {
                        Text("WLAN-IP:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(collab.hostIP)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                        Button {
                            UIPasteboard.general.string = "\(collab.hostIP):\(String(collab.hostPort))"
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }

                    Divider()

                    HStack {
                        Text("Port:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(collab.hostPort))
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                    }

                    if !collab.roomCode.isEmpty {
                        Divider()

                        HStack {
                            Text("Raum-PIN:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(collab.roomCode)
                                .font(.system(.title3, design: .monospaced))
                                .fontWeight(.black)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)

                // QR Code
                let qrPayload = "electronote://collab?ip=\(collab.hostIP)&port=\(String(collab.hostPort))&pin=\(collab.roomCode)&type=\(documentType.rawValue)"
                if let qrImage = generateQRCode(from: qrPayload) {
                    VStack(spacing: 8) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 150, height: 150)
                            .padding(8)
                            .background(Color.white)
                            .cornerRadius(10)
                            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)

                        Text("Mit Android oder iPad scannen zum Beitreten")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                // Peers List
                peersListView

                // Terminate Button
                Button(role: .destructive) {
                    collab.leaveSession()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.circle.fill")
                        Text("Sitzung beenden")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Active Connected View

    private var activeConnectedView: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 14, height: 14)
                    Text("Verbunden mit Host (\(collab.hostIP))")
                        .font(.headline)
                        .foregroundColor(.blue)
                    Spacer()
                }
                .padding()
                .background(Color.blue.opacity(0.12))
                .cornerRadius(12)
                .padding(.horizontal)

                // Peers List
                peersListView

                // Leave Button
                Button(role: .destructive) {
                    collab.leaveSession()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                        Text("Sitzung verlassen")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Peers List

    private var peersListView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Teilnehmer (\(collab.connectedPeers.count))")
                    .font(.headline)
                Spacer()
            }

            ForEach(collab.connectedPeers) { peer in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: peer.colorHex))
                        .frame(width: 12, height: 12)

                    Text(peer.name)
                        .font(.subheadline)
                        .fontWeight(peer.id == collab.myPeer.id ? .bold : .regular)

                    if peer.isHost {
                        Text("Host")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.25))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }

                    if peer.id == collab.myPeer.id {
                        Text("(Du)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(8)
                .background(Color(uiColor: .tertiarySystemFill))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func documentTypeLabel(_ type: CollabDocumentType) -> String {
        switch type {
        case .note: return "Notizbuch (.enote)"
        case .whiteboard: return "Whiteboard (.ewb)"
        case .pap: return "Ablaufplan (.epap)"
        case .mindmap: return "MindMap (.emm)"
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Color Hex Extension

extension Color {
    init(hex: String) {
        let hexClean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexClean).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexClean.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 122, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
