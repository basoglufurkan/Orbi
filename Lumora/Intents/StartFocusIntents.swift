import AppIntents
import Foundation

extension FocusCategory: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static let caseDisplayRepresentations: [FocusCategory: DisplayRepresentation] = [
        .study: DisplayRepresentation(title: "Study", image: .init(systemName: "book.closed")),
        .work: DisplayRepresentation(title: "Work", image: .init(systemName: "briefcase")),
        .coding: DisplayRepresentation(title: "Coding", image: .init(systemName: "chevron.left.forwardslash.chevron.right")),
        .reading: DisplayRepresentation(title: "Reading", image: .init(systemName: "text.book.closed")),
        .creative: DisplayRepresentation(title: "Creative", image: .init(systemName: "paintbrush")),
    ]
}

extension AmbientSound: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Ambience"
    static let caseDisplayRepresentations: [AmbientSound: DisplayRepresentation] = [
        .silence: "Silence",
        .deepSpace: "Deep space hum",
        .rain: "Rain on glass",
        .tides: "Slow tides",
        .brownNoise: "Brown noise",
        .solarWind: "Solar wind",
        .campfire: "Campfire",
    ]
}

/// The setup screen's preset lengths, as a spoken parameter
/// ("Start a 25 minute focus in Orbi"). Phrases can only interpolate
/// enums and entities, not free integers.
enum FocusLength: String, AppEnum {
    case fifteen = "15", twentyFive = "25", fortyFive = "45", sixty = "60"

    var minutes: Int { Int(rawValue) ?? 25 }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Length"
    static let caseDisplayRepresentations: [FocusLength: DisplayRepresentation] = [
        .fifteen: DisplayRepresentation(title: "15 minutes", synonyms: ["15 minute", "15-minute", "fifteen minute"]),
        .twentyFive: DisplayRepresentation(title: "25 minutes", synonyms: ["25 minute", "25-minute", "twenty-five minute", "pomodoro"]),
        .fortyFive: DisplayRepresentation(title: "45 minutes", synonyms: ["45 minute", "45-minute", "forty-five minute"]),
        .sixty: DisplayRepresentation(title: "60 minutes", synonyms: ["60 minute", "60-minute", "one hour", "an hour"]),
    ]
}

/// Starts a focus session without opening the app. A `LiveActivityIntent`
/// so the Live Activity can start while Lumora is in the background.
struct StartFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Focus"
    static let description = IntentDescription(
        "Starts an Orbi focus session without opening the app. Uses your default length and last category unless you choose.")

    @Parameter(title: "Minutes", description: "From 5 to 180. Leave empty for your default length.",
               inclusiveRange: (5, 180))
    var minutes: Int?

    @Parameter(title: "Category", description: "Leave empty for your last category.")
    var category: FocusCategory?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes) minute \(\.$category) focus")
    }

    init() {}

    init(minutes: Int?, category: FocusCategory?) {
        self.minutes = minutes
        self.category = category
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try FocusIntentRunner.live().start(minutes: minutes, category: category)
        return .result(dialog: outcome.dialog)
    }
}

/// "Start a 25 minute focus in Orbi" — same as `StartFocusIntent`, with
/// the length as a spoken preset.
struct StartTimedFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Timed Focus"
    static let description = IntentDescription("Starts a 15, 25, 45 or 60 minute Orbi focus session.")

    @Parameter(title: "Length")
    var length: FocusLength

    @Parameter(title: "Category", description: "Leave empty for your last category.")
    var category: FocusCategory?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$length) \(\.$category) focus")
    }

    init() {}

    init(length: FocusLength, category: FocusCategory? = nil) {
        self.length = length
        self.category = category
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try FocusIntentRunner.live().start(minutes: length.minutes, category: category)
        return .result(dialog: outcome.dialog)
    }
}
