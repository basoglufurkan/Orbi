import Foundation
import Observation
import SwiftData

/// Focusing together: host a room or join one (before or after it starts),
/// focus for the same length, and see everyone who's there in a shared
/// galaxy that updates as people arrive and leave. Remembers who you focused
/// with afterwards.
///
/// The room is polled while it matters (lobby, countdown, and while anyone
/// else is still focusing); nothing runs in the background otherwise.
@MainActor
@Observable
final class TogetherService {
    enum Phase: Equatable {
        case idle
        /// Waiting for friends to join (host) or for the host to start (guest).
        case lobby
        /// The session begins at `room.startsAt`.
        case countdown
        case focusing
        case finished
    }

    private(set) var phase: Phase = .idle
    private(set) var room: TogetherRoom?
    /// This device's seat: 0 for the host, 1…7 for friends.
    private(set) var slot: Int?
    private(set) var error: TogetherError?
    private(set) var isBusy = false
    /// A `lumora://together/CODE` link was opened: offer to join. Kept until
    /// the session begins or the room is left, so the join sheet stays up.
    var pendingJoinCode: String?

    var role: TogetherRole? { slot.map { $0 == 0 ? .host : .guest } }

    /// Everyone else who has been in the room, host first.
    var companions: [TogetherMember] {
        guard let room, let slot else { return [] }
        return room.members.filter { $0.slot != slot }
    }

    /// Everyone in the room right now, this device included, host first.
    func present(at now: Date) -> [TogetherMember] {
        guard let room else { return [] }
        return room.members.filter { $0.slot == slot ? phase != .finished : $0.isPresent(at: now) }
    }

    /// The others' names, as one line ("Ece", "Ece and Mert", "Ece, Mert and 3 more").
    var friendName: String? {
        let names = companions.map(\.name)
        guard !names.isEmpty else { return nil }
        return Self.names(names)
    }

    /// Everyone else who came has finished or left.
    var friendFinished: Bool {
        let others = companions
        return !others.isEmpty && others.allSatisfy { $0.doneAt != nil || $0.leftAt != nil }
    }

    @ObservationIgnored private let backend: TogetherBackend
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let clock: DateProvider
    @ObservationIgnored private let pollInterval: Duration?
    /// Starts the local timer; false if a session is already running.
    @ObservationIgnored var startFocus: (FocusConfiguration) -> Bool = { _ in false }
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var beginning: Task<Void, Never>?
    @ObservationIgnored private var shared: SharedFocus?
    @ObservationIgnored private var lastHeartbeat: Date?

    /// How far ahead the host schedules the start, so everyone begins together.
    static let leadTime: TimeInterval = 3

    init(backend: TogetherBackend, context: ModelContext, clock: DateProvider, pollInterval: Duration? = .seconds(1.5)) {
        self.backend = backend
        self.context = context
        self.clock = clock
        self.pollInterval = pollInterval
    }

    // MARK: Intents

    func host(minutes: Int, category: FocusCategory, name: String) async {
        let room = TogetherRoom(code: TogetherInvite.newCode(), hostName: Self.tidy(name), minutes: minutes,
                                categoryRaw: category.rawValue, createdAt: clock.now)
        await run {
            try await backend.create(room)
            self.room = room
            self.slot = 0
            self.phase = .lobby
            self.lastHeartbeat = clock.now
            Telemetry.log(.togetherRoomCreated(minutes: minutes))
            self.startPolling()
        }
    }

    /// Joins a room; if it has already started, focusing begins right away.
    func join(code raw: String, name: String) async {
        let code = TogetherInvite.normalize(raw)
        await run {
            guard TogetherInvite.isValid(code), let found = try await backend.room(code: code),
                  !found.isExpired(at: clock.now) else { throw TogetherError.noRoom }
            let seat = try await backend.join(code: code, name: Self.tidy(name), at: clock.now)
            self.room = try await backend.room(code: code) ?? found
            self.slot = seat
            self.phase = .lobby
            self.lastHeartbeat = clock.now
            Telemetry.log(.togetherJoined(viaLink: self.pendingJoinCode != nil))
            if let at = self.room?.startsAt { self.scheduleBegin(at: max(at, clock.now)) }
            self.startPolling()
        }
    }

    /// Host only: begin a few seconds from now on every device in the lobby.
    func startTogether() async {
        guard role == .host, let room, phase == .lobby, !isBusy else { return }
        let at = clock.now.addingTimeInterval(Self.leadTime)
        await run {
            try await backend.start(code: room.code, at: at)
            self.room?.startsAt = at
            self.scheduleBegin(at: at)
        }
    }

    /// Leaves the room: the others see this person go. After this device's
    /// session is recorded it only stops following the room.
    func leave() {
        if let room, let slot, phase == .lobby || phase == .countdown || phase == .focusing {
            let backend = backend, at = clock.now
            Task { try? await backend.leave(code: room.code, slot: slot, at: at) }
        }
        Self.saveActive(code: nil, slot: nil)
        polling?.cancel()
        beginning?.cancel()
        polling = nil
        beginning = nil
        phase = .idle
        room = nil
        slot = nil
        error = nil
        shared = nil
        lastHeartbeat = nil
        pendingJoinCode = nil
    }

    func clearError() { error = nil }

