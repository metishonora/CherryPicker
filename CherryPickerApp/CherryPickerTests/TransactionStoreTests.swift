import Foundation
import SwiftData
import XCTest

@testable import CherryPicker

final class TransactionStoreTests: XCTestCase {
    private let approvalMessage = """
    [Web발신]
    MG카드(4775)체크승인
    김*겸님
    2,500원
    08/03 18:00
    씨유(CU)삼성백암점
    통장잔액426,905원
    """

    private let flattenedApprovalMessage = "[Web발신] MG카드(4775)체크승인 김*겸님 2,500원 08/03 18:00 씨유(CU)삼성백암점 통장잔액426,905원"

    private func makeStore() throws -> (ModelContainer, TransactionStore) {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        return (container, TransactionStore(modelContainer: container))
    }

    private func records(in container: ModelContainer) throws -> [TransactionRecord] {
        let context = ModelContext(container)
        return try context.fetch(
            FetchDescriptor<TransactionRecord>(
                sortBy: [SortDescriptor(\TransactionRecord.receivedAt, order: .forward)]
            )
        )
    }

    func testSavePersistsRawMessageAndParsedFields() async throws {
        let (container, store) = try makeStore()
        let receivedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let outcome = try await store.save(rawMessage: approvalMessage, receivedAt: receivedAt)
        guard case .saved = outcome else {
            return XCTFail("Expected a new saved record, got \(outcome)")
        }

        let savedRecords = try records(in: container)
        XCTAssertEqual(savedRecords.count, 1)
        let record = try XCTUnwrap(savedRecords.first)
        XCTAssertEqual(record.originalMessage, approvalMessage)
        XCTAssertEqual(record.parseStatusRaw, ParseStatus.parsed.rawValue)
        XCTAssertEqual(record.kindRaw, "approval")
        XCTAssertEqual(record.cardLast4, "4775")
        XCTAssertEqual(record.amount, 2_500)
        XCTAssertEqual(record.month, 8)
        XCTAssertEqual(record.day, 3)
        XCTAssertEqual(record.hour, 18)
        XCTAssertEqual(record.minute, 0)
        XCTAssertEqual(record.merchant, "씨유(CU)삼성백암점")
        XCTAssertEqual(record.accountBalance, 426_905)
        XCTAssertNotNil(record.parserVersion)
    }

    func testDuplicateWithinTenMinutesReturnsExistingIDAndKeepsOneRecord() async throws {
        let (container, store) = try makeStore()
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)

        let firstOutcome = try await store.save(rawMessage: approvalMessage, receivedAt: firstDate)
        let firstID = try XCTUnwrap(firstOutcome.idIfSaved)
        let duplicateOutcome = try await store.save(
            rawMessage: approvalMessage,
            receivedAt: firstDate.addingTimeInterval(10 * 60)
        )

