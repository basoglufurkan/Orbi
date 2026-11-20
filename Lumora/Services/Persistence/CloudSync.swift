import CloudKit
import CoreData
import Foundation
import Observation

/// iCloud sync of the person's history to their private CloudKit database,
/// so a new phone or an iPad shows the same sky.
///
/// Only the synced store mirrors (see `DataStore`); the sky itself is redrawn
/// from that history on each device. The switch is read when the store opens,
/// so turning it on or off takes effect on the next launch.
@MainActor
@Observable
final class CloudSync {
    nonisolated static let enabledKey = "lumora.iCloudSync"

    /// On unless the person turned it off.
    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    enum Account: Equatable {
        case checking, available, noAccount, restricted, unavailable
    }

    /// Whether this launch opened the store with iCloud.
    let isActive: Bool
    /// The switch in Settings; applies from the next launch.
    var wantsSync: Bool {
        didSet { UserDefaults.standard.set(wantsSync, forKey: Self.enabledKey) }
    }
    private(set) var account: Account = .checking
    private(set) var lastChangeAt: Date?

    /// Called on the main actor, a moment after changes arrive from iCloud.
    @ObservationIgnored var didReceiveChanges: (() -> Void)?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(isActive: Bool) {
        self.isActive = isActive
        self.wantsSync = Self.isEnabled
        guard isActive else { return }
        // Imports arrive in bursts; settle before folding and redrawing.
        observers.append(NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleChanges() }
        })
        // Setup and export events say nothing new arrived; only a finished import does.
        observers.append(NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  event.type == .import, event.endDate != nil else { return }
            MainActor.assumeIsolated { self?.scheduleChanges() }
        })
    }

    var settingChangedSinceLaunch: Bool { wantsSync != isActive }

    func refreshAccount() async {
        do {
            account = switch try await CKContainer(identifier: DataStore.cloudContainerID).accountStatus() {
            case .available: .available
            case .noAccount: .noAccount
            case .restricted: .restricted
            default: .unavailable
            }
        } catch {
            account = .unavailable
        }
    }

    private func scheduleChanges() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            lastChangeAt = .now
            didReceiveChanges?()
        }
    }
}
