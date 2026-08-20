import Foundation
import XCTest

import CherryPickerCore
import CherryPickerServer
import Hummingbird
import HummingbirdTesting

@available(macOS 14.0, *)
final class Issue13CandidateSimulationBlackBoxAcceptanceTests: XCTestCase,
    @unchecked Sendable
{
    private let codec = OutboxJSONCodec()
    private let allowedLogin = "fixture-device@example.test"

    func testTemplateUsesStrictMonthAndExactIdentityWithoutExposingOriginalMessage()
        async throws
    {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let store = try SQLiteEventStore(databaseURL: databaseURL)
        let rawSentinel = "synthetic-original-only-account-balance"
        _ = try await store.ingest(OutboxEvent(
            eventId: UUID(uuidString: "00000000-0000-0000-0000-000000001330")!,
            capturedAt: try date("2026-08-03T18:01:00+09:00"),
            originalMessage: """
                [Web발신]
                MG카드(4775)체크승인
                10,000원
                08/03 18:00
                Synthetic Fixed
                통장잔액 99,999원 \(rawSentinel)
                """
        ))
        let app = try makeApplication(store: store)

        try await app.test(.router) { client in
            for uri in [
                "/api/v1/candidate-simulations/template",
                "/api/v1/candidate-simulations/template?month=2026-8",
                "/api/v1/candidate-simulations/template?month=2026-13",
                "/api/v1/candidate-simulations/template?month=2026-08-01"
            ] {
                _ = try await responseData(
                    uri: uri,
                    status: .badRequest,
                    headers: headers(login: allowedLogin),
                    using: client
                )
            }

            for login in [nil, "Fixture-device@example.test", "other-device@example.test"] {
                _ = try await responseData(
                    uri: "/api/v1/candidate-simulations/template?month=2026-08",
                    status: .unauthorized,
                    headers: headers(login: login),
                    using: client
                )
            }

            let data = try await responseData(
                uri: "/api/v1/candidate-simulations/template?month=2026-08",
                status: .ok,
                headers: headers(login: allowedLogin),
                using: client
            )
            let template = try codec.decode(
                CandidateSimulationTemplateResponse.self,
                from: data
            )
            XCTAssertEqual(template.analysisMonth, "2026-08")
            XCTAssertEqual(template.transactions.count, 1)
            XCTAssertEqual(template.transactions.first?.amount, 10_000)
            XCTAssertEqual(template.transactions.first?.merchant, "Synthetic Fixed")
            let body = String(decoding: data, as: UTF8.self)
            XCTAssertFalse(body.contains("originalMessage"))
            XCTAssertFalse(body.contains(rawSentinel))
            XCTAssertFalse(body.contains("통장잔액"))

            _ = try await responseData(
                uri: "/api/v1/candidate-simulations/current",
                status: .notFound,
                headers: headers(login: allowedLogin),
                using: client
            )
        }
    }

    func testPutGetPatchRecalculatesRangesAndRejectsInvalidDeltaAtomically()
        async throws
    {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let store = try SQLiteEventStore(databaseURL: databaseURL)
        let fixedIngestion = try await store.ingest(event(
            id: "00000000-0000-0000-0000-000000001340",
            capturedAt: "2026-08-03T18:01:00+09:00",
            amount: 10_000,
            occurredAt: "08/03 18:00",
            merchant: "Synthetic Fixed"
        ))
        let fixedID = try XCTUnwrap(fixedIngestion.transactionID)
        let ambiguousIngestion = try await store.ingest(event(
            id: "00000000-0000-0000-0000-000000001341",
            capturedAt: "2026-08-07T09:01:00+09:00",
            amount: 20_000,
            occurredAt: "08/07 09:00",
            merchant: "Synthetic Ambiguous"
        ))
        let ambiguousID = try XCTUnwrap(ambiguousIngestion.transactionID)
        let classifications = syntheticClassifications(
            fixedID: fixedID,
            ambiguousID: ambiguousID
        )
        let put = CandidateSimulationPutRequest(
            policy: try syntheticPolicy(),
            analysisMonth: "2026-08",
            defaultPerformanceAssumptionId: "standard",
            classifications: classifications
        )
        let putData = try codec.encode(put)
        let app = try makeApplication(store: store)

        try await app.test(.router) { client in
            _ = try await responseData(
                uri: "/api/v1/candidate-simulations/current",
                method: .put,
                status: .unauthorized,
                headers: headers(login: "other@example.test", json: true, csrf: true),
                body: putData,
                using: client
            )
            _ = try await responseData(
                uri: "/api/v1/candidate-simulations/current",
                method: .put,
                status: .forbidden,
                headers: headers(login: allowedLogin, json: true),
                body: putData,
                using: client
            )

            let transactionsBefore = try await responseData(
                uri: "/api/v1/transactions",
                status: .ok,
                headers: headers(login: allowedLogin),
                using: client
            )
            let dashboardBefore = try await responseData(
                uri: "/api/v1/cards/00000000-0000-0000-0000-000000004775/dashboard?month=2026-08",
                status: .ok,
                headers: headers(login: allowedLogin),
                using: client
            )

            let createdData = try await responseData(
                uri: "/api/v1/candidate-simulations/current",
                method: .put,
                status: .ok,
                headers: headers(login: allowedLogin, json: true, csrf: true),
                body: putData,
                using: client
            )
            let created = try codec.decode(CandidateSimulationResponse.self, from: createdData)
            XCTAssertFalse(created.simulation.state.policyConfirmed)
            XCTAssertFalse(created.simulation.state.questionsReviewed)
            XCTAssertEqual(created.simulation.state.selectedTransactionIds, [])
            XCTAssertEqual(created.simulation.state.answers, [])
            XCTAssertEqual(created.calculation.selectedTransactionAmount, 0)
            XCTAssertNil(created.calculation.pickingRatePercentage)
            XCTAssertEqual(Set(created.simulation.facts.map(\.id)), [fixedID, ambiguousID])
            XCTAssertEqual(created.simulation.calculatorVersion, "candidate-card-v1")

            let loadedData = try await responseData(
                uri: "/api/v1/candidate-simulations/current",
                status: .ok,
                headers: headers(login: allowedLogin),
                using: client
            )
            let loaded = try codec.decode(CandidateSimulationResponse.self, from: loadedData)
            XCTAssertEqual(loaded, created)

            let authorizedOnlyPatch = CandidateSimulationPatchRequest(
                draftId: created.simulation.id,
                expectedState: created.simulation.state,
                policyConfirmed: true
            )
            let authorizedOnlyPatchData = try codec.encode(authorizedOnlyPatch)
            _ = try await responseData(
                uri: "/api/v1/candidate-simulations/current",
                method: .patch,
                status: .unauthorized,
                headers: headers(login: "other@example.test", json: true, csrf: true),
                body: authorizedOnlyPatchData,
                using: client
            )
            _ = try await responseData(
                uri: "/api/v1/candidate-simulations/current",
                method: .patch,
                status: .forbidden,
                headers: headers(login: allowedLogin, json: true),
                body: authorizedOnlyPatchData,
                using: client
            )
            let afterRejectedPatchData = try await responseData(
                uri: "/api/v1/candidate-simulations/current",
                status: .ok,
                headers: headers(login: allowedLogin),
                using: client
            )
            XCTAssertEqual(
                try codec.decode(
                    CandidateSimulationResponse.self,
                    from: afterRejectedPatchData
                ),
                created
            )

            let impossibleStates = [
                CandidateSimulationPatchRequest(
                    draftId: created.simulation.id,
                    expectedState: created.simulation.state,
                    questionsReviewed: true
                ),
                CandidateSimulationPatchRequest(
                    draftId: created.simulation.id,
                    expectedState: created.simulation.state,
                    answers: [
                        CandidateSimulationAnswer(
                            transactionId: ambiguousID,
                            alternativeId: "eligible"
                        )
                    ]
                ),
                CandidateSimulationPatchRequest(
                    draftId: created.simulation.id,
                    expectedState: created.simulation.state,
                    selectedTransactionIds: [fixedID]
                )
            ]
            for impossible in impossibleStates {
                _ = try await responseData(
                    uri: "/api/v1/candidate-simulations/current",
                    method: .patch,
                    status: .badRequest,
                    headers: headers(login: allowedLogin, json: true, csrf: true),
                    body: try codec.encode(impossible),
                    using: client
                )
            }
            let afterImpossibleData = try await responseData(
                uri: "/api/v1/candidate-simulations/current",
                status: .ok,
                headers: headers(login: allowedLogin),
                using: client
            )
            XCTAssertEqual(
                try codec.decode(CandidateSimulationResponse.self, from: afterImpossibleData),
                created
            )

            let selectBoth = CandidateSimulationPatchRequest(
                draftId: created.simulation.id,
                expectedState: created.simulation.state,
                policyConfirmed: true,
                questionsReviewed: true,
                selectedTransactionIds: [ambiguousID, fixedID]
            )
            let rangedData = try await responseData(
                uri: "/api/v1/candidate-simulations/current",
                method: .patch,
                status: .ok,
                headers: headers(login: allowedLogin, json: true, csrf: true),
                body: try codec.encode(selectBoth),
                using: client
            )
            let ranged = try codec.decode(CandidateSimulationResponse.self, from: rangedData)
            XCTAssertEqual(ranged.calculation.selectedTransactionAmount, 30_000)
            XCTAssertEqual(ranged.calculation.benefitAmount, .init(minimum: 1_000, maximum: 3_000))
            XCTAssertEqual(
                ranged.calculation.pickingRatePercentage,
                .init(minimum: 100.0 / 30.0, maximum: 10.0)
            )

            let staleSameGeneration = CandidateSimulationPatchRequest(
                draftId: ranged.simulation.id,
                expectedState: created.simulation.state,
                answers: [
                    CandidateSimulationAnswer(
                        transactionId: ambiguousID,
                        alternativeId: "eligible"
                    )
                ]
            )
            _ = try await responseData(
                uri: "/api/v1/candidate-simulations/current",
                method: .patch,
                status: .badRequest,
                headers: headers(login: allowedLogin, json: true, csrf: true),
                body: try codec.encode(staleSameGeneration),
                using: client
            )
            let afterStaleData = try await responseData(
                uri: "/api/v1/candidate-simulations/current",
                status: .ok,
                headers: headers(login: allowedLogin),
                using: client
            )
            XCTAssertEqual(
                try codec.decode(CandidateSimulationResponse.self, from: afterStaleData),
                ranged
            )

            let invalid = CandidateSimulationPatchRequest(
                draftId: ranged.simulation.id,
                expectedState: ranged.simulation.state,
                selectedTransactionIds: [UUID()]
            )
            _ = try await responseData(
                uri: "/api/v1/candidate-simulations/current",
                method: .patch,
                status: .badRequest,
                headers: headers(login: allowedLogin, json: true, csrf: true),
                body: try codec.encode(invalid),
                using: client
            )
            let afterInvalidData = try await responseData(
                uri: "/api/v1/candidate-simulations/current",
                status: .ok,
                headers: headers(login: allowedLogin),
                using: client
            )
            XCTAssertEqual(
                try codec.decode(CandidateSimulationResponse.self, from: afterInvalidData),
                ranged
            )

            let answer = CandidateSimulationPatchRequest(
                draftId: ranged.simulation.id,
                expectedState: ranged.simulation.state,
                answers: [
                    CandidateSimulationAnswer(
                        transactionId: ambiguousID,
                        alternativeId: "eligible"
                    )
                ]
            )
            let answeredData = try await responseData(
                uri: "/api/v1/candidate-simulations/current",
                method: .patch,
                status: .ok,
                headers: headers(login: allowedLogin, json: true, csrf: true),
                body: try codec.encode(answer),
                using: client
            )
            let answered = try codec.decode(CandidateSimulationResponse.self, from: answeredData)
            XCTAssertEqual(answered.calculation.benefitAmount, .init(minimum: 3_000, maximum: 3_000))
            XCTAssertEqual(
                answered.calculation.pickingRatePercentage,
                .init(minimum: 10.0, maximum: 10.0)
            )

            let transactionsAfter = try await responseData(
                uri: "/api/v1/transactions",
                status: .ok,
                headers: headers(login: allowedLogin),
                using: client
            )
            let dashboardAfter = try await responseData(
                uri: "/api/v1/cards/00000000-0000-0000-0000-000000004775/dashboard?month=2026-08",
                status: .ok,
                headers: headers(login: allowedLogin),
                using: client
            )
            XCTAssertEqual(transactionsAfter, transactionsBefore)
            XCTAssertEqual(dashboardAfter, dashboardBefore)
        }
    }

    func testPutRequiresEverySourceApprovalExactlyOnceAndCurrentSurvivesRestart()
        async throws
    {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let fixedID: UUID
        let ambiguousID: UUID
        let replacementID = LockedCandidateSimulationValue<UUID?>(nil)
        let expectedAfterRestart = LockedCandidateSimulationValue<CandidateSimulationResponse?>(nil)
        do {
            let store = try SQLiteEventStore(databaseURL: databaseURL)
            let fixedIngestion = try await store.ingest(event(
                id: "00000000-0000-0000-0000-000000001350",
                capturedAt: "2026-08-03T18:01:00+09:00",
                amount: 10_000,
                occurredAt: "08/03 18:00",
                merchant: "Synthetic Fixed"
            ))
            fixedID = try XCTUnwrap(fixedIngestion.transactionID)
            let ambiguousIngestion = try await store.ingest(event(
                id: "00000000-0000-0000-0000-000000001351",
                capturedAt: "2026-08-07T09:01:00+09:00",
                amount: 20_000,
                occurredAt: "08/07 09:00",
                merchant: "Synthetic Ambiguous"
            ))
            ambiguousID = try XCTUnwrap(ambiguousIngestion.transactionID)
            let all = syntheticClassifications(fixedID: fixedID, ambiguousID: ambiguousID)
            let incomplete = CandidateSimulationPutRequest(
                policy: try syntheticPolicy(),
                analysisMonth: "2026-08",
                defaultPerformanceAssumptionId: "standard",
                classifications: [all[0]]
            )
            let complete = CandidateSimulationPutRequest(
                policy: try syntheticPolicy(),
                analysisMonth: "2026-08",
                defaultPerformanceAssumptionId: "standard",
                classifications: all
            )
            let app = try makeApplication(store: store)
            try await app.test(.router) { client in
                _ = try await responseData(
                    uri: "/api/v1/candidate-simulations/current",
                    method: .put,
                    status: .badRequest,
                    headers: headers(login: allowedLogin, json: true, csrf: true),
                    body: try codec.encode(incomplete),
                    using: client
                )
                _ = try await responseData(
                    uri: "/api/v1/candidate-simulations/current",
                    status: .notFound,
                    headers: headers(login: allowedLogin),
                    using: client
                )
                let firstData = try await responseData(
                    uri: "/api/v1/candidate-simulations/current",
                    method: .put,
                    status: .ok,
                    headers: headers(login: allowedLogin, json: true, csrf: true),
                    body: try codec.encode(complete),
                    using: client
                )
                let first = try codec.decode(
                    CandidateSimulationResponse.self,
                    from: firstData
                )
                _ = try await responseData(
                    uri: "/api/v1/candidate-simulations/current",
                    method: .patch,
                    status: .ok,
                    headers: headers(login: allowedLogin, json: true, csrf: true),
                    body: try codec.encode(
                        CandidateSimulationPatchRequest(
                            draftId: first.simulation.id,
                            expectedState: first.simulation.state,
                            policyConfirmed: true
                        )
                    ),
                    using: client
                )

                let replacementData = try await responseData(
                    uri: "/api/v1/candidate-simulations/current",
                    method: .put,
                    status: .ok,
                    headers: headers(login: allowedLogin, json: true, csrf: true),
                    body: try codec.encode(complete),
                    using: client
                )
                let replacement = try codec.decode(
                    CandidateSimulationResponse.self,
                    from: replacementData
                )
                XCTAssertNotEqual(replacement.simulation.id, first.simulation.id)
                XCTAssertEqual(
                    replacement.simulation.createdAt,
                    replacement.simulation.updatedAt
                )
                XCTAssertFalse(replacement.simulation.state.policyConfirmed)
                XCTAssertFalse(replacement.simulation.state.questionsReviewed)
                XCTAssertEqual(replacement.simulation.state.selectedTransactionIds, [])
                XCTAssertEqual(replacement.simulation.state.answers, [])

                _ = try await responseData(
                    uri: "/api/v1/candidate-simulations/current",
                    method: .patch,
                    status: .badRequest,
                    headers: headers(login: allowedLogin, json: true, csrf: true),
                    body: try codec.encode(
                        CandidateSimulationPatchRequest(
                            draftId: first.simulation.id,
                            expectedState: first.simulation.state,
                            policyConfirmed: true
                        )
                    ),
                    using: client
                )
                let afterStalePageData = try await responseData(
                    uri: "/api/v1/candidate-simulations/current",
                    status: .ok,
                    headers: headers(login: allowedLogin),
                    using: client
                )
                XCTAssertEqual(
                    try codec.decode(
                        CandidateSimulationResponse.self,
                        from: afterStalePageData
                    ),
                    replacement
                )
                replacementID.set(replacement.simulation.id)

                let savedData = try await responseData(
                    uri: "/api/v1/candidate-simulations/current",
                    method: .patch,
                    status: .ok,
                    headers: headers(login: allowedLogin, json: true, csrf: true),
                    body: try codec.encode(
                        CandidateSimulationPatchRequest(
                            draftId: replacement.simulation.id,
                            expectedState: replacement.simulation.state,
                            policyConfirmed: true,
                            questionsReviewed: true,
                            selectedTransactionIds: [fixedID, ambiguousID],
                            answers: [
                                CandidateSimulationAnswer(
                                    transactionId: ambiguousID,
                                    alternativeId: "eligible"
                                )
                            ]
                        )
                    ),
                    using: client
                )
                let saved = try codec.decode(
                    CandidateSimulationResponse.self,
                    from: savedData
                )
                XCTAssertEqual(saved.calculation.selectedTransactionAmount, 30_000)
                XCTAssertEqual(saved.calculation.benefitAmount, .init(minimum: 3_000, maximum: 3_000))
                expectedAfterRestart.set(saved)
            }
        }

        let reopened = try SQLiteEventStore(databaseURL: databaseURL)
        let reopenedApp = try makeApplication(store: reopened)
        try await reopenedApp.test(.router) { client in
            let data = try await responseData(
                uri: "/api/v1/candidate-simulations/current",
                status: .ok,
                headers: headers(login: allowedLogin),
                using: client
            )
            let response = try codec.decode(CandidateSimulationResponse.self, from: data)
            XCTAssertEqual(response.simulation.id, try XCTUnwrap(replacementID.get()))
            XCTAssertEqual(Set(response.simulation.facts.map(\.id)), [fixedID, ambiguousID])
            XCTAssertEqual(response.calculation.calculatorVersion, "candidate-card-v1")
            XCTAssertEqual(response, try XCTUnwrap(expectedAfterRestart.get()))
        }
    }

    private func syntheticPolicy() throws -> CandidateCardPolicyTemplate {
        CandidateCardPolicyTemplate(
            snapshotID: UUID(uuidString: "00000000-0000-0000-0000-000000001399")!,
            cardName: "Synthetic Candidate",
            issuerName: "Synthetic Issuer",
            productIdentifier: "synthetic-candidate-v1",
            source: CandidateCardPolicySource(
                name: "Synthetic policy fixture",
                reference: "fixture://candidate-card",
                effectiveDate: try date("2026-07-01T00:00:00+09:00"),
                structuredAt: try date("2026-08-20T12:00:00+09:00")
            ),
            annualFeeAmount: 0,
            performanceThresholdAmounts: [300_000],
            limitGroups: [CandidateCardLimitGroup(id: "shared", label: "통합 한도")],
            performanceAssumptions: [
                CandidateCardPerformanceAssumption(
                    id: "standard",
                    label: "30만원 달성",
                    previousMonthAmount: 300_000,
                    isGrace: false,
                    limitGroupMaximumAmounts: ["shared": 5_000]
                )
            ],
            benefits: [
                CandidateCardBenefitDefinition(
                    id: "ten-percent",
                    label: "합성 10% 할인",
                    conditionSummary: "분류된 합성 거래 승인액의 10%",
                    exclusionNotes: ["테스트에서 별도 제외 없음"],
                    rateBasisPoints: 1_000,
                    limitGroupIDs: ["shared"],
                    priority: 0,
                    rounding: CandidateCardRoundingRule(unit: 1, direction: .floor)
                )
            ],
            stacking: .highestPriorityOnly,
            performanceExclusions: [],
            benefitExclusions: [],
            unsupportedPolicyConditions: []
        )
    }

    private func syntheticClassifications(
        fixedID: UUID,
        ambiguousID: UUID
    ) -> [CandidateCardTransactionClassification] {
        [
            CandidateCardTransactionClassification(
                transactionID: fixedID,
                alternatives: [
                    CandidateCardClassificationAlternative(
                        id: "fixed",
                        performance: .included,
                        performanceReason: "합성 거래는 실적에 포함",
                        benefitIDs: ["ten-percent"],
                        benefitReason: "합성 10% 혜택 대상"
                    )
                ]
            ),
            CandidateCardTransactionClassification(
                transactionID: ambiguousID,
                question: "혜택 경로로 결제했나요?",
                alternatives: [
                    CandidateCardClassificationAlternative(
                        id: "eligible",
                        answerLabel: "예",
                        performance: .included,
                        performanceReason: "결제 경로와 무관하게 실적 포함",
                        benefitIDs: ["ten-percent"],
                        benefitReason: "혜택 경로이면 10% 대상"
                    ),
                    CandidateCardClassificationAlternative(
                        id: "ineligible",
                        answerLabel: "아니요",
                        performance: .included,
                        performanceReason: "결제 경로와 무관하게 실적 포함",
                        benefitIDs: [],
                        benefitReason: "혜택 경로가 아니면 혜택 제외"
                    )
                ]
            )
        ]
    }

    private func event(
        id: String,
        capturedAt: String,
        amount: Int,
        occurredAt: String,
        merchant: String
    ) throws -> OutboxEvent {
        OutboxEvent(
            eventId: UUID(uuidString: id)!,
            capturedAt: try date(capturedAt),
            originalMessage: """
                [Web발신]
                MG카드(4775)체크승인
                \(amount)원
                \(occurredAt)
                \(merchant)
                """
        )
    }

    private func makeApplication(
        store: SQLiteEventStore
    ) throws -> some ApplicationProtocol {
        try CherryPickerHTTPApplication(
            store: store,
            authorizer: TailscaleIdentityAuthorizer(allowedLogin: allowedLogin),
            codec: codec
        ).application
    }

    private func responseData<Client>(
        uri: String,
        method: HTTPRequest.Method = .get,
        status: HTTPResponse.Status,
        headers: HTTPFields,
        body: Data? = nil,
        using client: Client
    ) async throws -> Data where Client: TestClientProtocol {
        let captured = LockedCandidateSimulationValue<Data?>(nil)
        if let body {
            try await client.execute(
                uri: uri,
                method: method,
                headers: headers,
                body: byteBuffer(body)
            ) { response in
                try requireCandidateSimulationStatus(response, status)
                captured.set(Data(response.body.readableBytesView))
            }
        } else {
            try await client.execute(
                uri: uri,
                method: method,
                headers: headers
            ) { response in
                try requireCandidateSimulationStatus(response, status)
                captured.set(Data(response.body.readableBytesView))
            }
        }
        return try XCTUnwrap(captured.get())
    }

    private func headers(
        login: String? = nil,
        json: Bool = false,
        csrf: Bool = false
    ) -> HTTPFields {
        var fields: HTTPFields = [:]
        if let login { fields[.init("Tailscale-User-Login")!] = login }
        if json { fields[.contentType] = "application/json" }
        if csrf { fields[.init("X-CherryPicker-CSRF")!] = "same-origin" }
        return fields
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "Issue13CandidateSimulationBlackBoxAcceptanceTests-\(UUID().uuidString)"
            )
            .appendingPathExtension("sqlite")
    }

    private func removeDatabaseFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}

private final class LockedCandidateSimulationValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ newValue: Value) { lock.withLock { value = newValue } }
}

private struct UnexpectedCandidateSimulationHTTPStatus: Error, CustomStringConvertible {
    let expected: HTTPResponse.Status
    let actual: HTTPResponse.Status

    var description: String {
        "Expected HTTP \(expected.code), received \(actual.code)."
    }
}

private func requireCandidateSimulationStatus(
    _ response: TestResponse,
    _ expected: HTTPResponse.Status
) throws {
    guard response.status == expected else {
        throw UnexpectedCandidateSimulationHTTPStatus(
            expected: expected,
            actual: response.status
        )
    }
}

private func byteBuffer(_ data: Data) -> ByteBuffer {
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    buffer.writeBytes(data)
    return buffer
}
