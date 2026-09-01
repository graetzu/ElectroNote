import SwiftUI

// MARK: - Main sheet

struct SyncSettingsView: View {
    @StateObject private var vm: SyncViewModel
    @State private var serverInput = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let onPDFImport: (URL) -> Void

    init(localRoot: URL, onPDFImport: @escaping (URL) -> Void) {
        self.onPDFImport = onPDFImport
        _vm = StateObject(wrappedValue: SyncViewModel(localRoot: localRoot))
    }

    var body: some View {
        NavigationStack {
            Form {
                if vm.credentials == nil {
                    loginSection
                } else {
                    accountSection
                    syncSection
                    fileBrowserSection
                }
            }
            .navigationTitle("Nextcloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
            }
            // Open login URL in Safari; background poll in NextcloudLoginFlow handles the rest
            .onChange(of: vm.loginFlow.loginURL) { url in
                if let url { openURL(url) }
            }
            // Nextcloud file browser
            .sheet(isPresented: $vm.isBrowsing) {
                NextcloudFileBrowserView(vm: vm, onPDFImport: { url in
                    vm.isBrowsing = false
                    onPDFImport(url)
                    dismiss()
                })
            }
        }
    }

    // MARK: - Login section

    private var loginSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "icloud.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                Text("Nextcloud verbinden")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, alignment: .center)

                Text("Gib deine Nextcloud-Adresse ein. Du wirst zur Anmeldemaske in Safari weitergeleitet. Nach der Anmeldung kehre zu ElectroNote zurück.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 4)

            TextField("https://meincloud.example.com", text: $serverInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)

            if let err = vm.loginFlow.errorMessage {
                Label(err, systemImage: "xmark.circle").foregroundStyle(.red).font(.caption)
            }

            if vm.loginFlow.loginURL != nil {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Warte auf Anmeldung in Safari…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)

                Button(role: .cancel) {
                    vm.loginFlow.cancel()
                } label: {
                    Text("Abbrechen").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    vm.connect(serverURL: serverInput)
                } label: {
                    if vm.loginFlow.isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Mit Nextcloud verbinden").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(serverInput.trimmingCharacters(in: .whitespaces).isEmpty || vm.loginFlow.isLoading)
            }
        }
    }

    // MARK: - Account section

    private var accountSection: some View {
        Section("Verbunden") {
            if let creds = vm.credentials {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(creds.loginName).font(.headline)
                        Text(creds.displayHost).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "person.crop.circle.fill").foregroundStyle(.blue)
                }

                Button(role: .destructive) { vm.logout() } label: {
                    Label("Abmelden", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }

    // MARK: - Sync section

    private var syncSection: some View {
        Section("Synchronisation") {
            if let d = vm.lastSynced {
                Label {
                    Text("Zuletzt: \(d.formatted(date: .abbreviated, time: .shortened))")
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "checkmark.icloud").foregroundStyle(.green)
                }
            }

            switch vm.syncState {
            case .syncing:
                HStack {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Synchronisieren…")
                        if let msg = vm.progressMessage {
                            Text(msg).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            case .done(let msg):
                Label(msg, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed(let msg):
                Label(msg, systemImage: "xmark.circle.fill").foregroundStyle(.red)
            case .idle:
                EmptyView()
            }

            Button {
                vm.sync()
            } label: {
                Label("Jetzt synchronisieren", systemImage: "arrow.triangle.2.circlepath.icloud")
            }
            .disabled(vm.syncState.isActive)
        }
    }

    // MARK: - File browser section

    private var fileBrowserSection: some View {
        Section("Nextcloud-Dateien") {
            Button {
                vm.openBrowser()
            } label: {
                Label("Dateien durchsuchen", systemImage: "folder.badge.questionmark")
            }
        }
    }
}

// MARK: - Nextcloud File Browser

struct NextcloudFileBrowserView: View {
    @ObservedObject var vm: SyncViewModel
    let onPDFImport: (URL) -> Void
    @State private var importingFile: DAVFile?

    var body: some View {
        NavigationStack {
            Group {
                if vm.browserLoading {
                    ProgressView("Lädt…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = vm.browserError {
                    ContentUnavailableView(err, systemImage: "xmark.icloud")
                } else if vm.browserItems.isEmpty {
                    ContentUnavailableView("Leer", systemImage: "folder")
                } else {
                    fileList
                }
            }
            .navigationTitle(vm.browserPath.last?.name ?? "Nextcloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if vm.browserPath.isEmpty {
                        EmptyView()
                    } else {
                        Button {
                            vm.navigateUp()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left")
                                Text(vm.browserPath.dropLast().last?.name ?? "Nextcloud")
                            }
                        }
                    }
                }
            }
        }
    }

    private var fileList: some View {
        List(vm.browserItems, id: \.davPath) { file in
            if file.isDirectory {
                Button {
                    vm.navigateInto(file)
                } label: {
                    Label(file.name, systemImage: file.systemImage)
                        .foregroundStyle(.primary)
                }
            } else if file.isPDF {
                HStack {
                    Label {
                        Text(file.name)
                    } icon: {
                        Image(systemName: file.systemImage).foregroundStyle(.red)
                    }
                    Spacer()
                    if importingFile?.davPath == file.davPath {
                        ProgressView()
                    } else {
                        Button("Importieren") {
                            importingFile = file
                            Task {
                                if let url = await vm.downloadToTemp(file: file) {
                                    onPDFImport(url)
                                }
                                importingFile = nil
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
            } else {
                Label(file.name, systemImage: file.systemImage)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Helpers

private struct WrappedURL: Identifiable {
    let id = UUID()
    let url: URL
    init(_ url: URL) { self.url = url }
}
