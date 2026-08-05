import Foundation
import SwiftData
import XCTest

@testable import CherryPicker

final class CardStoreTests: XCTestCase {
    private func makeStore() throws -> (ModelContainer, CardStore) {
        let container = try PersistenceController.makeModelContainer(inMemory: true)
        return (container, CardStore(modelContainer: container))
    }

    func testDefaultCardSeedingIsIdempotent() async throws {
        let (container, store) = try makeStore()

        let first = try await store.seedDefaultCardIfNeeded()
        let second = try await store.seedDefaultCardIfNeeded()
        let cards = try ModelContext(container).fetch(FetchDescriptor<CardRecord>())

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(first.displayName, "MG 더나은 체크카드")
        XCTAssertEqual(first.issuerCode, "MG")
        XCTAssertEqual(first.lastFour, "4775")
        XCTAssertEqual(first.performanceTargetAmount, 300_000)
        XCTAssertEqual(first.periodRuleKindRaw, "calendarMonth")
        XCTAssertEqual(first.timeZoneIdentifier, "Asia/Seoul")
    }

    func testCardCanDisablePerformanceRequirementWithoutUsingZero() async throws {
        let (_, store) = try makeStore()
        let seeded = try await store.seedDefaultCardIfNeeded()

        let updated = try await store.save(CardSaveCommand(
            id: seeded.id,
            displayName: seeded.displayName,
            issuerCode: seeded.issuerCode,
            lastFour: seeded.lastFour,
            performanceTargetAmount: nil
        ))

        XCTAssertNil(updated.performanceTargetAmount)
    }

    func testCardRejectsZeroTargetAndMalformedFields() async throws {
        let (_, store) = try makeStore()

        await XCTAssertThrowsErrorAsync(try await store.save(CardSaveCommand(
            displayName: " ",
            issuerCode: "MG",
            lastFour: "4775",
            performanceTargetAmount: 300_000
        )))
        await XCTAssertThrowsErrorAsync(try await store.save(CardSaveCommand(
            displayName: "카드",
            issuerCode: "MG",
            lastFour: "47A5",
            performanceTargetAmount: 300_000
        )))
        await XCTAssertThrowsErrorAsync(try await store.save(CardSaveCommand(
            displayName: "카드",
            issuerCode: "MG",
            lastFour: "4775",
            performanceTargetAmount: 0
        )))
    }

    func testDuplicateIssuerAndLastFourIsRejected() async throws {
        let (_, store) = try makeStore()
        _ = try await store.seedDefaultCardIfNeeded()

        await XCTAssertThrowsErrorAsync(try await store.save(CardSaveCommand(
            displayName: "중복 카드",
            issuerCode: "mg",
            lastFour: "4775",
            performanceTargetAmount: nil
        ))) { error in
            XCTAssertEqual(error as? CardStoreError, .duplicateIssuerAndLastFour)
        }
    }

    func testChangingCardSuffixKeepsExistingTransactionRelationship() async throws {
        let (container, store) = try makeStore()
        let card = try await store.seedDefaultCardIfNeeded()
        let context = ModelContext(container)
        let cardRecord = try XCTUnwrap(try context.fetch(FetchDescriptor<CardRecord>()).first)
        let transaction = TransactionRecord(
            receivedAt: .now,
            originalMessage: "message",
            normalizedMessageHash: "hash",
            cardLast4: "4775"
        )
        transaction.card = cardRecord
        transaction.cardAssignmentSourceRaw = "automaticExactMatch"
        context.insert(transaction)
        try context.save()

        _ = try await store.save(CardSaveCommand(
            id: card.id,
            displayName: card.displayName,
            issuerCode: card.issuerCode,
            lastFour: "1234",
            performanceTargetAmount: card.performanceTargetAmount
        ))

        let refreshed = try XCTUnwrap(try context.fetch(FetchDescriptor<TransactionRecord>()).first)
        XCTAssertEqual(refreshed.card?.id, card.id)
    }

