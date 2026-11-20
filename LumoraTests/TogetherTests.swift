import Foundation
import SwiftData
import Testing
@testable import Lumora

@Suite("Focus together")
@MainActor
struct TogetherTests {
    final class Starts {
        var configs: [FocusConfiguration] = []
    }

    private func service(_ backend: TogetherBackend, _ clock: ManualDateProvider, _ starts: Starts) throws -> (TogetherService, ModelContext) {
        let context = try TestFixtures.makeContext()
        let s = TogetherService(backend: backend, context: context, clock: clock, pollInterval: nil)
        s.startFocus = { starts.configs.append($0); return true }
        return (s, context)
    }

    @Test func hostAndGuestStartTogetherAndRememberEachOther() async throws {
        let clock = ManualDateProvider(now: TestFixtures.baseDate)
        let backend = LocalTogetherBackend()
        let starts = Starts()
        let (host, hostContext) = try service(backend, clock, starts)
        let (guest, _) = try service(backend, clock, starts)

        await host.host(minutes: 25, category: .coding, name: "  Furkan ")
        let code = try #require(host.room?.code)
        #expect(host.phase == .lobby)
        #expect(host.room?.hostName == "Furkan")

        await guest.join(code: code.lowercased(), name: "Ece")   // typed codes are forgiving
        #expect(guest.phase == .lobby)
        #expect(guest.friendName == "Furkan")
        await host.refresh()
        #expect(host.friendName == "Ece")

        await host.startTogether()
        #expect(host.phase == .countdown)
        await guest.refresh()
        #expect(guest.phase == .countdown)
        #expect(guest.room?.startsAt == host.room?.startsAt)

        host.begin()
        guest.begin()
        #expect(host.phase == .focusing && guest.phase == .focusing)
        #expect(starts.configs.count == 2)
        #expect(starts.configs.allSatisfy { $0.plannedSeconds == 25 * 60 && $0.category == .coding })

        let session = UUID()
        await host.sessionRecorded(sessionID: session, completed: true)
        #expect(host.phase == .finished)
        #expect(!host.friendFinished)
        await guest.sessionRecorded(sessionID: UUID(), completed: true)
        await host.refresh()
        #expect(host.friendFinished)

        let record = try #require(try hostContext.fetch(FetchDescriptor<SharedFocus>()).first)
        #expect(record.sessionID == session)
        #expect(record.friendName == "Ece")
        #expect(record.role == .host)
        #expect(record.friendFinished)
    }

    @Test func joiningExplainsWhatWentWrong() async throws {
        let clock = ManualDateProvider(now: TestFixtures.baseDate)
        let backend = LocalTogetherBackend()
        let starts = Starts()
        let (stranger, _) = try service(backend, clock, starts)

        await stranger.join(code: "ZZZZZZ", name: "Ece")
        #expect(stranger.error == .noRoom)
        #expect(stranger.phase == .idle)

        let full = (1..<TogetherRoom.capacity).map {
            TogetherMember(slot: $0, name: "Friend \($0)", joinedAt: clock.now, seenAt: clock.now)
        }
        await backend.seed(TogetherRoom(code: "ABCDEF", hostName: "Can", minutes: 25, categoryRaw: "work",
                                        createdAt: clock.now, members: full))
        await stranger.join(code: "ABCDEF", name: "Ece")
        #expect(stranger.error == .roomFull)

        await backend.seed(TogetherRoom(code: "PQRSTU", hostName: "Can", minutes: 25, categoryRaw: "work",
                                        createdAt: clock.now.addingTimeInterval(-5 * 3600)))
        await stranger.join(code: "PQRSTU", name: "Ece")
        #expect(stranger.error == .noRoom)
    }

    @Test func aBusyTimerDoesNotStartTwice() async throws {
        let clock = ManualDateProvider(now: TestFixtures.baseDate)
        let backend = LocalTogetherBackend()
        let starts = Starts()
        let (host, _) = try service(backend, clock, starts)
        host.startFocus = { _ in false }   // already focusing
        await host.host(minutes: 25, category: .work, name: "Furkan")
        let code = try #require(host.room?.code)
        _ = try await backend.join(code: code, name: "Ece", at: clock.now)
        await host.refresh()
        await host.startTogether()
        host.begin()
        #expect(host.phase == .idle)
        #expect(host.error == .alreadyStarted)
    }

    /// A room is written by someone else's device: absurd values are reined in, not trusted.
    @Test func aHostileRoomCannotCrashOrOverrunTheTimer() async throws {
        let clock = ManualDateProvider(now: TestFixtures.baseDate)
        let backend = LocalTogetherBackend()
        let starts = Starts()
        let (guest, _) = try service(backend, clock, starts)
        await backend.seed(TogetherRoom(code: "ABCDEF", hostName: String(repeating: "x", count: 500), minutes: .max,
                                        categoryRaw: "not-a-category", createdAt: clock.now))
        await guest.join(code: "ABCDEF", name: "Ece")
        await backend.seed(TogetherRoom(code: "ABCDEF", hostName: "Can", minutes: .max, categoryRaw: "work",
                                        createdAt: clock.now, startsAt: clock.now,
                                        members: [TogetherMember(slot: 1, name: "Ece", joinedAt: clock.now, seenAt: clock.now)]))
        await guest.refresh()
        guest.begin()
        let config = try #require(starts.configs.first)
        #expect(config.plannedSeconds == TogetherRoom.minuteRange.upperBound * 60)
        #expect(TogetherRoom.sane(minutes: -5) == 1)
        #expect(TogetherRoom.sane(name: String(repeating: "x", count: 500)).count == TogetherRoom.nameLimit)
    }

