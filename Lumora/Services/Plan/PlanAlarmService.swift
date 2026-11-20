import AppIntents
import Foundation
import SwiftUI
import os
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Real alarms for plan blocks that ask for one: on iOS 26.1 and later
/// AlarmKit rings them like a clock alarm, through Silent mode and Focus.
/// Everywhere else the block's notifications are the reminder.
@MainActor
final class PlanAlarmService {
    enum Access: Equatable { case unsupported, notDetermined, denied, authorized }

    private let logger = Logger(subsystem: "com.mobapptech.lumora", category: "PlanAlarms")

    var access: Access {
        #if canImport(AlarmKit)
        if #available(iOS 26.1, *) {
            switch AlarmManager.shared.authorizationState {
            case .notDetermined: return .notDetermined
            case .denied: return .denied
            case .authorized: return .authorized
            @unknown default: return .denied
            }
        }
        #endif
        return .unsupported
    }

    var isSupported: Bool { access != .unsupported }
    var isAuthorized: Bool { access == .authorized }

    /// Asks once; returns whether alarms may ring.
    @discardableResult
    func requestAuthorization() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.1, *) {
            do {
                let state = try await AlarmManager.shared.requestAuthorization()
                Telemetry.log(.notificationPermission(granted: state == .authorized, source: "plan_alarm"))
                return state == .authorized
            } catch {
                logger.error("Alarm authorization failed: \(error.localizedDescription)")
            }
        }
        #endif
        return false
    }

    /// Makes the scheduled alarms exactly `wanted`: each block's alarm is
    /// identified by the block's ID, so a moved block's alarm moves with it.
    func sync(_ wanted: [PlanAlarmRequest]) async {
        #if canImport(AlarmKit)
        guard #available(iOS 26.1, *), isAuthorized else { return }
        let manager = AlarmManager.shared
        let existing = (try? manager.alarms) ?? []
        let wantedByID = Dictionary(wanted.map { ($0.block.id, $0) }, uniquingKeysWith: { first, _ in first })
        for alarm in existing {
            // A ringing alarm is the person's to stop; leave it be.
            guard alarm.state != .alerting else { continue }
            if let want = wantedByID[alarm.id], alarm.schedule == .fixed(want.fireDate) { continue }
            try? manager.cancel(id: alarm.id)
        }
        let kept = Set(existing.filter { alarm in
            alarm.state == .alerting || wantedByID[alarm.id].map { alarm.schedule == .fixed($0.fireDate) } == true
        }.map(\.id))
        for request in wanted where !kept.contains(request.block.id) {
            do {
                try await Self.schedule(request)
            } catch {
                logger.error("Alarm scheduling failed: \(error.localizedDescription)")
            }
        }
        #endif
    }

    #if canImport(AlarmKit)
    /// Built and handed to AlarmKit off the main actor: the configuration isn't Sendable.
    @available(iOS 26.1, *)
    private nonisolated static func schedule(_ request: PlanAlarmRequest) async throws {
        _ = try await AlarmManager.shared.schedule(id: request.block.id, configuration: configuration(for: request))
    }

    @available(iOS 26.1, *)
    private nonisolated static func configuration(for request: PlanAlarmRequest) -> AlarmManager.AlarmConfiguration<PlanAlarmMetadata> {
        let block = request.block
        let focus = AlarmButton(text: "Focus", textColor: Color(hex: Palette.deepSpace), systemImageName: "sparkle")
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: block.title),
                                            secondaryButton: focus, secondaryButtonBehavior: .custom)
        let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                                         metadata: PlanAlarmMetadata(blockID: block.id),
                                         tintColor: block.category.color)
        return .alarm(schedule: .fixed(block.start), attributes: attributes,
                      secondaryIntent: StartPlanBlockFocusIntent(blockID: block.id.uuidString))
    }
    #endif
}

#if canImport(AlarmKit)
/// What a plan alarm carries: the block it rings for.
@available(iOS 26.0, *)
struct PlanAlarmMetadata: AlarmMetadata {
    var blockID: UUID
}
#endif

/// The alarm's "Focus" button: opens Lumora and begins focusing on the block.
struct StartPlanBlockFocusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Focus on a planned block"
    static let openAppWhenRun = true
    static let isDiscoverable = false

    @Parameter(title: "Block") var blockID: String

    init() {}

    init(blockID: String) {
        self.blockID = blockID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: blockID) else { return .result() }
        let app = try AppRuntime.model()
        app.prepareForIntent()
        app.requestPlanFocus(id, source: "alarm")
        return .result()
    }
}
