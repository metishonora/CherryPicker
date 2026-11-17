import Foundation
import XCTest

import CherryPickerCore
import CherryPickerServer
import Hummingbird
import HummingbirdTesting

/// Black-box acceptance tests for Issue #4.
///
/// The suite drives the real HTTP application using only authenticated HTTP
/// requests and responses. It does not query SQLite or call store aggregation
/// methods directly. They define the feature's observable contract without
/// coupling assertions to its storage or aggregation implementation.
@available(macOS 14.0, *)
final class Issue4BlackBoxAcceptanceTests: XCTestCase, @unchecked Sendable {
    private let allowedLogin = "fixture-device@example.test"
    private let codec = OutboxJSONCodec()

    // MARK: - Monthly boundaries and navigation

    func testDashboardAndTransactionsAreSeparatedBySeoulCalendarMonth() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let cardID = try await firstCardID(using: client)
            let juneID = try await ingest(
                approval(
                    id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
                    capturedAt: "2026-06-30T23:59:00+09:00",
                    localDateTime: "06/30 23:59",
                    amount: 11_000,
                    merchant: "Synthetic June Boundary"
                ),
                using: client
            )
            let julyID = try await ingest(
                approval(
                    id: UUID(uuidString: "40000000-0000-0000-0000-000000000002")!,
                    capturedAt: "2026-07-01T00:01:00+09:00",
                    localDateTime: "07/01 00:01",
                    amount: 22_000,
                    merchant: "Synthetic July Boundary"
                ),
                using: client
            )
            try await review(
                transactionID: juneID,
                performance: "included",
                benefitIDs: [],
                using: client
            )
            try await review(
                transactionID: julyID,
                performance: "included",
                benefitIDs: [],
                using: client
            )

            let june = try await dashboard(cardID: cardID, month: "2026-06", using: client)
            let july = try await dashboard(cardID: cardID, month: "2026-07", using: client)
            let emptyMay = try await dashboard(cardID: cardID, month: "2026-05", using: client)
            XCTAssertEqual(june["period"] as? String, "2026-06")
            XCTAssertEqual(july["period"] as? String, "2026-07")
            XCTAssertEqual(emptyMay["period"] as? String, "2026-05")
            XCTAssertEqual(performance(june)["currentAmount"] as? Int, 11_000)
            XCTAssertEqual(performance(july)["currentAmount"] as? Int, 22_000)
            XCTAssertEqual(performance(emptyMay)["currentAmount"] as? Int, 0)

