import Foundation
import Testing
@testable import Lumora

@Suite("Year in review")
struct YearReviewTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TestFixtures.istanbul
        return c
    }()

    private func fact(_ day: Int, month: Int = 3, year: Int = 2026, minutes: Int, category: FocusCategory = .coding,
                      outcome: SessionOutcome = .completed) -> SessionFacts {
        let end = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 10))!
        return SessionFacts(id: UUID(), startedAt: end.addingTimeInterval(-Double(minutes * 60)), endedAt: end,
                            dayKey: DayKey(end, calendar: calendar), focusedSeconds: minutes * 60,
                            plannedSeconds: minutes * 60, pauseCount: 0, category: category, outcome: outcome, intention: "")
    }

    @Test func tellsTheYearInFacts() {
        let facts = [
            fact(1, minutes: 25), fact(2, minutes: 25, category: .study), fact(3, minutes: 60),
            fact(3, minutes: 45), fact(10, minutes: 25, category: .study),
            fact(11, minutes: 3, outcome: .tooShort),                 // no star: left out
            fact(5, year: 2025, minutes: 90),                         // another year: left out
        ]
        let review = YearReview.make(year: 2026, facts: facts, calendar: calendar)
        #expect(review.sessions == 5)
        #expect(review.totalMinutes == 180)
        #expect(review.activeDays == 4)
        #expect(review.brightestDay?.minutes == 105)
        #expect(review.longestSession?.minutes == 60)
        #expect(review.topCategory?.category == .coding)
        #expect(abs((review.topCategory?.fraction ?? 0) - 130.0 / 180.0) < 0.001)
        #expect(review.longestRun == 3)
        #expect(YearCard.cards(for: review).first == .intro)
        #expect(YearCard.cards(for: review).last == .finale)
        #expect(!YearCard.cards(for: review).contains(.odyssey))
    }

    @Test func anEmptyYearHasNothingToShow() {
        let review = YearReview.make(year: 2026, facts: [fact(1, year: 2025, minutes: 25)], calendar: calendar)
        #expect(!review.hasContent)
    }
}
