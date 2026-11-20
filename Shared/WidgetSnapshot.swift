import Foundation

/// The small, precomputed summary the app shares with its widgets.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct MiniStar: Codable, Equatable, Sendable {
        /// Normalized position in 0...1.
        var x: Double
        var y: Double
        var categoryRaw: String
        /// Visual scale, roughly 0.5...1.4.
        var size: Double
        var isPlanet: Bool
    }

    var generatedAt: Date
    var dayKey: String
    var todayMinutes: Int
    var goalMinutes: Int
    var rhythmDays: Int
    var totalStars: Int
    var planets: Int
    var constellations: Int
    var stars: [MiniStar]
    var nextWorldName: String?
    var sessionsToNextWorld: Int?
    /// Odyssey: the ship's current journey (optional, so older snapshots still decode).
    var expeditionWorld: String?
    var expeditionFraction: Double?
    var stardust: Int?
    /// Today's and tomorrow's day-plan blocks (optional, so older snapshots still decode).
    var plan: [PlanBlock]?
    /// Habits with today's state and streaks (optional, so older snapshots still decode).
    var habits: [HabitWidgetItem]?

    static let storageKey = "widget.snapshot.v1"

    static let placeholder = WidgetSnapshot(
        generatedAt: .now, dayKey: DayKey(.now).rawValue, todayMinutes: 70, goalMinutes: 120,
        rhythmDays: 12, totalStars: 113, planets: 2, constellations: 9,
        stars: (0..<18).map { i in
            let a = Double(i) * 2.399963
            let r = 0.12 + 0.36 * sqrt(Double(i) / 18)
            return MiniStar(x: 0.5 + cos(a) * r, y: 0.5 + sin(a) * r,
                            categoryRaw: FocusCategory.allCases[i % 5].rawValue,
                            size: 0.6 + Double(i % 3) * 0.25, isPlanet: i == 0)
        },
        nextWorldName: "Calyx", sessionsToNextWorld: 8
    )

    static func load(from defaults: UserDefaults = AppGroup.defaults) -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save(to defaults: UserDefaults = AppGroup.defaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Minutes focused today, or 0 if the snapshot is from an earlier day.
    func minutesToday(now: Date = .now, calendar: Calendar = .current) -> Int {
        dayKey == DayKey(now, calendar: calendar).rawValue ? todayMinutes : 0
    }

    var goalProgress: Double {
        guard goalMinutes > 0 else { return 0 }
        return min(1, Double(todayMinutes) / Double(goalMinutes))
    }
}