            let juneRows = try await transactions(
                cardID: cardID,
                month: "2026-06",
                using: client
            )
            let julyRows = try await transactions(
                cardID: cardID,
                month: "2026-07",
                using: client
            )
            let emptyMayRows = try await transactions(
                cardID: cardID,
                month: "2026-05",
                using: client
            )
            XCTAssertEqual(juneRows.compactMap { $0["id"] as? String }, [juneID])
            XCTAssertEqual(julyRows.compactMap { $0["id"] as? String }, [julyID])
            XCTAssertTrue(emptyMayRows.isEmpty)
        }
    }

    // MARK: - Performance summary

    func testDashboardSeparatesIncludedExcludedUnconfirmedAndAggregationExcludedAmounts() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let cardID = try await firstCardID(using: client)
            let includedID = try await ingest(
                approval(
                    id: UUID(uuidString: "41000000-0000-0000-0000-000000000001")!,
                    capturedAt: "2026-08-04T09:00:00+09:00",
                    localDateTime: "08/04 09:00",
                    amount: 10_000,
                    merchant: "Synthetic Included"
                ),
                using: client
            )
            let excludedID = try await ingest(
                approval(
                    id: UUID(uuidString: "41000000-0000-0000-0000-000000000002")!,
                    capturedAt: "2026-08-04T10:00:00+09:00",
                    localDateTime: "08/04 10:00",
                    amount: 4_000,
                    merchant: "Synthetic Performance Excluded"
                ),
                using: client
            )
            _ = try await ingest(
                approval(
                    id: UUID(uuidString: "41000000-0000-0000-0000-000000000003")!,
                    capturedAt: "2026-08-04T11:00:00+09:00",
                    localDateTime: "08/04 11:00",
                    amount: 3_000,
                    merchant: "Synthetic Unconfirmed"
                ),
                using: client
            )
            let aggregationExcludedID = try await ingest(
                approval(
                    id: UUID(uuidString: "41000000-0000-0000-0000-000000000004")!,
                    capturedAt: "2026-08-04T12:00:00+09:00",
                    localDateTime: "08/04 12:00",
                    amount: 9_000,
                    merchant: "Synthetic Aggregation Excluded"
                ),
                using: client
            )
            try await review(
                transactionID: includedID,
                performance: "included",
                benefitIDs: [],
                using: client
            )
            try await review(
                transactionID: excludedID,
                performance: "excluded",
                benefitIDs: [],
                using: client
            )
            try await review(
                transactionID: aggregationExcludedID,
                performance: nil,
                benefitIDs: [],
                aggregationExcluded: true,
                using: client
            )

            let value = try await dashboard(cardID: cardID, month: "2026-08", using: client)
            let summary = performance(value)
            XCTAssertEqual(summary["currentAmount"] as? Int, 10_000)
            XCTAssertEqual(summary["excludedAmount"] as? Int, 4_000)
            XCTAssertEqual(summary["unconfirmedAmount"] as? Int, 3_000)
            XCTAssertEqual(summary["unconfirmedCount"] as? Int, 1)
            XCTAssertEqual(summary["targetAmount"] as? Int, 300_000)
            XCTAssertEqual(summary["remainingAmount"] as? Int, 290_000)
            XCTAssertEqual(value["benefitUnconfirmedCount"] as? Int, 1)
        }
    }

    func testIndependentCancellationCanMakePerformanceNegativeAgainstAutomaticGoal() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let cardID = try await firstCardID(using: client)
            let cancellationID = try await ingest(
                cancellation(
                    id: UUID(uuidString: "42000000-0000-0000-0000-000000000001")!,
                    capturedAt: "2026-08-05T09:00:00+09:00",
                    localDate: "08/05",
                    amount: 50_000,
                    merchant: "Synthetic Independent Cancellation"
                ),
                using: client
            )
            try await review(
                transactionID: cancellationID,
                performance: "included",
                benefitIDs: [],
                using: client
            )

            let value = try await dashboard(cardID: cardID, month: "2026-08", using: client)
            let summary = performance(value)
            XCTAssertEqual(summary["currentAmount"] as? Int, -50_000)
            XCTAssertEqual(summary["targetAmount"] as? Int, 300_000)
            XCTAssertEqual(summary["remainingAmount"] as? Int, 350_000)
        }
    }

    func testPerformanceUsesAutomaticGoalWithoutOverageField() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let cardID = try await firstCardID(using: client)
            let transactionID = try await ingest(
                approval(
                    id: UUID(uuidString: "43000000-0000-0000-0000-000000000001")!,
                    capturedAt: "2026-08-06T09:00:00+09:00",
                    localDateTime: "08/06 09:00",
                    amount: 350_000,
                    merchant: "Synthetic Target Overage"
                ),
                using: client
            )
            try await review(
                transactionID: transactionID,
                performance: "included",
                benefitIDs: [],
                using: client
            )

            let value = try await dashboard(cardID: cardID, month: "2026-08", using: client)
            let summary = performance(value)
            XCTAssertEqual(summary["currentAmount"] as? Int, 350_000)
            XCTAssertEqual(summary["targetAmount"] as? Int, 300_000)
            XCTAssertEqual(summary["remainingAmount"] as? Int, 0)
            XCTAssertNil(summary["overageAmount"])
        }
    }

    // MARK: - Benefit summary

    func testChronologicalBenefitsPreviewAndPersistence() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let storedCardID = LockedIssue4Value<String?>(nil)
        let storedBenefitID = LockedIssue4Value<String?>(nil)
        do {
            let app = try makeApplication(databaseURL: databaseURL)
            try await app.test(.router) { client in
                let card = try await firstCard(using: client)
                let cardID = try requiredString(card, key: "id")
                let benefit = try XCTUnwrap((card["benefits"] as? [[String: Any]])?.first)
                let benefitID = try requiredString(benefit, key: "id")
                storedCardID.set(cardID); storedBenefitID.set(benefitID)
                try await qualifyExistingCardBenefits(cardID: cardID, using: client)
                let first = try await ingest(approval(
                    id: UUID(), capturedAt: "2026-08-07T09:00:00+09:00",
                    localDateTime: "08/07 09:00", amount: 27_000, merchant: "Synthetic First"
                ), using: client)
                let second = try await ingest(approval(
                    id: UUID(), capturedAt: "2026-08-07T10:00:00+09:00",
                    localDateTime: "08/07 10:00", amount: 15_000, merchant: "Synthetic Second"
                ), using: client)
                // Review order must not become benefit allocation order.
                try await review(transactionID: second, performance: "included", benefitIDs: [benefitID], using: client)
                try await review(transactionID: first, performance: "included", benefitIDs: [benefitID], using: client)
                let cancelled = try await ingest(cancellation(
                    id: UUID(), capturedAt: "2026-08-07T11:00:00+09:00",
                    localDate: "08/07", amount: 27_000, merchant: "Synthetic Cancellation"
                ), using: client)
                let payload: [String: Any] = [
                    "review": ["performance": "included", "benefitIds": [benefitID], "memo": "unsaved"],
                    "aggregationExcluded": false
                ]
                let previewURI = "/api/v1/transactions/\(cancelled)/review-preview"
                try await client.execute(uri: previewURI, method: .post,
                    headers: issue4Headers(login: allowedLogin, mutation: true),
                    body: issue4ByteBuffer(try issue4JSONData(payload))) { response in
                    try requireIssue4Status(response, .ok)
                    let preview = try XCTUnwrap(try issue4JSONObject(response.body)["dashboard"] as? [String: Any])
                    XCTAssertEqual(try self.receivedBenefit(benefitID, in: preview), 600)
                    XCTAssertFalse(issue4BodyString(response.body).contains("Synthetic Cancellation"))
                }
                let unchanged = try await dashboard(cardID: cardID, month: "2026-08", using: client)
                XCTAssertEqual(try receivedBenefit(benefitID, in: unchanged), 6_000)
                try await client.execute(uri: "/api/v1/transactions/\(cancelled)", method: .get,
                    headers: issue4Headers(login: allowedLogin)) { response in
                    let row = try XCTUnwrap(try issue4JSONObject(response.body)["transaction"] as? [String: Any])
                    XCTAssertEqual(row["reviewStatus"] as? String, "unreviewed")
                    XCTAssertEqual(row["memo"] as? String, "")
                }
                for (login, mutation, expected) in [
                    (nil as String?, true, HTTPResponse.Status.unauthorized),
                    (allowedLogin as String?, false, .forbidden)
                ] {
                    try await client.execute(uri: previewURI, method: .post,
                        headers: issue4Headers(login: login, mutation: mutation),
                        body: issue4ByteBuffer(try issue4JSONData(payload))) { response in
                        XCTAssertEqual(response.status, expected)
                    }
                }
                let invalid: [String: Any] = [
                    "review": ["performance": "included", "benefitIds": [UUID().uuidString], "memo": ""],
                    "aggregationExcluded": false
                ]
                try await client.execute(uri: previewURI, method: .post,
                    headers: issue4Headers(login: allowedLogin, mutation: true),
                    body: issue4ByteBuffer(try issue4JSONData(invalid))) { response in
                    XCTAssertEqual(response.status, .badRequest)
                }
                try await review(transactionID: cancelled, performance: "included", benefitIDs: [benefitID], using: client)
                let saved = try await dashboard(cardID: cardID, month: "2026-08", using: client)
                XCTAssertEqual(try receivedBenefit(benefitID, in: saved), 600)
                // Editing an earlier transaction needs a replay, not a delta on the current total.
                let exclude: [String: Any] = [
                    "review": ["performance": NSNull(), "benefitIds": [], "memo": ""],
                    "aggregationExcluded": true
                ]
                try await client.execute(uri: "/api/v1/transactions/\(first)/review-preview", method: .post,
                    headers: issue4Headers(login: allowedLogin, mutation: true),
                    body: issue4ByteBuffer(try issue4JSONData(exclude))) { response in
                    try requireIssue4Status(response, .ok)
                    let preview = try XCTUnwrap(try issue4JSONObject(response.body)["dashboard"] as? [String: Any])
                    XCTAssertEqual(try self.receivedBenefit(benefitID, in: preview), 0)
                }
                let later = try await ingest(approval(
                    id: UUID(), capturedAt: "2026-08-07T12:00:00+09:00",
                    localDateTime: "08/07 12:00", amount: 15_000, merchant: "Synthetic Later"
                ), using: client)
                try await review(transactionID: later, performance: "included", benefitIDs: [benefitID], using: client)
                let afterLater = try await dashboard(cardID: cardID, month: "2026-08", using: client)
                XCTAssertEqual(try receivedBenefit(benefitID, in: afterLater), 3_600)
            }
        }
        let reopened = try makeApplication(databaseURL: databaseURL)
        try await reopened.test(.router) { client in
            let result = try await dashboard(cardID: XCTUnwrap(storedCardID.get()), month: "2026-08", using: client)
            XCTAssertEqual(try receivedBenefit(XCTUnwrap(storedBenefitID.get()), in: result), 3_600)
        }
    }

    func testBenefitCapDiscardsExcessBeforeCancellationsAndNeverDisplaysNegative() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let card = try await firstCard(using: client)
            let cardID = try requiredString(card, key: "id")
            let benefit = try XCTUnwrap((card["benefits"] as? [[String: Any]])?.first)
            let benefitID = try requiredString(benefit, key: "id")
            try await qualifyExistingCardBenefits(cardID: cardID, using: client)
            let rate = try requiredInt(benefit, key: "rateBasisPoints")
            let maximum = try requiredInt(benefit, key: "maximumAmount")
            let approvalAmount = exactTransactionAmount(forBenefitAmount: maximum * 2, rate: rate)
            let firstCancellationAmount = exactTransactionAmount(
                forBenefitAmount: maximum / 2,
                rate: rate
            )
            let secondCancellationAmount = exactTransactionAmount(
                forBenefitAmount: maximum,
                rate: rate
            )
            let floorCancellationAmount = exactTransactionAmount(
                forBenefitAmount: maximum * 2,
                rate: rate
            )

            let approvalID = try await ingest(
                approval(
                    id: UUID(uuidString: "44000000-0000-0000-0000-000000000001")!,
                    capturedAt: "2026-08-07T09:00:00+09:00",
                    localDateTime: "08/07 09:00",
                    amount: approvalAmount,
                    merchant: "Synthetic Benefit Double Cap"
                ),
                using: client
            )
            try await review(
                transactionID: approvalID,
                performance: "excluded",
                benefitIDs: [benefitID],
                using: client
            )
            let afterApproval = try await dashboard(
                cardID: cardID,
                month: "2026-08",
                using: client
            )
            XCTAssertEqual(try receivedBenefit(benefitID, in: afterApproval), maximum)
            let cappedBenefit = try benefitProgress(benefitID, in: afterApproval)
            XCTAssertNil(cappedBenefit["overageAmount"])

            let firstCancellationID = try await ingest(
                cancellation(
                    id: UUID(uuidString: "44000000-0000-0000-0000-000000000002")!,
                    capturedAt: "2026-08-07T10:00:00+09:00",
                    localDate: "08/07",
                    amount: firstCancellationAmount,
                    merchant: "Synthetic Benefit Still Capped"
                ),
                using: client
            )
            try await review(
                transactionID: firstCancellationID,
                performance: "excluded",
                benefitIDs: [benefitID],
                using: client
            )
            let afterFirstCancellation = try await dashboard(
                cardID: cardID,
                month: "2026-08",
                using: client
            )
            XCTAssertEqual(
                try receivedBenefit(benefitID, in: afterFirstCancellation),
                maximum / 2,
                "A cancellation deducts from the applied benefit; discarded excess cannot absorb it."
            )

            let secondCancellationID = try await ingest(
                cancellation(
                    id: UUID(uuidString: "44000000-0000-0000-0000-000000000003")!,
                    capturedAt: "2026-08-07T11:00:00+09:00",
                    localDate: "08/07",
                    amount: secondCancellationAmount,
                    merchant: "Synthetic Benefit Below Cap"
                ),
                using: client
            )
            try await review(
                transactionID: secondCancellationID,
                performance: "excluded",
                benefitIDs: [benefitID],
                using: client
            )
            let afterSecondCancellation = try await dashboard(
                cardID: cardID,
                month: "2026-08",
                using: client
            )
            XCTAssertEqual(
                try receivedBenefit(benefitID, in: afterSecondCancellation),
                0
            )

            let floorCancellationID = try await ingest(
                cancellation(
                    id: UUID(uuidString: "44000000-0000-0000-0000-000000000004")!,
                    capturedAt: "2026-08-07T12:00:00+09:00",
                    localDate: "08/07",
                    amount: floorCancellationAmount,
                    merchant: "Synthetic Benefit Floor"
                ),
                using: client
            )
            try await review(
                transactionID: floorCancellationID,
                performance: "excluded",
                benefitIDs: [benefitID],
                using: client
            )
            let afterFloorCancellation = try await dashboard(
                cardID: cardID,
                month: "2026-08",
                using: client
            )
            XCTAssertEqual(try receivedBenefit(benefitID, in: afterFloorCancellation), 0)
        }
    }

    func testFullTransactionAmountFeedsEverySelectedBenefitAndUnselectedCancellationChangesNone() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let card = try await firstCard(using: client)
            let cardID = try requiredString(card, key: "id")
            let benefits = Array((card["benefits"] as? [[String: Any]] ?? []).prefix(2))
            XCTAssertEqual(benefits.count, 2)
            let benefitIDs = try benefits.map { try requiredString($0, key: "id") }
            try await qualifyExistingCardBenefits(cardID: cardID, using: client)
            let amount = 20_000
            let approvalID = try await ingest(
                approval(
                    id: UUID(uuidString: "45000000-0000-0000-0000-000000000001")!,
                    capturedAt: "2026-08-08T09:00:00+09:00",
                    localDateTime: "08/08 09:00",
                    amount: amount,
                    merchant: "Synthetic Multiple Benefits"
                ),
                using: client
            )
            try await review(
                transactionID: approvalID,
                performance: "excluded",
                benefitIDs: benefitIDs,
                using: client
            )

            let afterApproval = try await dashboard(
                cardID: cardID,
                month: "2026-08",
                using: client
            )
            for benefit in benefits {
                let id = try requiredString(benefit, key: "id")
                let rate = try requiredInt(benefit, key: "rateBasisPoints")
                let maximum = try requiredInt(benefit, key: "maximumAmount")
                XCTAssertEqual(
                    try receivedBenefit(id, in: afterApproval),
                    min(maximum, amount * rate / 10_000)
                )
            }

            let cancellationID = try await ingest(
                cancellation(
                    id: UUID(uuidString: "45000000-0000-0000-0000-000000000002")!,
                    capturedAt: "2026-08-08T10:00:00+09:00",
                    localDate: "08/08",
                    amount: amount,
                    merchant: "Synthetic Unselected Cancellation"
                ),
                using: client
            )
            try await review(
                transactionID: cancellationID,
                performance: "excluded",
                benefitIDs: [],
                using: client
            )
            let afterUnselectedCancellation = try await dashboard(
                cardID: cardID,
                month: "2026-08",
                using: client
            )
            for id in benefitIDs {
                XCTAssertEqual(
                    try receivedBenefit(id, in: afterUnselectedCancellation),
                    try receivedBenefit(id, in: afterApproval)
                )
            }
        }
    }

    // MARK: - Derived state, persistence, and card policy

    func testReviewChangesRecalculateImmediatelyAndSurviveRestart() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let transactionID = LockedIssue4Value<String?>(nil)
        let cardID = LockedIssue4Value<String?>(nil)

        do {
            let app = try makeApplication(databaseURL: databaseURL)
            try await app.test(.router) { client in
                let card = try await firstCard(using: client)
                let resolvedCardID = try requiredString(card, key: "id")
                cardID.set(resolvedCardID)
                let resolvedTransactionID = try await ingest(
                    approval(
                        id: UUID(uuidString: "46000000-0000-0000-0000-000000000001")!,
                        capturedAt: "2026-08-09T09:00:00+09:00",
                        localDateTime: "08/09 09:00",
                        amount: 15_000,
                        merchant: "Synthetic Recalculation"
                    ),
                    using: client
                )
                transactionID.set(resolvedTransactionID)

                let beforeReview = try await dashboard(
                    cardID: resolvedCardID,
                    month: "2026-08",
                    using: client
                )
                XCTAssertEqual(performance(beforeReview)["currentAmount"] as? Int, 0)
                XCTAssertEqual(performance(beforeReview)["unconfirmedAmount"] as? Int, 15_000)

                try await review(
                    transactionID: resolvedTransactionID,
                    performance: "included",
                    benefitIDs: [],
                    using: client
                )
                let recalculated = try await dashboard(
                    cardID: resolvedCardID,
                    month: "2026-08",
                    using: client
                )
                XCTAssertEqual(performance(recalculated)["currentAmount"] as? Int, 15_000)
                XCTAssertEqual(performance(recalculated)["unconfirmedAmount"] as? Int, 0)
                XCTAssertEqual(performance(recalculated)["unconfirmedCount"] as? Int, 0)
                XCTAssertEqual(performance(recalculated)["targetAmount"] as? Int, 300_000)
                XCTAssertEqual(performance(recalculated)["remainingAmount"] as? Int, 285_000)
            }
        }

        do {
            let reopenedApp = try makeApplication(databaseURL: databaseURL)
            try await reopenedApp.test(.router) { client in
                let persisted = try await dashboard(
                    cardID: try XCTUnwrap(cardID.get()),
                    month: "2026-08",
                    using: client
                )
                XCTAssertEqual(performance(persisted)["currentAmount"] as? Int, 15_000)
                XCTAssertEqual(performance(persisted)["targetAmount"] as? Int, 300_000)
                XCTAssertEqual(performance(persisted)["remainingAmount"] as? Int, 285_000)

                try await review(
                    transactionID: try XCTUnwrap(transactionID.get()),
                    performance: "excluded",
                    benefitIDs: [],
                    using: client
                )
                let afterDecisionChange = try await dashboard(
                    cardID: try XCTUnwrap(cardID.get()),
                    month: "2026-08",
                    using: client
                )
                XCTAssertEqual(performance(afterDecisionChange)["currentAmount"] as? Int, 0)
                XCTAssertEqual(performance(afterDecisionChange)["excludedAmount"] as? Int, 15_000)
            }
        }
    }

    func testCardDefinesStaticExclusionListsOutsideMonthlyDashboardState() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let card = try await firstCard(using: client)
            let performanceExclusions = try XCTUnwrap(card["performanceExclusions"] as? [String])
            let benefitExclusions = try XCTUnwrap(card["benefitExclusions"] as? [String])
            XCTAssertFalse(performanceExclusions.isEmpty)
            XCTAssertFalse(benefitExclusions.isEmpty)

            let cardID = try requiredString(card, key: "id")
            let june = try await dashboard(cardID: cardID, month: "2026-06", using: client)
            let august = try await dashboard(cardID: cardID, month: "2026-08", using: client)
            XCTAssertEqual(june["period"] as? String, "2026-06")
            XCTAssertEqual(august["period"] as? String, "2026-08")

            let cardAfterMonthNavigation = try await firstCard(using: client)
            XCTAssertEqual(
                cardAfterMonthNavigation["performanceExclusions"] as? [String],
                performanceExclusions
            )
            XCTAssertEqual(
                cardAfterMonthNavigation["benefitExclusions"] as? [String],
                benefitExclusions
            )
        }
    }

    func testProductPageExposesApprovedDashboardNavigationAndPolicyDisclosures() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/",
                method: .get,
                headers: issue4Headers(login: allowedLogin)
            ) { response in
                try requireIssue4Status(response, .ok)
                let body = issue4BodyString(response.body)
                XCTAssertTrue(body.contains("aria-label=\"카드 선택\""))
                XCTAssertTrue(body.contains("data-view=\"dashboard\""))
                XCTAssertTrue(body.contains("data-view=\"transactions\""))
                XCTAssertTrue(body.contains("aria-label=\"이전 달\""))
                XCTAssertTrue(body.contains("aria-label=\"다음 달\""))
                XCTAssertTrue(body.contains("const earliestMonth = '2026-08'"))
                XCTAssertTrue(body.contains("value.disabled = state.month <= earliestMonth"))
                XCTAssertTrue(body.contains("state.month = clampedMonth(next)"))
                XCTAssertEqual(body.components(separatedBy: "data-period-picker-trigger aria-haspopup=\"dialog\"").count - 1, 2)
                XCTAssertEqual(body.components(separatedBy: "data-month-picker role=\"dialog\"").count - 1, 2)
                XCTAssertTrue(body.contains("button { cursor: pointer; touch-action: manipulation; }"))
                XCTAssertFalse(body.contains("maximum-scale"))
                XCTAssertTrue(body.contains("async function selectMonth(value)"))
                XCTAssertTrue(body.contains("button.disabled = value < earliestMonth || value > currentMonth"))
                XCTAssertTrue(body.contains("실적 제외 항목"))
                XCTAssertTrue(body.contains("혜택 제외 항목"))
                XCTAssertFalse(body.contains("월 실적 진행도"))
                XCTAssertTrue(body.contains("benefit.minimumTransactionAmount"))
                XCTAssertTrue(body.contains("benefit.exclusionNotes"))
                XCTAssertFalse(body.contains("benefit.requiredPreviousMonthPerformanceAmount"))
                XCTAssertTrue(body.contains("benefit.eligibleMerchants"))
                XCTAssertTrue(body.contains("대상: ${benefit.eligibleMerchants.join(', ')}"))
                XCTAssertFalse(body.contains("selected.performanceCalculationBasis"))
                XCTAssertFalse(body.contains("const rate = benefit.rateBasisPoints"))
                XCTAssertFalse(body.contains("id=\"performance-basis\""))
                XCTAssertFalse(body.contains("id=\"benefit-unconfirmed\""))
                XCTAssertFalse(body.contains("월별 집계"))
                XCTAssertFalse(body.contains("혜택 미확인"))
                XCTAssertTrue(body.contains("name.className = 'cp-benefit-name'"))
                XCTAssertTrue(body.contains("wrap.append(terms)"))
                XCTAssertTrue(body.contains("조건: 건당 ${won(benefit.minimumTransactionAmount)} 이상"))
                XCTAssertFalse(body.contains("row.append(checkbox, label, terms, wrap)"))
                XCTAssertTrue(body.contains("row.append(checkbox, label, wrap)"))
                XCTAssertFalse(body.contains("originalMessage"))
            }
        }
    }

    func testDashboardRequiresExactIdentityAndNeverReturnsCapturedOriginals() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let cardID = try await firstCardID(using: client)
            let sentinel = "synthetic-original-must-never-reach-dashboard"
            _ = try await ingest(
                OutboxEvent(
                    eventId: UUID(uuidString: "47000000-0000-0000-0000-000000000001")!,
                    capturedAt: ISO8601DateFormatter().date(
                        from: "2026-08-10T09:00:00+09:00"
                    )!,
                    originalMessage: sentinel
                ),
                using: client
            )

            for login in [nil, "other-device@example.test"] {
                try await client.execute(
                    uri: "/api/v1/cards/\(cardID)/dashboard?month=2026-08",
                    method: .get,
                    headers: issue4Headers(login: login)
                ) { response in
                    XCTAssertEqual(response.status, .unauthorized)
                    XCTAssertFalse(issue4BodyString(response.body).contains(sentinel))
                }
            }

            try await client.execute(
                uri: "/api/v1/cards/\(cardID)/dashboard?month=2026-08",
                method: .get,
                headers: issue4Headers(login: allowedLogin)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let body = issue4BodyString(response.body)
                XCTAssertFalse(body.contains(sentinel))
                XCTAssertFalse(body.contains("originalMessage"))
            }
        }
    }

    // MARK: - HTTP-only helpers

    private func makeApplication(databaseURL: URL) throws -> some ApplicationProtocol {
        let store = try SQLiteEventStore(databaseURL: databaseURL)
        return try CherryPickerHTTPApplication(
            store: store,
            authorizer: TailscaleIdentityAuthorizer(allowedLogin: allowedLogin),
            codec: codec
        ).application
    }

    private func firstCard<Client>(using client: Client) async throws -> [String: Any]
    where Client: TestClientProtocol {
        let captured = LockedIssue4Value<[[String: Any]]>([])
        try await client.execute(
            uri: "/api/v1/cards",
            method: .get,
            headers: issue4Headers(login: allowedLogin)
        ) { response in
            try requireIssue4Status(response, .ok)
            let object = try issue4JSONObject(response.body)
            captured.set(try XCTUnwrap(object["cards"] as? [[String: Any]]))
        }
        return try XCTUnwrap(captured.get().first)
    }

    private func firstCardID<Client>(using client: Client) async throws -> String
    where Client: TestClientProtocol {
        try requiredString(try await firstCard(using: client), key: "id")
    }

    private func dashboard<Client>(
        cardID: String,
        month: String,
        using client: Client
    ) async throws -> [String: Any] where Client: TestClientProtocol {
        let captured = LockedIssue4Value<[String: Any]?>(nil)
        try await client.execute(
            uri: "/api/v1/cards/\(cardID)/dashboard?month=\(month)",
            method: .get,
            headers: issue4Headers(login: allowedLogin)
        ) { response in
            try requireIssue4Status(response, .ok)
            captured.set(try issue4JSONObject(response.body)["dashboard"] as? [String: Any])
        }
        return try XCTUnwrap(captured.get())
    }

    private func transactions<Client>(
        cardID: String,
        month: String,
        using client: Client
    ) async throws -> [[String: Any]] where Client: TestClientProtocol {
        let captured = LockedIssue4Value<[[String: Any]]>([])
        try await client.execute(
            uri: "/api/v1/cards/\(cardID)/transactions?filter=all&month=\(month)",
            method: .get,
            headers: issue4Headers(login: allowedLogin)
        ) { response in
            try requireIssue4Status(response, .ok)
            captured.set(
                try XCTUnwrap(issue4JSONObject(response.body)["transactions"] as? [[String: Any]])
            )
        }
        return captured.get()
    }

    private func ingest<Client>(_ event: OutboxEvent, using client: Client) async throws -> String
    where Client: TestClientProtocol {
        let captured = LockedIssue4Value<String?>(nil)
        let body = try codec.encode(BatchSyncRequest(events: [event]))
        try await client.execute(
            uri: "/api/v1/events/batch",
            method: .post,
            headers: issue4Headers(login: allowedLogin, mutation: true),
            body: issue4ByteBuffer(body)
        ) { response in
            try requireIssue4Status(response, .ok)
            let value = try self.codec.decode(
                BatchSyncResponse.self,
                from: Data(response.body.readableBytesView)
            )
            captured.set(value.results.first?.transactionID?.uuidString)
        }
        return try XCTUnwrap(captured.get())
    }

    private func review<Client>(
        transactionID: String,
        performance: String?,
        benefitIDs: [String],
        aggregationExcluded: Bool = false,
        using client: Client
    ) async throws where Client: TestClientProtocol {
        let performanceValue: Any = performance ?? NSNull()
        let payload: [String: Any] = [
            "review": [
                "performance": performanceValue,
                "benefitIds": benefitIDs,
                "memo": ""
            ],
            "aggregationExcluded": aggregationExcluded
        ]
        try await client.execute(
            uri: "/api/v1/transactions/\(transactionID)",
            method: .patch,
            headers: issue4Headers(login: allowedLogin, mutation: true),
            body: issue4ByteBuffer(try issue4JSONData(payload))
        ) { response in
            try requireIssue4Status(response, .ok)
        }
    }

    private func qualifyExistingCardBenefits<Client>(
        cardID: String,
        using client: Client
    ) async throws where Client: TestClientProtocol {
        let payload: [String: Any] = [
            "performanceOffsetAmount": 300_000,
            "benefitOffsets": []
        ]
        try await client.execute(
            uri: "/api/v1/cards/\(cardID)/monthly-offsets?month=2026-07",
            method: .put,
            headers: issue4Headers(login: allowedLogin, mutation: true),
            body: issue4ByteBuffer(try issue4JSONData(payload))
        ) { response in
            try requireIssue4Status(response, .ok)
        }
    }

    private func performance(_ dashboard: [String: Any]) -> [String: Any] {
        dashboard["performance"] as? [String: Any] ?? [:]
    }

    private func receivedBenefit(_ id: String, in dashboard: [String: Any]) throws -> Int {
        try requiredInt(try benefitProgress(id, in: dashboard), key: "receivedAmount")
    }

    private func benefitProgress(_ id: String, in dashboard: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap(
            (dashboard["benefits"] as? [[String: Any]])?.first { $0["id"] as? String == id }
        )
    }

    private func requiredString(_ object: [String: Any], key: String) throws -> String {
        try XCTUnwrap(object[key] as? String, "Missing string field: \(key)")
    }

    private func requiredInt(_ object: [String: Any], key: String) throws -> Int {
        try XCTUnwrap(object[key] as? Int, "Missing integer field: \(key)")
    }

    private func exactTransactionAmount(forBenefitAmount amount: Int, rate: Int) -> Int {
        precondition(rate > 0)
        precondition(amount * 10_000 % rate == 0)
        return amount * 10_000 / rate
    }

    private func approval(
        id: UUID,
        capturedAt: String,
        localDateTime: String,
        amount: Int,
        merchant: String
    ) -> OutboxEvent {
        OutboxEvent(
            eventId: id,
            capturedAt: ISO8601DateFormatter().date(from: capturedAt)!,
            originalMessage: """
            [Synthetic Fixture]
            MG카드(4775)체크승인
            \(formattedWon(amount))
            \(localDateTime)
            \(merchant)
            """
        )
    }

    private func cancellation(
        id: UUID,
        capturedAt: String,
        localDate: String,
        amount: Int,
        merchant: String
    ) -> OutboxEvent {
        OutboxEvent(
            eventId: id,
            capturedAt: ISO8601DateFormatter().date(from: capturedAt)!,
            originalMessage: """
            [Synthetic Fixture]
            [승인취소]
            MG체크카드(4775)
            \(formattedWon(amount))
            \(localDate).취소완료.
            \(merchant)
            """
        )
    }

    private func formattedWon(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return "\(formatter.string(from: NSNumber(value: amount))!)원"
    }

    private func temporaryDatabaseURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Issue4BlackBoxAcceptanceTests-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        return url
    }

    private func removeDatabaseFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}

