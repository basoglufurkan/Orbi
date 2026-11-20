import SwiftData
import SwiftUI

/// Sky display choices the viewer makes, remembered on this device.
enum SkyPreferences {
    /// Show Odyssey worlds not yet landed on (veiled). Off by default.
    static let showsUnchartedWorlds = "universe.showsUnchartedWorlds"
    /// Lines joining the stars of each constellation. On by default.
    static let connectsConstellations = "universe.connectsConstellations"
    /// Today's stars joined by a dashed line and framed. On by default.
    static let marksToday = "universe.marksToday"
    /// The sky's colours (`SkyTheme`). Classic by default.
    static let theme = "universe.skyTheme"
}

/// Builds a `UniverseScene` from live SwiftData queries and rebuilds it only
/// when the underlying data (or the day) changes — never per frame.
struct UniverseSceneReader<Content: View>: View {
    var visibleUntil: Date?
    @ViewBuilder var content: (UniverseScene) -> Content

    @Environment(AppModel.self) private var app
    @AppStorage(SkyPreferences.showsUnchartedWorlds) private var showsUncharted = false
    @Query(sort: \CelestialObject.bornAt) private var objects: [CelestialObject]
    @Query private var progress: [UniverseProgress]
    @Query private var shared: [SharedFocus]
    @State private var scene = UniverseScene()

    private struct Key: Equatable {
        var count: Int
        var day: DayKey
        var until: Date?
        var sessions: Int
        var odyssey: Int
        var uncharted: Bool
        var bridges: Int
    }

    var body: some View {
        let p = progress.first
        content(scene)
            .onChange(of: Key(count: objects.count, day: app.today, until: visibleUntil, sessions: p?.qualifyingSessionCount ?? 0,
                              odyssey: app.odyssey.revision, uncharted: showsUncharted,
                              bridges: shared.filter { $0.sessionID != nil }.count),
                      initial: true) { _, _ in
                var next = UniverseScene(objects: objects.map(CelestialSnapshot.init), today: app.today,
                                      qualifyingSessions: p?.qualifyingSessionCount ?? 0,
                                      ambientLight: p?.ambientLight ?? 0, visibleUntil: visibleUntil,
                                      ghostDetail: { n in
                                          n == 1 ? String(localized: "1 session away") : String(localized: "\(n) sessions away")
                                      })
                next.addOdyssey(worlds: app.odyssey.snapshot.worlds, visibleUntil: visibleUntil, includeUncharted: showsUncharted)
                next.addBridges(shared.compactMap { s in s.sessionID.map { ($0, s.friendName, s.roomCode) } })
                scene = next
            }
    }
}

/// Supplies `ProgressStats` computed from stored sessions, cached per change.
struct StatsReader<Content: View>: View {
    @ViewBuilder var content: (ProgressStats, [SessionFacts]) -> Content

    @Environment(AppModel.self) private var app
    @Query(sort: \FocusSession.endedAt) private var sessions: [FocusSession]
    @State private var stats = ProgressStats()
    @State private var facts: [SessionFacts] = []

    private struct Key: Equatable {
        var count: Int
        var day: DayKey
        var goal: Int
        var lastID: UUID?
    }

    var body: some View {
        content(stats, facts)
            .onChange(of: Key(count: sessions.count, day: app.today, goal: app.preferences.dailyGoalMinutes,
                              lastID: sessions.last?.id), initial: true) { _, _ in
                facts = sessions.map(SessionFacts.init)
                stats = ProgressStats.compute(sessions: facts, goalMinutes: app.preferences.dailyGoalMinutes,
                                              today: app.today, calendar: app.clock.calendar)
            }
    }
}
