import Foundation
import Testing
import UIKit
@testable import Lumora

@Suite("Share cards")
@MainActor
struct ShareCardTests {
    private func planet() -> CelestialSnapshot {
        CelestialSnapshot(id: UUID(), kind: .planet, rewardKey: "planet-1", position: .zero, scale: 1,
                          hue: "violet", name: "Velora", ordinal: 1, dayKey: DayKey(TestFixtures.baseDate),
                          bornAt: TestFixtures.baseDate, focusedMinutes: 0, region: .homeCluster, linkedOrdinals: [], seed: 7,
                          sourceSessionID: nil)
    }

    @Test func planetCardRendersAt1080x1350() throws {
        let content = ShareCardContent(subject: .celestial(planet()), eyebrow: "Milestone · World 1",
                                       title: "Velora is born.", stat: "9 focus sessions of light")
        let image = try #require(ShareCardRenderer.image(for: content))
        let cg = try #require(image.cgImage)
        #expect(cg.width == 1080)
        #expect(cg.height == 1350)
        #expect(image.size.width * image.scale == ShareCardView.pixelSize.width)
    }

    @Test func artifactCardEncodesAsPNG() throws {
        let content = ShareCardContent(subject: .artifact(.comet), eyebrow: "Artifact · No. 004",
                                       title: "First Comet", stat: "Found October 20, 2026")
        let data = try #require(ShareCardRenderer.pngData(for: content))
        let decoded = try #require(UIImage(data: data)?.cgImage)
        #expect(decoded.width == 1080 && decoded.height == 1350)
    }
}
