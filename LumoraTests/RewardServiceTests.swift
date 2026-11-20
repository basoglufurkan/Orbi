import Foundation
import SwiftData
import Testing
@testable import Lumora

@Suite("Rewards: persistence, idempotency, progression")
@MainActor
struct RewardServiceTests {
    let clock = ManualDateProvider(now: TestFixtures.baseDate, timeZone: TestFixtures.istanbul)

    func makeService() throws -> (RewardService, ModelContext) {
        let context = try TestFixtures.makeContext()
        return (RewardService(context: context, clock: clock, goalMinutes: { 120 }), context)
    }

    @Test func completedSessionCreatesOneStarAndFirstLight() throws {
        let (service, context) = try makeService()
        let reward = try service.record(TestFixtures.result(start: TestFixtures.baseDate))
        #expect(reward.star?.ordinal == 1)
        #expect(reward.star?.category == .coding)
        #expect(reward.newAchievements.map(\.id).contains("sessions.1"))
        #expect(try context.fetch(FetchDescriptorFactory.sessions()).first?.starNumber == 1)
        let progress = try context.fetch(FetchDescriptor<UniverseProgress>()).first
        #expect(progress?.starCount == 1)
        #expect(progress?.qualifyingSessionCount == 1)
    }

    @Test func recordingTheSameResultTwiceIsANoOp() throws {
        let (service, context) = try makeService()
        let result = TestFixtures.result(start: TestFixtures.baseDate)
        let a = try service.record(result)
        let b = try service.record(result)
        #expect(a == b)
        #expect(try context.fetch(FetchDescriptorFactory.sessions()).count == 1)
        #expect(try context.fetch(FetchDescriptorFactory.objects()).filter { $0.kind == .star }.count == 1)
        #expect(try context.fetch(FetchDescriptorFactory.unlocks()).count == 1)
    }

    @Test func endedEarlyEarnsASmallerStar() throws {
        let (service, _) = try makeService()
        let full = try service.record(TestFixtures.result(start: TestFixtures.baseDate, minutes: 25))
        let early = try service.record(TestFixtures.result(start: TestFixtures.baseDate.addingTimeInterval(3600), minutes: 25,
                                                           focusedMinutes: 14, reason: .endedByUser))
        #expect(early.outcome == .endedEarly)
        #expect((early.star?.scale ?? 1) < (full.star?.scale ?? 0))
        #expect(early.star != nil)
    }

    @Test func tooShortSessionIsRecordedWithoutReward() throws {
        let (service, context) = try makeService()
        let reward = try service.record(TestFixtures.result(start: TestFixtures.baseDate, minutes: 25, focusedMinutes: 3, reason: .endedByUser))
        #expect(reward.outcome == .tooShort)
        #expect(reward.star == nil)
        #expect(try context.fetch(FetchDescriptorFactory.sessions()).count == 1)
        #expect(try context.fetch(FetchDescriptorFactory.objects()).isEmpty)
    }

    @Test func failedSessionNeverErasesProgress() throws {
        let (service, context) = try makeService()
        for i in 0..<3 {
            _ = try service.record(TestFixtures.result(start: TestFixtures.baseDate.addingTimeInterval(Double(i) * 3600)))
        }
        let before = try context.fetch(FetchDescriptorFactory.objects()).count
        _ = try service.record(TestFixtures.result(start: TestFixtures.baseDate.addingTimeInterval(4 * 3600), focusedMinutes: 1, reason: .endedByUser))
        #expect(try context.fetch(FetchDescriptorFactory.objects()).count == before)
    }

    @Test func fourSessionsInADayFormAConstellation() throws {
        let (service, _) = try makeService()
        var last: SessionReward?
        for i in 0..<4 {
            last = try service.record(TestFixtures.result(start: TestFixtures.baseDate.addingTimeInterval(Double(i) * 1800)))
        }
        let constellation = try #require(last?.constellationFormed)
        #expect(constellation.linkedOrdinals == [1, 2, 3, 4])
        #expect(last?.newAchievements.map(\.id).contains("day.4") == true)
        #expect(last?.todayStars.count == 4)
    }

    @Test func tenthSessionGivesBirthToVelora() throws {
        let (service, _) = try makeService()
        var rewards: [SessionReward] = []
        for i in 0..<10 {
            let day = TestFixtures.baseDate.addingTimeInterval(Double(i / 3) * 86_400 + Double(i % 3) * 3600)
            rewards.append(try service.record(TestFixtures.result(start: day)))
        }
        #expect(rewards[8].planetBorn == nil)
        #expect(rewards[9].planetBorn?.name == "Velora")
        #expect(rewards[9].isMilestone)
        #expect(rewards[9].totalQualifyingSessions == 10)
    }

    @Test func eachObjectRecordsItsSource() throws {
        let (service, context) = try makeService()
        let result = TestFixtures.result(start: TestFixtures.baseDate)
        _ = try service.record(result)
        let objects = try context.fetch(FetchDescriptorFactory.objects())
        #expect(objects.allSatisfy { $0.sourceSessionID == result.segmentID })
        #expect(Set(objects.map(\.rewardKey)).count == objects.count)
    }

    @Test func rewardIsReconstructableAfterRelaunch() throws {
        let (service, context) = try makeService()
        let result = TestFixtures.result(start: TestFixtures.baseDate)
        let original = try service.record(result)
        let fresh = RewardService(context: context, clock: clock, goalMinutes: { 120 })
        #expect(fresh.reward(for: result.segmentID) == original)
    }

    @Test func taskIsLinkedAndReused() throws {
        let (service, context) = try makeService()
        _ = try service.record(TestFixtures.result(start: TestFixtures.baseDate, intention: "Essay"))
        _ = try service.record(TestFixtures.result(start: TestFixtures.baseDate.addingTimeInterval(3600), intention: "Essay"))
        let tasks = try context.fetch(FetchDescriptor<FocusTask>())
        #expect(tasks.count == 1)
        #expect(tasks.first?.sessions?.count == 2)
    }
}
