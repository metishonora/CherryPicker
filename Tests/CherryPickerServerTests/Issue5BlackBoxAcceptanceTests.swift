import Foundation
import XCTest

import CherryPickerCore
import CherryPickerServer
import Hummingbird
import HummingbirdTesting

/// Proposed black-box acceptance tests for Issue #5.
///
/// The suite constructs the real HTTP application, then observes only HTTP
/// requests and responses. It does not read SQLite tables or call store query
/// and mutation methods. These tests are the executable acceptance boundary
/// for the approved Issue #5 product behavior.
@available(macOS 14.0, *)
final class Issue5BlackBoxAcceptanceTests: XCTestCase, @unchecked Sendable {
    private let allowedLogin = "fixture-device@example.test"
    private let codec = OutboxJSONCodec()

    // MARK: - Cards and card settings

    func testCardsCanBeListedAndSelectedCardSettingsSurviveRestart() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let selectedCardID = LockedValue<String?>(nil)

        do {
            let app = try makeApplication(databaseURL: databaseURL)
            try await app.test(.router) { client in
                let cards = try await fetchCards(using: client)
                let card = try XCTUnwrap(cards.first)
                let cardID = try XCTUnwrap(card["id"] as? String)
                selectedCardID.set(cardID)

                XCTAssertNotNil(card["displayName"] as? String)
                XCTAssertNotNil(card["issuerCode"] as? String)
                XCTAssertNotNil(card["lastFour"] as? String)
                XCTAssertNil(card["performanceTargetAmount"])
                XCTAssertEqual(card["cardTypeCode"] as? String, "mg.the-better-check")
                XCTAssertEqual(
                    card["performanceCalculationBasis"] as? String,
                    "‘더나은’ 정상 이용금액"
                )
                let benefits = try XCTUnwrap(card["benefits"] as? [[String: Any]])
                XCTAssertEqual(benefits.compactMap { $0["label"] as? String }, [
                    "간편결제 20% 할인캐시백",
                    "온라인 쇼핑 20% 할인캐시백",
                    "커피 20% 할인캐시백"
                ])
                XCTAssertEqual(
                    benefits.compactMap { $0["rateBasisPoints"] as? Int },
                    [2_000, 2_000, 2_000]
                )
                XCTAssertEqual(
                    benefits.compactMap { $0["maximumAmount"] as? Int },
                    [6_000, 6_000, 6_000]
                )
                XCTAssertEqual(
                    benefits.compactMap { $0["minimumTransactionAmount"] as? Int },
                    [10_000, 10_000, 5_000]
                )
                XCTAssertTrue((card["performanceExclusions"] as? [String])?.contains(
                    "해외가맹점 이용금액(CD·ATM 인출 포함)"
                ) == true)
                XCTAssertTrue((card["benefitExclusions"] as? [String])?.contains(
                    "자동차 판매 업종(국산차·수입차·위탁판매·중고차·이륜차 포함)"
                ) == true)

                let update: [String: Any] = [
                    "displayName": "생활비 카드",
                    "issuerCode": card["issuerCode"] as? String ?? "MG",
                    "lastFour": card["lastFour"] as? String ?? "4775"
                ]
                try await client.execute(
                    uri: "/api/v1/cards/\(cardID)",
                    method: .put,
                    headers: managementHeaders(login: allowedLogin, mutation: true),
                    body: httpByteBuffer(try jsonData(update))
                ) { response in
                    try requireStatus(response, .ok)
                    let updated = try cardObject(from: response.body)
                    XCTAssertEqual(updated["id"] as? String, cardID)
                    XCTAssertEqual(updated["displayName"] as? String, "생활비 카드")
                    XCTAssertNil(updated["performanceTargetAmount"])
                }
            }
        }

