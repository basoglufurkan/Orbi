import Foundation
import Observation
import WatchConnectivity
import WatchKit

/// The watch's view of the iPhone timer, and the way to ask it to act.
@MainActor
@Observable
final class WatchSession: NSObject {
    private(set) var state = PhoneState()
    /// A session just finished on the wrist: show the new star.
    var celebrating = false
    /// The last request couldn't reach the iPhone.
    private(set) var unreachable = false

    private var watchedEnd: Date?

    func activate() {
        #if DEBUG
        if showDemo() { return }
        #endif
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func start(minutes: Int) { send("start", minutes: minutes, haptic: .start) }
    func pause() { send("pause", haptic: .click) }
    func resume() { send("resume", haptic: .start) }
    func end() { send("end", haptic: .stop) }

    /// Called every second while the countdown is on screen.
    func tick(at now: Date) {
        guard state.phase == .focusing, let end = state.endsAt, now >= end, watchedEnd != end else { return }
        finish(end)
    }

    private func send(_ action: String, minutes: Int? = nil, haptic: WKHapticType) {
        WKInterfaceDevice.current().play(haptic)
        let session = WCSession.default
        guard session.activationState == .activated else {
            unreachable = true
            session.activate()
            return
        }
        var message: [String: Any] = ["action": action]
        if let minutes { message["minutes"] = minutes }
        Self.deliver(message, via: session, to: self)
    }

    /// WatchConnectivity calls back on its own queue, so the handlers are
    /// built outside the main actor and hop back to it explicitly.
    nonisolated private static func deliver(_ message: [String: Any], via session: WCSession, to watch: WatchSession) {
        session.sendMessage(message, replyHandler: { reply in
            nonisolated(unsafe) let copy = reply
            Task { @MainActor in watch.apply(copy) }
        }, errorHandler: { _ in
            Task { @MainActor in watch.unreachable = true }
        })
    }

    private func apply(_ dictionary: [String: Any]) {
        let next = PhoneState(dictionary)
        // A focus that ran out between updates still deserves its moment.
        if state.phase == .focusing, let end = state.endsAt, next.phase != .focusing && next.phase != .paused,
           end <= Date().addingTimeInterval(2), watchedEnd != end {
            finish(end)
        }
        state = next
        unreachable = false
    }

    #if DEBUG
    /// Screenshots without a paired iPhone: `-lumora-watch-demo home|focus|star`.
    private func showDemo() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-lumora-watch-demo"), i + 1 < args.count else { return false }
        var demo = PhoneState()
        demo.todayMinutes = 70
        demo.stars = 72
        switch args[i + 1] {
        case "focus":
            demo.phase = .focusing
            // The iPhone sends its own (localized) category name.
            let c = args.firstIndex(of: "-lumora-watch-demo-category")
            demo.category = c.map { $0 + 1 < args.count ? args[$0 + 1] : "Study" } ?? "Study"
            demo.duration = 25 * 60
            demo.endsAt = Date().addingTimeInterval(16 * 60 + 42)
        case "star":
            celebrating = true
        default:
            break
        }
        state = demo
        return true
    }
    #endif

    private func finish(_ end: Date) {
        watchedEnd = end
        WKInterfaceDevice.current().play(.success)
        celebrating = true
    }
}

extension WatchSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let context = session.receivedApplicationContext
        nonisolated(unsafe) let copy = context
        Task { @MainActor in if !copy.isEmpty { self.apply(copy) } }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        nonisolated(unsafe) let copy = applicationContext
        Task { @MainActor in self.apply(copy) }
    }
}
