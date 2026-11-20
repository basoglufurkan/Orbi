import Foundation
import SwiftData
import os

/// Where the timer state machine checkpoints itself.
@MainActor
protocol TimerStateStore: AnyObject {
    func load() -> TimerState?
    func save(_ state: TimerState) throws
}

/// Volatile store for tests and previews.
@MainActor
final class InMemoryTimerStateStore: TimerStateStore {
    private(set) var saved: TimerState?
    private(set) var saveCount = 0

    init(_ initial: TimerState? = nil) { saved = initial }

    func load() -> TimerState? { saved }

    func save(_ state: TimerState) throws {
        saved = state
        saveCount += 1
    }
}

/// Production store: a single `TimerCheckpoint` row in SwiftData, saved
/// synchronously on every transition.
@MainActor
final class SwiftDataTimerStateStore: TimerStateStore {
    private let context: ModelContext
    private let logger = Logger(subsystem: "com.mobapptech.lumora", category: "TimerStore")

    init(context: ModelContext) { self.context = context }

    func load() -> TimerState? {
        guard let row = fetchRow() else { return nil }
        do {
            return try JSONDecoder().decode(TimerState.self, from: row.payload)
        } catch {
            // A corrupt checkpoint must never brick the app: start idle.
            logger.error("Discarding unreadable timer checkpoint: \(error.localizedDescription)")
            return nil
        }
    }

    func save(_ state: TimerState) throws {
        let data = try JSONEncoder().encode(state)
        if let row = fetchRow() {
            row.payload = data
            row.updatedAt = .now
        } else {
            context.insert(TimerCheckpoint(payload: data, updatedAt: .now))
        }
        try context.save()
    }

    private func fetchRow() -> TimerCheckpoint? {
        var descriptor = FetchDescriptor<TimerCheckpoint>()
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
