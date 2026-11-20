import Foundation
import Testing
import UIKit
@testable import Lumora

@Suite("Universe share card")
@MainActor
struct UniverseShareCardTests {
    /// Two weeks of real sessions through the reward path, then the card.
    @Test func rendersTheWholeSkyAtShareSize() throws {
        let clock = ManualDateProvider(now: TestFixtures.baseDate, timeZone: TestFixtures.istanbul)
        let context = try TestFixtures.makeContext()
        let rewards = RewardService(context: context, clock: clock, goalMinutes: { 120 })
        for i in 0..<60 {
            // Four sessions a day, so each day closes a constellation.
            let start = TestFixtures.baseDate.addingTimeInterval(-Double(15 - i / 4) * 86_400 + Double(i % 4) * 5_400)
            _ = try rewards.record(TestFixtures.result(start: start, category: FocusCategory.allCases[i % 5]))
        }
        let objects = try context.fetch(FetchDescriptorFactory.objects()).map(CelestialSnapshot.init)
        let scene = UniverseScene(objects: objects, today: DayKey(TestFixtures.baseDate), qualifyingSessions: 60, ambientLight: 0.6)
        #expect(scene.stars.count == 60)

        let content = UniverseShareContent(scene: scene, rank: NavigatorRank.all[3], day: 22,
                                           stat: [String(localized: "\(scene.stars.count) stars"),
                                                  String(localized: "\(scene.constellations.count) constellations"),
                                                  String(localized: "\(scene.planets.count) planets")].joined(separator: " · "))
        let image = try #require(ShareCardRenderer.image(rendering: UniverseShareCardView(content: content)))
        #expect(image.size.width * image.scale == 1080)
        #expect(image.size.height * image.scale == 1350)

        // Kept for eyeballing the design; the path is printed in the test log.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lumora-universe-card.png")
        try image.pngData()?.write(to: url)
        print("UNIVERSE-CARD \(url.path)")
    }
}
