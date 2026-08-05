import Foundation
import SwiftData
import XCTest

@testable import CherryPicker

final class PersistenceMigrationTests: XCTestCase {
    func testV1StoreMigratesTransactionsAndBackfillsDefaultCardWithoutLosingUserValues() throws {
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        let transactionID = UUID()
        let receivedAt = try makeDate("2026-08-03T18:01:00+09:00")
        do {
            let v1Container = try PersistenceController.makeV1ModelContainer(url: storeURL)
            let context = ModelContext(v1Container)
            let record = CherryPickerSchemaV1.TransactionRecord(
                id: transactionID,
                receivedAt: receivedAt,
                originalMessage: "saved V1 message",
                normalizedMessageHash: "hash",
                parseStatusRaw: ParseStatus.parsed.rawValue,
                kindRaw: "cancellation",
                cardLast4: "4775",
                amount: 99,
                month: 8,
                day: 3,
                merchant: "사용자 수정 가맹점",
                parserVersion: "mg-card-message-v1",
                reviewStatusRaw: ReviewStatus.reviewed.rawValue,
                performanceDecisionRaw: PerformanceDecision.included.rawValue,
                benefitDecisionRaw: BenefitDecision.received.rawValue,
                benefitAmount: 10,
                userMemo: "보존할 메모",
                hasUserEdits: true,
                updatedAt: receivedAt
            )
            context.insert(record)
            try context.save()
        }

        let migratedContainer = try PersistenceController.makeModelContainer(url: storeURL)
        let context = ModelContext(migratedContainer)
        let records = try context.fetch(FetchDescriptor<TransactionRecord>())
        let cards = try context.fetch(FetchDescriptor<CardRecord>())

        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.id, transactionID)
        XCTAssertEqual(record.originalMessage, "saved V1 message")
        XCTAssertEqual(record.receivedAt, receivedAt)
        XCTAssertEqual(record.kindRaw, "cancellation")
        XCTAssertEqual(record.amount, 99)
        XCTAssertEqual(record.merchant, "사용자 수정 가맹점")
        XCTAssertTrue(record.hasKindOverride)
        XCTAssertTrue(record.hasAmountOverride)
        XCTAssertTrue(record.hasDateOverride)
        XCTAssertTrue(record.hasMerchantOverride)
        XCTAssertEqual(record.reviewStatusRaw, ReviewStatus.reviewed.rawValue)
        XCTAssertEqual(record.performanceDecisionRaw, PerformanceDecision.included.rawValue)
        XCTAssertEqual(record.benefitDecisionRaw, BenefitDecision.received.rawValue)
        XCTAssertEqual(record.benefitAmount, 10)
        XCTAssertEqual(record.benefitUnitCode, "legacyUnspecified")
        XCTAssertEqual(record.userMemo, "보존할 메모")
        XCTAssertEqual(record.dateResolutionSourceRaw, "legacyReceivedYear")
        XCTAssertEqual(record.resolvedYear, 2026)

