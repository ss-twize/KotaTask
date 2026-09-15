import XCTest
@testable import KotaTaskMac

final class PriorityCalculatorTests: XCTestCase {

    let defaultWeights = PriorityWeights(
        urgency: 0.35,
        importance: 0.30,
        effort: 0.20,
        deadline: 0.15
    )

    func test_allMaxFactors_returns81() {
        let score = PriorityCalculator.calculate(
            urgency: 5, importance: 5, effort: 1,
            dueDate: nil,
            weights: defaultWeights
        )
        // urgency 1.0*0.35 + importance 1.0*0.30 + effort 0.8*0.20 + deadline 0*0.15
        // = 0.35 + 0.30 + 0.16 + 0 = 0.81 -> 81
        XCTAssertEqual(score, 81.0)
    }

    func test_allMinFactors_returnsLow() {
        let score = PriorityCalculator.calculate(
            urgency: 1, importance: 1, effort: 5,
            dueDate: nil,
            weights: defaultWeights
        )
        // 0.2*0.35 + 0.2*0.30 + 0.0*0.20 + 0.0*0.15 = 0.07 + 0.06 = 0.13 -> 13
        XCTAssertEqual(score, 13.0)
    }

    func test_overdueTask_higherThanNoDeadline() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let score = PriorityCalculator.calculate(
            urgency: 3, importance: 3, effort: 3, dueDate: yesterday, weights: defaultWeights
        )
        let scoreNoDeadline = PriorityCalculator.calculate(
            urgency: 3, importance: 3, effort: 3, dueDate: nil, weights: defaultWeights
        )
        XCTAssertGreaterThan(score, scoreNoDeadline)
    }

    func test_deadlineToday_higherThanNextWeek() {
        let today = Date()
        let nextWeek = Calendar.current.date(byAdding: .day, value: 8, to: Date())!
        let scoreToday = PriorityCalculator.calculate(
            urgency: 3, importance: 3, effort: 3, dueDate: today, weights: defaultWeights
        )
        let scoreNextWeek = PriorityCalculator.calculate(
            urgency: 3, importance: 3, effort: 3, dueDate: nextWeek, weights: defaultWeights
        )
        XCTAssertGreaterThan(scoreToday, scoreNextWeek)
    }

    func test_noDeadline_factorIsZero() {
        XCTAssertEqual(PriorityCalculator.deadlineFactor(dueDate: nil), 0.0)
    }

    func test_score_inRange0to100() {
        let score = PriorityCalculator.calculate(
            urgency: 4, importance: 4, effort: 2,
            dueDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()),
            weights: defaultWeights
        )
        XCTAssertGreaterThanOrEqual(score, 0.0)
        XCTAssertLessThanOrEqual(score, 100.0)
    }

    func test_customWeights_urgencyDominant() {
        let urgencyWeights = PriorityWeights(urgency: 0.90, importance: 0.05, effort: 0.03, deadline: 0.02)
        let highUrgency = PriorityCalculator.calculate(
            urgency: 5, importance: 1, effort: 5, dueDate: nil, weights: urgencyWeights
        )
        let lowUrgency = PriorityCalculator.calculate(
            urgency: 1, importance: 5, effort: 1, dueDate: nil, weights: urgencyWeights
        )
        XCTAssertGreaterThan(highUrgency, lowUrgency)
    }
}