private final class LockedIssue4Value<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value {
        lock.withLock { value }
    }

    func set(_ newValue: Value) {
        lock.withLock { value = newValue }
    }
}

private func issue4Headers(login: String? = nil, mutation: Bool = false) -> HTTPFields {
    var fields: HTTPFields = [:]
    if let login {
        fields[.init("Tailscale-User-Login")!] = login
    }
    if mutation {
        fields[.contentType] = "application/json"
        fields[.init("X-CherryPicker-CSRF")!] = "same-origin"
    }
    return fields
}

private func issue4JSONData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func issue4JSONObject(_ body: ByteBuffer) throws -> [String: Any] {
    try XCTUnwrap(
        JSONSerialization.jsonObject(with: Data(body.readableBytesView)) as? [String: Any]
    )
}

private func issue4ByteBuffer(_ data: Data) -> ByteBuffer {
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    buffer.writeBytes(data)
    return buffer
}

private func issue4BodyString(_ body: ByteBuffer) -> String {
    String(decoding: body.readableBytesView, as: UTF8.self)
}

private struct UnexpectedIssue4HTTPStatus: Error, CustomStringConvertible {
    let expected: HTTPResponse.Status
    let actual: HTTPResponse.Status

    var description: String {
        "Expected HTTP \(expected), received \(actual). The proposed Issue #4 contract is not implemented."
    }
}

private func requireIssue4Status(
    _ response: TestResponse,
    _ expected: HTTPResponse.Status
) throws {
    guard response.status == expected else {
        throw UnexpectedIssue4HTTPStatus(expected: expected, actual: response.status)
    }
}
