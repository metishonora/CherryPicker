import Foundation
import XCTest

@testable import CherryPickerCore

final class CardPolicyTests: XCTestCase {
    func testPerformanceRequirementDistinguishesNoRequirementFromPositiveTarget() throws {
        let noRequirement = try PerformanceRequirement(monthlyTargetAmount: nil)
        let target = try PerformanceRequirement(monthlyTargetAmount: 300_000)

        XCTAssertFalse(noRequirement.isEnabled)
        XCTAssertNil(noRequirement.monthlyTargetAmount)
        XCTAssertTrue(target.isEnabled)
        XCTAssertEqual(target.monthlyTargetAmount, 300_000)
    }

    func testPerformanceRequirementRejectsZeroAndNegativeTargets() {
        XCTAssertThrowsError(try PerformanceRequirement(monthlyTargetAmount: 0))
        XCTAssertThrowsError(try PerformanceRequirement(monthlyTargetAmount: -1))
    }

    func testCalendarMonthUsesSeoulStartInclusiveEndExclusiveBoundaries() throws {
        let resolver = DefaultPerformancePeriodResolver()
        let rule = PerformancePeriodRule.calendarMonth(timeZoneIdentifier: "Asia/Seoul")
        let reference = try makeDate("2026-08-15T12:00:00+09:00")

        let period = try resolver.period(containing: reference, rule: rule)

        XCTAssertEqual(period.start, try makeDate("2026-08-01T00:00:00+09:00"))
        XCTAssertEqual(period.end, try makeDate("2026-09-01T00:00:00+09:00"))
        XCTAssertTrue(period.start >= period.start && period.start < period.end)
        XCTAssertFalse(period.end >= period.start && period.end < period.end)
    }

    func testYearResolverTreatsDecemberTransactionReceivedInJanuaryAsPreviousYear() throws {
        let resolver = DefaultTransactionDateResolver()
        let partial = try ParsedLocalDate(
            month: 12,
            day: 31,
            hour: 23,
            minute: 50,
            timeZoneIdentifier: "Asia/Seoul"
        )
        let receivedAt = try makeDate("2027-01-01T00:10:00+09:00")

        let resolved = try resolver.resolve(partial, receivedAt: receivedAt)

        XCTAssertEqual(resolved.localComponents.year, 2026)
        XCTAssertEqual(resolved.source, .inferred)
        XCTAssertEqual(resolved.instant, try makeDate("2026-12-31T23:50:00+09:00"))
    }

    func testYearResolverKeepsSameDayInReceivedYearEvenWhenMessageTimeIsLater() throws {
        let resolver = DefaultTransactionDateResolver()
        let partial = try ParsedLocalDate(
            month: 8,
            day: 3,
            hour: 18,
            minute: 0,
            timeZoneIdentifier: "Asia/Seoul"
        )
        let receivedAt = try makeDate("2026-08-03T17:59:00+09:00")

        let resolved = try resolver.resolve(partial, receivedAt: receivedAt)

        XCTAssertEqual(resolved.localComponents.year, 2026)
    }

    func testDateOnlyTransactionResolvesToLocalStartOfDay() throws {
        let resolver = DefaultTransactionDateResolver()
        let partial = try ParsedLocalDate(
            month: 8,
            day: 3,
            timeZoneIdentifier: "Asia/Seoul"
        )

        let resolved = try resolver.resolve(
            partial,
            receivedAt: makeDate("2026-08-04T09:00:00+09:00")
        )

        XCTAssertEqual(resolved.precision, .day)
        XCTAssertEqual(resolved.instant, try makeDate("2026-08-03T00:00:00+09:00"))
    }

    func testYearResolverRejectsLeapDayWhenInferredYearIsNotLeap() throws {
        let resolver = DefaultTransactionDateResolver()
        let partial = try ParsedLocalDate(
            month: 2,
            day: 29,
            timeZoneIdentifier: "Asia/Seoul"
        )

        XCTAssertThrowsError(try resolver.resolve(
            partial,
            receivedAt: makeDate("2025-03-01T09:00:00+09:00")
        )) { error in
            XCTAssertEqual(error as? CardPolicyError, .invalidLocalDate)
        }
    }

    private func makeDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value))
    }
}
