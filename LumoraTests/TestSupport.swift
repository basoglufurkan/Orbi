import Foundation
import SwiftData
@testable import Lumora

enum TestFixtures {
    /// 2026-10-20 09:00:00 in Europe/Istanbul.
    static let istanbul = TimeZone(identifier: "Europe/Istanbul")!
    static let baseDate: Date = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = istanbul
        return c.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9))!
    }()

    static func config(minutes: Int = 25, category: FocusCategory = .coding, intention: String = "Refactor auth module") -> FocusConfiguration {
        FocusConfiguration(plannedSeconds: minutes * 60, category: category, intention: intention)
    }

    static func result(id: UUID = UUID(), start: Date, minutes: Int = 25, focusedMinutes: Int? = nil,
                       category: FocusCategory = .coding, reason: FocusEndReason = .completed,
                       intention: String = "Deep work") -> FocusResult {
        let focused = (focusedMinutes ?? minutes) * 60
        return FocusResult(segmentID: id, configuration: config(minutes: minutes, category: category, intention: intention),
                           startedAt: start, endedAt: start.addingTimeInterval(TimeInterval(focused)),
                           plannedSeconds: minutes * 60, focusedSeconds: focused, pausedSeconds: 0, pauseCount: 0,
                           endReason: reason)
    }

    @MainActor
    static func makeContext() throws -> ModelContext {
        let container = try DataStore.makeContainer(inMemory: true)
        return ModelContext(container)
    }
}

/// Counts how many times results are recorded and returns a canned reward.
@MainActor
final class SpyRecorder: FocusResultRecording {
    private(set) var recorded: [FocusResult] = []
    private var unique: [UUID: SessionReward] = [:]

    func record(_ result: FocusResult) throws -> SessionReward {
        recorded.append(result)
        if let r = unique[result.segmentID] { return r }
        let reward = SessionReward(sessionID: result.segmentID, outcome: .completed, category: result.configuration.category,
                                   intention: "", focusedMinutes: result.focusedSeconds / 60,
                                   plannedMinutes: result.plannedSeconds / 60, endedAt: result.endedAt, star: nil,
                                   newObjects: [], newAchievements: [], todayMinutesBefore: 0,
                                   todayMinutes: result.focusedSeconds / 60, goalMinutes: 120, todayStars: [],
                                   totalQualifyingSessions: 1, starsPerConstellation: 4)
        unique[result.segmentID] = reward
        return reward
    }

    func reward(for sessionID: UUID) -> SessionReward? { unique[sessionID] }
    var uniqueCount: Int { unique.count }
}
