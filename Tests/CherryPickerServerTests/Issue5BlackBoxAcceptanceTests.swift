import Foundation
import XCTest

import CherryPickerCore
import CherryPickerServer
import Hummingbird
import HummingbirdTesting

/// Proposed Issue #5 acceptance tests.
///
/// These tests intentionally use only public HTTP routes after constructing the
/// application. They do not inspect SQLite tables or call store query/update
/// methods, so an implementation may change its schema without changing this
/// suite as long as the approved product behavior remains the same.
///
/// The management routes exercised here do not exist yet. Until Issue #5 is
/// implemented, the suite is expected to compile and fail at the HTTP boundary.
@available(macOS 14.0, *)
final class Issue5BlackBoxAcceptanceTests: XCTestCase, @unchecked Sendable {
    private let allowedLogin = "fixture-device@example.test"
    private let codec = OutboxJSONCodec()

    // MARK: Card settings

    func testDefaultCardCanBeEditedAndSurvivesServerRestart() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let cardID = LockedValue<String?>(nil)

        do {
            let app = try makeApplication(databaseURL: databaseURL)
            try await app.test(.router) { client in
                try await client.execute(
                    uri: "/api/v1/card",
                    method: .get,
                    headers: managementHeaders(login: allowedLogin)
                ) { response in
                    try requireStatus(response, .ok)
                    let card = try cardObject(from: response.body)
                    XCTAssertEqual(card["displayName"] as? String, "MG 더나은 체크카드")
                    XCTAssertEqual(card["issuerCode"] as? String, "MG")
                    XCTAssertEqual(card["lastFour"] as? String, "4775")
                    XCTAssertEqual(card["performanceTargetAmount"] as? Int, 300_000)
                    XCTAssertEqual(card["periodRule"] as? String, "calendarMonth")
                    XCTAssertEqual(card["timeZoneIdentifier"] as? String, "Asia/Seoul")
                    cardID.set(card["id"] as? String)
                }

                let id = try XCTUnwrap(cardID.get())
                let update = try jsonData([
                    "displayName": "생활비 카드",
                    "issuerCode": "MG",
                    "lastFour": "4775",
                    "performanceTargetAmount": 350_000
                ])
                try await client.execute(
                    uri: "/api/v1/card/\(id)",
                    method: .put,
                    headers: managementHeaders(login: allowedLogin, mutation: true),
                    body: httpByteBuffer(update)
                ) { response in
                    try requireStatus(response, .ok)
                    let card = try cardObject(from: response.body)
                    XCTAssertEqual(card["id"] as? String, id)
                    XCTAssertEqual(card["displayName"] as? String, "생활비 카드")
                    XCTAssertEqual(card["performanceTargetAmount"] as? Int, 350_000)
                }
            }
        }

