import Foundation
import XCTest

import Hummingbird
import HummingbirdTesting

@testable import CherryPickerServer
import CherryPickerCore

/// Failing HTTP contract tests for the issue #7 local server.
///
/// The application is deliberately exercised in-process through
/// `HummingbirdTesting`.  Fixtures contain no names, balances, secrets, or
/// real Tailscale identities; `example.test` is reserved for this packet.
@available(macOS 14.0, *)
final class HTTPApplicationTests: XCTestCase {
    private let codec = OutboxJSONCodec()

    private let allowedLogin = "fixture-device@example.test"

    func testHealthzIsPublicAndDoesNotReturnSensitiveBody() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let store = try SQLiteEventStore(databaseURL: databaseURL)
        let app = try makeApplication(store: store)
        let allowedLogin = self.allowedLogin

        try await app.test(.router) { client in
            try await client.execute(uri: "/healthz", method: .get) { response in
                XCTAssertEqual(response.status, .ok)
                let body = httpBodyString(response.body)
                XCTAssertFalse(body.contains("originalMessage"))
                XCTAssertFalse(body.contains(allowedLogin))
            }
        }

    }

    func testAuthorizedBatchReturnsAcceptedAndPersistsReceiptAndTransaction() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let store = try SQLiteEventStore(databaseURL: databaseURL)
        let app = try makeApplication(store: store)
        let allowedLogin = self.allowedLogin
        let codec = self.codec
        let event = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
            capturedAt: try makeDate("2026-08-11T12:34:56+09:00")
        )
        let requestData = try codec.encode(BatchSyncRequest(events: [event]))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/v1/events/batch",
                method: .post,
                headers: httpHeaders(login: allowedLogin, contentType: true),
                body: httpByteBuffer(requestData)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let responseData = Data(response.body.readableBytesView)
                let decoded = try codec.decode(BatchSyncResponse.self, from: responseData)
                let result = try XCTUnwrap(decoded.results.first)
                XCTAssertEqual(result.eventId, event.eventId)
                XCTAssertEqual(result.status, .accepted)
                XCTAssertEqual(result.disposition, .stored)
                XCTAssertNotNil(result.transactionID)
            }
        }

        let receiptCount = await store.receiptCount()
        let transactionCount = await store.transactionCount()
        XCTAssertEqual(receiptCount, 1)
        XCTAssertEqual(transactionCount, 1)
        let storedReceipt = await store.receipt(for: event.eventId)
        let transactionID = try XCTUnwrap(storedReceipt?.transactionID)
        let storedValue = await store.transaction(id: transactionID)
        let storedTransaction = try XCTUnwrap(storedValue)
        XCTAssertEqual(storedTransaction.capturedAt, event.capturedAt)
        XCTAssertEqual(storedTransaction.originalMessage, event.originalMessage)
        XCTAssertEqual(storedTransaction.parseStatus, .parsed)
    }

    func testMissingOrWrongIdentityReturnsUnauthorizedWithoutWriting() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let store = try SQLiteEventStore(databaseURL: databaseURL)
        let app = try makeApplication(store: store)
        let event = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
            capturedAt: try makeDate("2026-08-11T12:35:56+09:00")
        )
        let requestData = try codec.encode(BatchSyncRequest(events: [event]))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/v1/events/batch",
                method: .post,
                headers: httpHeaders(contentType: true),
                body: httpByteBuffer(requestData)
            ) { response in
                XCTAssertEqual(response.status, .unauthorized)
                XCTAssertFalse(httpBodyString(response.body).contains(event.originalMessage))
            }

            try await client.execute(
                uri: "/api/v1/events/batch",
                method: .post,
                headers: httpHeaders(login: "other-device@example.test", contentType: true),
                body: httpByteBuffer(requestData)
            ) { response in
                XCTAssertEqual(response.status, .unauthorized)
                XCTAssertFalse(httpBodyString(response.body).contains(event.originalMessage))
            }
        }

        let receiptCount = await store.receiptCount()
        let transactionCount = await store.transactionCount()
        XCTAssertEqual(receiptCount, 0)
        XCTAssertEqual(transactionCount, 0)
    }

    func testMalformedBatchJSONReturnsGenericBadRequestWithoutEchoingBody() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let store = try SQLiteEventStore(databaseURL: databaseURL)
        let app = try makeApplication(store: store)
        let allowedLogin = self.allowedLogin
        let sentinel = "synthetic-malformed-body-must-not-echo"
        let malformedJSON = Data("{\"events\":[{\"originalMessage\":\"\(sentinel)\"}".utf8)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/v1/events/batch",
                method: .post,
                headers: httpHeaders(login: allowedLogin, contentType: true),
                body: httpByteBuffer(malformedJSON)
            ) { response in
                XCTAssertEqual(response.status, .badRequest)
                let body = httpBodyString(response.body)
                XCTAssertFalse(body.contains(sentinel))
                XCTAssertFalse(body.contains("originalMessage"))
                XCTAssertFalse(body.contains("events"))
            }
        }

        let receiptCount = await store.receiptCount()
        let transactionCount = await store.transactionCount()
        XCTAssertEqual(receiptCount, 0)
        XCTAssertEqual(transactionCount, 0)
    }

    func testTransactionsRequireIdentityAndHideOriginalMessageByDefault() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let store = try SQLiteEventStore(databaseURL: databaseURL)
        let app = try makeApplication(store: store)
        let allowedLogin = self.allowedLogin
        let event = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!,
            capturedAt: try makeDate("2026-08-11T12:36:56+09:00")
        )
        _ = try await store.ingest(event)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/api/v1/transactions",
                method: .get
            ) { response in
                XCTAssertEqual(response.status, .unauthorized)
            }

            try await client.execute(
                uri: "/api/v1/transactions",
                method: .get,
                headers: httpHeaders(login: allowedLogin)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let body = httpBodyString(response.body)
                XCTAssertTrue(body.contains("parseStatus"))
                XCTAssertTrue(body.contains("parsed"))
                XCTAssertTrue(body.contains("summary"))
                XCTAssertFalse(body.contains("originalMessage"))
                XCTAssertFalse(body.contains(event.originalMessage))
            }
        }
    }

    func testRootRequiresIdentityAndRendersMinimalHTMLWithoutOriginalMessage() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let store = try SQLiteEventStore(databaseURL: databaseURL)
        let app = try makeApplication(store: store)
        let allowedLogin = self.allowedLogin
        let event = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000104")!,
            capturedAt: try makeDate("2026-08-11T12:37:56+09:00")
        )
        _ = try await store.ingest(event)

        try await app.test(.router) { client in
            try await client.execute(uri: "/", method: .get) { response in
                XCTAssertEqual(response.status, .unauthorized)
            }

            try await client.execute(
                uri: "/",
                method: .get,
                headers: httpHeaders(login: allowedLogin)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let body = httpBodyString(response.body)
                XCTAssertTrue(body.localizedCaseInsensitiveContains("<html"))
                XCTAssertTrue(body.contains("parseStatus"))
                XCTAssertTrue(body.contains("summary"))
                XCTAssertFalse(body.contains("originalMessage"))
                XCTAssertFalse(body.contains(event.originalMessage))
            }
        }
    }

    func testRootRendersAuthenticatedSyncResultsWithoutOriginalMessage() async throws {
        let databaseURL = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let store = try SQLiteEventStore(databaseURL: databaseURL)
        let app = try makeApplication(store: store)
        let allowedLogin = self.allowedLogin
        let codec = self.codec
        let firstEvent = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000105")!,
            capturedAt: try makeDate("2026-08-11T12:40:56+09:00")
        )
        let secondEvent = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000106")!,
            capturedAt: try makeDate("2026-08-11T12:45:56+09:00")
        )

        try await app.test(.router) { client in
            for event in [firstEvent, secondEvent] {
                let requestData = try codec.encode(BatchSyncRequest(events: [event]))
                try await client.execute(
                    uri: "/api/v1/events/batch",
                    method: .post,
                    headers: httpHeaders(login: allowedLogin, contentType: true),
                    body: httpByteBuffer(requestData)
                ) { response in
                    XCTAssertEqual(response.status, .ok)
                    let responseData = Data(response.body.readableBytesView)
                    let decoded = try codec.decode(BatchSyncResponse.self, from: responseData)
                    let result = try XCTUnwrap(decoded.results.first)
                    XCTAssertEqual(result.status, .accepted)
                    if event.eventId == secondEvent.eventId {
                        XCTAssertEqual(result.disposition, .transactionDuplicate)
                    }
                }
            }

            try await client.execute(
                uri: "/",
                method: .get,
                headers: httpHeaders(login: allowedLogin)
            ) { response in
                XCTAssertEqual(response.status, .ok)
                let body = httpBodyString(response.body)
                XCTAssertTrue(body.contains("syncResult"))
                XCTAssertTrue(body.contains("transactionDuplicate"))
                XCTAssertFalse(body.contains("originalMessage"))
                XCTAssertFalse(body.contains(firstEvent.originalMessage))
                XCTAssertFalse(body.contains(secondEvent.originalMessage))
            }
        }

        let safeReceipts = try await store.safeEventReceipts()
        XCTAssertEqual(safeReceipts.map(\.eventId), [secondEvent.eventId, firstEvent.eventId])
        XCTAssertEqual(safeReceipts.first?.disposition, .transactionDuplicate)
    }

    // MARK: - Application and HTTP fixtures

    private func makeApplication(
        store: SQLiteEventStore
    ) throws -> some ApplicationProtocol {
        try CherryPickerHTTPApplication(
            store: store,
            authorizer: TailscaleIdentityAuthorizer(allowedLogin: allowedLogin),
            codec: codec
        ).application
    }

    private func makeEvent(eventID: UUID, capturedAt: Date) -> OutboxEvent {
        OutboxEvent(
            schemaVersion: OutboxEvent.currentSchemaVersion,
            eventId: eventID,
            capturedAt: capturedAt,
            originalMessage: """
            [Web발신]
            MG카드(4775)체크승인
            2,500원
            08/03 18:00
            Synthetic Merchant
            """
        )
    }

    private func makeDate(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func temporaryDatabaseURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CherryPickerHTTPApplicationTests-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        return url
    }

    private func removeDatabaseFiles(at url: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            try? fileManager.removeItem(atPath: url.path + suffix)
        }
    }
}

private func httpHeaders(
    login: String? = nil,
    contentType: Bool = false
) -> HTTPFields {
    var fields: HTTPFields = [:]
    if let login {
        fields[.init("Tailscale-User-Login")!] = login
    }
    if contentType {
        fields[.contentType] = "application/json"
    }
    return fields
}

private func httpByteBuffer(_ data: Data) -> ByteBuffer {
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    buffer.writeBytes(data)
    return buffer
}

private func httpBodyString(_ body: ByteBuffer) -> String {
    String(decoding: body.readableBytesView, as: UTF8.self)
}
