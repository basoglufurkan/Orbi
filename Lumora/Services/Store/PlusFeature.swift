import Foundation

/// What Orbi+ adds. Stars, the universe, the Odyssey, Year in review and
/// focusing together stay free; stardust is never sold.
enum PlusFeature: String, CaseIterable, Identifiable, Sendable {
    case skyThemes, ambience, shipFinishes, history, export

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .skyThemes: "paintpalette.fill"
        case .ambience: "waveform"
        case .shipFinishes: "airplane"
        case .history: "clock.arrow.circlepath"
        case .export: "tablecells"
        }
    }

    var title: String {
        switch self {
        case .skyThemes: String(localized: "Sky themes")
        case .ambience: String(localized: "Every soundscape")
        case .shipFinishes: String(localized: "Rare ship finishes")
        case .history: String(localized: "Your whole history")
        case .export: String(localized: "Spreadsheet export")
        }
    }

    var detail: String {
        switch self {
        case .skyThemes: String(localized: "Paint your sky in aurora, ember, ocean or eclipse light.")
        case .ambience: String(localized: "Rain, tides, solar wind and a crackling campfire while you focus.")
        case .shipFinishes: String(localized: "Eclipse and Opal paints and a Supernova trail, still earned with stardust.")
        case .history: String(localized: "Look back at any week or month, not just this one.")
        case .export: String(localized: "Every session as a CSV file, ready for any spreadsheet.")
        }
    }
}
