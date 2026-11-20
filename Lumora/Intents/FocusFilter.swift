import AppIntents
import Foundation

/// Defaults chosen in an iOS Focus mode's "Focus filters" for Lumora
/// (Settings → Focus → Work → Add Filter → Lumora). Overlaid on the user's
/// own last choices while that Focus is on; cleared when it turns off.
struct FocusFilterPreset: Codable, Equatable, Sendable {
    var category: FocusCategory?
    var ambient: AmbientSound?

    var isEmpty: Bool { category == nil && ambient == nil }
}

/// Stores the active preset. App-process only — the widget never needs it.
struct FocusFilterPresetStore {
    static let key = "lumora.focusFilterPreset"
    static var standard: FocusFilterPresetStore { FocusFilterPresetStore(defaults: .standard) }

    let defaults: UserDefaults

    func load() -> FocusFilterPreset? {
        guard let data = defaults.data(forKey: Self.key),
              let preset = try? JSONDecoder().decode(FocusFilterPreset.self, from: data),
              !preset.isEmpty else { return nil }
        return preset
    }

    /// Saving an empty preset (what the system sends when the Focus ends) clears it.
    func save(_ preset: FocusFilterPreset) {
        guard !preset.isEmpty, let data = try? JSONEncoder().encode(preset) else {
            defaults.removeObject(forKey: Self.key)
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}

/// The Focus filter from the design handoff: when a Focus such as "Work"
/// turns on, preset Lumora's default category and ambience. The system calls
/// `perform()` on activation and again, with empty values, on deactivation.
struct LumoraFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Set Orbi Defaults"
    static let description: IntentDescription? = IntentDescription(
        "Choose the category and ambience Orbi starts with while this Focus is on.")

    @Parameter(title: "Category")
    var category: FocusCategory?

    @Parameter(title: "Ambience")
    var ambience: AmbientSound?

    init() {}

    var displayRepresentation: DisplayRepresentation {
        let parts = [category?.displayName, ambience?.title].compactMap { $0 }
        return DisplayRepresentation(title: "Orbi",
                                     subtitle: parts.isEmpty ? "Your usual defaults" : "\(parts.joined(separator: " · "))")
    }

    func perform() async throws -> some IntentResult {
        FocusFilterPresetStore.standard.save(FocusFilterPreset(category: category, ambient: ambience))
        return .result()
    }
}