        do {
            let reopenedApp = try makeApplication(databaseURL: databaseURL)
            try await reopenedApp.test(.router) { client in
                let cards = try await fetchCards(using: client)
                let card = try XCTUnwrap(
                    cards.first { $0["id"] as? String == selectedCardID.get() }
                )
                XCTAssertEqual(card["displayName"] as? String, "생활비 카드")
                XCTAssertNil(card["performanceTargetAmount"])
            }
        }
    }

    // MARK: - Global inbox and card-scoped transactions

    func testGlobalUnreviewedFeedNeedsNoCardSelectionAndRowsCarryCardIdentity() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let firstID = try await ingest(
                makeApprovalEvent(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                    capturedAt: "2026-08-17T09:00:00+09:00",
                    amount: "1,000원",
                    merchant: "Synthetic Global Oldest"
                ),
                using: client
            )
            let secondID = try await ingest(
                makeApprovalEvent(
                    id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
                    capturedAt: "2026-08-17T11:00:00+09:00",
                    amount: "2,000원",
                    merchant: "Synthetic Global Newest"
                ),
                using: client
            )

            let before = try await fetchTransactions(
                uri: "/api/v1/transactions?scope=unreviewed",
                using: client
            )
            XCTAssertEqual(before.compactMap { $0["id"] as? String }, [secondID, firstID])
            XCTAssertTrue(before.allSatisfy { $0["reviewStatus"] as? String == "unreviewed" })
            XCTAssertTrue(before.allSatisfy { !($0["cardId"] as? String ?? "").isEmpty })
            XCTAssertTrue(before.allSatisfy { !($0["cardDisplayName"] as? String ?? "").isEmpty })
            XCTAssertTrue(before.allSatisfy { !($0["cardLastFour"] as? String ?? "").isEmpty })

            try await reviewTransaction(
                id: secondID,
                performance: "excluded",
                benefitIDs: [],
                aggregationExcluded: false,
                using: client
            ) { transaction in
                XCTAssertEqual(transaction["reviewStatus"] as? String, "reviewed")
            }

            let after = try await fetchTransactions(
                uri: "/api/v1/transactions?scope=unreviewed",
                using: client
            )
            XCTAssertEqual(after.compactMap { $0["id"] as? String }, [firstID])
        }
    }

    func testSelectedCardTransactionsSupportApprovalCancellationAndExcludedFilters() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let card = try await fetchFirstCard(using: client)
            let cardID = try XCTUnwrap(card["id"] as? String)
            let approvalID = try await ingest(
                makeApprovalEvent(
                    id: UUID(uuidString: "11000000-0000-0000-0000-000000000001")!,
                    capturedAt: "2026-08-17T09:00:00+09:00",
                    amount: "4,000원",
                    merchant: "Synthetic Approval"
                ),
                using: client
            )
            let cancellationID = try await ingest(
                makeCancellationEvent(
                    id: UUID(uuidString: "11000000-0000-0000-0000-000000000002")!,
                    capturedAt: "2026-08-17T10:00:00+09:00",
                    amount: "3,800원"
                ),
                using: client
            )
            let excludedID = try await ingest(
                makeApprovalEvent(
                    id: UUID(uuidString: "11000000-0000-0000-0000-000000000003")!,
                    capturedAt: "2026-08-17T11:00:00+09:00",
                    amount: "5,000원",
                    merchant: "Synthetic Excluded"
                ),
                using: client
            )
            try await reviewTransaction(
                id: excludedID,
                performance: nil,
                benefitIDs: [],
                aggregationExcluded: true,
                using: client
            ) { transaction in
                XCTAssertEqual(transaction["aggregationExcluded"] as? Bool, true)
            }

            let approvals = try await fetchTransactions(
                uri: "/api/v1/cards/\(cardID)/transactions?filter=approval",
                using: client
            )
            XCTAssertEqual(approvals.compactMap { $0["id"] as? String }, [approvalID])

            let cancellations = try await fetchTransactions(
                uri: "/api/v1/cards/\(cardID)/transactions?filter=cancellation",
                using: client
            )
            XCTAssertEqual(cancellations.compactMap { $0["id"] as? String }, [cancellationID])

            let excluded = try await fetchTransactions(
                uri: "/api/v1/cards/\(cardID)/transactions?filter=excluded",
                using: client
            )
            XCTAssertEqual(excluded.compactMap { $0["id"] as? String }, [excludedID])
        }
    }

    // MARK: - Review contract

    func testReviewKeepsFactsReadOnlyAndAcceptsZeroOrMultipleBenefits() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let card = try await fetchFirstCard(using: client)
            let benefitIDs = Array(
                (card["benefits"] as? [[String: Any]] ?? [])
                    .compactMap { $0["id"] as? String }
                    .prefix(3)
            )
            XCTAssertEqual(benefitIDs.count, 3)

            let noBenefitID = try await ingest(
                makeApprovalEvent(
                    id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
                    capturedAt: "2026-08-17T12:00:00+09:00",
                    amount: "2,500원",
                    merchant: "Synthetic Read Only Merchant"
                ),
                using: client
            )
            try await reviewTransaction(
                id: noBenefitID,
                performance: "included",
                benefitIDs: [],
                aggregationExcluded: false,
                using: client
            ) { transaction in
                XCTAssertEqual(transaction["amount"] as? Int, 2_500)
                XCTAssertEqual(transaction["merchant"] as? String, "Synthetic Read Only Merchant")
                XCTAssertEqual(transaction["benefitIds"] as? [String], [])
                XCTAssertNil(transaction["noApplicableBenefit"])
            }

            let multipleBenefitsID = try await ingest(
                makeApprovalEvent(
                    id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
                    capturedAt: "2026-08-17T13:00:00+09:00",
                    amount: "3,100원",
                    merchant: "Synthetic Multiple Benefits"
                ),
                using: client
            )
            try await reviewTransaction(
                id: multipleBenefitsID,
                performance: "included",
                benefitIDs: benefitIDs,
                aggregationExcluded: false,
                using: client
            ) { transaction in
                XCTAssertEqual(Set(transaction["benefitIds"] as? [String] ?? []), Set(benefitIDs))
            }

            let illegalMutation: [String: Any] = [
                "effectiveValues": [
                    "amount": 999_999,
                    "merchant": "Must Not Replace Parsed Facts"
                ],
                "review": [
                    "performance": "included",
                    "benefitIds": []
                ],
                "aggregationExcluded": false
            ]
            try await client.execute(
                uri: "/api/v1/transactions/\(noBenefitID)",
                method: .patch,
                headers: managementHeaders(login: allowedLogin, mutation: true),
                body: httpByteBuffer(try jsonData(illegalMutation))
            ) { response in
                try requireStatus(response, .badRequest)
            }

            let unchanged = try await fetchTransaction(id: noBenefitID, using: client)
            XCTAssertEqual(unchanged["amount"] as? Int, 2_500)
            XCTAssertEqual(unchanged["merchant"] as? String, "Synthetic Read Only Merchant")
        }
    }

    func testReviewAndMemoSurviveServerRestart() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let transactionID = LockedValue<String?>(nil)

        do {
            let app = try makeApplication(databaseURL: databaseURL)
            try await app.test(.router) { client in
                let id = try await ingest(
                    makeApprovalEvent(
                        id: UUID(uuidString: "21000000-0000-0000-0000-000000000001")!,
                        capturedAt: "2026-08-17T14:00:00+09:00",
                        amount: "7,000원",
                        merchant: "Synthetic Persistent Review"
                    ),
                    using: client
                )
                transactionID.set(id)
                try await reviewTransaction(
                    id: id,
                    performance: "included",
                    benefitIDs: [],
                    memo: "synthetic memo",
                    aggregationExcluded: false,
                    using: client
                ) { transaction in
                    XCTAssertEqual(transaction["reviewStatus"] as? String, "reviewed")
                }
            }
        }

        do {
            let reopenedApp = try makeApplication(databaseURL: databaseURL)
            try await reopenedApp.test(.router) { client in
                let transaction = try await fetchTransaction(
                    id: try XCTUnwrap(transactionID.get()),
                    using: client
                )
                XCTAssertEqual(transaction["reviewStatus"] as? String, "reviewed")
                XCTAssertEqual(transaction["performance"] as? String, "included")
                XCTAssertEqual(transaction["benefitIds"] as? [String], [])
                XCTAssertEqual(transaction["memo"] as? String, "synthetic memo")
            }
        }
    }

    // MARK: - Dashboard, cancellation, and exclusion

    func testSelectedCardDashboardTracksPerformanceAndBenefitProgress() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let card = try await fetchFirstCard(using: client)
            let cardID = try XCTUnwrap(card["id"] as? String)
            let benefitID = try XCTUnwrap(
                (card["benefits"] as? [[String: Any]])?.first?["id"] as? String
            )
            try await qualifyExistingCardBenefits(cardID: cardID, using: client)
            let before = try await fetchDashboard(cardID: cardID, using: client)
            let beforePerformance = try performanceAmount(from: before)
            let beforeBenefit = try benefitAmount(id: benefitID, from: before)

            let transactionID = try await ingest(
                makeApprovalEvent(
                    id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
                    capturedAt: "2026-08-17T15:00:00+09:00",
                    amount: "10,000원",
                    merchant: "Synthetic Dashboard Approval"
                ),
                using: client
            )
            try await reviewTransaction(
                id: transactionID,
                performance: "included",
                benefitIDs: [benefitID],
                aggregationExcluded: false,
                using: client
            ) { _ in }

            let after = try await fetchDashboard(cardID: cardID, using: client)
            XCTAssertEqual(try performanceAmount(from: after), beforePerformance + 10_000)
            XCTAssertGreaterThan(try benefitAmount(id: benefitID, from: after), beforeBenefit)
            XCTAssertEqual(
                (after["performance"] as? [String: Any])?["targetAmount"] as? Int,
                300_000
            )
            XCTAssertEqual(
                (after["performance"] as? [String: Any])?["remainingAmount"] as? Int,
                290_000
            )

            let benefit = try XCTUnwrap(
                (after["benefits"] as? [[String: Any]])?.first {
                    $0["id"] as? String == benefitID
                }
            )
            XCTAssertNotNil(benefit["label"] as? String)
            XCTAssertNotNil(benefit["maximumAmount"] as? Int)
        }
    }

    func testCancellationRequiresNoApprovalMatchAndSubtractsCurrentPeriodTotals() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let card = try await fetchFirstCard(using: client)
            let cardID = try XCTUnwrap(card["id"] as? String)
            let benefitID = try XCTUnwrap(
                (card["benefits"] as? [[String: Any]])?.first?["id"] as? String
            )
            try await qualifyExistingCardBenefits(cardID: cardID, using: client)

            let approvalID = try await ingest(
                makeApprovalEvent(
                    id: UUID(uuidString: "31000000-0000-0000-0000-000000000001")!,
                    capturedAt: "2026-08-17T15:30:00+09:00",
                    amount: "20,000원",
                    merchant: "Synthetic Dashboard Baseline"
                ),
                using: client
            )
            try await reviewTransaction(
                id: approvalID,
                performance: "included",
                benefitIDs: [benefitID],
                aggregationExcluded: false,
                using: client
            ) { _ in }
            let afterApproval = try await fetchDashboard(cardID: cardID, using: client)

            let cancellationID = try await ingest(
                makeCancellationEvent(
                    id: UUID(uuidString: "31000000-0000-0000-0000-000000000002")!,
                    capturedAt: "2026-08-17T16:00:00+09:00",
                    amount: "3,800원"
                ),
                using: client
            )
            try await reviewTransaction(
                id: cancellationID,
                performance: "included",
                benefitIDs: [benefitID],
                aggregationExcluded: false,
                using: client
            ) { transaction in
                XCTAssertEqual(transaction["kind"] as? String, "cancellation")
                XCTAssertNil(transaction["linkedApprovalId"])
            }

            let afterCancellation = try await fetchDashboard(cardID: cardID, using: client)
            XCTAssertEqual(
                try performanceAmount(from: afterCancellation),
                try performanceAmount(from: afterApproval) - 3_800
            )
            XCTAssertLessThan(
                try benefitAmount(id: benefitID, from: afterCancellation),
                try benefitAmount(id: benefitID, from: afterApproval)
            )
        }
    }

    func testAggregationExclusionIsVisibleReversibleAndNeverDeletesTransaction() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let card = try await fetchFirstCard(using: client)
            let cardID = try XCTUnwrap(card["id"] as? String)
            let benefitID = try XCTUnwrap(
                (card["benefits"] as? [[String: Any]])?.first?["id"] as? String
            )
            let id = try await ingest(
                makeApprovalEvent(
                    id: UUID(uuidString: "32000000-0000-0000-0000-000000000001")!,
                    capturedAt: "2026-08-17T17:00:00+09:00",
                    amount: "4,000원",
                    merchant: "Synthetic Reversible Exclusion"
                ),
                using: client
            )
            try await reviewTransaction(
                id: id,
                performance: "included",
                benefitIDs: [benefitID],
                aggregationExcluded: false,
                using: client
            ) { _ in }
            let includedDashboard = try await fetchDashboard(cardID: cardID, using: client)

            try await reviewTransaction(
                id: id,
                performance: nil,
                benefitIDs: [],
                aggregationExcluded: true,
                using: client
            ) { transaction in
                XCTAssertEqual(transaction["aggregationExcluded"] as? Bool, true)
                XCTAssertNil(transaction["performance"])
                XCTAssertEqual(transaction["benefitIds"] as? [String], [])
            }
            let excludedDashboard = try await fetchDashboard(cardID: cardID, using: client)
            XCTAssertEqual(
                try performanceAmount(from: excludedDashboard),
                try performanceAmount(from: includedDashboard) - 4_000
            )
            let excludedRows = try await fetchTransactions(
                uri: "/api/v1/cards/\(cardID)/transactions?filter=excluded",
                using: client
            )
            XCTAssertEqual(excludedRows.compactMap { $0["id"] as? String }, [id])

            try await reviewTransaction(
                id: id,
                performance: "excluded",
                benefitIDs: [],
                aggregationExcluded: false,
                using: client
            ) { transaction in
                XCTAssertEqual(transaction["aggregationExcluded"] as? Bool, false)
            }
            let restoredTransaction = try await fetchTransaction(id: id, using: client)
            XCTAssertEqual(restoredTransaction["id"] as? String, id)
        }
    }

    // MARK: - Security boundary

    func testManagementReadsRequireExactLoginAndMutationsRequireCSRFHeader() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/v1/cards", method: .get) { response in
                try requireStatus(response, .unauthorized)
            }
            try await client.execute(
                uri: "/api/v1/cards",
                method: .get,
                headers: managementHeaders(login: "other-device@example.test")
            ) { response in
                try requireStatus(response, .unauthorized)
            }

            let card = try await fetchFirstCard(using: client)
            let cardID = try XCTUnwrap(card["id"] as? String)
            let update: [String: Any] = [
                "displayName": "Must Not Save",
                "issuerCode": card["issuerCode"] as? String ?? "MG",
                "lastFour": card["lastFour"] as? String ?? "4775"
            ]
            try await client.execute(
                uri: "/api/v1/cards/\(cardID)",
                method: .put,
                headers: managementHeaders(login: allowedLogin, json: true),
                body: httpByteBuffer(try jsonData(update))
            ) { response in
                try requireStatus(response, .forbidden)
            }
        }
    }

    // MARK: - HTTP-only helpers

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
            headers: managementHeaders(login: allowedLogin, mutation: true),
            body: httpByteBuffer(try jsonData(payload))
        ) { response in
            try requireStatus(response, .ok)
        }
    }

    private func makeApplication(databaseURL: URL) throws -> some ApplicationProtocol {
        let store = try SQLiteEventStore(databaseURL: databaseURL)
        return try CherryPickerHTTPApplication(
            store: store,
            authorizer: TailscaleIdentityAuthorizer(allowedLogin: allowedLogin),
            codec: codec
        ).application
    }

    private func fetchCards<Client>(using client: Client) async throws -> [[String: Any]]
    where Client: TestClientProtocol {
        let captured = LockedValue<[[String: Any]]>([])
        try await client.execute(
            uri: "/api/v1/cards",
            method: .get,
            headers: managementHeaders(login: allowedLogin)
        ) { response in
            try requireStatus(response, .ok)
            captured.set(try cardObjects(from: response.body))
        }
        return captured.get()
    }

    private func fetchFirstCard<Client>(using client: Client) async throws -> [String: Any]
    where Client: TestClientProtocol {
        let cards = try await fetchCards(using: client)
        return try XCTUnwrap(cards.first)
    }

    private func fetchTransactions<Client>(
        uri: String,
        using client: Client
    ) async throws -> [[String: Any]] where Client: TestClientProtocol {
        let captured = LockedValue<[[String: Any]]>([])
        try await client.execute(
            uri: uri,
            method: .get,
            headers: managementHeaders(login: allowedLogin)
        ) { response in
            try requireStatus(response, .ok)
            captured.set(try transactionObjects(from: response.body))
        }
        return captured.get()
    }

    private func fetchTransaction<Client>(
        id: String,
        using client: Client
    ) async throws -> [String: Any] where Client: TestClientProtocol {
        let captured = LockedValue<[String: Any]?>(nil)
        try await client.execute(
            uri: "/api/v1/transactions/\(id)",
            method: .get,
            headers: managementHeaders(login: allowedLogin)
        ) { response in
            try requireStatus(response, .ok)
            captured.set(try transactionObject(from: response.body))
        }
        return try XCTUnwrap(captured.get())
    }

    private func fetchDashboard<Client>(
        cardID: String,
        using client: Client
    ) async throws -> [String: Any] where Client: TestClientProtocol {
        let captured = LockedValue<[String: Any]?>(nil)
        try await client.execute(
            uri: "/api/v1/cards/\(cardID)/dashboard",
            method: .get,
            headers: managementHeaders(login: allowedLogin)
        ) { response in
            try requireStatus(response, .ok)
            captured.set(try jsonObject(from: response.body)["dashboard"] as? [String: Any])
        }
        return try XCTUnwrap(captured.get())
    }

    private func ingest<Client>(_ event: OutboxEvent, using client: Client) async throws -> String
    where Client: TestClientProtocol {
        let captured = LockedValue<String?>(nil)
        let request = try codec.encode(BatchSyncRequest(events: [event]))
        try await client.execute(
            uri: "/api/v1/events/batch",
            method: .post,
            headers: managementHeaders(login: allowedLogin, json: true),
            body: httpByteBuffer(request)
        ) { response in
            try requireStatus(response, .ok)
            let decoded = try self.codec.decode(
                BatchSyncResponse.self,
                from: Data(response.body.readableBytesView)
            )
            captured.set(decoded.results.first?.transactionID?.uuidString)
        }
        return try XCTUnwrap(captured.get())
    }

    private func reviewTransaction<Client>(
        id: String,
        performance: String?,
        benefitIDs: [String],
        memo: String = "",
        aggregationExcluded: Bool,
        using client: Client,
        assertions: @escaping @Sendable ([String: Any]) throws -> Void
    ) async throws where Client: TestClientProtocol {
        let review: [String: Any] = [
            "performance": performance ?? NSNull(),
            "benefitIds": benefitIDs,
            "memo": memo
        ]
        let payload: [String: Any] = [
            "review": review,
            "aggregationExcluded": aggregationExcluded
        ]
        try await client.execute(
            uri: "/api/v1/transactions/\(id)",
            method: .patch,
            headers: managementHeaders(login: allowedLogin, mutation: true),
            body: httpByteBuffer(try jsonData(payload))
        ) { response in
            try requireStatus(response, .ok)
            try assertions(transactionObject(from: response.body))
        }
    }

    private func performanceAmount(from dashboard: [String: Any]) throws -> Int {
        try XCTUnwrap((dashboard["performance"] as? [String: Any])?["currentAmount"] as? Int)
    }

    private func benefitAmount(id: String, from dashboard: [String: Any]) throws -> Int {
        let benefit = try XCTUnwrap(
            (dashboard["benefits"] as? [[String: Any]])?.first { $0["id"] as? String == id }
        )
        return try XCTUnwrap(benefit["receivedAmount"] as? Int)
    }

    private func makeApprovalEvent(
        id: UUID,
        capturedAt: String,
        amount: String,
        merchant: String
    ) -> OutboxEvent {
        OutboxEvent(
            eventId: id,
            capturedAt: ISO8601DateFormatter().date(from: capturedAt)!,
            originalMessage: """
            [Synthetic Fixture]
            MG카드(4775)체크승인
            \(amount)
            08/17 08:55
            \(merchant)
            """
        )
    }

    private func makeCancellationEvent(
        id: UUID,
        capturedAt: String,
        amount: String
    ) -> OutboxEvent {
        OutboxEvent(
            eventId: id,
            capturedAt: ISO8601DateFormatter().date(from: capturedAt)!,
            originalMessage: """
            [Synthetic Fixture]
            [승인취소]
            MG체크카드(4775)
            \(amount)
            08/17.취소완료.
            Synthetic Cancellation Merchant
            """
        )
    }

    private func temporaryDatabaseURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Issue5BlackBoxAcceptanceTests-\(UUID().uuidString)")
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

