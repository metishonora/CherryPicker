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
        XCTAssertEqual(result.performance.excludedAmount, 4_000)
        XCTAssertEqual(result.performance.unconfirmedAmount, 3_000)
        XCTAssertEqual(result.performance.unconfirmedCount, 1)
        XCTAssertEqual(result.benefitUnconfirmedCount, 1)
    }

    private let benefitID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let secondBenefitID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    func testCancellationDoesNotRetroactivelyRewardEarlierCappedApproval() throws {
        let transactions = [
            transaction(id: 1, amount: 900, benefitIDs: [benefitID]),
            transaction(id: 2, amount: 500, benefitIDs: [benefitID]),
            transaction(id: 3, amount: 900, kind: .cancellation, benefitIDs: [benefitID])
        ]
        XCTAssertEqual(try calculate(transactions).benefits.first?.receivedAmount, 10)
        XCTAssertEqual(try calculate(transactions.reversed()).benefits.first?.receivedAmount, 10)
        let laterApproval = transaction(id: 4, amount: 500, benefitIDs: [benefitID])
        XCTAssertEqual(try calculate(transactions + [laterApproval]).benefits.first?.receivedAmount, 60)
    }

    func testOversizedApprovalDiscardsExcessAndKeepsSignedCancellationForOffset() throws {
        let transactions = [
            transaction(id: 1, amount: 2_000, benefitIDs: [benefitID]),
            transaction(id: 2, amount: 1_500, kind: .cancellation, benefitIDs: [benefitID])
        ]
        let result = try calculate(transactions)
        XCTAssertEqual(result.benefits.first?.calculationAmount, -50)
        XCTAssertEqual(result.benefits.first?.receivedAmount, 0)
        let corrected = try calculate(transactions, offsets: [benefitID: 70])
        XCTAssertEqual(corrected.benefits.first?.receivedAmount, 20)
    }

    func testOffsetsApplyAfterAllocationAndCannotChangePastHeadroom() throws {
        let transactions = [
            transaction(id: 1, amount: 900, benefitIDs: [benefitID]),
            transaction(id: 2, amount: 500, benefitIDs: [benefitID]),
            // The second approval received 10 but retains its rate-based 50 deduction.
            transaction(id: 3, amount: 500, kind: .cancellation, benefitIDs: [benefitID])
        ]
        XCTAssertEqual(try calculate(transactions).benefits.first?.receivedAmount, 50)
        XCTAssertEqual(try calculate(transactions, offsets: [benefitID: 40]).benefits.first?.receivedAmount, 90)
        XCTAssertEqual(try calculate(transactions, offsets: [benefitID: -20]).benefits.first?.receivedAmount, 30)
        XCTAssertEqual(try calculate(transactions, offsets: [benefitID: 500]).benefits.first?.receivedAmount, 100)
        XCTAssertEqual(try calculate(transactions, offsets: [benefitID: -500]).benefits.first?.receivedAmount, 0)
    }

    func testIntegratedLimitFollowsTransactionOrderAcrossBenefits() throws {
        let transactions = [
            transaction(id: 1, amount: 900, benefitIDs: [secondBenefitID]),
            transaction(id: 2, amount: 500, benefitIDs: [benefitID]),
            transaction(id: 3, amount: 900, kind: .cancellation, benefitIDs: [secondBenefitID])
        ]
        let result = try calculate(transactions.reversed(), integrated: true)
        XCTAssertEqual(result.benefits.map(\.calculationAmount), [10, 0])
        let later = transaction(id: 4, amount: 500, benefitIDs: [secondBenefitID])
        XCTAssertEqual(try calculate(transactions + [later], integrated: true).benefits.map(\.calculationAmount), [10, 50])
    }

    func testSeparateLimitsAndMultipleSelectedBenefitsStayIndependent() throws {
        let result = try calculate([
            transaction(id: 1, amount: 900, benefitIDs: [benefitID, secondBenefitID]),
            transaction(id: 2, amount: 500, benefitIDs: [benefitID, secondBenefitID]),
            transaction(id: 3, amount: 900, kind: .cancellation, benefitIDs: [benefitID])
        ])
        XCTAssertEqual(result.benefits.map(\.receivedAmount), [10, 100])
        let integrated = try calculate([
            transaction(id: 1, amount: 900, benefitIDs: [benefitID, secondBenefitID])
        ], integrated: true)
        XCTAssertEqual(integrated.benefits.map(\.calculationAmount), [90, 10])
    }

    func testUnreviewedExcludedAndOtherMonthTransactionsDoNotConsumeLimit() throws {
        let result = try calculate([
            transaction(id: 1, amount: 2_000, isReviewed: false, benefitIDs: [benefitID]),
            transaction(id: 2, amount: 2_000, aggregationExcluded: true, benefitIDs: [benefitID]),
            transaction(id: 3, occurredAt: "2026-09-01T00:00:00+09:00", amount: 2_000, benefitIDs: [benefitID]),
            transaction(id: 4, amount: 900, benefitIDs: [benefitID]),
            transaction(id: 5, amount: 900, kind: .cancellation)
        ])
        XCTAssertEqual(result.benefits.first?.receivedAmount, 90)
        XCTAssertEqual(result.benefitUnconfirmedCount, 1)
    }

    func testOccurrenceThenCaptureThenIDDetermineOrder() throws {
        let approval = transaction(id: 1, occurredAt: "2026-08-15T09:00:00+09:00", capturedAt: "2026-08-16T12:00:00+09:00", amount: 2_000, benefitIDs: [benefitID])
        let cancellation = transaction(id: 2, occurredAt: "2026-08-15T10:00:00+09:00", amount: 500, kind: .cancellation, benefitIDs: [benefitID])
        XCTAssertEqual(try calculate([cancellation, approval]).benefits.first?.receivedAmount, 50)
        let earlierCapture = transaction(id: 9, capturedAt: "2026-08-15T12:00:00+09:00", amount: 2_000, benefitIDs: [benefitID])
        let laterCapture = transaction(id: 1, capturedAt: "2026-08-15T13:00:00+09:00", amount: 500, kind: .cancellation, benefitIDs: [benefitID])
        XCTAssertEqual(try calculate([laterCapture, earlierCapture]).benefits.first?.receivedAmount, 50)
    }

    func testZeroAndUnlimitedLimits() throws {
        let result = calculator.calculate(
            period: try DashboardMonth(identifier: "2026-08").interval,
            benefits: [
                DashboardBenefitDefinition(id: benefitID, rateBasisPoints: 1_000, maximumAmount: 0),
                DashboardBenefitDefinition(id: secondBenefitID, rateBasisPoints: 1_000, maximumAmount: nil)
            ],
            transactions: [transaction(amount: 2_000, benefitIDs: [benefitID, secondBenefitID])]
        )
        XCTAssertEqual(result.benefits.map(\.receivedAmount), [0, 200])
    }

    private func calculate(
        _ transactions: [DashboardTransactionInput],
        integrated: Bool = false,
        offsets: [UUID: Int] = [:]
    ) throws -> MonthlyDashboardCalculation {
        calculator.calculate(
            period: try DashboardMonth(identifier: "2026-08").interval,
            benefits: [benefitID, secondBenefitID].map {
                DashboardBenefitDefinition(id: $0, rateBasisPoints: 1_000, maximumAmount: integrated ? nil : 100)
            },
            transactions: transactions,
            integratedMaximumAmount: integrated ? 100 : nil,
            benefitOffsetAmounts: offsets
        )
    }

    private func transaction(
        id: Int = 1,
        occurredAt: String = "2026-08-15T12:00:00+09:00",
        capturedAt: String? = nil,
        amount: Int,
        isReviewed: Bool = true,
        aggregationExcluded: Bool = false,
        kind: DashboardTransactionKind = .approval,
        performance: DashboardPerformanceDecision? = .excluded,
        benefitIDs: Set<UUID> = []
    ) -> DashboardTransactionInput {
        DashboardTransactionInput(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!,
            capturedAt: date(capturedAt ?? occurredAt),
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
