import Foundation
import XCTest

import CherryPickerServer
import Hummingbird
import HummingbirdTesting

/// Proposed black-box acceptance tests for the Issue #12 approval parser.
///
/// The suite uses only the product HTTP boundary. It creates synthetic card
/// instances, submits privacy-safe synthetic outbox events, and observes the
/// public card, sync, and transaction responses. Production parser and store
/// types are deliberately not called from the assertions.
@available(macOS 14.0, *)
final class Issue12ParserBlackBoxAcceptanceTests: XCTestCase, @unchecked Sendable {
    private let allowedLogin = "fixture-device@example.test"
    private let mgPlusCardTypeCode = "hana.mg-plus-s"

    func testApprovalFormatsRouteExclusivelyAcrossCardTypes() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let existingCards = try await cards(using: client)
            let betterCheckCard = try XCTUnwrap(
                existingCards.first {
                    $0["cardTypeCode"] as? String == "mg.the-better-check"
                }
            )
            let betterCheckCardID = try requiredString(betterCheckCard, key: "id")
            let mgPlusCard = try await createCard(
                cardTypeCode: mgPlusCardTypeCode,
                displayName: "합성 MG+S 하나카드",
                lastFour: "1234",
                using: client
            )
            let mgPlusCardID = try requiredString(mgPlusCard, key: "id")
            XCTAssertEqual(mgPlusCard["cardTypeCode"] as? String, mgPlusCardTypeCode)
            XCTAssertEqual(mgPlusCard["lastFour"] as? String, "1234")

            let mgPlusResult = try await ingest(
                id: UUID(uuidString: "12000000-0000-0000-0000-000000000001")!,
                capturedAt: "2026-01-15T13:00:00+09:00",
                message: mgPlusApproval(maskedIdentifier: "1*3*"),
                using: client
            )
            XCTAssertEqual(mgPlusResult["status"] as? String, "accepted")
            XCTAssertEqual(mgPlusResult["disposition"] as? String, "stored")

            let mgPlusTransaction = try await transaction(
                id: try requiredString(mgPlusResult, key: "transactionId"),
                using: client
            )
            XCTAssertEqual(mgPlusTransaction["parseStatus"] as? String, "parsed")
            XCTAssertEqual(mgPlusTransaction["cardId"] as? String, mgPlusCardID)
            XCTAssertEqual(mgPlusTransaction["cardLastFour"] as? String, "1234")
            XCTAssertEqual(mgPlusTransaction["kind"] as? String, "approval")
            XCTAssertEqual(mgPlusTransaction["amount"] as? Int, 12_340)
            XCTAssertEqual(mgPlusTransaction["merchant"] as? String, "합성상점")
            XCTAssertEqual(
                try dateValue(mgPlusTransaction, key: "occurredAt"),
                try requiredDate("2026-01-15T03:34:00Z")
            )

            let betterCheckResult = try await ingest(
                id: UUID(uuidString: "12000000-0000-0000-0000-000000000002")!,
                capturedAt: "2026-01-15T14:00:00+09:00",
                message: betterCheckApproval(),
                using: client
            )
            XCTAssertEqual(betterCheckResult["disposition"] as? String, "stored")
            let betterCheckTransaction = try await transaction(
                id: try requiredString(betterCheckResult, key: "transactionId"),
                using: client
            )
            XCTAssertEqual(betterCheckTransaction["cardId"] as? String, betterCheckCardID)
            XCTAssertEqual(betterCheckTransaction["cardLastFour"] as? String, "4775")
            XCTAssertEqual(betterCheckTransaction["merchant"] as? String, "합성기존가맹점")

            let wonderResult = try await ingest(
                id: UUID(uuidString: "12000000-0000-0000-0000-000000000003")!,
                capturedAt: "2026-01-15T15:00:00+09:00",
                message: wonderApproval(),
                using: client
            )
            XCTAssertEqual(wonderResult["status"] as? String, "accepted")
            XCTAssertEqual(wonderResult["disposition"] as? String, "parseFailed")

            let wonderTransaction = try await transaction(
                id: try requiredString(wonderResult, key: "transactionId"),
                using: client
            )
            XCTAssertEqual(wonderTransaction["parseStatus"] as? String, "failed")
            assertUnassigned(wonderTransaction)