        XCTAssertEqual(cards.count, 1)
        let card = try XCTUnwrap(cards.first)
        XCTAssertEqual(card.displayName, "MG 더나은 체크카드")
        XCTAssertEqual(card.issuerCode, "MG")
        XCTAssertEqual(card.lastFour, "4775")
        XCTAssertEqual(card.performanceTargetAmount, 300_000)
        XCTAssertEqual(card.periodRuleKindRaw, "calendarMonth")
        XCTAssertEqual(card.timeZoneIdentifier, "Asia/Seoul")
        XCTAssertEqual(record.card?.id, card.id)
    }

    func testV1UneditedAndUnmatchedTransactionRemainsWithoutOverridesOrCard() throws {
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        do {
            let v1Container = try PersistenceController.makeV1ModelContainer(url: storeURL)
            let context = ModelContext(v1Container)
            context.insert(CherryPickerSchemaV1.TransactionRecord(
                receivedAt: try makeDate("2026-08-03T18:01:00+09:00"),
                originalMessage: "other card",
                normalizedMessageHash: "other-hash",
                parseStatusRaw: ParseStatus.parsed.rawValue,
                kindRaw: "approval",
                cardLast4: "9999",
                amount: 2_500,
                month: 8,
                day: 3,
                hour: 18,
                minute: 0,
                merchant: "가맹점",
                parserVersion: "mg-card-message-v2",
                hasUserEdits: false
            ))
            try context.save()
        }

        let migratedContainer = try PersistenceController.makeModelContainer(url: storeURL)
        let context = ModelContext(migratedContainer)
        let record = try XCTUnwrap(try context.fetch(FetchDescriptor<TransactionRecord>()).first)

        XCTAssertFalse(record.hasKindOverride)
        XCTAssertFalse(record.hasAmountOverride)
        XCTAssertFalse(record.hasDateOverride)
        XCTAssertFalse(record.hasMerchantOverride)
        XCTAssertNil(record.card)
        XCTAssertEqual(record.kindRaw, "approval")
        XCTAssertEqual(record.amount, 2_500)
    }

    func testV1FailedAndCardlessTransactionsPreserveIdentityAndRawCapture() throws {
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        let failedID = UUID()
        let cardlessID = UUID()
        do {
            let v1Container = try PersistenceController.makeV1ModelContainer(url: storeURL)
            let context = ModelContext(v1Container)
            context.insert(CherryPickerSchemaV1.TransactionRecord(
                id: failedID,
                receivedAt: try makeDate("2026-08-03T18:01:00+09:00"),
                originalMessage: "지원하지 않는 원문",
                normalizedMessageHash: "failed-hash",
                parseStatusRaw: ParseStatus.failed.rawValue,
                parserVersion: "mg-card-message-v2",
                parseFailureReason: "unsupported",
                reviewStatusRaw: ReviewStatus.unreviewed.rawValue,
                performanceDecisionRaw: PerformanceDecision.undecided.rawValue,
                benefitDecisionRaw: BenefitDecision.undecided.rawValue,
                hasUserEdits: false
            ))
            context.insert(CherryPickerSchemaV1.TransactionRecord(
                id: cardlessID,
                receivedAt: try makeDate("2026-08-04T09:00:00+09:00"),
                originalMessage: "카드 번호 없는 원문",
                normalizedMessageHash: "cardless-hash",
                parseStatusRaw: ParseStatus.parsed.rawValue,
                kindRaw: "approval",
                amount: 1_000,
                month: 8,
                day: 4,
                merchant: "가맹점",
                parserVersion: "mg-card-message-v2",
                hasUserEdits: false
            ))
            try context.save()
        }

        let migratedContainer = try PersistenceController.makeModelContainer(url: storeURL)
        let records = try ModelContext(migratedContainer).fetch(FetchDescriptor<TransactionRecord>())

        XCTAssertEqual(records.count, 2)
        let failed = try XCTUnwrap(records.first(where: { $0.id == failedID }))
        XCTAssertEqual(failed.originalMessage, "지원하지 않는 원문")
        XCTAssertEqual(failed.normalizedMessageHash, "failed-hash")
        XCTAssertEqual(failed.parseStatusRaw, ParseStatus.failed.rawValue)
        XCTAssertEqual(failed.parseFailureReason, "unsupported")
        XCTAssertNil(failed.card)
        XCTAssertEqual(failed.hasUserEdits, false)

        let cardless = try XCTUnwrap(records.first(where: { $0.id == cardlessID }))
        XCTAssertEqual(cardless.originalMessage, "카드 번호 없는 원문")
        XCTAssertEqual(cardless.normalizedMessageHash, "cardless-hash")
        XCTAssertEqual(cardless.amount, 1_000)
        XCTAssertNil(cardless.parsedCardLastFour)
        XCTAssertNil(cardless.card)
        XCTAssertEqual(cardless.hasUserEdits, false)
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CherryPickerMigrationTests-\(UUID().uuidString)")
            .appendingPathExtension("store")
    }

    private func removeStoreFiles(at storeURL: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            try? fileManager.removeItem(atPath: storeURL.path + suffix)
        }
    }

    private func makeDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try XCTUnwrap(formatter.date(from: value))
    }
}
