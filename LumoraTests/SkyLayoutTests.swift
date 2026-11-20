import Foundation
import SwiftData
import Testing
@testable import Lumora

@Suite("Sky layout")
@MainActor
struct SkyLayoutTests {
    /// The densest sky there is: a year of focus with every world grown.
    @Test func worldsAndGalaxiesNeverSitOnOtherBodies() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TestFixtures.istanbul
        let scene = try FinishedUniverse.makeScene(calendar: calendar)
        #expect(!scene.voyages.isEmpty && !scene.galaxies.isEmpty && !scene.planets.isEmpty)

        let worldReach = Double(UniverseRenderer.odysseyWorldRadius) * 2.4
        let galaxyReach = Double(UniverseRenderer.odysseyGalaxyRadius) * 1.3
        let planetReach = Double(UniverseRenderer.planetRadius) * 1.8
        let bodies = scene.planets.map { ($0.position, planetReach) } + scene.moons.map { ($0.position, 30.0) }
            + scene.comets.map { ($0.position, 40.0) }

        for v in scene.voyages {
            for (p, reach) in bodies {
                #expect(v.position.distance(to: p) >= reach + worldReach, "\(v.world.blueprint.name) overlaps a planet, moon or comet")
            }
            for g in scene.galaxies {
                #expect(v.position.distance(to: g.center) >= galaxyReach + worldReach, "\(v.world.blueprint.name) sits on \(g.blueprint.name)")
            }
            for other in scene.voyages where other.world.ordinal != v.world.ordinal {
                #expect(v.position.distance(to: other.position) >= 2 * worldReach)
            }
        }
        for g in scene.galaxies {
            for (p, reach) in bodies {
                #expect(g.center.distance(to: p) >= reach + galaxyReach, "\(g.blueprint.name) sits on a planet, moon or comet")
            }
        }
    }

    /// A newly opened region grows from the sky's edge, not far away across empty space.
    @Test func aNewRegionStartsBesideTheStarsBeforeIt() throws {
        let clock = ManualDateProvider(now: TestFixtures.baseDate, timeZone: TestFixtures.istanbul)
        let context = try TestFixtures.makeContext()
        let store = Lumora.DataStore(container: context.container)
        store.ensureUniverse(createdAt: TestFixtures.baseDate, calendar: clock.calendar)
        let rewards = RewardService(context: store.context, clock: clock, goalMinutes: { 120 })
        // 32 sessions over three days: Rose Veil opens at 25, so day three begins there.
        for i in 0..<32 {
            let start = TestFixtures.baseDate.addingTimeInterval(TimeInterval((i / 13) * 86_400 + (i % 13) * 1_800))
            _ = try rewards.record(TestFixtures.result(start: start))
        }
        let stars = try store.context.fetch(FetchDescriptor<CelestialObject>()).filter { $0.kind == .star }
        let home = stars.filter { $0.region == .homeCluster }.map(\.position)
        let rose = stars.filter { $0.region == .roseVeil }.sorted { $0.ordinal < $1.ordinal }
        let first = try #require(rose.first)
        let gap = home.map { $0.distance(to: first.position) }.min() ?? .infinity
        #expect(gap < 320, "the first Rose Veil star is \(Int(gap)) units from the nearest earlier star")
        #expect(gap > UniverseLayout.starClearance)
        // …and it still lies toward the region it belongs to.
        let c = UniverseRegion.roseVeil.center
        #expect(first.position.x * c.x + first.position.y * c.y > 0)
    }
}
