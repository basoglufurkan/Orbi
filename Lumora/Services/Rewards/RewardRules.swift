import Foundation

/// Every tunable of the reward economy in one place.
///
/// Short sessions are never worthless: any qualifying session earns a star;
/// longer sessions earn a larger, brighter one ("more light"), not more stars.
struct RewardRules: Equatable, Sendable {
    /// Minimum focused time for an ended-early session to earn a star.
    var minimumQualifyingSeconds = 5 * 60
    /// Same-day stars that connect into one constellation.
    var starsPerConstellation = 4
    /// Qualifying-session counts that give birth to a planet.
    var planetMilestones = [10, 60, 120, 200, 300, 450, 600, 800, 1000]
    var planetNames = ["Velora", "Ostra", "Calyx", "Thessa", "Mirren", "Oberine", "Solace", "Ilyth", "Vantor"]
    /// Qualifying-session counts at which the newest planet captures a moon.
    var moonMilestones = [30, 90, 160, 250, 380]
    var moonNames = ["Ione", "Lumen", "Cora", "Nyx", "Sable"]
    /// Days of rhythm per nebula.
    var nebulaRhythmDays = 7
    var nebulaNames = ["Rose Veil", "Azure Wake", "Golden Hush", "Violet Tide", "Ember Drift"]
    /// Focus hours that summon a comet.
    var cometHourMilestones = [5, 25, 50, 100, 200, 500]
    /// Ended-early stars are drawn at this fraction of their size.
    var endedEarlyScale = 0.6
    /// Sky brightness gained per star, up to 1.
    var ambientLightPerStar = 0.012

    static let standard = RewardRules()

    func outcome(for result: FocusResult) -> SessionOutcome {
        if result.endReason == .completed { return .completed }
        return result.focusedSeconds >= minimumQualifyingSeconds ? .endedEarly : .tooShort
    }

    /// Size grows with duration: 15m ≈ 0.85, 25m ≈ 0.95, 60m ≈ 1.3.
    func starScale(focusedSeconds: Int, outcome: SessionOutcome) -> Double {
        let minutes = Double(focusedSeconds) / 60
        let base = 0.7 + 0.6 * min(1, minutes / 60)
        return outcome == .endedEarly ? base * endedEarlyScale : base
    }

    func planetName(index: Int) -> String {
        index < planetNames.count ? planetNames[index] : "World \(index + 1)"
    }

    /// The next planet milestone after `count` sessions, if any.
    func nextPlanet(after count: Int) -> (name: String, sessions: Int)? {
        guard let i = planetMilestones.firstIndex(where: { $0 > count }) else { return nil }
        return (planetName(index: i), planetMilestones[i])
    }
}
