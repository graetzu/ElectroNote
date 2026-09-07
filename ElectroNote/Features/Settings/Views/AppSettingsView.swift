import SwiftUI

struct AppSettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @ObservedObject private var syncManager = UnifiedSyncManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showICloudPicker = false
    @State private var showNextcloudBrowser = false
    @State private var showGoogleDriveBrowser = false
    @State private var showGoogleDriveLoginSheet = false
    @State private var nextcloudServerInput = ""

    // Callback when user imports a PDF from cloud inside Settings
    var onPDFImport: ((URL) -> Void)? = nil

    var body: some View {
        NavigationStack {
            Form {
                cloudSyncSection
                aiAssistantSection
                handwritingSection
                canvasSection
                aboutSection
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showICloudPicker) {
                DocumentPicker(contentTypes: [.folder]) { url in
                    syncManager.icloudEngine.setCustomFolder(url)
                }
            }
            .sheet(isPresented: $showNextcloudBrowser) {
                NextcloudFileBrowserView(vm: syncManager.nextcloudVM) { pdfURL in
                    showNextcloudBrowser = false
                    onPDFImport?(pdfURL)
                    dismiss()
                }
            }
            .sheet(isPresented: $showGoogleDriveBrowser) {
                if let creds = syncManager.googleDriveEngine.credentials {
                    GoogleDriveFileBrowserView(credentials: creds) { pdfURL in
                        showGoogleDriveBrowser = false
                        onPDFImport?(pdfURL)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showGoogleDriveLoginSheet) {
                GoogleDriveLoginSheet(engine: syncManager.googleDriveEngine)
            }
        }
    }

    // MARK: - 1. Cloud & Synchronisation

    private var cloudSyncSection: some View {
        Section {
            // Provider selector
            Picker("Cloud-Dienst", selection: $syncManager.activeProvider) {
                ForEach(SyncProvider.allCases) { provider in
                    Label(provider.shortName, systemImage: provider.icon)
                        .tag(provider)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)

            // Provider detail card
            switch syncManager.activeProvider {
            case .none:
                HStack(spacing: 12) {
                    Image(systemName: "internaldrive")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nur lokale Speicherung")
                            .font(.headline)
                        Text("Deine Notizen werden sicher und offline auf diesem iPad gesichert.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

            case .nextcloud:
                nextcloudConfigurationView

            case .icloud:
                icloudConfigurationView

            case .googleDrive:
                googleDriveConfigurationView
            }

            // Automatic Sync toggles (only if a cloud provider is active)
            if syncManager.activeProvider != .none {
                Toggle("Beim Start der App synchronisieren", isOn: $syncManager.autoSyncOnLaunch)
                Toggle("Beim Speichern / Schließen synchronisieren", isOn: $syncManager.autoSyncOnSave)
            }

        } header: {
            Label("Cloud & Synchronisation", systemImage: "arrow.triangle.2.circlepath.icloud")
        } footer: {
            if syncManager.activeProvider == .none {
                Text("Wähle einen Dienst wie Nextcloud, iCloud Drive oder Google Drive, um deine Notizen zwischen iPad, Mac und anderen Geräten synchron zu halten.")
            }
        }
    }

    // MARK: - Nextcloud Subview

    @ViewBuilder
    private var nextcloudConfigurationView: some View {
        let ncVM = syncManager.nextcloudVM

        if let creds = ncVM.credentials {
            // Connected
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.connected.to.line.below.fill")
                    .font(.title2)
                    .foregroundStyle(Color.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(creds.loginName).font(.headline)
                    Text(creds.displayHost).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abmelden", role: .destructive) {
                    ncVM.logout()
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
            .padding(.vertical, 2)

            if let d = ncVM.lastSynced {
                HStack {
                    Label("Zuletzt synchronisiert", systemImage: "clock")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(d.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            if ncVM.syncState.isActive {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text(ncVM.progressMessage ?? "Synchronisieren…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if case .done(let summary) = ncVM.syncState {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if case .failed(let err) = ncVM.syncState {
                Label(err, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button {
                    ncVM.sync()
                } label: {
                    Label("Jetzt synchronisieren", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(ncVM.syncState.isActive)

                Spacer()

                Button {
                    showNextcloudBrowser = true
                } label: {
                    Label("Dateien durchsuchen", systemImage: "folder")
                }
            }

        } else {
            // Not connected
            VStack(alignment: .leading, spacing: 8) {
                Text("Nextcloud-Server verbinden")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack {
                    TextField("https://cloud.example.com", text: $nextcloudServerInput)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Button("Verbinden") {
                        ncVM.connect(serverURL: nextcloudServerInput)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(nextcloudServerInput.trimmingCharacters(in: .whitespaces).isEmpty || ncVM.loginFlow.isLoading)
                }

                if ncVM.loginFlow.isLoading {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("Anmeldung in Safari geöffnet…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - iCloud Subview

    @ViewBuilder
    private var icloudConfigurationView: some View {
        let icloud = syncManager.icloudEngine

        HStack(spacing: 12) {
            Image(systemName: "icloud.fill")
                .font(.title2)
                .foregroundStyle(Color(red: 0.20, green: 0.60, blue: 1.0))

            VStack(alignment: .leading, spacing: 2) {
                Text("Apple iCloud Drive")
                    .font(.headline)
                Text(icloud.statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)

        if let d = icloud.lastSynced {
            HStack {
                Label("Zuletzt synchronisiert", systemImage: "clock")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(d.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }

        if icloud.isSyncing {
            HStack {
                ProgressView().scaleEffect(0.8)
                Text(syncManager.progressMessage ?? "iCloud synchronisiert…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let summary = icloud.lastSummary {
            Label(summary, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if let err = icloud.errorMessage {
            Label(err, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }

        HStack {
            Button {
                Task {
                    _ = await icloud.sync { _ in }
                }
            } label: {
                Label("Jetzt abgleichen", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(icloud.isSyncing)

            Spacer()

            Button {
                showICloudPicker = true
            } label: {
                Label(icloud.customFolderName == nil ? "Ordner wählen…" : "Ordner ändern…", systemImage: "folder.badge.gearshape")
            }
        }

        if icloud.customFolderName != nil {
            Button("Standard-App-Container wiederherstellen", role: .destructive) {
                icloud.clearCustomFolder()
            }
            .font(.caption)
        }
    }

    // MARK: - Google Drive Subview

    @ViewBuilder
    private var googleDriveConfigurationView: some View {
        let gdrive = syncManager.googleDriveEngine

        if let creds = gdrive.credentials {
            HStack(spacing: 12) {
                Image(systemName: "tray.and.arrow.up.fill")
                    .font(.title2)
                    .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.15))

                VStack(alignment: .leading, spacing: 2) {
                    Text(creds.userName ?? "Google Drive")
                        .font(.headline)
                    Text(creds.userEmail ?? "Verbunden")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Abmelden", role: .destructive) {
                    gdrive.logout()
                }
                .buttonStyle(.bordered)
                .font(.caption)
            }
            .padding(.vertical, 2)

            if let d = gdrive.lastSynced {
                HStack {
                    Label("Zuletzt synchronisiert", systemImage: "clock")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(d.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            if gdrive.isSyncing {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text(gdrive.progressMessage ?? "Google Drive synchronisiert…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let summary = gdrive.lastSummary {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if let err = gdrive.errorMessage {
                Label(err, systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button {
                    Task {
                        _ = await gdrive.sync { _ in }
                    }
                } label: {
                    Label("Jetzt abgleichen", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(gdrive.isSyncing)

                Spacer()

                Button {
                    showGoogleDriveBrowser = true
                } label: {
                    Label("Dateien durchsuchen", systemImage: "folder")
                }
            }

        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Google Drive verbinden")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Synchronisiere deine Notizen direkt mit einem 'ElectroNote'-Ordner in Google Drive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    showGoogleDriveLoginSheet = true
                } label: {
                    Label("Google-Konto verbinden", systemImage: "person.badge.key.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.95, green: 0.65, blue: 0.15))
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 2. KI-Assistent & Abos

    private var aiAssistantSection: some View {
        Section {
            Picker("Standard-Modell", selection: $vm.defaultAIProvider) {
                ForEach(AIProvider.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }

            Picker("Fachbereich / Kontext", selection: $vm.aiDomainFocus) {
                ForEach(AIDomainFocus.allCases) { focus in
                    Text(focus.rawValue).tag(focus)
                }
            }

            Text(vm.aiDomainFocus.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if vm.aiDomainFocus == .custom {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Eigener System-Prompt-Zusatz:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("z. B. 'Du bist Experte für Gebäudeautomation…'", text: $vm.customPromptText, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // AI Session Reset Button
            Button(role: .destructive) {
                vm.resetAICacheAndCookies()
            } label: {
                HStack {
                    Label("KI-Sitzungsdaten & Cookies zurücksetzen", systemImage: "arrow.clockwise.circle")
                    if vm.isClearingAICache {
                        Spacer()
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }

            if vm.aiCacheClearedSuccess {
                Label("Sitzung erfolgreich zurückgesetzt. Du kannst dich neu anmelden.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

        } header: {
            Label("KI-Assistent & Abos", systemImage: "sparkles")
        } footer: {
            Text("ElectroNote nutzt die Web-Oberflächen von ChatGPT, Claude und Gemini mit deinem persönlichen Abo (keine Token-Kosten). Deine Sitzung bleibt lokal gespeichert.")
        }
    }

    // MARK: - 3. Handschrift & Suche

    private var handwritingSection: some View {
        Section {
            Toggle("Handschrifterkennung (OCR)", isOn: $vm.handwritingOCRActive)

            HStack {
                Label("Suchindex-Status", systemImage: "magnifyingglass")
                Spacer()
                Text("\(vm.indexedDocCount) Notizen · \(vm.indexedChunkCount) Einträge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                vm.rebuildFullIndex()
            } label: {
                HStack {
                    Label("Suchindex komplett neu aufbauen", systemImage: "arrow.triangle.2.circlepath")
                    if vm.isReindexing {
                        Spacer()
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .disabled(vm.isReindexing)

        } header: {
            Label("Handschrift & Suche", systemImage: "text.viewfinder")
        } footer: {
            Text("Durchsucht handschriftliche Notizen, Formeln und importierte PDF-Texte blitzschnell lokal auf dem Gerät (Apple Vision).")
        }
    }

    // MARK: - 4. Canvas & Layout

    private var canvasSection: some View {
        Section {
            Picker("Standard-Raster", selection: $vm.defaultBackground) {
                ForEach(BackgroundStyle.allCases) { style in
                    Label(style.rawValue, systemImage: style.symbolName).tag(style)
                }
            }

            Picker("Standard-Linienabstand", selection: $vm.defaultLineSpacing) {
                ForEach(LineSpacing.allCases) { spacing in
                    Text(spacing.rawValue).tag(spacing)
                }
            }

        } header: {
            Label("Canvas & Notizbuch-Standards", systemImage: "square.grid.3x3.square")
        }
    }

    // MARK: - 5. Über ElectroNote

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0 (Build 2026.09)")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Lokaler Notiz-Speicher")
                Spacer()
                Text(vm.storageUsageFormatted)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Datenschutz")
                Spacer()
                Text("100% lokal auf deinem iPad")
                    .foregroundStyle(.secondary)
            }

        } header: {
            Label("Über ElectroNote", systemImage: "info.circle")
        }
    }
}

// MARK: - Google Drive Login Sheet

struct GoogleDriveLoginSheet: View {
    @ObservedObject var engine: GoogleDriveSyncEngine
    @Environment(\.dismiss) private var dismiss

    @State private var tokenInput = ""
    @State private var emailInput = ""
    @State private var nameInput = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Gib dein Google OAuth 2.0 Access Token oder deine API-Zugangsdaten ein, um ElectroNote mit Google Drive zu verknüpfen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("OAuth Access Token", text: $tokenInput)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Google E-Mail (optional)", text: $emailInput)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Name (optional)", text: $nameInput)
                        .textFieldStyle(.roundedBorder)

                } header: {
                    Label("Zugangsdaten", systemImage: "key.fill")
                } footer: {
                    Text("Das Token wird sicher im verschlüsselten Apple Keychain dieses iPads gespeichert.")
                }

                Section {
                    Button {
                        isSaving = true
                        Task {
                            await engine.login(
                                accessToken: tokenInput.trimmingCharacters(in: .whitespacesAndNewlines),
                                email: emailInput.isEmpty ? nil : emailInput.trimmingCharacters(in: .whitespacesAndNewlines),
                                name: nameInput.isEmpty ? nil : nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        if isSaving {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Speichern & Verbinden").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .navigationTitle("Google Drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}
