import CloudKit
import Foundation

/// Where rooms live. The app uses CloudKit's public database; tests and the
/// debug demo use an in-memory stand-in. Slot 0 is always the host.
protocol TogetherBackend: Sendable {
    func create(_ room: TogetherRoom) async throws
    func room(code: String) async throws -> TogetherRoom?
    /// Takes the first free seat in a room and returns its slot (fails when full).
    func join(code: String, name: String, at date: Date) async throws -> Int
    func start(code: String, at date: Date) async throws
    /// "Still here": keeps this person in everyone's galaxy.
    func heartbeat(code: String, slot: Int, at date: Date) async throws
    func finish(code: String, slot: Int, at date: Date) async throws
    func leave(code: String, slot: Int, at date: Date) async throws
}

// MARK: - CloudKit

/// Rooms in the public database of the app's container (`DataStore.cloudContainerID`). Records
/// are addressed by name (`room-CODE` for the host, `member-CODE-1` …
/// `member-CODE-7` for each friend's seat), so nothing needs a query index.
/// Public records can only be changed by whoever made them, so every device
/// writes only its own record and reads everyone else's.
struct CloudKitTogetherBackend: TogetherBackend {
    private var database: CKDatabase { CKContainer(identifier: DataStore.cloudContainerID).publicCloudDatabase }

    private static func roomID(_ code: String) -> CKRecord.ID { CKRecord.ID(recordName: "room-\(code)") }
    private static func memberID(_ code: String, _ slot: Int) -> CKRecord.ID { CKRecord.ID(recordName: "member-\(code)-\(slot)") }
    private static var seats: ClosedRange<Int> { 1...(TogetherRoom.capacity - 1) }

    func create(_ room: TogetherRoom) async throws {
        let record = CKRecord(recordType: "FocusRoom", recordID: Self.roomID(room.code))
        record["hostName"] = room.hostName
        record["minutes"] = room.minutes
        record["category"] = room.categoryRaw
        record["createdAt"] = room.createdAt
        record["hostSeenAt"] = room.createdAt
        try await perform { _ = try await database.save(record) }
    }

    func room(code: String) async throws -> TogetherRoom? {
        try await perform {
            guard let record = try await fetch(Self.roomID(code)) else { return nil }
            let createdAt = record["createdAt"] as? Date ?? .distantPast
            var room = TogetherRoom(code: code,
                                    hostName: TogetherRoom.sane(name: record["hostName"] as? String ?? ""),
                                    minutes: TogetherRoom.sane(minutes: record["minutes"] as? Int ?? 25),
                                    categoryRaw: record["category"] as? String ?? FocusCategory.work.rawValue,
                                    createdAt: createdAt,
                                    startsAt: record["startsAt"] as? Date,
                                    members: try await members(code))
            room.members[0].seenAt = record["hostSeenAt"] as? Date ?? createdAt
            room.members[0].doneAt = record["hostDoneAt"] as? Date
            room.members[0].leftAt = record["hostLeftAt"] as? Date
            return room
        }
    }

    func join(code: String, name: String, at date: Date) async throws -> Int {
        try await perform {
            let taken = Set(try await members(code).map(\.slot))
            for slot in Self.seats where !taken.contains(slot) {
                let member = CKRecord(recordType: "FocusRoomMember", recordID: Self.memberID(code, slot))
                member["name"] = name
                member["joinedAt"] = date
                member["seenAt"] = date
                do {
                    _ = try await database.save(member)
                    return slot
                } catch let error as CKError where error.code == .serverRecordChanged {
                    continue   // someone took this seat a moment ago
                }
            }
            throw TogetherError.roomFull
        }
    }

    func start(code: String, at date: Date) async throws {
        try await patch(Self.roomID(code), type: "FocusRoom") { $0["startsAt"] = date }
    }

    func heartbeat(code: String, slot: Int, at date: Date) async throws {
        try await write(code: code, slot: slot, host: "hostSeenAt", member: "seenAt", date: date)
    }

    func finish(code: String, slot: Int, at date: Date) async throws {
        try await write(code: code, slot: slot, host: "hostDoneAt", member: "doneAt", date: date)
    }

    func leave(code: String, slot: Int, at date: Date) async throws {
        try await write(code: code, slot: slot, host: "hostLeftAt", member: "leftAt", date: date)
    }

    private func write(code: String, slot: Int, host: String, member: String, date: Date) async throws {
        if slot == 0 {
            try await patch(Self.roomID(code), type: "FocusRoom") { $0[host] = date }
        } else {
            try await patch(Self.memberID(code, slot), type: "FocusRoomMember") { $0[member] = date }
        }
    }

