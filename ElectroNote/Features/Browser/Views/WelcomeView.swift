import SwiftUI

struct WelcomeView: View {
    var selectedItemName: String? = nil
    var viewModel: BrowserViewModel? = nil
    var onSelectDocument: ((DocumentItem) -> Void)? = nil

    @ObservedObject private var collab = LiveCollabSessionManager.shared
    @ObservedObject private var liveCast = LiveCastServer.shared

    @State private var showDocTypePicker = false
    @State private var pendingDocType: DocumentType? = nil
    @State private var showNewDocNameSheet = false

    @State private var showCollabSheet = false
    @State private var collabInitialTab = 1
    @State private var showLiveCastSheet = false

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "note.text.badge.plus")
                .font(.system(size: 58))
                .foregroundStyle(.blue.gradient)

            if let name = selectedItemName {
                Text(name)
                    .font(.title2.bold())
                Text("Viewer für diesen Dateityp folgt in der nächsten Phase.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                VStack(spacing: 8) {
                    Text("InfiniteNote")
                        .font(.largeTitle.bold())
                    Text("Erstelle ein neues Dokument oder wähle eines aus der Seitenleiste.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Primary centered action: Create New Document
                Button {
                    showDocTypePicker = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                        Text("Neues Dokument erstellen…")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 14)
                    .background(Color.blue.gradient)
                    .clipShape(Capsule())
                    .shadow(color: .blue.opacity(0.32), radius: 8, y: 4)
                }
                .padding(.top, 6)

                // Secondary subtle submenu for Live Session / Cast
                Menu {
                    Section("Live-Zusammenarbeit") {
                        Button {
                            collabInitialTab = 0
                            showCollabSheet = true
                        } label: {
                            Label("Sitzung hosten…", systemImage: "person.2.wave.2.fill")
                        }

                        Button {
                            collabInitialTab = 1
                            showCollabSheet = true
                        } label: {
                            Label("Sitzung beitreten…", systemImage: "arrow.right.circle.fill")
                        }
                    }

                    Section("Bildschirmübertragung") {
                        Button {
                            showLiveCastSheet = true
                        } label: {
                            Label("WLAN Live-Übertragung (Cast)…", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if collab.sessionState == .hosting || collab.sessionState == .connected {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                        } else if liveCast.isStreaming {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                        } else {
                            Image(systemName: "person.2.wave.2")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("Live-Sitzung")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                    )
                }
            }
        }
        .sheet(isPresented: $showDocTypePicker) {
            DocumentTypePickerView { docType in
                pendingDocType = docType
                showDocTypePicker = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showNewDocNameSheet = true
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showNewDocNameSheet) {
            NewItemSheet(title: "Neues Dokument", placeholder: "Name") { name in
                guard let vm = viewModel else { return }
                let created: DocumentItem?
                if let type = pendingDocType {
                    created = vm.createDocument(named: name, type: type)
                } else {
                    created = vm.createNote(named: name)
                }
                pendingDocType = nil
                if let item = created {
                    onSelectDocument?(item)
                }
            }
        }
        .sheet(isPresented: $showCollabSheet) {
            LiveCollabSheetView(documentName: "Live-Zusammenarbeit", documentType: .note, initialTab: collabInitialTab)
        }
        .sheet(isPresented: $showLiveCastSheet) {
            LiveCastSheetView()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
