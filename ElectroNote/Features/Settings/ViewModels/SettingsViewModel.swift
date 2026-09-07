import Foundation
import SwiftUI
import WebKit

enum AIDomainFocus: String, CaseIterable, Identifiable {
    case electrical  = "Elektrotechnik (DIN VDE)"
    case school      = "Schule & Ausbildung"
    case engineering = "Ingenieurstudium"
    case neutral     = "Standard / Neutral"
    case custom      = "Benutzerdefiniert"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .electrical:
            return "Optimiert für Fachbegriffe, DIN VDE Normen, Schutzmaßnahmen und Prüfungsvorbereitung."
        case .school:
            return "Erklärt Zusammenhänge anschaulich und didaktisch mit einfachen Worten."
        case .engineering:
            return "Fokus auf exakte mathematische Herleitungen, Formeln und physikalische Zusammenhänge."
        case .neutral:
            return "Neutrale und direkte Beantwortung ohne fachspezifische Rollenanpassung."
        case .custom:
            return "Verwendet deinen eigenen eingegebenen Prompt-Zusatz."
        }
    }

    var promptPrefix: String {
        switch self {
        case .electrical:
            return "Du bist ein erfahrener Fachlehrer und Prüfungsmeister für Elektrotechnik (DIN VDE, Schutzmaßnahmen, Schaltungsanalyse). Antworte fachlich präzise nach geltenden deutschen VDE-Normen."
        case .school:
            return "Du bist ein verständlicher Tutor für Schule und Berufsausbildung. Erkläre Sachverhalte anschaulich mit Beispielen und einfachen Worten."
        case .engineering:
            return "Du bist ein Dozent für Ingenieurwissenschaften und angewandte Physik. Berücksichtige mathematische Herleitungen, SI-Einheiten und Berechnungen."
        case .neutral:
            return "Du bist ein hilfreicher und präziser Studien- und Notizassistent."
        case .custom:
            return ""
        }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Sync Manager Reference
    @ObservedObject var syncManager = UnifiedSyncManager.shared

    // MARK: - AI Settings
    @Published var defaultAIProvider: AIProvider {
        didSet {
            UserDefaults.standard.set(defaultAIProvider.rawValue, forKey: "electroNote_lastAIProvider")
        }
    }

    @Published var aiDomainFocus: AIDomainFocus {
        didSet {
            UserDefaults.standard.set(aiDomainFocus.rawValue, forKey: "electroNote_aiDomainFocus")
        }
    }

    @Published var customPromptText: String {
        didSet {
            UserDefaults.standard.set(customPromptText, forKey: "electroNote_aiCustomPrompt")
        }
    }

    @Published var isClearingAICache = false
    @Published var aiCacheClearedSuccess = false

    // MARK: - Handwriting & Indexing
    @Published var handwritingOCRActive: Bool {
        didSet {
            UserDefaults.standard.set(handwritingOCRActive, forKey: "electroNote_ocrEnabled")
        }
    }

    @Published var indexedDocCount: Int = 0
    @Published var indexedChunkCount: Int = 0
    @Published var isReindexing: Bool = false

    // MARK: - Canvas Preferences
    @Published var defaultBackground: BackgroundStyle {
        didSet {
            UserDefaults.standard.set(defaultBackground.rawValue, forKey: "electroNote_defaultBackground")
        }
    }

    @Published var defaultLineSpacing: LineSpacing {
        didSet {
            UserDefaults.standard.set(defaultLineSpacing.rawValue, forKey: "electroNote_defaultLineSpacing")
        }
    }

    // MARK: - Storage Info
    @Published var storageUsageFormatted: String = "Berechne…"

    init() {
        // AI
        let aiRaw = UserDefaults.standard.string(forKey: "electroNote_lastAIProvider") ?? AIProvider.chatGPT.rawValue
        self.defaultAIProvider = AIProvider(rawValue: aiRaw) ?? .chatGPT

        let focusRaw = UserDefaults.standard.string(forKey: "electroNote_aiDomainFocus") ?? AIDomainFocus.electrical.rawValue
        self.aiDomainFocus = AIDomainFocus(rawValue: focusRaw) ?? .electrical

        self.customPromptText = UserDefaults.standard.string(forKey: "electroNote_aiCustomPrompt") ?? ""

        // Handwriting
        self.handwritingOCRActive = UserDefaults.standard.object(forKey: "electroNote_ocrEnabled") as? Bool ?? true

        // Canvas
        let bgRaw = UserDefaults.standard.string(forKey: "electroNote_defaultBackground") ?? BackgroundStyle.grid.rawValue
        self.defaultBackground = BackgroundStyle(rawValue: bgRaw) ?? .grid

        let spaceRaw = UserDefaults.standard.string(forKey: "electroNote_defaultLineSpacing") ?? LineSpacing.medium.rawValue
        self.defaultLineSpacing = LineSpacing(rawValue: spaceRaw) ?? .medium

        Task {
            await refreshIndexStats()
            await calculateStorage()
        }
    }

    // MARK: - AI Cache Reset

    func resetAICacheAndCookies() {
        isClearingAICache = true
        let dataStore = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let epoch = Date(timeIntervalSince1970: 0)

        dataStore.removeData(ofTypes: types, modifiedSince: epoch) { [weak self] in
            DispatchQueue.main.async {
                self?.isClearingAICache = false
                self?.aiCacheClearedSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self?.aiCacheClearedSuccess = false
                }
            }
        }
    }

    // MARK: - Index Management

    func refreshIndexStats() async {
        let stats = await NoteSearchDatabase.shared.getIndexStats()
        self.indexedDocCount = stats.docCount
        self.indexedChunkCount = stats.entryCount
    }

    func rebuildFullIndex() {
        guard !isReindexing else { return }
        isReindexing = true

        Task {
            await NoteSearchDatabase.shared.clearAllIndex()
            NoteIndexingService.shared.startIndexingAllDocuments(fileService: FileService())
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await self.refreshIndexStats()
            self.isReindexing = false
        }
    }

    // MARK: - Storage

    func calculateStorage() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let root = FileService.defaultRootURL
                var totalBytes: Int64 = 0
                if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey], options: []) {
                    for case let fileURL as URL in enumerator {
                        if let res = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                           let size = res.fileSize {
                            totalBytes += Int64(size)
                        }
                    }
                }
                let formatted = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
                DispatchQueue.main.async {
                    self.storageUsageFormatted = formatted
                    continuation.resume()
                }
            }
        }
    }
}
