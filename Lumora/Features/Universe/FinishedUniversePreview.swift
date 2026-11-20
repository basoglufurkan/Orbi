#if DEBUG
import SwiftData
import SwiftUI

/// Debug-only: what a universe looks like once everything has happened — a
/// year of sessions, every region open, and five Odyssey galaxies with every
/// world charted and grown to Wonder. Built in a throwaway in-memory store
/// through the real reward path, so the user's own data is never touched.
@MainActor
enum FinishedUniverse {
    static let sessionCount = 1_100
    static let galaxyCount = 5

    static func makeScene(calendar: Calendar) throws -> UniverseScene {
        let now = Date()
        let context = ModelContext(try DataStore.makeContainer(inMemory: true))
        let rewards = RewardService(context: context, clock: SystemDateProvider(), goalMinutes: { 120 })

        // A year of focus: most days have a few sessions, some rest.
        let durations = [25, 25, 45, 15, 25, 60, 25, 45]
        let days = 365
        var produced = 0
        for day in stride(from: days, through: 0, by: -1) where produced < sessionCount {
            guard let dayStart = calendar.date(byAdding: .day, value: -day, to: calendar.startOfDay(for: now)) else { continue }
            let perDay = day % 6 == 5 ? 0 : 2 + (day * 7 + 3) % 3
            for k in 0..<perDay where produced < sessionCount {
                let minutes = durations[(produced + day) % durations.count]
                let start = dayStart.addingTimeInterval(TimeInterval(9 * 3600 + k * 5400))
                guard start.addingTimeInterval(TimeInterval(minutes * 60)) < now else { continue }
                let config = FocusConfiguration(plannedSeconds: minutes * 60,
                                                category: FocusCategory.allCases[(produced * 3 + day) % 5], intention: "")
                _ = try rewards.record(FocusResult(segmentID: UUID(), configuration: config, startedAt: start,
                                                   endedAt: start.addingTimeInterval(TimeInterval(minutes * 60)),
                                                   plannedSeconds: minutes * 60, focusedSeconds: minutes * 60,
                                                   pausedSeconds: 0, pauseCount: 0, endReason: .completed))
                produced += 1
            }
        }

        let objects = try context.fetch(FetchDescriptor<CelestialObject>(sortBy: [SortDescriptor(\.bornAt)]))
            .map(CelestialSnapshot.init)
        var scene = UniverseScene(objects: objects, today: DayKey(now, calendar: calendar),
                                  qualifyingSessions: produced, ambientLight: 0.7)

        // Every world of the first galaxies, charted and grown to Wonder,
        // forming at even steps through the year.
        let rules = OdysseyRules.standard
        let worldCount = (0..<galaxyCount).map(rules.galaxyCapacity).reduce(0, +)
        let starTimes = scene.stars.map(\.bornAt).sorted()
        let worlds: [WorldState] = (1...worldCount).map { ordinal in
            let place = rules.placement(ofWorld: ordinal)
            let index = min(starTimes.count - 1, (ordinal - 1) * starTimes.count / worldCount)
            let born = starTimes.isEmpty ? now : starTimes[max(0, index)]
            return WorldState(ordinal: ordinal, blueprint: WorldGenerator.blueprint(ordinal: ordinal),
                              galaxy: place.galaxy, slot: place.slot, status: .charted, stage: .wonder,
                              emergedAt: born, visitedAt: born.addingTimeInterval(86_400))
        }
        scene.addOdyssey(worlds: worlds)
        return scene
    }
}

/// A full-screen, explorable look at `FinishedUniverse`.
struct FinishedUniversePreview: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var scene: UniverseScene?
    @State private var camera = UniverseCamera(center: .zero, zoom: 0.3)
    @State private var flight: CameraFlight?

    var body: some View {
        ZStack(alignment: .topLeading) {
            CosmicBackgroundView(mood: .home, light: 0.7, showsStars: false)
            if let scene {
                UniverseCanvasView(scene: scene, camera: $camera, flight: $flight, interactive: true)
                    .ignoresSafeArea()
                    .accessibilityIdentifier("finished.canvas")
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "Finished universe")
                        .font(LMFont.largeTitle).foregroundStyle(LMColor.textPrimary)
                    Text(verbatim: "\(scene.stars.count) stars · \(scene.constellations.count) constellations · "
                         + "\(scene.planets.count) planets · \(scene.voyages.count) worlds at Wonder · \(scene.galaxies.count) galaxies")
                        .font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
                    Text(verbatim: "Debug preview · your data is untouched")
                        .font(LMFont.footnote).foregroundStyle(LMColor.textTertiary)
                }
                .padding(.horizontal, LMSpace.l)
                .padding(.top, 64)
            } else {
                VStack(spacing: LMSpace.s) {
                    ProgressView()
                    Text(verbatim: "Growing a year of focus…").font(LMFont.footnote).foregroundStyle(LMColor.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            RoundControlButton(systemImage: "xmark", label: "Back", size: 44) { dismiss() }
                .padding(.leading, LMSpace.m)
                .padding(.top, LMSpace.xs)
        }
        .task {
            guard scene == nil, let built = try? FinishedUniverse.makeScene(calendar: app.clock.calendar) else { return }
            let points = built.all.map(\.position) + built.voyages.map(\.position) + built.galaxies.map(\.center)
            // Frame the whole year; the sky itself stays dim enough that worlds read as the jewels.
            camera = UniverseCamera.fitting(points, in: CGSize(width: 400, height: 700), padding: 30, zoomRange: 0.22...1)
            scene = built
        }
    }
}
#endif
