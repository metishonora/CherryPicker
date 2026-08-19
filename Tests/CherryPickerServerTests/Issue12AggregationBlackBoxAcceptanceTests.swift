import Foundation
import XCTest

import CherryPickerServer
import Hummingbird
import HummingbirdTesting

/// HTTP-only acceptance contract for the Issue #12 aggregation and approved UI flow.
///
/// These tests intentionally avoid importing internal card policy or dashboard calculator types.
/// They describe the wire behavior that the product UI consumes and are expected to fail until
/// the tiered integrated-limit implementation replaces the legacy single-target model.
@available(macOS 14.0, *)
final class Issue12AggregationBlackBoxAcceptanceTests: XCTestCase, @unchecked Sendable {
    private let allowedLogin = "fixture-device@example.test"
    private let mgPlusCardTypeCode = "hana.mg-plus-s"

    func testMGPlusPolicyExposesThreeBenefitsAndCommonExclusionsWithoutEditableTarget()
        async throws
    {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let card = try await createMGPlusCard(lastFour: "1234", using: client)

            XCTAssertNil(
                card["performanceTargetAmount"],
                "A card with several performance tiers must not expose one editable target."
            )
            XCTAssertEqual(
                card["performanceThresholdAmounts"] as? [Int],
                [300_000, 600_000, 1_000_000],
                "The card policy must expose every fixed performance threshold for live previews."
            )

            guard let limitPolicy = contractObject(card, key: "benefitLimitPolicy") else {
                return
            }
            XCTAssertEqual(limitPolicy["type"] as? String, "integrated")
            guard let tiers = contractObjects(limitPolicy, key: "tiers") else { return }
            XCTAssertEqual(
                try tiers.map { tier in
                    [
                        try requiredInt(tier, key: "minimumPreviousMonthPerformanceAmount"),
                        try requiredInt(tier, key: "maximumAmount")
                    ]
                },
                [
                    [0, 0],
                    [300_000, 15_000],
                    [600_000, 30_000],
                    [1_000_000, 60_000]
                ]
            )

            guard let benefits = contractObjects(card, key: "benefits") else { return }
            XCTAssertEqual(benefits.count, 3)
            guard benefits.count == 3 else { return }
            let benefitsByLabel = Dictionary(
                uniqueKeysWithValues: benefits.compactMap { benefit -> (String, [String: Any])? in
                    guard let label = benefit["label"] as? String else { return nil }
                    return (label, benefit)
                }
            )

            let simplePay = try XCTUnwrap(benefitsByLabel["간편결제 10% 청구할인"])
            XCTAssertEqual(
                Set(simplePay["eligibleMerchants"] as? [String] ?? []),
                Set(["네이버페이", "카카오페이", "토스페이", "SSG페이", "11pay", "스마일페이"])
            )
            XCTAssertEqual(simplePay["minimumTransactionAmount"] as? Int, 10_000)
            XCTAssertEqual(simplePay["rateBasisPoints"] as? Int, 1_000)
            XCTAssertEqual(simplePay["recurringPaymentOnly"] as? Bool, false)

            let streaming = try XCTUnwrap(benefitsByLabel["영상 스트리밍 50% 청구할인"])
            XCTAssertEqual(
                Set(streaming["eligibleMerchants"] as? [String] ?? []),
                Set(["유튜브", "디즈니플러스", "Wavve", "넷플릭스", "티빙"])
            )
            XCTAssertEqual(streaming["minimumTransactionAmount"] as? Int, 0)
            XCTAssertEqual(streaming["rateBasisPoints"] as? Int, 5_000)
            XCTAssertEqual(streaming["recurringPaymentOnly"] as? Bool, true)

            let membership = try XCTUnwrap(benefitsByLabel["디지털 멤버십 50% 청구할인"])
            XCTAssertEqual(
                Set(membership["eligibleMerchants"] as? [String] ?? []),
                Set(["네이버플러스멤버십", "컬리멤버스", "쿠팡와우멤버십"])
            )
            XCTAssertEqual(membership["minimumTransactionAmount"] as? Int, 0)
            XCTAssertEqual(membership["rateBasisPoints"] as? Int, 5_000)
            XCTAssertEqual(membership["recurringPaymentOnly"] as? Bool, true)

            for benefit in benefits {
                XCTAssertNil(
                    benefit["maximumAmount"],
                    "A shared limit must not be presented as an individual benefit cap."
                )
                XCTAssertNil(benefit["requiredPreviousMonthPerformanceAmount"])
            }

            XCTAssertEqual(
                Set(card["benefitExclusions"] as? [String] ?? []),
                Set([
                    "국세",
                    "지방세",
                    "그 외 공과금(우편요금, 과태료, 범칙금, 벌금, 국가·공공기관·공공단체가 부과하는 부담금)",
                    "국민연금, 고용보험료, 산재보험료와 건강보험료 납부 금액",
                    "수도요금",
                    "스쿨뱅킹",
                    "초·중·고 학교 납입금",
                    "대학등록금",
                    "대학원등록금",
                    "상품권 및 기프트카드 구매",
                    "선불카드 및 선불전자지급수단(하나머니 등) 충전 금액",
                    "부동산 임대료",
                    "무이자 할부 및 부분 무이자 할부 이용금액 전체"
                ])
            )
        }
    }

    func testPreviousMonthOffsetSelectsEveryIntegratedLimitBoundary() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let card = try await createMGPlusCard(lastFour: "1234", using: client)
            let cardID = try requiredString(card, key: "id")
            let examples = [
                (previousMonthFinal: 0, expectedLimit: 0),
                (previousMonthFinal: 299_999, expectedLimit: 0),
                (previousMonthFinal: 300_000, expectedLimit: 15_000),
                (previousMonthFinal: 599_999, expectedLimit: 15_000),
                (previousMonthFinal: 600_000, expectedLimit: 30_000),
                (previousMonthFinal: 999_999, expectedLimit: 30_000),
                (previousMonthFinal: 1_000_000, expectedLimit: 60_000)
            ]

            for example in examples {
                try await putOffsets(
                    cardID: cardID,
                    month: "2026-07",
                    performance: example.previousMonthFinal,
                    benefits: [],
                    using: client
                )
                let dashboard = try await dashboard(
                    cardID: cardID,
                    month: "2026-08",
                    using: client
                )
                guard let limit = contractObject(dashboard, key: "benefitLimit") else {
                    return
                }
                XCTAssertEqual(limit["type"] as? String, "integrated")
                XCTAssertEqual(
                    limit["maximumAmount"] as? Int,
                    example.expectedLimit,
                    "Wrong limit for previous-month final performance \(example.previousMonthFinal)."
                )
                XCTAssertEqual(limit["receivedAmount"] as? Int, 0)
                XCTAssertEqual(limit["remainingAmount"] as? Int, example.expectedLimit)
                XCTAssertEqual(
                    try requiredObject(dashboard, key: "performance")["currentAmount"] as? Int,
                    0,
                    "A previous-month offset must not become current-month performance."
                )
            }
        }
    }

    func testCurrentPerformanceSelectsTheNextAutomaticGoalAtEveryMGPlusBoundary()
        async throws
    {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let card = try await createMGPlusCard(lastFour: "1234", using: client)
            let cardID = try requiredString(card, key: "id")
            let examples = [
                (current: 0, target: 300_000, remaining: 300_000),
                (current: 299_999, target: 300_000, remaining: 1),
                (current: 300_000, target: 600_000, remaining: 300_000),
                (current: 599_999, target: 600_000, remaining: 1),
                (current: 600_000, target: 1_000_000, remaining: 400_000),
                (current: 999_999, target: 1_000_000, remaining: 1),
                (current: 1_000_000, target: 1_000_000, remaining: 0),
                (current: 1_200_000, target: 1_000_000, remaining: 0)
            ]

            for example in examples {
                try await putOffsets(
                    cardID: cardID,
                    month: "2026-08",
                    performance: example.current,
                    benefits: [],
                    using: client
                )
                let august = try await dashboard(
                    cardID: cardID,
                    month: "2026-08",
                    using: client
                )
                let performance = try requiredObject(august, key: "performance")
                XCTAssertEqual(performance["currentAmount"] as? Int, example.current)
                XCTAssertEqual(
                    performance["targetAmount"] as? Int,
                    example.target,
                    "Wrong automatic goal for current performance \(example.current)."
                )
                XCTAssertEqual(
                    performance["remainingAmount"] as? Int,
                    example.remaining,
                    "Wrong remaining amount for current performance \(example.current)."
                )
            }
        }
    }

    func testReviewedPreviousMonthPerformanceCombinesWithItsOffsetOnly() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let card = try await createMGPlusCard(lastFour: "1234", using: client)
            let cardID = try requiredString(card, key: "id")
            let julyTransactionID = try await ingestMGPlusApproval(
                eventID: UUID(uuidString: "12000000-0000-0000-0000-000000000101")!,
                capturedAt: "2026-07-15T13:00:00+09:00",
                maskedIdentifier: "1*3*",
                amount: "575,000",
                monthDay: "07/15",
                time: "12:34",
                merchant: "합성전월가맹점",
                using: client
            )
            try await review(
                transactionID: julyTransactionID,
                performance: "included",
                benefitIDs: [],
                using: client
            )
            try await putOffsets(
                cardID: cardID,
                month: "2026-07",
                performance: 25_000,
                benefits: [],
                using: client
            )
            try await putOffsets(
                cardID: cardID,
                month: "2026-08",
                performance: 400_000,
                benefits: [],
                using: client
            )

            let august = try await dashboard(
                cardID: cardID,
                month: "2026-08",
                using: client
            )
            let september = try await dashboard(
                cardID: cardID,
                month: "2026-09",
                using: client
            )
            guard
                let augustLimit = contractObject(august, key: "benefitLimit"),
                let septemberLimit = contractObject(september, key: "benefitLimit")
            else {
                return
            }
            XCTAssertEqual(
                augustLimit["maximumAmount"] as? Int,
                30_000,
                "575,000원 of reviewed July spend plus July's 25,000원 offset reaches 600,000원."
            )
            XCTAssertEqual(
                try requiredObject(august, key: "performance")["currentAmount"] as? Int,
                400_000,
                "August's offset belongs to August performance, not August's benefit limit."
            )

            XCTAssertEqual(
                septemberLimit["maximumAmount"] as? Int,
                15_000,
                "August's 400,000원 final performance determines September's limit."
            )
        }
    }

    func testThreeBenefitsConsumeOneSharedLimitInsteadOfThreeIndependentCaps() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let card = try await createMGPlusCard(lastFour: "1234", using: client)
            let cardID = try requiredString(card, key: "id")
            guard let benefits = contractObjects(card, key: "benefits") else { return }
            XCTAssertEqual(benefits.count, 3)
            guard benefits.count == 3 else { return }
            let simplePayID = try benefitID(label: "간편결제 10% 청구할인", in: benefits)
            let streamingID = try benefitID(label: "영상 스트리밍 50% 청구할인", in: benefits)
            let membershipID = try benefitID(label: "디지털 멤버십 50% 청구할인", in: benefits)

            try await putOffsets(
                cardID: cardID,
                month: "2026-07",
                performance: 600_000,
                benefits: [],
                using: client
            )

            let examples: [(UUID, String, String, String)] = [
                (
                    UUID(uuidString: "12000000-0000-0000-0000-000000000111")!,
                    "100,000", "합성간편결제", simplePayID
                ),
                (
                    UUID(uuidString: "12000000-0000-0000-0000-000000000112")!,
                    "20,000", "합성스트리밍", streamingID
                ),
                (
                    UUID(uuidString: "12000000-0000-0000-0000-000000000113")!,
                    "20,000", "합성멤버십", membershipID
                ),
                (
                    UUID(uuidString: "12000000-0000-0000-0000-000000000114")!,
                    "100,000", "합성추가간편결제", simplePayID
                )
            ]

            for (index, example) in examples.enumerated() {
                let transactionID = try await ingestMGPlusApproval(
                    eventID: example.0,
                    capturedAt: "2026-08-\(String(format: "%02d", 10 + index))T13:00:00+09:00",
                    maskedIdentifier: "1*3*",
                    amount: example.1,
                    monthDay: "08/\(String(format: "%02d", 10 + index))",
                    time: "12:3\(index)",
                    merchant: example.2,
                    using: client
                )
                try await review(
                    transactionID: transactionID,
                    performance: "included",
                    benefitIDs: [example.3],
                    using: client
                )
            }

            let august = try await dashboard(
                cardID: cardID,
                month: "2026-08",
                using: client
            )
            guard let limit = contractObject(august, key: "benefitLimit") else { return }
            XCTAssertEqual(limit["type"] as? String, "integrated")
            XCTAssertEqual(limit["maximumAmount"] as? Int, 30_000)
            XCTAssertEqual(
                limit["receivedAmount"] as? Int,
                30_000,
                "Raw benefit calculations total 40,000원 but one 30,000원 cap applies."
            )
            XCTAssertEqual(limit["remainingAmount"] as? Int, 0)

            let benefitRows = try requiredObjects(august, key: "benefits")
            XCTAssertEqual(
                benefitRows.reduce(0) { partial, row in
                    partial + (row["calculationAmount"] as? Int ?? 0)
                },
                40_000
            )
            XCTAssertTrue(benefitRows.allSatisfy { $0["maximumAmount"] == nil })
            XCTAssertEqual(
                try requiredObject(august, key: "performance")["currentAmount"] as? Int,
                240_000,
                "Payments receiving a benefit still count toward performance when reviewed as included."
            )
        }
    }

    func testPerformanceOffsetsAreIsolatedByCardAndBenefitMonth() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let firstCard = try await createMGPlusCard(
                displayName: "합성 MG+S 첫 번째",
                lastFour: "1234",
                using: client
            )
            let secondCard = try await createMGPlusCard(
                displayName: "합성 MG+S 두 번째",
                lastFour: "5678",
                using: client
            )
            let firstID = try requiredString(firstCard, key: "id")
            let secondID = try requiredString(secondCard, key: "id")

            try await putOffsets(
                cardID: firstID,
                month: "2026-07",
                performance: 600_000,
                benefits: [],
                using: client
            )
            try await putOffsets(
                cardID: secondID,
                month: "2026-07",
                performance: 300_000,
                benefits: [],
                using: client
            )
            try await putOffsets(
                cardID: firstID,
                month: "2026-08",
                performance: 1_000_000,
                benefits: [],
                using: client
            )

            let firstAugust = try await dashboard(
                cardID: firstID,
                month: "2026-08",
                using: client
            )
            let secondAugust = try await dashboard(
                cardID: secondID,
                month: "2026-08",
                using: client
            )
            let firstSeptember = try await dashboard(
                cardID: firstID,
                month: "2026-09",
                using: client
            )
            guard
                let firstAugustLimit = contractObject(firstAugust, key: "benefitLimit"),
                let secondAugustLimit = contractObject(secondAugust, key: "benefitLimit"),
                let firstSeptemberLimit = contractObject(firstSeptember, key: "benefitLimit")
            else {
                return
            }

            XCTAssertEqual(
                firstAugustLimit["maximumAmount"] as? Int,
                30_000
            )
            XCTAssertEqual(
                secondAugustLimit["maximumAmount"] as? Int,
                15_000
            )
            XCTAssertEqual(
                firstSeptemberLimit["maximumAmount"] as? Int,
                60_000
            )
        }
    }

    func testExistingCardKeepsPerBenefitCapsAndUsesItsFixedConditionAsAutomaticGoal()
        async throws
    {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let existingCard = try await firstCard(cardTypeCode: "mg.the-better-check", using: client)
            let cardID = try requiredString(existingCard, key: "id")

            XCTAssertNil(existingCard["performanceTargetAmount"])
            XCTAssertEqual(
                existingCard["performanceThresholdAmounts"] as? [Int],
                [300_000]
            )
            guard let existingPolicy = contractObject(
                existingCard,
                key: "benefitLimitPolicy"
            ) else {
                return
            }
            XCTAssertEqual(
                existingPolicy["type"] as? String,
                "perBenefit"
            )
            XCTAssertEqual(
                try requiredObjects(existingCard, key: "benefits").compactMap {
                    $0["maximumAmount"] as? Int
                },
                [6_000, 6_000, 6_000]
            )

            let updatePayload = try jsonData([
                "displayName": "합성 수정 카드",
                "lastFour": "2468"
            ])
            try await client.execute(
                uri: "/api/v1/cards/\(cardID)",
                method: .put,
                headers: headers(mutation: true),
                body: byteBuffer(updatePayload)
            ) { response in
                try requireStatus(response, .ok)
                let updated = try requiredObject(jsonObject(response.body), key: "card")
                XCTAssertEqual(updated["displayName"] as? String, "합성 수정 카드")
                XCTAssertNil(updated["performanceTargetAmount"])
                XCTAssertEqual(
                    updated["performanceThresholdAmounts"] as? [Int],
                    [300_000]
                )
            }

            let dashboard = try await dashboard(
                cardID: cardID,
                month: "2026-08",
                using: client
            )
            let performance = try requiredObject(dashboard, key: "performance")
            XCTAssertEqual(performance["targetAmount"] as? Int, 300_000)
            XCTAssertEqual(performance["remainingAmount"] as? Int, 300_000)
            XCTAssertEqual(
                try requiredObject(dashboard, key: "benefitLimit")["type"] as? String,
                "perBenefit"
            )

            try await client.execute(
                uri: "/",
                method: .get,
                headers: headers()
            ) { response in
                try requireStatus(response, .ok)
                let html = String(decoding: response.body.readableBytesView, as: UTF8.self)
                XCTAssertFalse(html.contains("setting-target"))
                XCTAssertFalse(html.contains("월 실적 목표"))
                XCTAssertTrue(html.contains("performance.targetAmount"))
                XCTAssertTrue(html.contains("performance-progress"))
                XCTAssertTrue(html.contains("detail-performance-progress"))
                XCTAssertTrue(html.contains("다음 실적 구간까지"))
                XCTAssertTrue(html.contains("id=\"benefit-overview-received\""))
                XCTAssertTrue(html.contains("id=\"benefit-overview-maximum\""))
                XCTAssertTrue(html.contains("id=\"benefit-overview-progress\""))
                XCTAssertTrue(html.contains("받은 통합혜택"))
                XCTAssertTrue(html.contains("받은 혜택"))
                XCTAssertTrue(html.contains("function integratedReviewBenefitProgress"))
                XCTAssertTrue(html.contains("dashboard.benefitLimit.maximumAmount || 0"))
                XCTAssertTrue(html.contains("integratedReviewBenefitProgress(dashboard, previewCalculations)"))
                XCTAssertTrue(html.contains("혜택별 받은 금액"))
                XCTAssertTrue(html.contains("cp-benefit-summary"))
                XCTAssertTrue(html.contains("data-card-theme"))
                XCTAssertTrue(
                    html.contains(
                        "if (benefit.eligibleMerchants.length > 0) values.push(`대상: ${benefit.eligibleMerchants.join(', ')}`);"
                    )
                )
                XCTAssertFalse(html.contains("integrated-remaining"))
                XCTAssertFalse(html.contains("integrated-received"))
            }
        }
    }

    private func makeApplication(databaseURL: URL) throws -> some ApplicationProtocol {
        try CherryPickerHTTPApplication(
            store: SQLiteEventStore(databaseURL: databaseURL),
            authorizer: TailscaleIdentityAuthorizer(allowedLogin: allowedLogin),
            codec: OutboxJSONCodec()
        ).application
    }

    private func createMGPlusCard<Client>(
        displayName: String = "합성 MG+S 하나카드",
        lastFour: String,
        using client: Client
    ) async throws -> [String: Any] where Client: TestClientProtocol {
        let captured = LockedIssue12AggregationValue<[String: Any]?>(nil)
        let payload = try jsonData([
            "cardTypeCode": mgPlusCardTypeCode,
            "displayName": displayName,
            "lastFour": lastFour
        ])
        try await client.execute(
            uri: "/api/v1/cards",
            method: .post,
            headers: headers(mutation: true),
            body: byteBuffer(payload)
        ) { response in
            try requireStatus(response, .created)
            captured.set(try requiredObject(jsonObject(response.body), key: "card"))
        }
        return try XCTUnwrap(captured.get())
    }

    private func firstCard<Client>(
        cardTypeCode: String,
        using client: Client
    ) async throws -> [String: Any] where Client: TestClientProtocol {
        let captured = LockedIssue12AggregationValue<[String: Any]?>(nil)
        try await client.execute(
            uri: "/api/v1/cards",
            method: .get,
            headers: headers()
        ) { response in
            try requireStatus(response, .ok)
            let cards = try requiredObjects(jsonObject(response.body), key: "cards")
            captured.set(cards.first { $0["cardTypeCode"] as? String == cardTypeCode })
        }
        return try XCTUnwrap(captured.get())
    }

    private func putOffsets<Client>(
        cardID: String,
        month: String,
        performance: Int,
        benefits: [[String: Any]],
        using client: Client
    ) async throws where Client: TestClientProtocol {
        let payload = try jsonData([
            "performanceOffsetAmount": performance,
            "benefitOffsets": benefits
        ])
        try await client.execute(
            uri: "/api/v1/cards/\(cardID)/monthly-offsets?month=\(month)",
            method: .put,
            headers: headers(mutation: true),
            body: byteBuffer(payload)
        ) { response in
            try requireStatus(response, .ok)
        }
    }

    private func dashboard<Client>(
        cardID: String,
        month: String,
        using client: Client
    ) async throws -> [String: Any] where Client: TestClientProtocol {
        let captured = LockedIssue12AggregationValue<[String: Any]?>(nil)
        try await client.execute(
            uri: "/api/v1/cards/\(cardID)/dashboard?month=\(month)",
            method: .get,
            headers: headers()
        ) { response in
            try requireStatus(response, .ok)
            captured.set(try requiredObject(jsonObject(response.body), key: "dashboard"))
        }
        return try XCTUnwrap(captured.get())
    }

    private func ingestMGPlusApproval<Client>(
        eventID: UUID,
        capturedAt: String,
        maskedIdentifier: String,
        amount: String,
        monthDay: String,
        time: String,
        merchant: String,
        using client: Client
    ) async throws -> String where Client: TestClientProtocol {
        let request: [String: Any] = [
            "events": [[
                "schemaVersion": 1,
                "eventId": eventID.uuidString,
                "capturedAt": capturedAt,
                "originalMessage": """
                [Web발신]
                MG+ 하나\(maskedIdentifier)승인 홍*동 \(amount)원 일시불 \(monthDay) \(time) \(merchant) 누적987,654원
                """
            ]]
        ]
        let captured = LockedIssue12AggregationValue<String?>(nil)
        try await client.execute(
            uri: "/api/v1/events/batch",
            method: .post,
            headers: headers(json: true),
            body: byteBuffer(try jsonData(request))
        ) { response in
            try requireStatus(response, .ok)
            let results = try requiredObjects(jsonObject(response.body), key: "results")
            captured.set(try requiredString(try XCTUnwrap(results.first), key: "transactionId"))
        }
        return try XCTUnwrap(captured.get())
    }

    private func review<Client>(
        transactionID: String,
        performance: String,
        benefitIDs: [String],
        using client: Client
    ) async throws where Client: TestClientProtocol {
        let payload: [String: Any] = [
            "review": [
                "performance": performance,
                "benefitIds": benefitIDs,
                "memo": ""
            ],
            "aggregationExcluded": false
        ]
        try await client.execute(
            uri: "/api/v1/transactions/\(transactionID)",
            method: .patch,
            headers: headers(mutation: true),
            body: byteBuffer(try jsonData(payload))
        ) { response in
            try requireStatus(response, .ok)
        }
    }

    private func benefitID(label: String, in benefits: [[String: Any]]) throws -> String {
        let benefit = try XCTUnwrap(benefits.first { $0["label"] as? String == label })
        return try requiredString(benefit, key: "id")
    }

    private func headers(json: Bool = false, mutation: Bool = false) -> HTTPFields {
        var fields: HTTPFields = [
            .init("Tailscale-User-Login")!: allowedLogin
        ]
        if json || mutation { fields[.contentType] = "application/json" }
        if mutation { fields[.init("X-CherryPicker-CSRF")!] = "same-origin" }
        return fields
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Issue12AggregationBlackBoxAcceptanceTests-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private func removeDatabaseFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}

