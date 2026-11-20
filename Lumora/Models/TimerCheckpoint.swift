import Foundation
import SwiftData

/// Persisted snapshot of the timer state machine (`TimerState`, JSON-encoded).
/// A single row; written synchronously on every state transition so a session
/// survives backgrounding, termination and relaunch.
@Model
final class TimerCheckpoint {
    var payload: Data = Data()
    var updatedAt: Date = Date.distantPast

    init(payload: Data, updatedAt: Date) {
        self.payload = payload
        self.updatedAt = updatedAt
    }
}
