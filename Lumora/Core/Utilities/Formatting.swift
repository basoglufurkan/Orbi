import Foundation

enum LMFormat {
    /// "23:36" or "1:02:05" for a remaining interval.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// "1h 35m", "45m", "0m".
    static func minutes(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return String(localized: "\(m)m") }
        if m == 0 { return String(localized: "\(h)h") }
        return String(localized: "\(h)h \(m)m")
    }

    /// Spoken form for VoiceOver: "1 hour 35 minutes".
    static func spokenMinutes(_ minutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) minutes"
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }
}