            let encodedWonder = try JSONSerialization.data(
                withJSONObject: wonderTransaction,
                options: [.sortedKeys]
            )
            let safeWonderBody = String(decoding: encodedWonder, as: UTF8.self)
            XCTAssertFalse(safeWonderBody.contains("합성멤버십"))
            XCTAssertFalse(safeWonderBody.contains("originalMessage"))
        }
    }

    func testMaskedIdentifierAssignsOnlyOneMatchingCardInstance() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            let firstCard = try await createCard(
                cardTypeCode: mgPlusCardTypeCode,
                displayName: "합성 MG+S 첫 번째",
                lastFour: "1234",
                using: client
            )
            let secondCard = try await createCard(
                cardTypeCode: mgPlusCardTypeCode,
                displayName: "합성 MG+S 두 번째",
                lastFour: "1938",
                using: client
            )
            XCTAssertNotEqual(
                try requiredString(firstCard, key: "id"),
                try requiredString(secondCard, key: "id")
            )

            // Both synthetic cards produce the same A*C* signature: 1*3*.
            // Parsing can succeed, but assignment must remain unresolved.
            let ambiguousResult = try await ingest(
                id: UUID(uuidString: "12000000-0000-0000-0000-000000000011")!,
                capturedAt: "2026-01-15T13:00:00+09:00",
                message: mgPlusApproval(maskedIdentifier: "1*3*"),
                using: client
            )
            XCTAssertEqual(ambiguousResult["status"] as? String, "accepted")
            let ambiguousTransaction = try await transaction(
                id: try requiredString(ambiguousResult, key: "transactionId"),
                using: client
            )
            XCTAssertEqual(ambiguousTransaction["parseStatus"] as? String, "parsed")
            assertUnassigned(ambiguousTransaction)

            // A valid MG+S body with no matching stored signature is likewise
            // reviewable but never guessed onto either card.
            let unmatchedResult = try await ingest(
                id: UUID(uuidString: "12000000-0000-0000-0000-000000000012")!,
                capturedAt: "2026-01-15T14:00:00+09:00",
                message: mgPlusApproval(maskedIdentifier: "7*9*"),
                using: client
            )
            XCTAssertEqual(unmatchedResult["status"] as? String, "accepted")
            let unmatchedTransaction = try await transaction(
                id: try requiredString(unmatchedResult, key: "transactionId"),
                using: client
            )
            XCTAssertEqual(unmatchedTransaction["parseStatus"] as? String, "parsed")
            assertUnassigned(unmatchedTransaction)
        }
    }

    func testDeferredCancellationIsStoredForReviewWithoutGuessingACard() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)

        try await app.test(.router) { client in
            _ = try await createCard(
                cardTypeCode: mgPlusCardTypeCode,
                displayName: "합성 MG+S 하나카드",
                lastFour: "1234",
                using: client
            )

            let originalMessage = """
            [Web발신]
            MG+ 하나1*3*승인취소 홍*동 12,340원 01/16 09:00 합성취소가맹점
            """
            let result = try await ingest(
                id: UUID(uuidString: "12000000-0000-0000-0000-000000000021")!,
                capturedAt: "2026-01-16T10:00:00+09:00",
                message: originalMessage,
                using: client
            )
            XCTAssertEqual(result["status"] as? String, "accepted")
            XCTAssertEqual(result["disposition"] as? String, "parseFailed")

            let resolved = try await transaction(
                id: try requiredString(result, key: "transactionId"),
                using: client
            )
            XCTAssertEqual(resolved["parseStatus"] as? String, "failed")
            assertUnassigned(resolved)

            let encoded = try JSONSerialization.data(
                withJSONObject: resolved,
                options: [.sortedKeys]
            )
            let safeBody = String(decoding: encoded, as: UTF8.self)
            XCTAssertFalse(safeBody.contains(originalMessage))
            XCTAssertFalse(safeBody.contains("originalMessage"))
            XCTAssertFalse(safeBody.contains("합성취소가맹점"))
        }
    }

    func testCardCreationRequiresIdentityAndCSRFAndRejectsUnknownTypes() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let app = try makeApplication(databaseURL: databaseURL)
        let validPayload = try cardCreatePayload(
            cardTypeCode: mgPlusCardTypeCode,
            displayName: "합성 MG+S 하나카드",
            lastFour: "1234"
        )

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/v1/cards",
                method: .post,
                headers: [:],
                body: byteBuffer(validPayload)
            ) { response in
                XCTAssertEqual(response.status, .unauthorized)
            }
            try await client.execute(
                uri: "/api/v1/cards",
                method: .post,
                headers: headers(),
                body: byteBuffer(validPayload)
            ) { response in
                XCTAssertEqual(response.status, .forbidden)
            }

            let unknownPayload = try cardCreatePayload(
                cardTypeCode: "unknown.card-type",
                displayName: "알 수 없는 합성 카드",
                lastFour: "9876"
            )
            try await client.execute(
                uri: "/api/v1/cards",
                method: .post,
                headers: headers(mutation: true),
                body: byteBuffer(unknownPayload)
            ) { response in
                XCTAssertEqual(response.status, .badRequest)
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

    private func cards<Client>(using client: Client) async throws -> [[String: Any]]
    where Client: TestClientProtocol {
        let captured = LockedIssue12Value<[[String: Any]]>([])
        try await client.execute(
            uri: "/api/v1/cards",
            method: .get,
            headers: headers()
        ) { response in
            try requireStatus(response, .ok)
            captured.set(
                try XCTUnwrap(jsonObject(response.body)["cards"] as? [[String: Any]])
            )
        }
        return captured.get()
    }

    private func createCard<Client>(
        cardTypeCode: String,
        displayName: String,
        lastFour: String,
        using client: Client
    ) async throws -> [String: Any] where Client: TestClientProtocol {
        let captured = LockedIssue12Value<[String: Any]?>(nil)
        try await client.execute(
            uri: "/api/v1/cards",
            method: .post,
            headers: headers(mutation: true),
            body: byteBuffer(try cardCreatePayload(
                cardTypeCode: cardTypeCode,
                displayName: displayName,
                lastFour: lastFour
            ))
        ) { response in
            guard response.status == .created || response.status == .ok else {
                throw UnexpectedIssue12HTTPStatus(
                    expected: "HTTP 200 or 201",
                    actual: response.status
                )
            }
            captured.set(try XCTUnwrap(jsonObject(response.body)["card"] as? [String: Any]))
        }
        return try XCTUnwrap(captured.get())
    }

    private func cardCreatePayload(
        cardTypeCode: String,
        displayName: String,
        lastFour: String
    ) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "cardTypeCode": cardTypeCode,
            "displayName": displayName,
            "lastFour": lastFour
        ], options: [.sortedKeys])
    }

    private func ingest<Client>(
        id: UUID,
        capturedAt: String,
        message: String,
        using client: Client
    ) async throws -> [String: Any] where Client: TestClientProtocol {
        let request: [String: Any] = [
            "events": [[
                "schemaVersion": 1,
                "eventId": id.uuidString,
                "capturedAt": capturedAt,
                "originalMessage": message
            ]]
        ]
        let captured = LockedIssue12Value<[String: Any]?>(nil)
        try await client.execute(
            uri: "/api/v1/events/batch",
            method: .post,
            headers: headers(mutation: true),
            body: byteBuffer(try JSONSerialization.data(
                withJSONObject: request,
                options: [.sortedKeys]
            ))
        ) { response in
            try requireStatus(response, .ok)
            let results = try XCTUnwrap(
                jsonObject(response.body)["results"] as? [[String: Any]]
            )
            captured.set(try XCTUnwrap(results.first))
        }
        return try XCTUnwrap(captured.get())
    }

    private func transaction<Client>(
        id: String,
        using client: Client
    ) async throws -> [String: Any] where Client: TestClientProtocol {
        let captured = LockedIssue12Value<[String: Any]?>(nil)
        try await client.execute(
            uri: "/api/v1/transactions/\(id)",
            method: .get,
            headers: headers()
        ) { response in
            try requireStatus(response, .ok)
            captured.set(
                try XCTUnwrap(jsonObject(response.body)["transaction"] as? [String: Any])
            )
        }
        return try XCTUnwrap(captured.get())
    }

    private func headers(mutation: Bool = false) -> HTTPFields {
        var fields: HTTPFields = [
            .init("Tailscale-User-Login")!: allowedLogin
        ]
        if mutation {
            fields[.contentType] = "application/json"
            fields[.init("X-CherryPicker-CSRF")!] = "same-origin"
        }
        return fields
    }

    private func assertUnassigned(
        _ transaction: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(isNilJSONValue(transaction["cardId"]), file: file, line: line)
        XCTAssertTrue(isNilJSONValue(transaction["cardDisplayName"]), file: file, line: line)
        XCTAssertTrue(isNilJSONValue(transaction["cardLastFour"]), file: file, line: line)
    }

    private func isNilJSONValue(_ value: Any?) -> Bool {
        value == nil || value is NSNull
    }

    private func requiredString(_ object: [String: Any], key: String) throws -> String {
        try XCTUnwrap(object[key] as? String, "Missing string field: \(key)")
    }

    private func dateValue(_ object: [String: Any], key: String) throws -> Date {
        try requiredDate(try requiredString(object, key: key))
    }

    private func requiredDate(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func mgPlusApproval(maskedIdentifier: String) -> String {
        """
        [Web발신]
        MG+ 하나\(maskedIdentifier)승인 홍*동 12,340원 일시불 01/15 12:34 합성상점 누적123,456원
        """
    }

    private func wonderApproval() -> String {
        """
        [Web발신]
        하나9*8*승인 홍*동 5,200원 일시불 01/15 12:45 합성멤버십 누적98,765원
        """
    }

    private func betterCheckApproval() -> String {
        """
        [Web발신]
        MG카드(4775)체크승인
        2,500원
        01/15 12:40
        합성기존가맹점
        """
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Issue12ParserBlackBoxAcceptanceTests-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private func removeDatabaseFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}

private final class LockedIssue12Value<Value>: @unchecked Sendable {
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

private struct UnexpectedIssue12HTTPStatus: Error, CustomStringConvertible {
    let expected: String
    let actual: HTTPResponse.Status

    var description: String {
        "Expected \(expected), received \(actual). The Issue #12 contract is not implemented yet."
    }
}

private func requireStatus(
    _ response: TestResponse,
    _ expected: HTTPResponse.Status
) throws {
    guard response.status == expected else {
        throw UnexpectedIssue12HTTPStatus(
            expected: "HTTP \(expected.code)",
            actual: response.status
        )
    }
}

private func jsonObject(_ body: ByteBuffer) throws -> [String: Any] {
    try XCTUnwrap(
        JSONSerialization.jsonObject(with: Data(body.readableBytesView)) as? [String: Any]
    )
}

private func byteBuffer(_ data: Data) -> ByteBuffer {
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    buffer.writeBytes(data)
    return buffer
}
