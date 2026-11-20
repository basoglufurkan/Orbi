import SwiftUI

/// How much motion the app may use, combining the system Reduce Motion
/// setting with the in-app preference and constrained-device detection.
enum MotionLevel: Int, Comparable, Sendable {
    /// No loops, no particles, crossfades only.
    case reduced = 0
    /// Calm loops, fewer particles (older / Low Power devices, or user choice).
    case simplified = 1
    case full = 2

    static func < (lhs: MotionLevel, rhs: MotionLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var particleBudget: Int {
        switch self {
        case .reduced: 0
        case .simplified: 120
        case .full: 240
        }
    }

    var animatesContinuously: Bool { self != .reduced }

    /// Seconds between frames for an ambient loop that looks right at `fps`.
    /// Calm motion (Low Power, older devices, or the user's choice) runs it
    /// at half the rate: the drift reads the same and the battery lasts.
    func frameInterval(_ fps: Double) -> TimeInterval {
        1 / (self == .full ? fps : fps / 2)
    }
}

enum MotionPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, simplified, reduced
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: String(localized: "Full")
        case .simplified: String(localized: "Calm")
        case .reduced: String(localized: "Minimal")
        }
    }

    func resolve(systemReduceMotion: Bool, lowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled) -> MotionLevel {
        if systemReduceMotion || self == .reduced { return .reduced }
        if self == .simplified || lowPower || DeviceClass.isConstrained { return .simplified }
        return .full
    }
}

enum DeviceClass {
    /// A13/A14-class devices (and anything with little memory) get the
    /// simplified particle budget. Heuristic based on physical memory.
    static let isConstrained: Bool = ProcessInfo.processInfo.physicalMemory < 5_000_000_000
        && ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] == nil
}

private struct MotionLevelKey: EnvironmentKey {
    static let defaultValue: MotionLevel = .full
}

extension EnvironmentValues {
    /// Resolved motion level for the current scene.
    var motionLevel: MotionLevel {
        get { self[MotionLevelKey.self] }
        set { self[MotionLevelKey.self] = newValue }
    }
}