private final class LockedIssue12AggregationValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ newValue: Value) { lock.withLock { value = newValue } }
}

private struct UnexpectedIssue12AggregationHTTPStatus: Error, CustomStringConvertible {
    let expected: HTTPResponse.Status
    let actual: HTTPResponse.Status

    var description: String {
        "Expected HTTP \(expected.code), received \(actual.code)."
    }
}

private func requireStatus(
    _ response: TestResponse,
    _ expected: HTTPResponse.Status
) throws {
    guard response.status == expected else {
        throw UnexpectedIssue12AggregationHTTPStatus(expected: expected, actual: response.status)
    }
}

private func jsonData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func jsonObject(_ body: ByteBuffer) throws -> [String: Any] {
    try XCTUnwrap(
        JSONSerialization.jsonObject(with: Data(body.readableBytesView)) as? [String: Any]
    )
}

private func contractObject(
    _ object: [String: Any],
    key: String,
    file: StaticString = #filePath,
    line: UInt = #line
) -> [String: Any]? {
    guard let value = object[key] as? [String: Any] else {
        XCTFail("Missing Issue #12 object field: \(key)", file: file, line: line)
        return nil
    }
    return value
}

private func contractObjects(
    _ object: [String: Any],
    key: String,
    file: StaticString = #filePath,
    line: UInt = #line
) -> [[String: Any]]? {
    guard let value = object[key] as? [[String: Any]] else {
        XCTFail("Missing Issue #12 object array: \(key)", file: file, line: line)
        return nil
    }
    return value
}

private func requiredObject(
    _ object: [String: Any],
    key: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> [String: Any] {
    try XCTUnwrap(object[key] as? [String: Any], "Missing object field: \(key)", file: file, line: line)
}

private func requiredObjects(
    _ object: [String: Any],
    key: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> [[String: Any]] {
    try XCTUnwrap(object[key] as? [[String: Any]], "Missing object array: \(key)", file: file, line: line)
}

private func requiredStrings(
    _ object: [String: Any],
    key: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> [String] {
    try XCTUnwrap(object[key] as? [String], "Missing string array: \(key)", file: file, line: line)
}

private func requiredString(
    _ object: [String: Any],
    key: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> String {
    try XCTUnwrap(object[key] as? String, "Missing string field: \(key)", file: file, line: line)
}

private func requiredInt(
    _ object: [String: Any],
    key: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> Int {
    try XCTUnwrap(object[key] as? Int, "Missing integer field: \(key)", file: file, line: line)
}

private func byteBuffer(_ data: Data) -> ByteBuffer {
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    buffer.writeBytes(data)
    return buffer
}