    /// Fetches the room once, says "still here", and moves the phase along.
    func refresh() async {
        guard let code = room?.code, phase != .idle else { return }
        await heartbeatIfDue(code: code)
        guard let latest = try? await backend.room(code: code) else { return }
        // Unchanged rooms don't redraw everything that watches them.
        if room != latest { room = latest }
        if phase == .lobby, let at = latest.startsAt { scheduleBegin(at: max(at, clock.now)) }
        if let shared {
            let names = Self.names(companions.map(\.name))
            if !names.isEmpty, shared.friendName != names { shared.friendName = names }
            if friendFinished, !shared.friendFinished { shared.friendFinished = true }
            if shared.hasChanges { try? context.save() }
        }
        // Done once nobody else is still focusing, or when the room expires.
        if phase == .finished, present(at: clock.now).isEmpty { stopPolling() }
        if latest.isExpired(at: clock.now) { stopPolling() }
    }

    /// A session was recorded. If it was the together session, link it and
    /// leave everyone's galaxy.
    func sessionRecorded(sessionID: UUID, completed: Bool) async {
        guard phase == .focusing, let room, let slot, let shared else { return }
        shared.sessionID = sessionID
        try? context.save()
        phase = .finished
        Self.saveActive(code: nil, slot: nil)
        // Ended early or not, this astronaut leaves the others' galaxy.
        try? await backend.finish(code: room.code, slot: slot, at: clock.now)
        await refresh()
    }

    /// After a relaunch: if a session together was running, take this seat
    /// again; if it ended while Lumora wasn't running, tell the others.
    func resume(timerRunning: Bool) async {
        guard phase == .idle, let (code, seat) = Self.loadActive() else { return }
        guard timerRunning else {
            Self.saveActive(code: nil, slot: nil)
            try? await backend.finish(code: code, slot: seat, at: clock.now)
            return
        }
        guard let found = try? await backend.room(code: code), !found.isExpired(at: clock.now),
              found.member(seat) != nil else { return Self.saveActive(code: nil, slot: nil) }
        guard phase == .idle else { return }
        room = found
        slot = seat
        phase = .focusing
        let match = code
        var open = FetchDescriptor<SharedFocus>(predicate: #Predicate { $0.roomCode == match && $0.sessionID == nil },
                                                sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        open.fetchLimit = 1
        shared = try? context.fetch(open).first
        lastHeartbeat = nil
        startPolling()
    }

    private static let activeKey = "lumora.together.active"

    private static func saveActive(code: String?, slot: Int?) {
        if let code, let slot {
            UserDefaults.standard.set("\(code):\(slot)", forKey: activeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: activeKey)
        }
    }

    private static func loadActive() -> (String, Int)? {
        guard let raw = UserDefaults.standard.string(forKey: activeKey) else { return nil }
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let slot = Int(parts[1]) else { return nil }
        return (String(parts[0]), slot)
    }

    // MARK: Steps

    private func heartbeatIfDue(code: String) async {
        guard let slot, phase != .finished else { return }
        let now = clock.now
        if let last = lastHeartbeat, now.timeIntervalSince(last) < TogetherMember.heartbeat { return }
        lastHeartbeat = now
        try? await backend.heartbeat(code: code, slot: slot, at: now)
    }

    private func scheduleBegin(at date: Date) {
        guard phase == .lobby else { return }
        phase = .countdown
        beginning?.cancel()
        let wait = max(0, date.timeIntervalSince(clock.now))
        beginning = Task { [weak self] in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            self?.begin()
        }
    }

    /// Every device reaches this at `startsAt`, or on arrival when joining late.
    func begin() {
        guard phase == .countdown, let room, let role, let slot else { return }
        let others = room.present(at: clock.now).filter { $0.slot != slot }.map(\.name)
        let intention = others.isEmpty ? "" : String(localized: "Together with \(Self.names(others))")
        let minutes = TogetherRoom.sane(minutes: room.minutes)
        let config = FocusConfiguration(plannedSeconds: minutes * 60, category: room.category, intention: intention)
        guard startFocus(config) else {
            leave()
            error = .alreadyStarted
            return
        }
        let record = SharedFocus(roomCode: room.code, friendName: friendName ?? "", role: role,
                                 startedAt: clock.now, plannedMinutes: minutes)
        context.insert(record)
        try? context.save()
        shared = record
        pendingJoinCode = nil
        phase = .focusing
        Self.saveActive(code: room.code, slot: slot)
        Telemetry.log(.togetherStarted(role: role == .host ? "host" : "guest"))
    }

    private func startPolling() {
        guard let interval = pollInterval, polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                // Quick while waiting for the start; while focusing, arrivals
                // and departures show up within a few seconds.
                let waiting = self.map { $0.phase == .lobby || $0.phase == .countdown } ?? false
                try? await Task.sleep(for: waiting ? interval : interval * Self.focusPollFactor)
            }
        }
    }

    /// Focusing polls this many times slower than the lobby (1.5 s → 6 s).
    static let focusPollFactor = 4

    private func stopPolling() {
        polling?.cancel()
        polling = nil
    }

    private func run(_ work: () async throws -> Void) async {
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch let e as TogetherError {
            error = e
            Telemetry.log(.togetherFailed(reason: String(describing: e)))
        } catch {
            self.error = .unavailable
            Telemetry.log(.togetherFailed(reason: "unavailable"))
        }
    }

    /// "Ece", "Ece and Mert", "Ece, Mert and Ayla", "Ece, Mert and 3 more".
    static func names(_ names: [String]) -> String {
        guard names.count > 3 else { return names.formatted(.list(type: .and)) }
        let shown = names.prefix(2).joined(separator: ", ")
        return String(localized: "\(shown) and \(names.count - 2) more")
    }

    private static func tidy(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((trimmed.isEmpty ? String(localized: "A friend") : trimmed).prefix(24))
    }
}