    func testCardSettingsPersistAfterClosingAndReopeningDiskStore() async throws {
        let storeURL = temporaryStoreURL()
        defer { removeStoreFiles(at: storeURL) }

        let cardID: UUID
        do {
            let container = try PersistenceController.makeModelContainer(url: storeURL)
            let store = CardStore(modelContainer: container)
            let seeded = try await store.seedDefaultCardIfNeeded()
            cardID = seeded.id
            _ = try await store.save(CardSaveCommand(
                id: seeded.id,
                displayName: "생활비 카드",
                issuerCode: "mg",
                lastFour: "4775",
                performanceTargetAmount: nil
            ))
        }

        do {
            let reopened = try PersistenceController.makeModelContainer(url: storeURL)
            let cards = try await CardStore(modelContainer: reopened).cards()

            XCTAssertEqual(cards.count, 1)
            let card = try XCTUnwrap(cards.first)
            XCTAssertEqual(card.id, cardID)
            XCTAssertEqual(card.displayName, "생활비 카드")
            XCTAssertEqual(card.issuerCode, "MG")
            XCTAssertEqual(card.lastFour, "4775")
            XCTAssertNil(card.performanceTargetAmount)
            XCTAssertEqual(card.periodRuleKindRaw, "calendarMonth")
            XCTAssertEqual(card.timeZoneIdentifier, "Asia/Seoul")
        }
    }

    func testDeletingCardNullifiesRelationshipWithoutDeletingTransaction() async throws {
        let (container, store) = try makeStore()
        let card = try await store.seedDefaultCardIfNeeded()
        let context = ModelContext(container)
        let cardRecord = try XCTUnwrap(try context.fetch(FetchDescriptor<CardRecord>()).first)
        let transactionID = UUID()
        let transaction = TransactionRecord(
            id: transactionID,
            receivedAt: .now,
            originalMessage: "message",
            normalizedMessageHash: "hash",
            cardLast4: "4775"
        )
        transaction.card = cardRecord
        context.insert(transaction)
        try context.save()

        try await store.delete(id: card.id)

        let records = try context.fetch(FetchDescriptor<TransactionRecord>())
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, transactionID)
        XCTAssertNil(records.first?.card)
    }

    func testRegisteringCardBackfillsOnlyExactUnassignedTransactions() async throws {
        let (container, store) = try makeStore()
        let context = ModelContext(container)
        let matchingID = UUID()
        let unmatchedID = UUID()
        context.insert(TransactionRecord(
            id: matchingID,
            receivedAt: .now,
            originalMessage: "matching",
            normalizedMessageHash: "matching-hash",
            cardLast4: "4775"
        ))
        context.insert(TransactionRecord(
            id: unmatchedID,
            receivedAt: .now,
            originalMessage: "unmatched",
            normalizedMessageHash: "unmatched-hash",
            cardLast4: "9999"
        ))
        try context.save()

        let card = try await store.save(CardSaveCommand(
            displayName: "MG 더나은 체크카드",
            issuerCode: "MG",
            lastFour: "4775",
            performanceTargetAmount: 300_000
        ))

        let records = try context.fetch(FetchDescriptor<TransactionRecord>())
        let matching = try XCTUnwrap(records.first(where: { $0.id == matchingID }))
        let unmatched = try XCTUnwrap(records.first(where: { $0.id == unmatchedID }))
        XCTAssertEqual(matching.card?.id, card.id)
        XCTAssertEqual(matching.cardAssignmentSourceRaw, "backfillExactMatch")
        XCTAssertNil(unmatched.card)
        XCTAssertNil(unmatched.cardAssignmentSourceRaw)
    }

    private func temporaryStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CherryPickerCardStoreTests-\(UUID().uuidString)")
            .appendingPathExtension("store")
    }

    private func removeStoreFiles(at storeURL: URL) {
        let fileManager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            try? fileManager.removeItem(atPath: storeURL.path + suffix)
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