    /// Up to eight people: friends take seats in order, late arrivals start
    /// on joining, and anyone who finishes, leaves or goes quiet drops out.
    @Test func aRoomFillsAndEmptiesAsPeopleComeAndGo() async throws {
        let clock = ManualDateProvider(now: TestFixtures.baseDate)
        let backend = LocalTogetherBackend()
        let starts = Starts()
        let (host, _) = try service(backend, clock, starts)
        let (ece, _) = try service(backend, clock, starts)
        let (mert, _) = try service(backend, clock, starts)
        let (late, _) = try service(backend, clock, starts)

        await host.host(minutes: 25, category: .study, name: "Furkan")
        let code = try #require(host.room?.code)
        await ece.join(code: code, name: "Ece")
        await mert.join(code: code, name: "Mert")
        #expect(ece.slot == 1 && mert.slot == 2)
        await host.refresh()
        #expect(host.present(at: clock.now).map(\.name) == ["Furkan", "Ece", "Mert"])
        #expect(host.friendName == ["Ece", "Mert"].formatted(.list(type: .and)))

        await host.startTogether()
        for s in [ece, mert] { await s.refresh() }
        for s in [host, ece, mert] { s.begin() }
        #expect([host, ece, mert].allSatisfy { $0.phase == .focusing })

        // Joining after the start begins focusing straight away.
        await late.join(code: code, name: "Ayla")
        #expect(late.phase == .countdown)
        late.begin()
        #expect(late.phase == .focusing)
        #expect(starts.configs.count == 4)
        await host.refresh()
        #expect(host.present(at: clock.now).count == 4)

        // Mert leaves, Ece finishes: both drop out of everyone's galaxy.
        mert.leave()
        try await Task.sleep(for: .milliseconds(50))
        await ece.sessionRecorded(sessionID: UUID(), completed: true)
        await host.refresh()
        #expect(host.present(at: clock.now).map(\.name) == ["Furkan", "Ayla"])

        // Someone who goes quiet (app closed, no signal) fades out too.
        clock.advance(by: TogetherMember.presenceTimeout + 1)
        await host.refresh()
        #expect(host.present(at: clock.now).map(\.name) == ["Furkan"])
        await late.refresh()
        await host.refresh()
        #expect(host.present(at: clock.now).map(\.name) == ["Furkan", "Ayla"])
    }

    @Test func aFullRoomSaysSo() async throws {
        let clock = ManualDateProvider(now: TestFixtures.baseDate)
        let backend = LocalTogetherBackend()
        let starts = Starts()
        let (host, _) = try service(backend, clock, starts)
        await host.host(minutes: 25, category: .work, name: "Furkan")
        let code = try #require(host.room?.code)
        for i in 1..<TogetherRoom.capacity {
            let (friend, _) = try service(backend, clock, starts)
            await friend.join(code: code, name: "Friend \(i)")
            #expect(friend.slot == i)
        }
        let (ninth, _) = try service(backend, clock, starts)
        await ninth.join(code: code, name: "One too many")
        #expect(ninth.error == .roomFull)
        // Formatted for the device's language, so check the parts rather than the words.
        let five = TogetherService.names(["Ece", "Mert", "Ayla", "Deniz", "Can"])
        #expect(five.hasPrefix("Ece, Mert") && five.contains("3") && !five.contains("Ayla"))
    }

    @Test func seatsFitTheScreen() {
        #expect(TogetherGalaxyLayout.seats(count: 3, perRow: 3).allSatisfy { $0.row == 0 })
        let five = TogetherGalaxyLayout.seats(count: 5, perRow: 3)
        #expect(five.filter { $0.row == 0 }.count == 3 && five.filter { $0.row == 1 }.count == 2)
        #expect(TogetherGalaxyLayout.seats(count: 8, perRow: 4).count == 8)
        #expect(TogetherGalaxyLayout.seats(count: 0, perRow: 3).isEmpty)
    }

    @Test func inviteLinksAndCodes() {
        let code = TogetherInvite.newCode()
        #expect(TogetherInvite.isValid(code))
        #expect(TogetherInvite.code(from: TogetherInvite.link(for: code)) == code)
        #expect(TogetherInvite.code(from: URL(string: "lumora://together/ab-cd ef")!) == "ABCDEF")
        #expect(TogetherInvite.link(for: "ABCDEF").absoluteString == "https://www.mobapptech.com/lumora/join/?code=ABCDEF")
        #expect(TogetherInvite.code(from: URL(string: "https://www.mobapptech.com/lumora/join?code=ab-cdef")!) == "ABCDEF")
        #expect(TogetherInvite.code(from: URL(string: "https://example.com/together/ABCDEF")!) == nil)
        #expect(TogetherInvite.code(from: URL(string: "https://example.com/lumora/join/?code=ABCDEF")!) == nil)
        #expect(TogetherInvite.code(from: URL(string: "https://www.mobapptech.com/other/?code=ABCDEF")!) == nil)
        #expect(TogetherInvite.normalize("o0-1lI") == "")   // ambiguous characters never appear in codes
    }
}
