import SwiftUI

struct LiveCastSheetView: View {
    @ObservedObject private var liveCast = LiveCastServer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var copiedURL = false
    @State private var copiedIP = false
    @State private var copiedPort = false
    @State private var showPortEditSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let errorMsg = liveCast.lastErrorMessage {
                        errorCard(errorMsg)
                    }

                    // Header Status Card
                    statusCard

                    if liveCast.isStreaming {
                        // QR Code Card
                        qrCodeCard

                        // URL Card with Copy Button
                        urlCard

                        // Viewer Stats & Quality Settings
                        settingsCard
                    } else {
                        // Explanation & Feature Promo
                        introCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Live-Übertragung (Web Cast)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .bold()
                }
            }
            .onAppear {
                liveCast.refreshIP()
            }
            .sheet(isPresented: $showPortEditSheet) {
                PortSettingsSheet()
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Error Card

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.title3)

            Text(message)
                .font(.caption)
                .foregroundColor(.primary)

            Spacer()

            Button {
                showPortEditSheet = true
            } label: {
                Text("Port ändern")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Status Card

    var statusCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(liveCast.isStreaming ? Color.red.opacity(0.15) : Color.gray.opacity(0.15))
                        .frame(width: 54, height: 54)

                    Image(systemName: liveCast.isStreaming ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(liveCast.isStreaming ? .red : .secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("WLAN Live-Stream")
                            .font(.headline)

                        if liveCast.isStreaming {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 7, height: 7)
                                Text("LIVE")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }

                    if liveCast.isStreaming {
                        HStack(spacing: 6) {
                            Text("IP: \(liveCast.localIP)")
                                .fontWeight(.semibold)
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("Port: \(String(liveCast.port))")
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    } else {
                        Text("Übertrage die App live an jeden Browser im WLAN")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { liveCast.isStreaming },
                    set: { _ in liveCast.toggleStreaming() }
                ))
                .labelsHidden()
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - QR Code Card

    var qrCodeCard: some View {
        VStack(spacing: 12) {
            Text("QR-Code mit Kamera scannen")
                .font(.subheadline.bold())
                .foregroundColor(.primary)

            if let qrImage = liveCast.generateQRCode(for: liveCast.serverURL) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 170, height: 170)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            }

            Text("Funktioniert mit Smartphone, PC, Mac, Tablet oder Smart-TV im selben WLAN")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - URL Card

    var urlCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Verbindungsdaten für Browser:")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    liveCast.refreshIP()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("IP aktualisieren")
                    }
                    .font(.caption.bold())
                    .foregroundColor(.blue)
                }
            }

            // IP & Port Info Grid
            HStack(spacing: 12) {
                // IP Card
                VStack(alignment: .leading, spacing: 4) {
                    Text("IP-ADRESSE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    HStack {
                        Text(liveCast.localIP.isEmpty ? "127.0.0.1" : liveCast.localIP)
                            .font(.system(.subheadline, design: .monospaced).bold())
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = liveCast.localIP
                            copiedIP = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { copiedIP = false }
                        } label: {
                            Image(systemName: copiedIP ? "checkmark" : "doc.on.doc")
                                .font(.caption.bold())
                                .foregroundColor(copiedIP ? .green : .blue)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Port Card
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("PORT")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button {
                            showPortEditSheet = true
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "pencil")
                                Text("Ändern")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.blue)
                        }
                    }
                    HStack {
                        Text(String(liveCast.port))
                            .font(.system(.subheadline, design: .monospaced).bold())
                            .foregroundColor(.primary)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = String(liveCast.port)
                            copiedPort = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { copiedPort = false }
                        } label: {
                            Image(systemName: copiedPort ? "checkmark" : "doc.on.doc")
                                .font(.caption.bold())
                                .foregroundColor(copiedPort ? .green : .blue)
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // Full URL Box
            VStack(alignment: .leading, spacing: 6) {
                Text("VOLLSTÄNDIGE WEB-ADRESSE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                HStack {
                    Text(liveCast.serverURL)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer()

                    Button {
                        UIPasteboard.general.string = liveCast.serverURL
                        copiedURL = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            copiedURL = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedURL ? "checkmark" : "doc.on.doc")
                            Text(copiedURL ? "Kopiert!" : "Kopieren")
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(copiedURL ? Color.green : Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                }
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text("Wichtig: Immer **http://** (ohne „s“) eingeben. Moderne Browser setzen sonst automatisch ein fehlerhaftes https:// davor.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 2)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Settings & Viewer Stats Card

    var settingsCard: some View {
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(.blue)
                    Text("Verbundene Zuschauer:")
                        .font(.subheadline)
                }

                Spacer()

                Text("\(liveCast.viewerCount)")
                    .font(.headline.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(liveCast.viewerCount > 0 ? Color.blue.opacity(0.15) : Color(.systemGray5))
                    .foregroundColor(liveCast.viewerCount > 0 ? .blue : .secondary)
                    .clipShape(Capsule())
            }

            Divider()

            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "network")
                        .foregroundColor(.blue)
                    Text("Server-Port:")
                        .font(.subheadline)
                }

                Spacer()

                Text(String(liveCast.port))
                    .font(.system(.subheadline, design: .monospaced).bold())
                    .foregroundColor(.primary)

                Button("Ändern") {
                    showPortEditSheet = true
                }
                .font(.subheadline.bold())
                .foregroundColor(.blue)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Bildrate & Qualität")
                    .font(.subheadline.bold())

                Picker("FPS", selection: $liveCast.targetFPS) {
                    Text("10 FPS (Sparsam)").tag(10)
                    Text("20 FPS (Flüssig)").tag(20)
                    Text("30 FPS (Ultra)").tag(30)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Intro Card

    var introCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "tv.and.mediabox")
                .font(.system(size: 44))
                .foregroundColor(.blue)
                .padding(.top, 8)

            Text("Kein Apple TV nötig!")
                .font(.title3.bold())

            Text("Übertrage deine handschriftlichen Notizen, Formeln, Whiteboards und PAP-Diagramme in Echtzeit auf jeden Computer, Windows-PC, Android-Gerät, Smart-TV oder Beamer im selben WLAN.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            HStack(spacing: 8) {
                Image(systemName: "wifi")
                    .foregroundColor(.blue)
                    .font(.caption)
                Text("IP: **\(liveCast.localIP.isEmpty ? "WLAN prüfen" : liveCast.localIP)** • Port: **\(String(liveCast.port))**")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    showPortEditSheet = true
                } label: {
                    Text("Port ändern")
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                }
            }
            .padding(.top, 4)

            Button {
                liveCast.startStreaming()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("Live-Übertragung starten")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 4)
        }
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - PortSettingsSheet

