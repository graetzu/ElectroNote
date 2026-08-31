import Foundation

struct ClipArtEntry: Identifiable {
    let id: String          // SF Symbol name
    let label: String
    let category: Category

    enum Category: String, CaseIterable {
        case arrows       = "Pfeile"
        case shapes       = "Formen"
        case electrical   = "Elektrotechnik"
        case math         = "Mathematik"
        case general      = "Allgemein"
    }
}

enum ClipArtLibrary {
    static let catalog: [ClipArtEntry] = arrows + shapes + electrical + math + general

    static let arrows: [ClipArtEntry] = [
        .init(id: "arrow.right",                  label: "Pfeil rechts",     category: .arrows),
        .init(id: "arrow.left",                   label: "Pfeil links",      category: .arrows),
        .init(id: "arrow.up",                     label: "Pfeil oben",       category: .arrows),
        .init(id: "arrow.down",                   label: "Pfeil unten",      category: .arrows),
        .init(id: "arrow.right.circle.fill",      label: "Pfeil Kreis",      category: .arrows),
        .init(id: "arrow.clockwise",              label: "Uhrzeiger",        category: .arrows),
        .init(id: "arrow.counterclockwise",       label: "Gegen-UZS",       category: .arrows),
        .init(id: "arrow.triangle.2.circlepath",  label: "Drehfeld",         category: .arrows),
        .init(id: "arrow.right.arrow.left",       label: "Bidirektional",    category: .arrows),
        .init(id: "arrow.up.arrow.down",          label: "Auf/Ab",           category: .arrows),
    ]

    static let shapes: [ClipArtEntry] = [
        .init(id: "circle",               label: "Kreis",         category: .shapes),
        .init(id: "circle.fill",          label: "Kreis (voll)",  category: .shapes),
        .init(id: "square",               label: "Quadrat",       category: .shapes),
        .init(id: "square.fill",          label: "Quadrat (voll)",category: .shapes),
        .init(id: "triangle",             label: "Dreieck",       category: .shapes),
        .init(id: "triangle.fill",        label: "Dreieck (voll)",category: .shapes),
        .init(id: "diamond",              label: "Raute",         category: .shapes),
        .init(id: "diamond.fill",         label: "Raute (voll)",  category: .shapes),
        .init(id: "rectangle",            label: "Rechteck",      category: .shapes),
        .init(id: "oval",                 label: "Oval",          category: .shapes),
        .init(id: "star",                 label: "Stern",         category: .shapes),
    ]

    static let electrical: [ClipArtEntry] = [
        .init(id: "bolt",                                   label: "Spannung",        category: .electrical),
        .init(id: "bolt.fill",                              label: "Spannung (voll)", category: .electrical),
        .init(id: "bolt.circle.fill",                       label: "Spannung Kreis",  category: .electrical),
        .init(id: "waveform",                               label: "Welle",           category: .electrical),
        .init(id: "waveform.path.ecg",                      label: "Oszillogramm",    category: .electrical),
        .init(id: "lightbulb",                              label: "Glühlampe",       category: .electrical),
        .init(id: "lightbulb.fill",                         label: "Glühlampe (an)",  category: .electrical),
        .init(id: "battery.100",                            label: "Batterie voll",   category: .electrical),
        .init(id: "battery.50",                             label: "Batterie halb",   category: .electrical),
        .init(id: "power",                                  label: "Ein/Aus",         category: .electrical),
        .init(id: "gauge",                                  label: "Messgerät",       category: .electrical),
        .init(id: "thermometer",                            label: "Temperatur",      category: .electrical),
        .init(id: "fan",                                    label: "Motor/Lüfter",    category: .electrical),
        .init(id: "cpu",                                    label: "Prozessor",       category: .electrical),
        .init(id: "memorychip",                             label: "Chip",            category: .electrical),
        .init(id: "antenna.radiowaves.left.and.right",      label: "Antenne",         category: .electrical),
        .init(id: "switch.2",                               label: "Schalter",        category: .electrical),
        .init(id: "cable.connector",                        label: "Stecker",         category: .electrical),
    ]

    static let math: [ClipArtEntry] = [
        .init(id: "plus",               label: "Plus",        category: .math),
        .init(id: "minus",              label: "Minus",       category: .math),
        .init(id: "multiply",           label: "Mal",         category: .math),
        .init(id: "divide",             label: "Geteilt",     category: .math),
        .init(id: "equal",              label: "Gleich",      category: .math),
        .init(id: "plusminus",          label: "Plus/Minus",  category: .math),
        .init(id: "infinity",           label: "Unendlich",   category: .math),
        .init(id: "percent",            label: "Prozent",     category: .math),
        .init(id: "sum",                label: "Summe",       category: .math),
        .init(id: "x.squareroot",       label: "Wurzel",      category: .math),
        .init(id: "function",           label: "Funktion",    category: .math),
    ]

    static let general: [ClipArtEntry] = [
        .init(id: "checkmark.circle.fill",    label: "Richtig",       category: .general),
        .init(id: "xmark.circle.fill",        label: "Falsch",        category: .general),
        .init(id: "exclamationmark.triangle", label: "Achtung",       category: .general),
        .init(id: "info.circle",              label: "Info",          category: .general),
        .init(id: "questionmark.circle",      label: "Frage",         category: .general),
        .init(id: "1.circle.fill",            label: "1",             category: .general),
        .init(id: "2.circle.fill",            label: "2",             category: .general),
        .init(id: "3.circle.fill",            label: "3",             category: .general),
        .init(id: "a.circle.fill",            label: "A",             category: .general),
        .init(id: "b.circle.fill",            label: "B",             category: .general),
    ]

    static func search(_ query: String) -> [ClipArtEntry] {
        guard !query.isEmpty else { return catalog }
        return catalog.filter {
            $0.label.localizedCaseInsensitiveContains(query) ||
            $0.id.localizedCaseInsensitiveContains(query)
        }
    }
}
