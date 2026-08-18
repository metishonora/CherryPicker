import Foundation
import SQLite3
import XCTest
@testable import CherryPickerCore
@testable import CherryPickerServer

final class CardTypeDefinitionPersistenceTests: XCTestCase {
    func testOwnedCardReferencesDefinitionAndConsumesItsPolicy() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }
        let definition = MGTheBetterCheckCardDefinition()
        let store = try SQLiteEventStore(databaseURL: databaseURL, cardType: definition)

        let cards = try await store.managedCards()
        let card = try XCTUnwrap(cards.first)

        XCTAssertEqual(card.cardTypeCode, definition.code)
        XCTAssertEqual(card.issuerCode, definition.issuerCode)
        XCTAssertEqual(card.performanceTargetAmount, definition.defaultMonthlyPerformanceTargetAmount)
        XCTAssertEqual(card.performanceCalculationBasis, "‘더나은’ 정상 이용금액")
        XCTAssertEqual(card.benefits.map(\.label), definition.benefits.map(\.label))
        XCTAssertEqual(card.benefits.count, 3)
        XCTAssertTrue(card.benefits.allSatisfy { $0.rateBasisPoints == 2_000 })
        XCTAssertTrue(card.benefits.allSatisfy { $0.maximumAmount == 6_000 })
        XCTAssertEqual(card.benefits.first?.minimumTransactionAmount, 10_000)
        XCTAssertEqual(card.benefits.last?.minimumTransactionAmount, 5_000)
        XCTAssertEqual(card.benefits.first?.requiredPreviousMonthPerformanceAmount, 300_000)
        XCTAssertEqual(
            card.benefits.first?.eligibleMerchants,
            ["네이버페이", "카카오페이", "페이코"]
        )
    }

    func testOwnedCardUpdateCannotMutateCardTypeIdentity() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }
        let definition = MGTheBetterCheckCardDefinition()
        let store = try SQLiteEventStore(databaseURL: databaseURL, cardType: definition)
        let cards = try await store.managedCards()
        let original = try XCTUnwrap(cards.first)

        let updated = try await store.updateManagedCard(
            id: original.id,
            request: CardUpdateRequest(
                displayName: "생활비 카드",
                issuerCode: "MUTATION-MUST-NOT-WIN",
                lastFour: "1234",
                performanceTargetAmount: 350_000
            )
        )

        XCTAssertEqual(updated?.displayName, "생활비 카드")
        XCTAssertEqual(updated?.lastFour, "1234")
        XCTAssertEqual(updated?.performanceTargetAmount, 350_000)
        XCTAssertEqual(updated?.cardTypeCode, definition.code)
        XCTAssertEqual(updated?.issuerCode, definition.issuerCode)
    }

    func testIngestionUsesParserOwnedByCardDefinition() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }
        let definition = MGTheBetterCheckCardDefinition(
            parser: MGCardMessageParser(parserVersion: "definition-owned-parser")
        )
        let store = try SQLiteEventStore(databaseURL: databaseURL, cardType: definition)
        let event = OutboxEvent(
            schemaVersion: OutboxEvent.currentSchemaVersion,
            eventId: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            originalMessage: "[Web발신] MG카드(4775)체크승인 2,500원 08/03 18:00 네이버페이"
        )

        let result = try await store.ingest(event)
        let transactionID = try XCTUnwrap(result.transactionID)
        let storedTransaction = await store.transaction(id: transactionID)
        let transaction = try XCTUnwrap(storedTransaction)

        XCTAssertEqual(transaction.parsedTransaction?.parserVersion, "definition-owned-parser")
    }

    func testOpeningLegacyCardsTableAddsTypeReferenceAndPreservesInstanceValues() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        let legacyCardID = "00000000-0000-0000-0000-000000004775"
        let sql = """
        CREATE TABLE cards (
            id TEXT PRIMARY KEY NOT NULL,
            display_name TEXT NOT NULL,
            issuer_code TEXT NOT NULL,
            last_four TEXT NOT NULL,
            performance_target_amount INTEGER NOT NULL,
            created_at REAL NOT NULL
        );
        INSERT INTO cards VALUES (
            '\(legacyCardID)', '기존 사용자 이름', '사용자가 바꾼 값', '9876', 420000, 0
        );
        """
        XCTAssertEqual(sqlite3_exec(database, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)

        let store = try SQLiteEventStore(databaseURL: databaseURL)
        let cards = try await store.managedCards()
        let card = try XCTUnwrap(cards.first(where: { $0.id.uuidString == legacyCardID }))

        XCTAssertEqual(card.cardTypeCode, MGTheBetterCheckCardDefinition().code)
        XCTAssertEqual(card.displayName, "기존 사용자 이름")
        XCTAssertEqual(card.issuerCode, "MG")
        XCTAssertEqual(card.lastFour, "9876")
        XCTAssertEqual(card.performanceTargetAmount, 420_000)
    }

    private func temporaryDatabaseURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CherryPicker-CardTypeTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("store.sqlite")
    }
}