struct PortSettingsSheet: View {
    @ObservedObject private var liveCast = LiveCastServer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var portText: String = ""
    @State private var validationError: String? = nil

    private let commonPorts: [(name: String, port: UInt16)] = [
        ("8080 (Standard)", 8080),
        ("8081 (Alternative 1)", 8081),
        ("8888 (Web-Port)", 8888),
        ("9090 (Netzwerk-Port)", 9090),
        ("5000 (Universal-Port)", 5000)
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                            Text("Apple-Netzwerkfreigabe")
                                .font(.subheadline.bold())
                        }
                        Text("Apple erlaubt Apps auf iOS & iPadOS die freie Belegung beliebiger unprivilegierter Ports zwischen **1024** und **65535** (Standard ist 8080).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Port eingeben") {
                    HStack {
                        Text("Server-Port:")
                            .font(.body.bold())
                        Spacer()
                        TextField("8080", text: $portText)
                            .keyboardType(.numberPad)
                            .font(.system(.body, design: .monospaced).bold())
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 130)
                            .onChange(of: portText) {
                                validationError = nil
                            }
                    }

                    if let err = validationError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                            Text(err)
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }

                Section("Häufig genutzte Ports") {
                    ForEach(commonPorts, id: \.port) { item in
                        Button {
                            portText = String(item.port)
                            validationError = nil
                        } label: {
                            HStack {
                                Text(item.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if portText == String(item.port) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                        .bold()
                                }
                            }
                        }
                    }
                }

                Section("Vorschau der Web-Adresse") {
                    let previewPort = portText.trimmingCharacters(in: .whitespacesAndNewlines)
                    HStack {
                        Text("Adresse:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("http://\(liveCast.localIP.isEmpty ? "192.168.x.x" : liveCast.localIP):\(previewPort.isEmpty ? "8080" : previewPort)")
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundColor(.blue)
                    }

                    if liveCast.isStreaming {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.orange)
                            Text("Der laufende Stream wird nach dem Speichern automatisch auf dem neuen Port fortgesetzt.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Server-Port anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        savePort()
                    }
                    .bold()
                }
            }
            .onAppear {
                portText = String(liveCast.port)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func savePort() {
        let cleaned = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = UInt16(cleaned), value >= 1024 && value <= 65535 else {
            validationError = "Ungültiger Port. Bitte eine Zahl zwischen 1024 und 65535 eingeben."
            return
        }
        let res = liveCast.updatePort(value)
        if res.success {
            dismiss()
        } else {
            validationError = res.message
        }
    }
}