        XCTAssertEqual(duplicateOutcome, .duplicate(firstID))
        XCTAssertEqual(try records(in: container).count, 1)
    }

    func testSameMessageAfterTenMinutesIsSavedAgain() async throws {
        let (container, store) = try makeStore()
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000)

        _ = try await store.save(rawMessage: approvalMessage, receivedAt: firstDate)
        let secondOutcome = try await store.save(
            rawMessage: approvalMessage,
            receivedAt: firstDate.addingTimeInterval(10 * 60 + 1)
        )

        guard case .saved = secondOutcome else {
            return XCTFail("Expected a second saved record, got \(secondOutcome)")
        }
        XCTAssertEqual(try records(in: container).count, 2)
    }

    func testUnsupportedMessageStillPersistsRawMessageAsFailed() async throws {
        let (container, store) = try makeStore()
        let message = "[Web발신]\n지원하지 않는 알림"

        _ = try await store.save(rawMessage: message, receivedAt: Date(timeIntervalSince1970: 1_800_000_000))

        let record = try XCTUnwrap(try records(in: container).first)
        XCTAssertEqual(record.originalMessage, message)
        XCTAssertEqual(record.parseStatusRaw, ParseStatus.failed.rawValue)
        XCTAssertNil(record.amount)
        XCTAssertNotNil(record.parseFailureReason)
    }

    func testNewRecordInitializesReviewFieldsWithDefaults() async throws {
        let (container, store) = try makeStore()
        let receivedAt = Date(timeIntervalSince1970: 1_800_000_000)

        _ = try await store.save(rawMessage: approvalMessage, receivedAt: receivedAt)

        let record = try XCTUnwrap(try records(in: container).first)
        XCTAssertEqual(record.reviewStatusRaw, ReviewStatus.unreviewed.rawValue)
        XCTAssertEqual(record.performanceDecisionRaw, PerformanceDecision.undecided.rawValue)
        XCTAssertEqual(record.benefitDecisionRaw, BenefitDecision.undecided.rawValue)
        XCTAssertNil(record.benefitAmount)
        XCTAssertNil(record.userMemo)
        XCTAssertEqual(record.hasUserEdits, false)
        XCTAssertEqual(record.updatedAt, receivedAt)
    }

    func testUserEditedDuplicateIsNotReparsedWhenParserVersionChanges() async throws {
        let (container, store) = try makeStore()
        let context = ModelContext(container)
        let receivedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let normalizedHash = MessageFingerprint.sha256(MessageFingerprint.normalized(approvalMessage))
        let userEdited = TransactionRecord(
            receivedAt: receivedAt,
            originalMessage: approvalMessage,
            normalizedMessageHash: normalizedHash,
            parseStatusRaw: ParseStatus.parsed.rawValue,
            kindRaw: "cancellation",
            amount: 99,
            merchant: "사용자 입력 가맹점",
            parserVersion: "mg-card-message-v1",
            hasUserEdits: true
        )
        context.insert(userEdited)
        try context.save()

        let outcome = try await store.save(
            rawMessage: approvalMessage,
            receivedAt: receivedAt.addingTimeInterval(60)
        )

        XCTAssertEqual(outcome, .duplicate(userEdited.id))
        let record = try XCTUnwrap(try records(in: container).first)
        XCTAssertEqual(record.kindRaw, "cancellation")
        XCTAssertEqual(record.amount, 99)
        XCTAssertEqual(record.merchant, "사용자 입력 가맹점")
        XCTAssertEqual(record.parserVersion, "mg-card-message-v1")
        XCTAssertEqual(record.hasUserEdits, true)
    }

    func testPendingDuplicateIsReparsedBeforeDuplicateOutcome() async throws {
        let (container, store) = try makeStore()
        let context = ModelContext(container)
        let receivedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let normalizedHash = MessageFingerprint.sha256(MessageFingerprint.normalized(approvalMessage))
        let pending = TransactionRecord(
            receivedAt: receivedAt,
            originalMessage: approvalMessage,
            normalizedMessageHash: normalizedHash
        )
        context.insert(pending)
        try context.save()

        let outcome = try await store.save(
            rawMessage: approvalMessage,
            receivedAt: receivedAt.addingTimeInterval(60)
        )

        XCTAssertEqual(outcome, .duplicate(pending.id))
        let record = try XCTUnwrap(try records(in: container).first)
        XCTAssertEqual(record.parseStatusRaw, ParseStatus.parsed.rawValue)
        XCTAssertEqual(record.amount, 2_500)
        XCTAssertEqual(record.merchant, "씨유(CU)삼성백암점")
    }

    func testFailedDuplicateFromOlderParserIsReparsed() async throws {
        let (container, store) = try makeStore()
        let context = ModelContext(container)
        let receivedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let normalizedHash = MessageFingerprint.sha256(
            MessageFingerprint.normalized(flattenedApprovalMessage)
        )
        let failed = TransactionRecord(
            receivedAt: receivedAt,
            originalMessage: flattenedApprovalMessage,
            normalizedMessageHash: normalizedHash,
            parseStatusRaw: ParseStatus.failed.rawValue,
            parserVersion: "mg-card-message-v1",
            parseFailureReason: "The transaction amount could not be read."
        )
        context.insert(failed)
        try context.save()

        let outcome = try await store.save(
            rawMessage: flattenedApprovalMessage,
            receivedAt: receivedAt.addingTimeInterval(60)
        )

        XCTAssertEqual(outcome, .duplicate(failed.id))
        let record = try XCTUnwrap(try records(in: container).first)
        XCTAssertEqual(record.parseStatusRaw, ParseStatus.parsed.rawValue)
        XCTAssertEqual(record.parserVersion, "mg-card-message-v2")
        XCTAssertEqual(record.amount, 2_500)
        XCTAssertEqual(record.merchant, "씨유(CU)삼성백암점")
        XCTAssertEqual(record.accountBalance, 426_905)
        XCTAssertNil(record.parseFailureReason)
    }
}

private extension SaveOutcome {
    var idIfSaved: UUID? {
        guard case let .saved(id) = self else { return nil }
        return id
    }
}
