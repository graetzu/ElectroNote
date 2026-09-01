import SwiftUI

// MARK: - Main sheet

struct SyncSettingsView: View {
    @StateObject private var vm: SyncViewModel
    @State private var serverInput = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let onPDFImport: (URL) -> Void

    init(localRoot: URL = FileService.defaultRootURL, onPDFImport: @escaping (URL) -> Void = { _ in }) {
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
    @State private var searchText = ""

    private var filteredItems: [DAVFile] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return vm.browserItems
        } else {
            return vm.browserItems.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Breadcrumb path header
                breadcrumbBar

                Divider()

                Group {
                    if vm.browserLoading && vm.browserItems.isEmpty {
                        ProgressView("Dateien werden geladen…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let err = vm.browserError {
                        ContentUnavailableView(err, systemImage: "xmark.icloud")
                    } else if filteredItems.isEmpty {
                        ContentUnavailableView(
                            "Keine Dateien gefunden",
                            systemImage: searchText.isEmpty ? "folder" : "magnifyingglass",
                            description: Text(searchText.isEmpty ? "Dieser Ordner ist leer." : "Keine Treffer für '\(searchText)'.")
                        )
                    } else {
                        fileList
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Dateien & Ordner suchen…")
            .navigationTitle(vm.browserPath.last?.name ?? "Nextcloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !vm.browserPath.isEmpty {
                        Button {
                            vm.navigateUp()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left")
                                Text("Zurück")
                            }
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(vm.browserLoading)
                }
            }
            .onAppear {
                if vm.browserItems.isEmpty {
                    vm.openBrowser()
                }
            }
        }
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    vm.navigateTo(index: -1)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "icloud.fill")
                        Text("Root")
                    }
                    .font(.caption.weight(vm.browserPath.isEmpty ? .bold : .regular))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(vm.browserPath.isEmpty ? Color.blue.opacity(0.15) : Color.clear)
                    .clipShape(Capsule())
                }

                ForEach(Array(vm.browserPath.enumerated()), id: \.element.davPath) { index, folder in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    let isLast = index == vm.browserPath.count - 1
                    Button {
                        vm.navigateTo(index: index)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                            Text(folder.name)
                        }
                        .font(.caption.weight(isLast ? .bold : .regular))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isLast ? Color.blue.opacity(0.15) : Color.clear)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(Color(.secondarySystemBackground))
    }

    private var fileList: some View {
        List(filteredItems, id: \.davPath) { file in
            if file.isDirectory {
                Button {
                    searchText = ""
                    vm.navigateInto(file)
                } label: {
                    HStack {
                        Label(file.name, systemImage: file.systemImage)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if file.isImportable {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.body)
                                .foregroundColor(.primary)
                            Text(file.isPDF ? "PDF-Dokument" : "Office / Dokument")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: file.systemImage)
                            .foregroundStyle(file.isPDF ? .red : .blue)
                    }
                    Spacer()
                    if importingFile?.davPath == file.davPath {
                        ProgressView()
                    } else {
                        Button("Einfügen") {
                            importingFile = file
                            Task {
                                if let url = await vm.downloadToTemp(file: file) {
                                    onPDFImport(url)
                                }
                                importingFile = nil
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.caption)
                    }
                }
            } else {
                Label(file.name, systemImage: file.systemImage)
                    .foregroundStyle(.secondary)
            }
        }
        .refreshable {
            await vm.refresh()
        }
    }
}

// MARK: - Helpers

private struct WrappedURL: Identifiable {
    let id = UUID()
    let url: URL
    init(_ url: URL) { self.url = url }
}
