import Foundation
import XCTest

import CherryPickerServer
import Hummingbird
import HummingbirdTesting

@available(macOS 14.0, *)
final class Issue10BlackBoxAcceptanceTests: XCTestCase, @unchecked Sendable {
    private let allowedLogin = "fixture-device@example.test"
    private let codec = OutboxJSONCodec()

    func testMonthlyOffsetsRequireIdentityAndCSRFAndRejectUnknownBenefits() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let card = try await firstCard(using: client)
            let cardID = try requiredString(card, key: "id")
            let benefitID = try requiredString(try firstBenefit(card), key: "id")
            let uri = "/api/v1/cards/\(cardID)/monthly-offsets?month=2026-08"
            let payload = try jsonData([
                "performanceOffsetAmount": -20_000,
                "benefitOffsets": [["benefitId": benefitID, "offsetAmount": -1_000]]
            ])

            try await client.execute(uri: uri, method: .get) { response in
                XCTAssertEqual(response.status, .unauthorized)
            }
            try await client.execute(
                uri: uri,
                method: .put,
                headers: headers(login: allowedLogin, json: true),
                body: byteBuffer(payload)
            ) { response in
                XCTAssertEqual(response.status, .forbidden)
            }
            try await client.execute(
                uri: uri,
                method: .put,
                headers: headers(login: allowedLogin, mutation: true),
                body: byteBuffer(payload)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let offsets = try monthlyOffsets(from: response.body)
                XCTAssertEqual(offsets["performanceOffsetAmount"] as? Int, -20_000)
            }
            try await client.execute(
                uri: uri,
                method: .get,
                headers: headers(login: allowedLogin)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let offsets = try monthlyOffsets(from: response.body)
                XCTAssertEqual(offsets["period"] as? String, "2026-08")
                XCTAssertEqual(
                    (offsets["benefitOffsets"] as? [[String: Any]])?.map {
                        $0["offsetAmount"] as? Int
                    },
                    [-1_000, 0, 0]
                )
            }

