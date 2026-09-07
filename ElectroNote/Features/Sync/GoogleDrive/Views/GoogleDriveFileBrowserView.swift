import SwiftUI

struct GoogleDriveBreadcrumbItem: Identifiable, Hashable {
    let id = UUID()
    let folderId: String?
    let name: String
}

struct GoogleDriveFileBrowserView: View {
    let credentials: GoogleDriveCredentials
    let onPDFImport: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentFolderId: String? = nil
    @State private var folderPath: [GoogleDriveBreadcrumbItem] = [
        GoogleDriveBreadcrumbItem(folderId: nil, name: "Mein Google Drive")
    ]
    @State private var files: [GoogleDriveFile] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var importingFile: GoogleDriveFile?
    @State private var searchText = ""

    private var filteredFiles: [GoogleDriveFile] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return files
        } else {
            return files.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Breadcrumb path
                breadcrumbBar

                Divider()

                Group {
                    if isLoading && files.isEmpty {
                        ProgressView("Google Drive wird geladen…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let err = errorMessage {
                        ContentUnavailableView(err, systemImage: "xmark.icloud")
                    } else if filteredFiles.isEmpty {
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
            .navigationTitle(folderPath.last?.name ?? "Google Drive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await loadCurrentFolder() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .task {
                await loadCurrentFolder()
            }
            .overlay {
                if let item = importingFile {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("\(item.name) wird importiert…")
                                .font(.subheadline)
                                .bold()
                        }
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .cornerRadius(16)
                    }
                }
            }
        }
    }

    // MARK: - Breadcrumb bar

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(folderPath, id: \.id) { (entry: GoogleDriveBreadcrumbItem) in
                    let isLast = folderPath.last?.id == entry.id
                    if let first = folderPath.first, entry.id != first.id {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        navigateTo(item: entry)
                    } label: {
                        Text(entry.name)
                            .font(.subheadline)
                            .foregroundColor(isLast ? .primary : .blue)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - File list

    private var fileList: some View {
        List {
            ForEach(filteredFiles) { file in
                if file.isFolder {
                    Button {
                        navigateInto(folder: file)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name).font(.body).foregroundStyle(.primary)
                                Text("Ordner").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                } else {
                    let isPDF = file.name.lowercased().hasSuffix(".pdf")
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name).font(.body)
                                HStack(spacing: 6) {
                                    if !file.sizeFormatted.isEmpty {
                                        Text(file.sizeFormatted)
                                    }
                                    Text(file.lastModifiedDate.formatted(date: .abbreviated, time: .shortened))
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: isPDF ? "doc.richtext.fill" : "doc.fill")
                                .foregroundStyle(isPDF ? .red : .secondary)
                        }

                        Spacer()

                        if isPDF {
                            Button("Importieren") {
                                Task { await importPDF(file: file) }
                            }
                            .buttonStyle(.borderedProminent)
                            .font(.caption)
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Navigation & Actions

    private func navigateInto(folder: GoogleDriveFile) {
        folderPath.append(GoogleDriveBreadcrumbItem(folderId: folder.id, name: folder.name))
        currentFolderId = folder.id
        Task { await loadCurrentFolder() }
    }

    private func navigateTo(item: GoogleDriveBreadcrumbItem) {
        guard let idx = folderPath.firstIndex(where: { $0.id == item.id }) else { return }
        folderPath = Array(folderPath.prefix(idx + 1))
        currentFolderId = folderPath.last?.folderId
        Task { await loadCurrentFolder() }
    }

    private func loadCurrentFolder() async {
        isLoading = true
        errorMessage = nil
        let client = GoogleDriveClient(credentials: credentials)
        do {
            let fetched = try await client.listFiles(inFolderId: currentFolderId)
            files = fetched.sorted { ($0.isFolder ? 0 : 1, $0.name.lowercased()) < ($1.isFolder ? 0 : 1, $1.name.lowercased()) }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func importPDF(file: GoogleDriveFile) async {
        importingFile = file
        let client = GoogleDriveClient(credentials: credentials)
        do {
            let data = try await client.downloadFile(fileId: file.id)
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try data.write(to: tempURL, options: .atomic)
            importingFile = nil
            onPDFImport(tempURL)
            dismiss()
        } catch {
            importingFile = nil
            errorMessage = "Import fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