    /// Every friend's seat that exists, in one round trip.
    private func members(_ code: String) async throws -> [TogetherMember] {
        let ids = Self.seats.map { Self.memberID(code, $0) }
        let results = try await database.records(for: ids)
        return Self.seats.compactMap { slot in
            guard case let .success(record)? = results[Self.memberID(code, slot)] else { return nil }
            let joined = record["joinedAt"] as? Date ?? .distantPast
            return TogetherMember(slot: slot,
                                  name: TogetherRoom.sane(name: record["name"] as? String ?? ""),
                                  joinedAt: joined,
                                  seenAt: record["seenAt"] as? Date ?? joined,
                                  doneAt: record["doneAt"] as? Date,
                                  leftAt: record["leftAt"] as? Date)
        }
    }

    private func fetch(_ id: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    /// Changes only the given fields of one's own record, without reading it first.
    private func patch(_ id: CKRecord.ID, type: String, _ change: (CKRecord) -> Void) async throws {
        try await perform {
            let record = CKRecord(recordType: type, recordID: id)
            change(record)
            let (saved, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys)
            if case let .failure(error)? = saved[id] { throw error }
        }
    }

    /// Turns CloudKit's errors into ones a person can act on.
    private func perform<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as TogetherError {
            throw error
        } catch let error as CKError {
            switch error.code {
            case .notAuthenticated: throw TogetherError.notSignedIn
            default: throw TogetherError.unavailable
            }
        }
    }
}

// MARK: - In memory

/// Rooms that live only in this process, for tests and the debug demo.
/// With `simulatedFriends`, those friends join a hosted room one after
/// another, the last one leaves partway through, and the rest finish when
/// the host does.
actor LocalTogetherBackend: TogetherBackend {
    private var rooms: [String: TogetherRoom] = [:]
    private let simulatedFriends: [String]
    private let friendDelay: Duration

    init(simulatedFriends: [String] = [], friendDelay: Duration = .seconds(2)) {
        self.simulatedFriends = simulatedFriends
        self.friendDelay = friendDelay
    }

    func create(_ room: TogetherRoom) async throws {
        rooms[room.code] = room
        guard !simulatedFriends.isEmpty else { return }
        let friends = simulatedFriends
        let delay = friendDelay
        Task {
            var slots: [Int] = []
            for friend in friends {
                try? await Task.sleep(for: delay)
                if let slot = try? await self.join(code: room.code, name: friend, at: Date()) {
                    self.keepAlive(code: room.code, slot: slot)
                    slots.append(slot)
                }
            }
            // One friend heads off early, so leaving can be seen too.
            guard friends.count > 1, let last = slots.last else { return }
            try? await Task.sleep(for: delay * 10)
            try? await self.leave(code: room.code, slot: last, at: Date())
        }
    }

    func room(code: String) async throws -> TogetherRoom? { rooms[code] }

    func join(code: String, name: String, at date: Date) async throws -> Int {
        guard var room = rooms[code] else { throw TogetherError.noRoom }
        let taken = Set(room.members.map(\.slot))
        guard let slot = (1..<TogetherRoom.capacity).first(where: { !taken.contains($0) }) else { throw TogetherError.roomFull }
        room.members.append(TogetherMember(slot: slot, name: name, joinedAt: date, seenAt: date))
        rooms[code] = room
        return slot
    }

    func start(code: String, at date: Date) async throws {
        guard rooms[code] != nil else { throw TogetherError.noRoom }
        rooms[code]?.startsAt = date
    }

    func heartbeat(code: String, slot: Int, at date: Date) async throws {
        try change(code, slot) { $0.seenAt = date }
    }

    func finish(code: String, slot: Int, at date: Date) async throws {
        try change(code, slot) { $0.doneAt = date }
        // Simulated friends finish with the host.
        guard slot == 0, !simulatedFriends.isEmpty, let room = rooms[code] else { return }
        for member in room.members where member.slot != 0 && member.doneAt == nil && member.leftAt == nil {
            try change(code, member.slot) { $0.doneAt = date }
        }
    }

    func leave(code: String, slot: Int, at date: Date) async throws {
        try change(code, slot) { $0.leftAt = date }
    }

    /// Test helper: seed a room someone else is hosting.
    func seed(_ room: TogetherRoom) { rooms[room.code] = room }

    /// Simulated friends never go quiet.
    private func keepAlive(code: String, slot: Int) {
        try? change(code, slot) { $0.seenAt = .distantFuture }
    }

    private func change(_ code: String, _ slot: Int, _ update: (inout TogetherMember) -> Void) throws {
        guard var room = rooms[code], let i = room.members.firstIndex(where: { $0.slot == slot }) else { throw TogetherError.noRoom }
        update(&room.members[i])
        rooms[code] = room
    }
}