            let unknownPayload = try jsonData([
                "performanceOffsetAmount": 0,
                "benefitOffsets": [["benefitId": UUID().uuidString, "offsetAmount": 1]]
            ])
            try await client.execute(
                uri: uri,
                method: .put,
                headers: headers(login: allowedLogin, mutation: true),
                body: byteBuffer(unknownPayload)
            ) { response in
                XCTAssertEqual(response.status, .badRequest)
            }
        }
    }

    func testOffsetsRecalculateWithReviewsPersistAcrossRestartAndAppearInProductSettings() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let cardID = LockedIssue10Value<String?>(nil)
        let benefitID = LockedIssue10Value<String?>(nil)
        let transactionID = LockedIssue10Value<String?>(nil)

        do {
            let app = try makeApplication(databaseURL: databaseURL)
            try await app.test(.router) { client in
                let card = try await firstCard(using: client)
                let resolvedCardID = try requiredString(card, key: "id")
                let resolvedBenefitID = try requiredString(try firstBenefit(card), key: "id")
                cardID.set(resolvedCardID)
                benefitID.set(resolvedBenefitID)

                try await putOffsets(
                    cardID: resolvedCardID,
                    month: "2026-08",
                    performance: 50_000,
                    benefits: [["benefitId": resolvedBenefitID, "offsetAmount": 1_500]],
                    using: client
                )
                let beforeReview = try await dashboard(
                    cardID: resolvedCardID,
                    month: "2026-08",
                    using: client
                )
                XCTAssertEqual(performance(beforeReview)["currentAmount"] as? Int, 50_000)
                XCTAssertEqual(try receivedBenefit(resolvedBenefitID, in: beforeReview), 1_500)

                let resolvedTransactionID = try await ingestApproval(using: client)
                transactionID.set(resolvedTransactionID)
                try await review(
                    transactionID: resolvedTransactionID,
                    performance: "included",
                    benefitIDs: [resolvedBenefitID],
                    using: client
                )
                let afterReview = try await dashboard(
                    cardID: resolvedCardID,
                    month: "2026-08",
                    using: client
                )
                XCTAssertEqual(performance(afterReview)["currentAmount"] as? Int, 60_000)
                XCTAssertEqual(try receivedBenefit(resolvedBenefitID, in: afterReview), 3_500)

                try await client.execute(
                    uri: "/",
                    method: .get,
                    headers: headers(login: allowedLogin)
                ) { response in
                    XCTAssertEqual(response.status, .ok)
                    let html = String(decoding: response.body.readableBytesView, as: UTF8.self)
                    XCTAssertTrue(html.contains("이번 달 수동 조정"))
                    XCTAssertTrue(html.contains("setting-performance-offset"))
                    XCTAssertTrue(html.contains("settings-benefit-offsets"))
                    XCTAssertTrue(html.contains("/monthly-offsets?month=${currentMonth}"))
                    XCTAssertFalse(html.contains("originalMessage"))
                }
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
                XCTAssertEqual(performance(persisted)["currentAmount"] as? Int, 60_000)
                XCTAssertEqual(
                    try receivedBenefit(try XCTUnwrap(benefitID.get()), in: persisted),
                    3_500
                )

                try await review(
                    transactionID: try XCTUnwrap(transactionID.get()),
                    performance: "excluded",
                    benefitIDs: [],
                    using: client
                )
                let recalculated = try await dashboard(
                    cardID: try XCTUnwrap(cardID.get()),
                    month: "2026-08",
                    using: client
                )
                XCTAssertEqual(performance(recalculated)["currentAmount"] as? Int, 50_000)
                XCTAssertEqual(
                    try receivedBenefit(try XCTUnwrap(benefitID.get()), in: recalculated),
                    1_500
                )
            }
        }
    }

    private func makeApplication(databaseURL: URL) throws -> some ApplicationProtocol {
        try CherryPickerHTTPApplication(
            store: SQLiteEventStore(databaseURL: databaseURL),
            authorizer: TailscaleIdentityAuthorizer(allowedLogin: allowedLogin),
            codec: codec
        ).application
    }

    private func firstCard<Client>(using client: Client) async throws -> [String: Any]
    where Client: TestClientProtocol {
        let captured = LockedIssue10Value<[String: Any]?>(nil)
        try await client.execute(
            uri: "/api/v1/cards",
            method: .get,
            headers: headers(login: allowedLogin)
        ) { response in
            XCTAssertEqual(response.status, .ok)
            let cards = try XCTUnwrap(jsonObject(response.body)["cards"] as? [[String: Any]])
            captured.set(cards.first)
        }
        return try XCTUnwrap(captured.get())
    }

    private func firstBenefit(_ card: [String: Any]) throws -> [String: Any] {
        try XCTUnwrap((card["benefits"] as? [[String: Any]])?.first)
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
            headers: headers(login: allowedLogin, mutation: true),
            body: byteBuffer(payload)
        ) { response in
            XCTAssertEqual(response.status, .ok)
        }
    }

    private func dashboard<Client>(
        cardID: String,
        month: String,
        using client: Client
    ) async throws -> [String: Any] where Client: TestClientProtocol {
        let captured = LockedIssue10Value<[String: Any]?>(nil)
        try await client.execute(
            uri: "/api/v1/cards/\(cardID)/dashboard?month=\(month)",
            method: .get,
            headers: headers(login: allowedLogin)
        ) { response in
            XCTAssertEqual(response.status, .ok)
            captured.set(try jsonObject(response.body)["dashboard"] as? [String: Any])
        }
        return try XCTUnwrap(captured.get())
    }

    private func ingestApproval<Client>(using client: Client) async throws -> String
    where Client: TestClientProtocol {
        let event = OutboxEvent(
            eventId: UUID(uuidString: "10000000-0000-0000-0000-000000001010")!,
            capturedAt: ISO8601DateFormatter().date(from: "2026-08-17T09:00:00+09:00")!,
            originalMessage: """
            [Synthetic Fixture]
            MG카드(4775)체크승인
            10,000원
            08/17 08:55
            Synthetic Offset Recalculation
            """
        )
        let result = LockedIssue10Value<String?>(nil)
        try await client.execute(
            uri: "/api/v1/events/batch",
            method: .post,
            headers: headers(login: allowedLogin, json: true),
            body: byteBuffer(try codec.encode(BatchSyncRequest(events: [event])))
        ) { response in
            XCTAssertEqual(response.status, .ok)
            let decoded = try self.codec.decode(
                BatchSyncResponse.self,
                from: Data(response.body.readableBytesView)
            )
            result.set(decoded.results.first?.transactionID?.uuidString)
        }
        return try XCTUnwrap(result.get())
    }

    private func review<Client>(
        transactionID: String,
        performance: String,
        benefitIDs: [String],
        using client: Client
    ) async throws where Client: TestClientProtocol {
        let payload: [String: Any] = [
            "review": ["performance": performance, "benefitIds": benefitIDs, "memo": ""],
            "aggregationExcluded": false
        ]
        try await client.execute(
            uri: "/api/v1/transactions/\(transactionID)",
            method: .patch,
            headers: headers(login: allowedLogin, mutation: true),
            body: byteBuffer(try jsonData(payload))
        ) { response in
            XCTAssertEqual(response.status, .ok)
        }
    }

    private func performance(_ dashboard: [String: Any]) -> [String: Any] {
        dashboard["performance"] as? [String: Any] ?? [:]
    }

    private func receivedBenefit(_ id: String, in dashboard: [String: Any]) throws -> Int {
        let benefit = try XCTUnwrap(
            (dashboard["benefits"] as? [[String: Any]])?.first { $0["id"] as? String == id }
        )
        return try XCTUnwrap(benefit["receivedAmount"] as? Int)
    }

    private func requiredString(_ object: [String: Any], key: String) throws -> String {
        try XCTUnwrap(object[key] as? String)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Issue10BlackBoxAcceptanceTests-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private func removeDatabaseFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}

private final class LockedIssue10Value<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }
    func get() -> Value { lock.withLock { value } }
    func set(_ newValue: Value) { lock.withLock { value = newValue } }
}

private func headers(
    login: String? = nil,
    json: Bool = false,
    mutation: Bool = false
) -> HTTPFields {
    var fields: HTTPFields = [:]
    if let login { fields[.init("Tailscale-User-Login")!] = login }
    if json || mutation { fields[.contentType] = "application/json" }
    if mutation { fields[.init("X-CherryPicker-CSRF")!] = "same-origin" }
    return fields
}

private func jsonData(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func jsonObject(_ body: ByteBuffer) throws -> [String: Any] {
    try XCTUnwrap(
        JSONSerialization.jsonObject(with: Data(body.readableBytesView)) as? [String: Any]
    )
}

private func monthlyOffsets(from body: ByteBuffer) throws -> [String: Any] {
    try XCTUnwrap(jsonObject(body)["monthlyOffsets"] as? [String: Any])
}

private func byteBuffer(_ data: Data) -> ByteBuffer {
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    buffer.writeBytes(data)
    return buffer
}
