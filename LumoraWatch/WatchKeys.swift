import Foundation

/// What the iPhone publishes about its timer. Keys mirror
/// Lumora/Services/System/WatchSyncService.swift and AppModel.watchState().
struct PhoneState: Equatable {
    enum Phase: String { case idle, focusing, paused, `break` }

    var phase: Phase = .idle
    /// Real time the running segment ends (nil while paused or idle).
    var endsAt: Date?
    /// Real seconds left, as of when the phone sent this.
    var remaining: TimeInterval = 0
    var duration: TimeInterval = 0
    var category = ""
    var intention = ""
    var todayMinutes = 0
    var goalMinutes = 120
    var stars = 0
    var defaultMinutes = 25

    init() {}

    init(_ d: [String: Any]) {
        phase = (d["phase"] as? String).flatMap(Phase.init(rawValue:)) ?? .idle
        endsAt = (d["endsAt"] as? Double).map(Date.init(timeIntervalSince1970:))
        remaining = d["remaining"] as? Double ?? 0
        duration = d["duration"] as? Double ?? 0
        category = d["category"] as? String ?? ""
        intention = d["intention"] as? String ?? ""
        todayMinutes = d["todayMinutes"] as? Int ?? 0
        goalMinutes = d["goalMinutes"] as? Int ?? 120
        stars = d["stars"] as? Int ?? 0
        defaultMinutes = d["defaultMinutes"] as? Int ?? 25
    }

    var isFocusing: Bool { phase == .focusing || phase == .paused }

    func remaining(at now: Date) -> TimeInterval {
        if let endsAt { return max(0, endsAt.timeIntervalSince(now)) }
        return remaining
    }

    func progress(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(at: now) / duration))
    }
}
