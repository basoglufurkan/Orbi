import Foundation
import WatchConnectivity

/// Keeps the Apple Watch app in step with the iPhone timer. The phone stays
/// the single source of truth: the watch sends start / pause / resume / end
/// requests (which wake the app if needed) and draws whatever state the
/// phone last published. Keys are mirrored in LumoraWatch/WatchKeys.swift.
@MainActor
final class WatchSyncService: NSObject {
    enum Action: String {
        case start, pause, resume, end
    }

    /// The state to publish, as a property-list dictionary.
    var currentState: () -> [String: Any] = { [:] }
    /// Carries out a request from the watch.
    var perform: (Action, Int?) -> Void = { _, _ in }

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Sends the latest state; only the newest context is ever delivered.
    func publish() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        var state = currentState()
        state["rev"] = Date().timeIntervalSince1970
        try? session.updateApplicationContext(state)
    }
}

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.publish() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // A new watch was paired: start talking to it.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.publish() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let action = (message["action"] as? String).flatMap(Action.init(rawValue:))
        let minutes = message["minutes"] as? Int
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in
            if let action { self.perform(action, minutes) }
            var state = self.currentState()
            state["rev"] = Date().timeIntervalSince1970
            reply(state)
            self.publish()
        }
    }
}
