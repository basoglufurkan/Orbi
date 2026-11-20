import Foundation
import Observation

/// Something Pell has to say: peeks in from the edge of the screen, says it,
/// and slips away. Each tip is shown once (or once per `id`, which can carry
/// a day for daily notes).
struct PellTip: Identifiable, Equatable {
    enum Edge { case leading, trailing }
    /// Which layer shows it: the tabs, or the focus flow above them.
    enum Scope { case main, focus }
    enum Action: Equatable { case askName }

    var id: String
    var message: String
    var mood: PellExpression = .happy
    var edge: Edge = .trailing
    var scope: Scope = .main
    /// A button under the message, e.g. "Tell Pell your name".
    var action: Action?
    var actionTitle: String?
}

/// Pell's notes, one at a time. What's been said is remembered on this
/// device, so a tip never nags.
@MainActor
@Observable
final class PellGuide {
    private(set) var current: PellTip?
    /// A note waiting for the current one to leave.
    @ObservationIgnored private var queue: [PellTip] = []
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var seen: Set<String>
    /// Off for UI tests and screenshots, so nothing covers what they look at.
    @ObservationIgnored var isEnabled = true

    private static let seenKey = "lumora.pell.seen"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        seen = Set(defaults.stringArray(forKey: Self.seenKey) ?? [])
    }

    func hasSeen(_ id: String) -> Bool { seen.contains(id) }

    /// Shows `tip` a moment from now, unless it was already said. The delay
    /// lets the screen settle first, so Pell arrives into a still scene.
    func offer(_ tip: PellTip, after delay: Duration = .seconds(0.9)) {
        guard isEnabled, !seen.contains(tip.id), current?.id != tip.id, !queue.contains(where: { $0.id == tip.id }) else { return }
        queue.append(tip)
        guard current == nil, pending == nil else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.pending = nil
            self?.showNext()
        }
    }

    /// Pell leaves; the next note, if any, follows shortly.
    func dismiss() {
        current = nil
        guard !queue.isEmpty, pending == nil else { return }
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled else { return }
            self?.pending = nil
            self?.showNext()
        }
    }

    /// Drops whatever is waiting (e.g. a screen with its own notes closed).
    func clear(scope: PellTip.Scope) {
        queue.removeAll { $0.scope == scope }
        if current?.scope == scope { current = nil }
    }

    /// Forgets every note, so they come back (Erase all data).
    func reset() {
        pending?.cancel()
        pending = nil
        queue.removeAll()
        current = nil
        seen.removeAll()
        defaults.removeObject(forKey: Self.seenKey)
    }

    private func showNext() {
        guard current == nil, !queue.isEmpty else { return }
        let tip = queue.removeFirst()
        current = tip
        seen.insert(tip.id)
        defaults.set(Array(seen), forKey: Self.seenKey)
    }
}
