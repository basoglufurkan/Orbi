import Foundation
import SwiftData

/// A session focused together with a friend. It ties your star to theirs:
/// the universe draws a bridge of light to a companion star in their name.
@Model
final class SharedFocus {
    var id: UUID = UUID()
    var roomCode: String = ""
    var friendName: String = ""
    var roleRaw: String = TogetherRole.host.rawValue
    var startedAt: Date = Date.distantPast
    var plannedMinutes: Int = 25
    /// The session this produced, once it was recorded.
    var sessionID: UUID?
    var friendFinished: Bool = false

    init(roomCode: String, friendName: String, role: TogetherRole, startedAt: Date, plannedMinutes: Int) {
        self.roomCode = roomCode
        self.friendName = friendName
        self.roleRaw = role.rawValue
        self.startedAt = startedAt
        self.plannedMinutes = plannedMinutes
    }

    var role: TogetherRole { TogetherRole(rawValue: roleRaw) ?? .host }
}
