import Foundation
import XCTest

import CherryPickerCore
@testable import CherryPickerServer

final class MonthlyOffsetsPersistenceTests: XCTestCase {
    func testSignedOffsetsAreCardMonthAndBenefitScopedAndSurviveRestart() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }
        let august = try DashboardMonth(identifier: "2026-08")
        let september = try DashboardMonth(identifier: "2026-09")
        var cardID: UUID!
        var benefitIDs: [UUID] = []

        do {
            let store = try SQLiteEventStore(databaseURL: databaseURL)
            let cards = try await store.managedCards()
            let card = try XCTUnwrap(cards.first)
            cardID = card.id
            benefitIDs = card.benefits.map(\.id)

            _ = try await store.updateMonthlyOffsets(
                cardID: card.id,
                month: try DashboardMonth(identifier: "2026-07"),
                request: MonthlyOffsetsUpdateRequest(
                    performanceOffsetAmount: 300_000,
                    benefitOffsets: []
                )
            )

            let augustValue = try await store.updateMonthlyOffsets(
                cardID: card.id,
                month: august,
                request: MonthlyOffsetsUpdateRequest(
                    performanceOffsetAmount: 20_000,
                    benefitOffsets: [
                        BenefitOffset(benefitId: benefitIDs[0], offsetAmount: 1_500),
                        BenefitOffset(benefitId: benefitIDs[1], offsetAmount: -500)
                    ]
                )
            )
            XCTAssertEqual(augustValue?.period, "2026-08")
            XCTAssertEqual(augustValue?.performanceOffsetAmount, 20_000)
            XCTAssertEqual(augustValue?.benefitOffsets.map(\.offsetAmount), [1_500, -500, 0])

            let septemberValue = try await store.updateMonthlyOffsets(
                cardID: card.id,
                month: september,
                request: MonthlyOffsetsUpdateRequest(
                    performanceOffsetAmount: -10_000,
                    benefitOffsets: [
                        BenefitOffset(benefitId: benefitIDs[2], offsetAmount: 7_000)
                    ]
                )
            )
            XCTAssertEqual(septemberValue?.benefitOffsets.map(\.offsetAmount), [0, 0, 7_000])

            let augustDashboardValue = try await store.dashboard(cardID: card.id, month: august)
            let augustDashboard = try XCTUnwrap(augustDashboardValue)
            XCTAssertEqual(augustDashboard.performance.currentAmount, 20_000)
            XCTAssertEqual(augustDashboard.benefits.map(\.receivedAmount), [1_500, 0, 0])
            XCTAssertEqual(augustDashboard.benefits.map(\.calculationAmount), [1_500, -500, 0])

            let septemberDashboardValue = try await store.dashboard(
                cardID: card.id,
                month: september
            )
            let septemberDashboard = try XCTUnwrap(septemberDashboardValue)
            XCTAssertEqual(septemberDashboard.performance.currentAmount, -10_000)
            XCTAssertEqual(septemberDashboard.benefits.map(\.receivedAmount), [0, 0, 0])
            XCTAssertEqual(septemberDashboard.benefits.map(\.calculationAmount), [0, 0, 7_000])
        }

        do {
            let reopened = try SQLiteEventStore(databaseURL: databaseURL)
            let persistedAugustValue = try await reopened.monthlyOffsets(
                cardID: cardID,
                month: august
            )
            let persistedAugust = try XCTUnwrap(persistedAugustValue)
            XCTAssertEqual(persistedAugust.performanceOffsetAmount, 20_000)
            XCTAssertEqual(persistedAugust.benefitOffsets.map(\.offsetAmount), [1_500, -500, 0])

            let persistedSeptemberValue = try await reopened.monthlyOffsets(
                cardID: cardID,
                month: september
            )
            let persistedSeptember = try XCTUnwrap(persistedSeptemberValue)
            XCTAssertEqual(persistedSeptember.performanceOffsetAmount, -10_000)
            XCTAssertEqual(persistedSeptember.benefitOffsets.map(\.offsetAmount), [0, 0, 7_000])

            await XCTAssertThrowsErrorAsync(
                try await reopened.updateMonthlyOffsets(
                    cardID: cardID,
                    month: august,
                    request: MonthlyOffsetsUpdateRequest(
                        performanceOffsetAmount: 0,
                        benefitOffsets: [
                            BenefitOffset(benefitId: UUID(), offsetAmount: 1)
                        ]
                    )
                )
            ) { error in
                XCTAssertEqual(error as? ManagementStoreError, .invalidInput)
            }

            let unchanged = try await reopened.monthlyOffsets(cardID: cardID, month: august)
            XCTAssertEqual(unchanged?.performanceOffsetAmount, 20_000)
            XCTAssertEqual(unchanged?.benefitOffsets.map(\.offsetAmount), [1_500, -500, 0])

            _ = try await reopened.updateMonthlyOffsets(
                cardID: cardID,
                month: august,
                request: MonthlyOffsetsUpdateRequest(
                    performanceOffsetAmount: 0,
                    benefitOffsets: []
                )
            )
            let clearedDashboard = try await reopened.dashboard(cardID: cardID, month: august)
            XCTAssertEqual(clearedDashboard?.performance.currentAmount, 0)
            XCTAssertEqual(clearedDashboard?.benefits.map(\.receivedAmount), [0, 0, 0])
        }
    }

    private func temporaryDatabaseURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MonthlyOffsetsPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("store.sqlite")
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}
