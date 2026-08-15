import Foundation
import XCTest

@testable import CherryPickerServer
import CherryPickerCore

/// Contract tests for product loss prevention and idempotency at the SQLite
/// boundary.
final class CherryPickerServerContractTests: XCTestCase {
    private let codec = OutboxJSONCodec()

    func testOutboxEventUsesTheCapturedAtJSONContractAndRoundTrips() throws {
        let event = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            capturedAt: try makeDate("2026-08-11T12:34:56+09:00")
        )

        let data = try codec.encode(event)
        XCTAssertEqual(data, try codec.encode(event))
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["eventId"] as? String, event.eventId.uuidString)
        XCTAssertEqual(object["originalMessage"] as? String, event.originalMessage)

        let capturedAtString = try XCTUnwrap(object["capturedAt"] as? String)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: capturedAtString))
        XCTAssertEqual(try codec.decode(OutboxEvent.self, from: data), event)
    }

    func testBatchRequestAndResponseAreCodable() async throws {
        let event = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            capturedAt: try makeDate("2026-08-11T12:35:00+09:00")
        )
        let request = BatchSyncRequest(events: [event])

        let requestData = try codec.encode(request)
        XCTAssertEqual(
            try codec.decode(BatchSyncRequest.self, from: requestData),
            request
        )

        let url = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: url) }
        let store = try SQLiteEventStore(databaseURL: url)
        let result = try await store.ingest(event)
        let response = BatchSyncResponse(results: [result])
        let responseData = try codec.encode(response)
        let responseObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        )
        let firstResult = try XCTUnwrap(
            (responseObject["results"] as? [[String: Any]])?.first
        )
        XCTAssertNotNil(firstResult["transactionId"])
        XCTAssertNil(firstResult["transactionID"])
        XCTAssertEqual(
            try codec.decode(BatchSyncResponse.self, from: responseData),
            response
        )
    }

    func testAcceptedParsedEventIsStoredWithCapturedAtAndOriginal() async throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: url) }
        let store = try SQLiteEventStore(databaseURL: url)
        let event = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
            capturedAt: try makeDate("2026-08-11T10:00:00+09:00")
        )

        let result = try await store.ingest(event)

        XCTAssertEqual(result.eventId, event.eventId)
        XCTAssertEqual(result.status, .accepted)
        XCTAssertEqual(result.disposition, .stored)
        let transactionID = try XCTUnwrap(result.transactionID)
        let receiptCount = await store.receiptCount()
        let transactionCount = await store.transactionCount()
        XCTAssertEqual(receiptCount, 1)
        XCTAssertEqual(transactionCount, 1)

        let storedTransaction = await store.transaction(id: transactionID)
        let transaction = try XCTUnwrap(storedTransaction)
        XCTAssertEqual(transaction.capturedAt, event.capturedAt)
        XCTAssertEqual(transaction.originalMessage, event.originalMessage)
        XCTAssertEqual(transaction.parseStatus, .parsed)
    }

    func testExactEventIDReplayIsDuplicateAndDoesNotCreateAnotherTransaction() async throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: url) }
        let store = try SQLiteEventStore(databaseURL: url)
        let event = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            capturedAt: try makeDate("2026-08-11T10:01:00+09:00")
        )

        let first = try await store.ingest(event)
        let replay = try await store.ingest(event)

        XCTAssertEqual(first.status, .accepted)
        XCTAssertEqual(replay.status, .duplicate)
        XCTAssertEqual(replay.eventId, event.eventId)
        let receiptCount = await store.receiptCount()
        let transactionCount = await store.transactionCount()
        XCTAssertEqual(receiptCount, 1)
        XCTAssertEqual(transactionCount, 1)
    }

    func testDifferentEventIDSameFingerprintWithinTenMinutesIsTransactionDuplicate() async throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: url) }
        let store = try SQLiteEventStore(databaseURL: url)
        let firstEvent = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            capturedAt: try makeDate("2026-08-11T10:02:00+09:00")
        )
        let secondEvent = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
            capturedAt: try makeDate("2026-08-11T10:12:00+09:00")
        )

        let first = try await store.ingest(firstEvent)
        let second = try await store.ingest(secondEvent)

        XCTAssertEqual(first.status, .accepted)
        XCTAssertEqual(first.disposition, .stored)
        XCTAssertEqual(second.status, .accepted)
        XCTAssertEqual(second.disposition, .transactionDuplicate)
        XCTAssertEqual(second.transactionID, first.transactionID)
        let receiptCount = await store.receiptCount()
        let transactionCount = await store.transactionCount()
        XCTAssertEqual(receiptCount, 2)
        XCTAssertEqual(transactionCount, 1)
    }

    func testSameFingerprintOutsideTenMinuteWindowIsStoredAsNewTransaction() async throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: url) }
        let store = try SQLiteEventStore(databaseURL: url)
        let firstEvent = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000014")!,
            capturedAt: try makeDate("2026-08-11T10:14:00+09:00")
        )
        let secondEvent = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            capturedAt: try makeDate("2026-08-11T10:03:00+09:00")
        )

        let first = try await store.ingest(firstEvent)
        let second = try await store.ingest(secondEvent)

        XCTAssertEqual(first.disposition, .stored)
        XCTAssertEqual(second.status, .accepted)
        XCTAssertEqual(second.disposition, .stored)
        XCTAssertNotEqual(second.transactionID, first.transactionID)
        let receiptCount = await store.receiptCount()
        let transactionCount = await store.transactionCount()
        XCTAssertEqual(receiptCount, 2)
        XCTAssertEqual(transactionCount, 2)
    }

    func testWhitespaceInsideMessageRemainsSignificantForFingerprinting() async throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: url) }
        let store = try SQLiteEventStore(databaseURL: url)
        let spaced = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
            capturedAt: try makeDate("2026-08-11T10:15:00+09:00")
        )
        let compact = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!,
            capturedAt: try makeDate("2026-08-11T10:16:00+09:00"),
            originalMessage: validSyntheticMessage.replacingOccurrences(
                of: "Synthetic Merchant",
                with: "SyntheticMerchant"
            )
        )

        let first = try await store.ingest(spaced)
        let second = try await store.ingest(compact)

        XCTAssertEqual(first.disposition, .stored)
        XCTAssertEqual(second.disposition, .stored)
        XCTAssertNotEqual(second.transactionID, first.transactionID)
        let transactionCount = await store.transactionCount()
        XCTAssertEqual(transactionCount, 2)
    }

    func testParseFailureIsAcceptedAndOriginalMessageIsPreserved() async throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: url) }
        let store = try SQLiteEventStore(databaseURL: url)
        let event = OutboxEvent(
            schemaVersion: 1,
            eventId: UUID(uuidString: "00000000-0000-0000-0000-000000000016")!,
            capturedAt: try makeDate("2026-08-11T10:04:00+09:00"),
            originalMessage: "synthetic unsupported card fixture"
        )

        let result = try await store.ingest(event)

        XCTAssertEqual(result.status, .accepted)
        XCTAssertEqual(result.disposition, .parseFailed)
        let transactionID = try XCTUnwrap(result.transactionID)
        let storedTransaction = await store.transaction(id: transactionID)
        let transaction = try XCTUnwrap(storedTransaction)
        XCTAssertEqual(transaction.originalMessage, event.originalMessage)
        XCTAssertEqual(transaction.capturedAt, event.capturedAt)
        XCTAssertEqual(transaction.parseStatus, .failed)
    }

    func testSemanticInvalidEventIsRejectedWithAReasonCode() async throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: url) }
        let store = try SQLiteEventStore(databaseURL: url)
        let invalidEvent = OutboxEvent(
            schemaVersion: 99,
            eventId: UUID(uuidString: "00000000-0000-0000-0000-000000000017")!,
            capturedAt: try makeDate("2026-08-11T10:05:00+09:00"),
            originalMessage: "synthetic invalid schema fixture"
        )

        let result = try await store.ingest(invalidEvent)

        XCTAssertEqual(result.status, .rejected)
        XCTAssertNotNil(result.rejectionReason)
        let receiptCount = await store.receiptCount()
        let transactionCount = await store.transactionCount()
        XCTAssertEqual(receiptCount, 0)
        XCTAssertEqual(transactionCount, 0)
    }

    func testMixedBatchReturnsAcceptedDuplicateAndRejectedResults() async throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: url) }
        let store = try SQLiteEventStore(databaseURL: url)
        let authorizer = TailscaleIdentityAuthorizer(allowedLogin: "fixture-device@example.test")
        let service = IngestionService(store: store, authorizer: authorizer)
        let accepted = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000018")!,
            capturedAt: try makeDate("2026-08-11T10:06:00+09:00")
        )
        let prior = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            capturedAt: try makeDate("2026-08-11T10:06:15+09:00")
        )
        let invalid = OutboxEvent(
            schemaVersion: 99,
            eventId: UUID(uuidString: "00000000-0000-0000-0000-000000000019")!,
            capturedAt: try makeDate("2026-08-11T10:06:30+09:00"),
            originalMessage: "synthetic invalid schema fixture"
        )
        _ = try await store.ingest(prior)

        let request = BatchSyncRequest(events: [accepted, prior, invalid])
        let response = try await service.ingest(request, login: "fixture-device@example.test")

        XCTAssertEqual(response.results.map(\.status), [.accepted, .duplicate, .rejected])
        XCTAssertEqual(response.results[0].disposition, .transactionDuplicate)
        XCTAssertEqual(response.results.map(\.eventId), [accepted.eventId, prior.eventId, invalid.eventId])
        let receiptCount = await store.receiptCount()
        let transactionCount = await store.transactionCount()
        XCTAssertEqual(receiptCount, 2)
        XCTAssertEqual(transactionCount, 1)
    }

    func testRetryAfterCommittedWriteModelsResponseLossAndReturnsDuplicate() async throws {
        let url = try temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: url) }
        let firstStore = try SQLiteEventStore(databaseURL: url)
        let event = makeEvent(
            eventID: UUID(uuidString: "00000000-0000-0000-0000-000000000020")!,
            capturedAt: try makeDate("2026-08-11T10:07:00+09:00")
        )

        let committed = try await firstStore.ingest(event)
        XCTAssertEqual(committed.status, .accepted)

        // Reopen the same disk-backed database to model a response lost after
        // commit and an eventual client retry.
        let reopenedStore = try SQLiteEventStore(databaseURL: url)
        let retry = try await reopenedStore.ingest(event)

        XCTAssertEqual(retry.status, .duplicate)
        let receiptCount = await reopenedStore.receiptCount()
        let transactionCount = await reopenedStore.transactionCount()
        XCTAssertEqual(receiptCount, 1)
        XCTAssertEqual(transactionCount, 1)
    }

    func testTailscaleIdentityAuthorizationRequiresAnExactAllowedLogin() {
        let authorizer = TailscaleIdentityAuthorizer(allowedLogin: "fixture-device@example.test")

        XCTAssertTrue(authorizer.isAuthorized(login: "fixture-device@example.test"))
        XCTAssertFalse(authorizer.isAuthorized(login: "other-device@example.test"))
        XCTAssertFalse(authorizer.isAuthorized(login: nil))
    }

    // MARK: - Fixtures

    private func makeEvent(
        eventID: UUID,
        capturedAt: Date,
        originalMessage: String? = nil
    ) -> OutboxEvent {
        OutboxEvent(
            schemaVersion: 1,
            eventId: eventID,
            capturedAt: capturedAt,
            originalMessage: originalMessage ?? validSyntheticMessage
        )
    }

    private var validSyntheticMessage: String {
        """
        [Web발신]
        MG카드(4775)체크승인
        2,500원
        08/03 18:00
        Synthetic Merchant
        """
    }

    private func makeDate(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func temporaryDatabaseURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CherryPickerServerTests-\(UUID().uuidString)")
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
