import Foundation
import XCTest

import CherryPickerCore
import CherryPickerServer
import Hummingbird
import HummingbirdTesting

/// Black-box acceptance tests for reviewing several unconfirmed transactions
/// at once from the inbox. Observes only HTTP requests and responses.
@available(macOS 14.0, *)
final class BulkTransactionReviewBlackBoxAcceptanceTests: XCTestCase, @unchecked Sendable {
    private let allowedLogin = "fixture-device@example.test"
    private let codec = OutboxJSONCodec()

    func testBulkReviewSetsPerformanceAndBenefitsForEverySelectedTransaction() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let card = try await fetchFirstCard(using: client)
            let benefitIDs = (card["benefits"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            let firstBenefit = try XCTUnwrap(benefitIDs.first)

            let firstID = try await ingest(
                makeApprovalEvent(
                    id: UUID(uuidString: "B1000000-0000-0000-0000-000000000001")!,
                    capturedAt: "2026-08-17T10:00:00+09:00",
                    amount: "11,000원",
                    merchant: "Synthetic Bulk First"
                ),
                using: client
            )
            let secondID = try await ingest(
                makeApprovalEvent(
                    id: UUID(uuidString: "B1000000-0000-0000-0000-000000000002")!,
                    capturedAt: "2026-08-17T11:00:00+09:00",
                    amount: "12,000원",
                    merchant: "Synthetic Bulk Second"
                ),
                using: client
            )
            let untouchedID = try await ingest(
                makeApprovalEvent(
                    id: UUID(uuidString: "B1000000-0000-0000-0000-000000000003")!,
                    capturedAt: "2026-08-17T12:00:00+09:00",
                    amount: "13,000원",
                    merchant: "Synthetic Bulk Untouched"
                ),
                using: client
            )

            let payload: [String: Any] = ["items": [firstID, secondID].map { id in
                [
                    "id": id,
                    "review": ["performance": "included", "benefitIds": [firstBenefit], "memo": ""],
                    "aggregationExcluded": false
                ] as [String: Any]
            }]
            try await client.execute(
                uri: "/api/v1/transactions/bulk-review",
                method: .post,
                headers: managementHeaders(login: allowedLogin, mutation: true),
                body: httpByteBuffer(try jsonData(payload))
            ) { response in
                try requireStatus(response, .ok)
                let transactions = try transactionObjects(from: response.body)
                XCTAssertEqual(transactions.compactMap { $0["id"] as? String }, [firstID, secondID])
                for transaction in transactions {
                    XCTAssertEqual(transaction["reviewStatus"] as? String, "reviewed")
                    XCTAssertEqual(transaction["performance"] as? String, "included")
                    XCTAssertEqual(transaction["benefitIds"] as? [String], [firstBenefit])
                }
            }

            let unreviewed = try await fetchTransactions(
                uri: "/api/v1/transactions?scope=unreviewed",
                using: client
            )
            XCTAssertEqual(unreviewed.compactMap { $0["id"] as? String }, [untouchedID])
        }
    }

    func testBulkReviewIsAllOrNothing() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let validID = try await ingest(
                makeApprovalEvent(
                    id: UUID(uuidString: "B2000000-0000-0000-0000-000000000001")!,
                    capturedAt: "2026-08-17T10:00:00+09:00",
                    amount: "5,000원",
                    merchant: "Synthetic Atomic Valid"
                ),
                using: client
            )
            let otherID = try await ingest(
                makeApprovalEvent(
                    id: UUID(uuidString: "B2000000-0000-0000-0000-000000000002")!,
                    capturedAt: "2026-08-17T11:00:00+09:00",
                    amount: "6,000원",
                    merchant: "Synthetic Atomic Other"
                ),
                using: client
            )

            func item(_ id: String, benefitIDs: [String] = [], performance: Any = "included") -> [String: Any] {
                [
                    "id": id,
                    "review": ["performance": performance, "benefitIds": benefitIDs, "memo": ""],
                    "aggregationExcluded": false
                ]
            }
            let cases: [([[String: Any]], HTTPResponse.Status)] = [
                ([item(validID), item(otherID, benefitIDs: [UUID().uuidString])], .badRequest),
                ([item(validID), item(otherID, performance: NSNull())], .badRequest),
                ([item(validID), item(UUID().uuidString)], .notFound),
                ([item(validID), item(validID)], .badRequest),
                ([], .badRequest)
            ]
            for (items, status) in cases {
                try await client.execute(
                    uri: "/api/v1/transactions/bulk-review",
                    method: .post,
                    headers: managementHeaders(login: allowedLogin, mutation: true),
                    body: httpByteBuffer(try jsonData(["items": items]))
                ) { response in
                    try requireStatus(response, status)
                }
            }

            try await client.execute(
                uri: "/api/v1/transactions/bulk-review",
                method: .post,
                headers: managementHeaders(login: allowedLogin, json: true),
                body: httpByteBuffer(try jsonData(["items": [item(validID)]]))
            ) { response in
                try requireStatus(response, .forbidden)
            }

            let unreviewed = try await fetchTransactions(
                uri: "/api/v1/transactions?scope=unreviewed",
                using: client
            )
            XCTAssertEqual(Set(unreviewed.compactMap { $0["id"] as? String }), [validID, otherID])
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

    private func temporaryDatabaseURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BulkTransactionReviewTests-\(UUID().uuidString)")
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

private func cardObjects(from body: ByteBuffer) throws -> [[String: Any]] {
    try XCTUnwrap(jsonObject(from: body)["cards"] as? [[String: Any]])
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
        "Expected HTTP \(expected), received \(actual). The bulk review route may not be implemented yet."
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
