import Foundation

/// A shared focus room for up to `capacity` people. The host creates it and
/// shares its code; friends join with the code, before or after the host
/// starts; everyone focuses for the same length. Only what's here ever
/// leaves the device.
struct TogetherRoom: Equatable, Sendable {
    var code: String
    var minutes: Int
    var categoryRaw: String
    var createdAt: Date
    /// Set by the host when they press Start; people in the lobby begin then,
    /// anyone joining later begins on arrival.
    var startsAt: Date?
    /// Everyone who has been in the room, host first (slot 0), by slot.
    var members: [TogetherMember]

    init(code: String, hostName: String, minutes: Int, categoryRaw: String, createdAt: Date,
         startsAt: Date? = nil, members: [TogetherMember] = []) {
        self.code = code
        self.minutes = minutes
        self.categoryRaw = categoryRaw
        self.createdAt = createdAt
        self.startsAt = startsAt
        let host = TogetherMember(slot: 0, name: hostName, joinedAt: createdAt, seenAt: createdAt)
        self.members = [host] + members.filter { $0.slot != 0 }.sorted { $0.slot < $1.slot }
    }

    var category: FocusCategory { FocusCategory(rawValue: categoryRaw) ?? .work }
    var host: TogetherMember? { member(0) }
    var hostName: String { host?.name ?? "" }

    func member(_ slot: Int) -> TogetherMember? { members.first { $0.slot == slot } }

    /// The people in the room right now, host first.
    func present(at now: Date) -> [TogetherMember] { members.filter { $0.isPresent(at: now) } }

    /// The host plus up to seven friends.
    static let capacity = 8
    /// Rooms come from another person's device through the public database,
    /// so what they say is kept to what the app could have written itself.
    static let minuteRange = 1...180
    static let nameLimit = 24

    static func sane(minutes: Int) -> Int { min(max(minutes, minuteRange.lowerBound), minuteRange.upperBound) }
    static func sane(name: String) -> String { String(name.prefix(nameLimit)) }

    /// Rooms are for focusing now, not later: after a few hours a code is spent.
    func isExpired(at now: Date) -> Bool { now.timeIntervalSince(createdAt) > 4 * 3600 }
}

/// One person in a room. Each device writes only its own record, and tells
/// the others it's still there with `seenAt`; a person who stops doing so
/// (closed the app, lost connection) drops out after `presenceTimeout`.
struct TogetherMember: Equatable, Sendable, Identifiable {
    var slot: Int
    var name: String
    var joinedAt: Date
    var seenAt: Date
    var doneAt: Date?
    var leftAt: Date?

    var id: Int { slot }
    var isHost: Bool { slot == 0 }

    /// In the room: hasn't finished, hasn't left, and was heard from recently.
    func isPresent(at now: Date) -> Bool {
        doneAt == nil && leftAt == nil && now.timeIntervalSince(seenAt) < Self.presenceTimeout
    }

    /// How often a device says it's still there, and how long silence is tolerated.
    static let heartbeat: TimeInterval = 20
    static let presenceTimeout: TimeInterval = 75
}

enum TogetherRole: String, Sendable {
    case host, guest
}

enum TogetherError: LocalizedError, Equatable {
    case noRoom
    case roomFull
    case alreadyStarted
    case notSignedIn
    case unavailable

    var errorDescription: String? {
        switch self {
        case .noRoom: String(localized: "There's no room with that code. Check it with your friend.")
        case .roomFull: String(localized: "This room is full. Up to 8 people can focus together.")
        case .alreadyStarted: String(localized: "A session is already running. End it to focus together.")
        case .notSignedIn: String(localized: "Sign in to iCloud in Settings to focus together.")
        case .unavailable: String(localized: "Couldn't reach iCloud. Check your connection and try again.")
        }
    }
}

/// Invite codes and links. Codes follow `TogetherCode`; links are
/// `DeepLink.join`, shared as the web form so messaging apps make them tappable.
enum TogetherInvite {
    static let alphabet = TogetherCode.alphabet
    static let length = TogetherCode.length

    static func newCode() -> String {
        var rng = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &rng)! })
    }

    static func normalize(_ raw: String) -> String { TogetherCode.normalize(raw) }

    static func isValid(_ code: String) -> Bool { TogetherCode.isValid(code) }

    static func link(for code: String) -> URL { DeepLink.join(code: code).webURL }

    /// The code in an invite link, if it is one.
    static func code(from url: URL) -> String? {
        guard case let .join(code) = DeepLink(url: url) else { return nil }
        return code
    }
}
