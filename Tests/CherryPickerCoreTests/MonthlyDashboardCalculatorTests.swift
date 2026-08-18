import Foundation
import XCTest

@testable import CherryPickerCore

final class MonthlyDashboardCalculatorTests: XCTestCase {
    private let calculator = MonthlyDashboardCalculator()

    func testDashboardMonthUsesStrictIdentifierAndSeoulBoundaries() throws {
        let month = try DashboardMonth(identifier: "2026-08")
        let interval = try month.interval

        XCTAssertEqual(month.identifier, "2026-08")
        XCTAssertEqual(interval.start, date("2026-07-31T15:00:00Z"))
        XCTAssertEqual(interval.end, date("2026-08-31T15:00:00Z"))
        XCTAssertThrowsError(try DashboardMonth(identifier: "2026-8"))
        XCTAssertThrowsError(try DashboardMonth(identifier: "2026-13"))
    }

    func testCalculationSeparatesMonthlyReviewStatesAndPreservesNegativePerformance() throws {
        let month = try DashboardMonth(identifier: "2026-08")
        let result = calculator.calculate(
            period: try month.interval,
            targetAmount: 300_000,
            benefits: [],
            transactions: [
                transaction(amount: 10_000, performance: .included),
                transaction(amount: 50_000, kind: .cancellation, performance: .included),
                transaction(amount: 4_000, performance: .excluded),
                transaction(amount: 3_000, isReviewed: false),
                transaction(amount: 9_000, aggregationExcluded: true, performance: .included),
                transaction(
                    occurredAt: "2026-09-01T00:00:00+09:00",
                    amount: 100_000,
                    performance: .included
                )
            ]
        )

        XCTAssertEqual(result.performance.currentAmount, -40_000)
        XCTAssertEqual(result.performance.remainingAmount, 340_000)
        XCTAssertEqual(result.performance.excludedAmount, 4_000)
        XCTAssertEqual(result.performance.unconfirmedAmount, 3_000)
        XCTAssertEqual(result.performance.unconfirmedCount, 1)
        XCTAssertEqual(result.benefitUnconfirmedCount, 1)
    }

    func testBenefitDisplayClampsOnlyAfterAllApprovalsAndCancellationsAreCombined() throws {
        let benefitID = UUID(uuidString: "00000000-0000-0000-0001-000000004475")!
        let benefit = DashboardBenefitDefinition(
            id: benefitID,
            rateBasisPoints: 1_000,
            maximumAmount: 5_000
        )
        let month = try DashboardMonth(identifier: "2026-08")

        let stillCapped = calculator.calculate(
            period: try month.interval,
            targetAmount: 300_000,
            benefits: [benefit],
            transactions: [
                transaction(amount: 100_000, benefitIDs: [benefitID]),
                transaction(amount: 20_000, kind: .cancellation, benefitIDs: [benefitID])
            ]
        )
        XCTAssertEqual(stillCapped.benefits.first?.calculationAmount, 8_000)
        XCTAssertEqual(stillCapped.benefits.first?.receivedAmount, 5_000)

        let belowCap = calculator.calculate(
            period: try month.interval,
            targetAmount: 300_000,
            benefits: [benefit],
            transactions: [
                transaction(amount: 100_000, benefitIDs: [benefitID]),
                transaction(amount: 60_000, kind: .cancellation, benefitIDs: [benefitID])
            ]
        )
        XCTAssertEqual(belowCap.benefits.first?.calculationAmount, 4_000)
        XCTAssertEqual(belowCap.benefits.first?.receivedAmount, 4_000)

        let floored = calculator.calculate(
            period: try month.interval,
            targetAmount: 300_000,
            benefits: [benefit],
            transactions: [
                transaction(amount: 100_000, benefitIDs: [benefitID]),
                transaction(amount: 200_000, kind: .cancellation, benefitIDs: [benefitID])
            ]
        )
        XCTAssertEqual(floored.benefits.first?.calculationAmount, -10_000)
        XCTAssertEqual(floored.benefits.first?.receivedAmount, 0)
    }

    func testSignedOffsetsUseStableBenefitIDsAndClampOnlyTheDisplayedBenefit() throws {
        let benefitIDs = [
            UUID(uuidString: "00000000-0000-0000-0001-000000001010")!,
            UUID(uuidString: "00000000-0000-0000-0002-000000001010")!,
            UUID(uuidString: "00000000-0000-0000-0003-000000001010")!
        ]
        let benefits = benefitIDs.map {
            DashboardBenefitDefinition(id: $0, rateBasisPoints: 2_000, maximumAmount: 6_000)
        }
        let unknownBenefitID = UUID(uuidString: "00000000-0000-0000-9999-000000001010")!
        let month = try DashboardMonth(identifier: "2026-08")

        let result = calculator.calculate(
            period: try month.interval,
            targetAmount: 300_000,
            benefits: benefits,
            transactions: [
                transaction(
                    amount: 300_000,
                    performance: .included,
                    benefitIDs: Set(benefitIDs)
                )
            ],
            performanceOffsetAmount: -20_000,
            benefitOffsetAmounts: [
                benefitIDs[0]: -57_000,
                benefitIDs[1]: 5_000,
                benefitIDs[2]: -65_000,
                unknownBenefitID: 999_999
            ]
        )

        XCTAssertEqual(result.performance.currentAmount, 280_000)
        XCTAssertEqual(result.performance.remainingAmount, 20_000)
        XCTAssertEqual(result.benefits[0].calculationAmount, 3_000)
        XCTAssertEqual(result.benefits[0].receivedAmount, 3_000)
        XCTAssertEqual(result.benefits[1].calculationAmount, 65_000)
        XCTAssertEqual(result.benefits[1].receivedAmount, 6_000)
        XCTAssertEqual(result.benefits[2].calculationAmount, -5_000)
        XCTAssertEqual(result.benefits[2].receivedAmount, 0)
        XCTAssertEqual(result.benefits.map(\.id), benefitIDs)
    }

    private func transaction(
        occurredAt: String = "2026-08-15T12:00:00+09:00",
        amount: Int,
        isReviewed: Bool = true,
        aggregationExcluded: Bool = false,
        kind: DashboardTransactionKind = .approval,
        performance: DashboardPerformanceDecision? = .excluded,
        benefitIDs: Set<UUID> = []
    ) -> DashboardTransactionInput {
        DashboardTransactionInput(
            occurredAt: date(occurredAt),
            isReviewed: isReviewed,
            aggregationExcluded: aggregationExcluded,
            kind: kind,
            amount: amount,
            performance: performance,
            benefitIDs: benefitIDs
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