        // A second application over the same disk DB models a server restart.
        do {
            let reopenedApp = try makeApplication(databaseURL: databaseURL)
            try await reopenedApp.test(.router) { client in
                try await client.execute(
                    uri: "/api/v1/card",
                    method: .get,
                    headers: managementHeaders(login: allowedLogin)
                ) { response in
                    try requireStatus(response, .ok)
                    let card = try cardObject(from: response.body)
                    XCTAssertEqual(card["id"] as? String, try XCTUnwrap(cardID.get()))
                    XCTAssertEqual(card["displayName"] as? String, "생활비 카드")
                    XCTAssertEqual(card["performanceTargetAmount"] as? Int, 350_000)
                }
            }
        }
    }

    // MARK: Transaction list

    func testTransactionListIsNewestFirstAndSupportsApprovedFilters() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)
        let transactionIDs = LockedValue<[UUID: String]>([:])
        let events = [
            makeEvent(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                capturedAt: "2026-08-17T09:00:00+09:00",
                marker: "체크승인",
                amount: "1,000원",
                dateLine: "08/17 08:55",
                merchant: "Synthetic Oldest"
            ),
            makeEvent(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
                capturedAt: "2026-08-17T11:00:00+09:00",
                marker: "체크승인",
                amount: "2,000원",
                dateLine: "08/17 10:55",
                merchant: "Synthetic Newest"
            ),
            makeCancellationEvent(
                id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
                capturedAt: "2026-08-17T10:00:00+09:00"
            )
        ]

        try await app.test(.router) { client in
            for event in events {
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
                    let id = try XCTUnwrap(decoded.results.first?.transactionID?.uuidString)
                    transactionIDs.mutate { $0[event.eventId] = id }
                }
            }

            try await client.execute(
                uri: "/api/v1/transactions?filter=all",
                method: .get,
                headers: managementHeaders(login: allowedLogin)
            ) { response in
                try requireStatus(response, .ok)
                let rows = try transactionObjects(from: response.body)
                XCTAssertEqual(
                    rows.compactMap { $0["id"] as? String },
                    [events[1], events[2], events[0]].compactMap {
                        transactionIDs.get()[$0.eventId]
                    }
                )
                XCTAssertEqual(rows.filter { $0["reviewStatus"] as? String == "unreviewed" }.count, 3)
            }

            try await client.execute(
                uri: "/api/v1/transactions?filter=cancellation",
                method: .get,
                headers: managementHeaders(login: allowedLogin)
            ) { response in
                try requireStatus(response, .ok)
                let rows = try transactionObjects(from: response.body)
                XCTAssertEqual(rows.count, 1)
                XCTAssertEqual(rows.first?["kind"] as? String, "cancellation")
            }
        }
    }

    // MARK: Review, benefits, and cancellation

    func testReviewAcceptsMultipleBenefitsAndPersistsAcrossRestart() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let transactionID = LockedValue<String?>(nil)
        let selectedBenefitIDs = LockedValue<[String]>([])

        do {
            let app = try makeApplication(databaseURL: databaseURL)
            try await app.test(.router) { client in
                let card = try await fetchCard(using: client)
                let benefits = card["benefits"] as? [[String: Any]] ?? []
                XCTAssertGreaterThanOrEqual(
                    benefits.count,
                    2,
                    "Replace the synthetic minimum with approved MG benefit fixtures before implementation."
                )
                selectedBenefitIDs.set(Array(benefits.compactMap { $0["id"] as? String }.prefix(2)))

                let event = makeEvent(
                    id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
                    capturedAt: "2026-08-17T12:00:00+09:00",
                    marker: "체크승인",
                    amount: "2,500원",
                    dateLine: "08/17 11:55",
                    merchant: "Synthetic Parsed Merchant"
                )
                transactionID.set(try await ingest(event, using: client))

                let id = try XCTUnwrap(transactionID.get())
                let review = try jsonData([
                    "effectiveValues": [
                        "cardId": try XCTUnwrap(card["id"] as? String),
                        "kind": "approval",
                        "amount": 3_100,
                        "occurredAt": "2026-08-17T11:58:00+09:00",
                        "datePrecision": "minute",
                        "merchant": "Synthetic User Merchant"
                    ],
                    "review": [
                        "performance": "included",
                        "benefitIds": selectedBenefitIDs.get(),
                        "noApplicableBenefit": false,
                        "memo": "synthetic reviewed memo"
                    ],
                    "aggregationExcluded": false
                ])
                try await client.execute(
                    uri: "/api/v1/transactions/\(id)",
                    method: .patch,
                    headers: managementHeaders(login: allowedLogin, mutation: true),
                    body: httpByteBuffer(review)
                ) { response in
                    try requireStatus(response, .ok)
                    try self.assertReviewedTransaction(
                        response.body,
                        amount: 3_100,
                        merchant: "Synthetic User Merchant",
                        benefitIDs: selectedBenefitIDs.get()
                    )
                }
            }
        }

        do {
            let reopenedApp = try makeApplication(databaseURL: databaseURL)
            try await reopenedApp.test(.router) { client in
                let id = try XCTUnwrap(transactionID.get())
                try await client.execute(
                    uri: "/api/v1/transactions/\(id)",
                    method: .get,
                    headers: managementHeaders(login: allowedLogin)
                ) { response in
                    try requireStatus(response, .ok)
                    try self.assertReviewedTransaction(
                        response.body,
                        amount: 3_100,
                        merchant: "Synthetic User Merchant",
                        benefitIDs: selectedBenefitIDs.get()
                    )
                }
            }
        }
    }

    func testCancellationReviewRequiresNoApprovalMatch() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let card = try await fetchCard(using: client)
            let benefitID = try XCTUnwrap(
                (card["benefits"] as? [[String: Any]])?.first?["id"] as? String
            )
            let event = makeCancellationEvent(
                id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
                capturedAt: "2026-08-17T13:00:00+09:00"
            )
            let transactionID = try await ingest(event, using: client)
            let review = try jsonData([
                "review": [
                    "performance": "included",
                    "benefitIds": [benefitID],
                    "noApplicableBenefit": false,
                    "memo": "synthetic independent cancellation"
                ],
                "aggregationExcluded": false
            ])

            try await client.execute(
                uri: "/api/v1/transactions/\(transactionID)",
                method: .patch,
                headers: managementHeaders(login: allowedLogin, mutation: true),
                body: httpByteBuffer(review)
            ) { response in
                try requireStatus(response, .ok)
                let transaction = try transactionObject(from: response.body)
                XCTAssertEqual(transaction["kind"] as? String, "cancellation")
                XCTAssertEqual(transaction["reviewStatus"] as? String, "reviewed")
                XCTAssertEqual(Set(transaction["benefitIds"] as? [String] ?? []), [benefitID])
                XCTAssertNil(transaction["linkedApprovalId"])
            }
        }
    }

    // MARK: Exclusion, overrides, and reset

    func testAggregationExclusionIsVisibleReversibleAndNeverDeletesTheTransaction() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let event = makeEvent(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
                capturedAt: "2026-08-17T14:00:00+09:00",
                marker: "체크승인",
                amount: "4,000원",
                dateLine: "08/17 13:55",
                merchant: "Synthetic Excluded Merchant"
            )
            let id = try await ingest(event, using: client)

            try await patchTransaction(
                id: id,
                object: ["aggregationExcluded": true, "memo": "synthetic non-transaction"],
                using: client
            ) { transaction in
                XCTAssertEqual(transaction["aggregationExcluded"] as? Bool, true)
            }

            try await client.execute(
                uri: "/api/v1/transactions?filter=excluded",
                method: .get,
                headers: managementHeaders(login: allowedLogin)
            ) { response in
                try requireStatus(response, .ok)
                let rows = try transactionObjects(from: response.body)
                XCTAssertEqual(rows.compactMap { $0["id"] as? String }, [id])
            }

            try await patchTransaction(
                id: id,
                object: ["aggregationExcluded": false],
                using: client
            ) { transaction in
                XCTAssertEqual(transaction["aggregationExcluded"] as? Bool, false)
            }

            try await client.execute(
                uri: "/api/v1/transactions/\(id)",
                method: .get,
                headers: managementHeaders(login: allowedLogin)
            ) { response in
                try requireStatus(response, .ok)
                XCTAssertEqual(try transactionObject(from: response.body)["id"] as? String, id)
            }
        }
    }

    func testReparseProtectsOverridesAndResetRestoresParserValuesWithoutClearingReview() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let event = makeEvent(
                id: UUID(uuidString: "30000000-0000-0000-0000-000000000002")!,
                capturedAt: "2026-08-17T15:00:00+09:00",
                marker: "체크승인",
                amount: "5,000원",
                dateLine: "08/17 14:55",
                merchant: "Synthetic Parser Merchant"
            )
            let id = try await ingest(event, using: client)
            let patch = try jsonData([
                "effectiveValues": ["amount": 5_500, "merchant": "Synthetic Override Merchant"],
                "review": [
                    "performance": "included",
                    "benefitIds": [],
                    "noApplicableBenefit": true,
                    "memo": "synthetic memo must survive reset"
                ],
                "aggregationExcluded": false
            ])
            try await client.execute(
                uri: "/api/v1/transactions/\(id)",
                method: .patch,
                headers: managementHeaders(login: allowedLogin, mutation: true),
                body: httpByteBuffer(patch)
            ) { response in
                try requireStatus(response, .ok)
            }

            try await client.execute(
                uri: "/api/v1/transactions/\(id)/reparse",
                method: .post,
                headers: managementHeaders(login: allowedLogin, mutation: true),
                body: httpByteBuffer(try jsonData([:]))
            ) { response in
                try requireStatus(response, .ok)
                let transaction = try transactionObject(from: response.body)
                XCTAssertEqual(transaction["amount"] as? Int, 5_500)
                XCTAssertEqual(transaction["merchant"] as? String, "Synthetic Override Merchant")
                XCTAssertEqual(transaction["reviewStatus"] as? String, "reviewed")
                XCTAssertEqual(transaction["memo"] as? String, "synthetic memo must survive reset")
            }

            let reset = try jsonData([
                "fields": ["card", "kind", "amount", "occurredAt", "merchant"]
            ])
            try await client.execute(
                uri: "/api/v1/transactions/\(id)/reset",
                method: .post,
                headers: managementHeaders(login: allowedLogin, mutation: true),
                body: httpByteBuffer(reset)
            ) { response in
                try requireStatus(response, .ok)
                let transaction = try transactionObject(from: response.body)
                XCTAssertEqual(transaction["amount"] as? Int, 5_000)
                XCTAssertEqual(transaction["merchant"] as? String, "Synthetic Parser Merchant")
                XCTAssertEqual(transaction["reviewStatus"] as? String, "reviewed")
                XCTAssertEqual(transaction["performance"] as? String, "included")
                XCTAssertEqual(transaction["noApplicableBenefit"] as? Bool, true)
                XCTAssertEqual(transaction["memo"] as? String, "synthetic memo must survive reset")
            }
        }
    }

    // MARK: Security and rendering

    func testManagementReadsRequireExactLoginAndMutationsRequireCSRFHeader() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/v1/card", method: .get) { response in
                try requireStatus(response, .unauthorized)
            }

            let card = try await fetchCard(using: client)
            let cardID = try XCTUnwrap(card["id"] as? String)
            let update = try jsonData([
                "displayName": "Must Not Save",
                "issuerCode": "MG",
                "lastFour": "4775",
                "performanceTargetAmount": 300_000
            ])
            try await client.execute(
                uri: "/api/v1/card/\(cardID)",
                method: .put,
                headers: managementHeaders(login: allowedLogin, json: true),
                body: httpByteBuffer(update)
            ) { response in
                try requireStatus(response, .forbidden)
            }

            try await client.execute(
                uri: "/api/v1/card",
                method: .get,
                headers: managementHeaders(login: allowedLogin)
            ) { response in
                try requireStatus(response, .ok)
                XCTAssertEqual(
                    try cardObject(from: response.body)["displayName"] as? String,
                    "MG 더나은 체크카드"
                )
            }
        }
    }

    func testDetailEscapesOriginalAndUserControlledValues() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let sentinel = "<img src=x onerror=alert('synthetic-xss')>"
            let event = makeEvent(
                id: UUID(uuidString: "40000000-0000-0000-0000-000000000001")!,
                capturedAt: "2026-08-17T16:00:00+09:00",
                marker: "체크승인",
                amount: "6,000원",
                dateLine: "08/17 15:55",
                merchant: sentinel
            )
            let id = try await ingest(event, using: client)

            try await client.execute(
                uri: "/transactions/\(id)",
                method: .get,
                headers: managementHeaders(login: allowedLogin)
            ) { response in
                try requireStatus(response, .ok)
                let html = httpBodyString(response.body)
                XCTAssertTrue(html.contains("<details"))
                XCTAssertTrue(html.contains("&lt;img src=x onerror=alert"))
                XCTAssertFalse(html.contains(sentinel))
                XCTAssertFalse(html.contains("<img src=x"))
            }
        }
    }

    // MARK: HTTP-only fixture helpers

    private func makeApplication(databaseURL: URL) throws -> some ApplicationProtocol {
        let store = try SQLiteEventStore(databaseURL: databaseURL)
        return try CherryPickerHTTPApplication(
            store: store,
            authorizer: TailscaleIdentityAuthorizer(allowedLogin: allowedLogin),
            codec: codec
        ).application
    }

    private func fetchCard<Client>(using client: Client) async throws -> [String: Any]
    where Client: TestClientProtocol {
        let captured = LockedValue<[String: Any]?>(nil)
        try await client.execute(
            uri: "/api/v1/card",
            method: .get,
            headers: managementHeaders(login: allowedLogin)
        ) { response in
            try requireStatus(response, .ok)
            captured.set(try cardObject(from: response.body))
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

    private func patchTransaction<Client>(
        id: String,
        object: [String: Any],
        using client: Client,
        assertions: @escaping @Sendable ([String: Any]) throws -> Void
    ) async throws where Client: TestClientProtocol {
        try await client.execute(
            uri: "/api/v1/transactions/\(id)",
            method: .patch,
            headers: managementHeaders(login: allowedLogin, mutation: true),
            body: httpByteBuffer(try jsonData(object))
        ) { response in
            try requireStatus(response, .ok)
            try assertions(transactionObject(from: response.body))
        }
    }

    private func assertReviewedTransaction(
        _ body: ByteBuffer,
        amount: Int,
        merchant: String,
        benefitIDs: [String]
    ) throws {
        let transaction = try transactionObject(from: body)
        XCTAssertEqual(transaction["reviewStatus"] as? String, "reviewed")
        XCTAssertEqual(transaction["performance"] as? String, "included")
        XCTAssertEqual(transaction["amount"] as? Int, amount)
        XCTAssertEqual(transaction["merchant"] as? String, merchant)
        XCTAssertEqual(Set(transaction["benefitIds"] as? [String] ?? []), Set(benefitIDs))
        XCTAssertEqual(transaction["aggregationExcluded"] as? Bool, false)
    }

    private func makeEvent(
        id: UUID,
        capturedAt: String,
        marker: String,
        amount: String,
        dateLine: String,
        merchant: String
    ) -> OutboxEvent {
        OutboxEvent(
            eventId: id,
            capturedAt: ISO8601DateFormatter().date(from: capturedAt)!,
            originalMessage: """
            [Synthetic Fixture]
            MG카드(4775)\(marker)
            \(amount)
            \(dateLine)
            \(merchant)
            """
        )
    }

    private func makeCancellationEvent(id: UUID, capturedAt: String) -> OutboxEvent {
        OutboxEvent(
            eventId: id,
            capturedAt: ISO8601DateFormatter().date(from: capturedAt)!,
            originalMessage: """
            [Synthetic Fixture]
            [승인취소]
            MG체크카드(4775)
            3,800원
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

    func mutate(_ body: (inout Value) -> Void) {
        lock.withLock { body(&value) }
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
        // A required non-simple header is the proposed CSRF boundary. A
        // cross-origin HTML form cannot add it, and the server must not enable
        // cross-origin CORS for management endpoints.
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

private func httpBodyString(_ body: ByteBuffer) -> String {
    String(decoding: body.readableBytesView, as: UTF8.self)
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