private final class LockedValue<Value>: @unchecked Sendable {
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

private func managementHeaders(
    login: String? = nil,
    json: Bool = false,
    mutation: Bool = false
) -> HTTPFields {
    var fields: HTTPFields = [:]
    if let login {
        fields[.init("Tailscale-User-Login")!] = login
    }
    if json || mutation {
        fields[.contentType] = "application/json"
    }
    if mutation {
        fields[.init("X-CherryPicker-CSRF")!] = "same-origin"
    }
    return fields
}

private func jsonData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func jsonObject(from body: ByteBuffer) throws -> [String: Any] {
    try XCTUnwrap(
        JSONSerialization.jsonObject(with: Data(body.readableBytesView)) as? [String: Any]
    )
}

private func cardObject(from body: ByteBuffer) throws -> [String: Any] {
    try XCTUnwrap(jsonObject(from: body)["card"] as? [String: Any])
}

private func cardObjects(from body: ByteBuffer) throws -> [[String: Any]] {
    try XCTUnwrap(jsonObject(from: body)["cards"] as? [[String: Any]])
}

private func transactionObject(from body: ByteBuffer) throws -> [String: Any] {
    try XCTUnwrap(jsonObject(from: body)["transaction"] as? [String: Any])
}

private func transactionObjects(from body: ByteBuffer) throws -> [[String: Any]] {
    try XCTUnwrap(jsonObject(from: body)["transactions"] as? [[String: Any]])
}

private func httpByteBuffer(_ data: Data) -> ByteBuffer {
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    buffer.writeBytes(data)
    return buffer
}

private struct UnexpectedHTTPStatus: Error, CustomStringConvertible {
    let expected: HTTPResponse.Status
    let actual: HTTPResponse.Status

    var description: String {
        "Expected HTTP \(expected), received \(actual). The Issue #5 route may not be implemented yet."
    }
}

private func requireStatus(
    _ response: TestResponse,
    _ expected: HTTPResponse.Status
) throws {
    guard response.status == expected else {
        throw UnexpectedHTTPStatus(expected: expected, actual: response.status)
    }
}
