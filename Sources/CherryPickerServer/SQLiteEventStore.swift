import CryptoKit
import Foundation
import SQLite3
import CherryPickerCore

/// Errors raised for local database failures. No error includes an event body,
/// request payload, or identity value.
public enum SQLiteEventStoreError: Error, Equatable, Sendable {
    case unableToOpenDatabase(String)
    case schema(String)
    case statement(String)
    case bind(String)
    case transaction(String)
    case invalidStoredValue(String)
}

public enum ManagementStoreError: Error, Equatable, Sendable {
    case invalidInput
}

private let sqliteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)

private final class SQLiteConnection: @unchecked Sendable {
    let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        sqlite3_close(pointer)
    }
}

/// Actor-isolated, disk-backed event and canonical-transaction store.
public actor SQLiteEventStore {
    private static let defaultCardID = UUID(uuidString: "00000000-0000-0000-0000-000000004775")!

    private let connection: SQLiteConnection
    private let cardTypes: [any CardTypeDefining]
    private let defaultCardType: any CardTypeDefining

    public init(databaseURL: URL) throws {
        try self.init(
            databaseURL: databaseURL,
            cardTypes: [MGTheBetterCheckCardDefinition(), MGPlusSHanaCardDefinition()],
            defaultCardType: MGTheBetterCheckCardDefinition()
        )
    }

    public init(databaseURL: URL, cardType: any CardTypeDefining) throws {
        try self.init(
            databaseURL: databaseURL,
            cardTypes: [cardType],
            defaultCardType: cardType
        )
    }

    private init(
        databaseURL: URL,
        cardTypes: [any CardTypeDefining],
        defaultCardType: any CardTypeDefining
    ) throws {
        precondition(!cardTypes.isEmpty)
        precondition(Set(cardTypes.map(\.code)).count == cardTypes.count)
        precondition(cardTypes.contains { $0.code == defaultCardType.code })
        self.cardTypes = cardTypes
        self.defaultCardType = defaultCardType

        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(databaseURL.path, &opened, flags, nil)
        guard openResult == SQLITE_OK, let opened else {
            let reason = opened.map { String(cString: sqlite3_errmsg($0)) }
                ?? "sqlite3_open_v2 returned \(openResult)"
            if let opened { sqlite3_close(opened) }
            throw SQLiteEventStoreError.unableToOpenDatabase(reason)
        }
        let connection = SQLiteConnection(pointer: opened)
        self.connection = connection
        try Self.configureAndCreateSchema(database: opened, cardType: defaultCardType)
        try Self.ensureBenefitDefinitions(database: opened, cardTypes: cardTypes)
    }

    // MARK: - Ingestion

    public func ingest(_ event: OutboxEvent) throws -> SyncItemResult {
        guard event.schemaVersion == OutboxEvent.currentSchemaVersion else {
            return SyncItemResult(
                eventId: event.eventId,
                status: .rejected,
                rejectionReason: .unsupportedSchemaVersion
            )
        }
        guard !event.originalMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return SyncItemResult(
                eventId: event.eventId,
                status: .rejected,
                rejectionReason: .emptyOriginalMessage
            )
        }

        try beginTransaction()
        do {
            // The event_id primary key is the transport idempotency boundary.
            // Check it before parsing so an exact retry returns promptly even
            // if parser rules have changed since the original write.
            if let existingReceipt = try fetchReceipt(eventId: event.eventId) {
                try commitTransaction()
                return SyncItemResult(
                    eventId: event.eventId,
                    status: .duplicate,
                    disposition: existingReceipt.disposition,
                    transactionID: existingReceipt.transactionID
                )
            }

            let fingerprint = normalizedFingerprint(for: event.originalMessage)
            if let existingTransactionID = try fetchTransactionID(
                fingerprint: fingerprint,
                capturedAt: event.capturedAt
            ) {
                try insertReceipt(
                    eventId: event.eventId,
                    transactionID: existingTransactionID,
                    capturedAt: event.capturedAt,
                    status: .accepted,
                    disposition: .transactionDuplicate,
                    rejectionReason: nil
                )
                try commitTransaction()
                return SyncItemResult(
                    eventId: event.eventId,
                    status: .accepted,
                    disposition: .transactionDuplicate,
                    transactionID: existingTransactionID
                )
            }

            // Keep the raw event and its pending status in the same SQLite
            // transaction before invoking parsing. If the process disappears
            // during parsing, the pending row and eventual receipt roll back
            // together, so the outbox item is retried rather than acked.
            let transactionID = UUID()
            try insertPendingTransaction(
                id: transactionID,
                event: event,
                fingerprint: fingerprint
            )
            let routed = route(message: event.originalMessage)
            let parseResult = routed.parseResult
            try updateTransaction(id: transactionID, parseResult: parseResult)
            try assignCard(
                transactionID: transactionID,
                parseResult: parseResult,
                cardType: routed.cardType
            )
            let disposition: SyncDisposition
            if case .success = parseResult {
                disposition = .stored
            } else {
                disposition = .parseFailed
            }
            try insertReceipt(
                eventId: event.eventId,
                transactionID: transactionID,
                capturedAt: event.capturedAt,
                status: .accepted,
                disposition: disposition,
                rejectionReason: nil
            )
            try commitTransaction()
            return SyncItemResult(
                eventId: event.eventId,
                status: .accepted,
                disposition: disposition,
                transactionID: transactionID
            )
        } catch {
            rollbackTransaction()
            throw error
        }
    }

    // MARK: - Read-only inspection used by tests and the product status page

    public func receiptCount() -> Int {
        (try? scalarInt(sql: "SELECT COUNT(*) FROM event_receipts")) ?? 0
    }

    public func transactionCount() -> Int {
        (try? scalarInt(sql: "SELECT COUNT(*) FROM canonical_transactions")) ?? 0
    }

    public func transaction(id: UUID) -> StoredTransaction? {
        try? transactionValue(id: id)
    }

    /// Return only fields approved for the authenticated report surface.
    ///
    /// This query deliberately omits `original_message`, `card_last4`, and
    /// `account_balance` from the SELECT list.  Keeping the redaction at the
    /// persistence boundary prevents a future HTTP handler from accidentally
    /// serializing the canonical row in full.
    public func safeTransactions() throws -> [SafeTransaction] {
        let statement = try prepare("""
            SELECT id, captured_at, parse_status,
                   transaction_kind, amount, merchant
            FROM canonical_transactions
            ORDER BY captured_at DESC, id DESC
            """)
        defer { sqlite3_finalize(statement) }

        var values: [SafeTransaction] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE {
                break
            }
            guard stepResult == SQLITE_ROW else {
                throw SQLiteEventStoreError.statement(lastSQLiteMessage())
            }

            guard
                let idText = columnString(statement, at: 0),
                let id = UUID(uuidString: idText),
                let statusText = columnString(statement, at: 2),
                let parseStatus = StoredParseStatus(rawValue: statusText)
            else {
                throw SQLiteEventStoreError.invalidStoredValue("safe transaction")
            }

            let kind = parseStatus == .parsed
                ? columnString(statement, at: 3)
                : "review-needed"
            let amount = nullableInt(statement, at: 4)
            let merchant = columnString(statement, at: 5)
            values.append(
                SafeTransaction(
                    id: id,
                    capturedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                    parseStatus: parseStatus,
                    summary: SafeTransactionSummary(
                        kind: kind,
                        amount: amount,
                        merchant: merchant,
                        reviewNeeded: parseStatus != .parsed
                    )
                )
            )
        }
        return values
    }

    /// Return only receipt metadata approved for the authenticated sync report.
    /// Rejection reasons are intentionally omitted from this query.
    public func safeEventReceipts() throws -> [SafeEventReceipt] {
        let statement = try prepare("""
            SELECT event_id, transaction_id, captured_at, status, disposition
            FROM event_receipts
            ORDER BY captured_at DESC, event_id DESC
            """)
        defer { sqlite3_finalize(statement) }

        var values: [SafeEventReceipt] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE {
                break
            }
            guard stepResult == SQLITE_ROW else {
                throw SQLiteEventStoreError.statement(lastSQLiteMessage())
            }

            guard
                let eventText = columnString(statement, at: 0),
                let eventID = UUID(uuidString: eventText),
                let transactionText = columnString(statement, at: 1),
                let transactionID = UUID(uuidString: transactionText),
                let statusText = columnString(statement, at: 3),
                let status = SyncItemStatus(rawValue: statusText)
            else {
                throw SQLiteEventStoreError.invalidStoredValue("safe event receipt")
            }

            values.append(
                SafeEventReceipt(
                    eventId: eventID,
                    transactionID: transactionID,
                    capturedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
                    status: status,
                    disposition: columnString(statement, at: 4).flatMap(SyncDisposition.init(rawValue:))
                )
            )
        }
        return values
    }

    // MARK: - Product management surface

    public func managedCards() throws -> [ManagedCard] {
        let statement = try prepare("""
            SELECT id, card_type_code, display_name, last_four, performance_target_amount
            FROM cards
            ORDER BY created_at ASC, id ASC
            """)
        defer { sqlite3_finalize(statement) }

        var cards: [ManagedCard] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw SQLiteEventStoreError.statement(lastSQLiteMessage())
            }
            cards.append(try decodeCard(from: statement))
        }
        return cards
    }

    public func managedCard(id: UUID) throws -> ManagedCard? {
        let statement = try prepare("""
            SELECT id, card_type_code, display_name, last_four, performance_target_amount
            FROM cards
            WHERE id = ?
            LIMIT 1
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(id.uuidString, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try decodeCard(from: statement)
    }

    public func createManagedCard(request: CardCreateRequest) throws -> ManagedCard {
        let displayName = request.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastFour = request.lastFour.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let cardType = cardType(code: request.cardTypeCode),
            !displayName.isEmpty,
            lastFour.count == 4,
            lastFour.allSatisfy(\.isNumber)
        else {
            throw ManagementStoreError.invalidInput
        }

        let existingStatement = try prepare("""
            SELECT 1 FROM cards
            WHERE card_type_code = ? AND last_four = ?
            LIMIT 1
            """)
        defer { sqlite3_finalize(existingStatement) }
        try bindText(cardType.code, to: existingStatement, at: 1)
        try bindText(lastFour, to: existingStatement, at: 2)
        let existingResult = sqlite3_step(existingStatement)
        if existingResult == SQLITE_ROW {
            throw ManagementStoreError.invalidInput
        }
        guard existingResult == SQLITE_DONE else {
            throw SQLiteEventStoreError.statement(lastSQLiteMessage())
        }

        let id = UUID()
        try beginTransaction()
        do {
            let statement = try prepare("""
                INSERT INTO cards (
                    id, card_type_code, display_name, issuer_code, last_four,
                    performance_target_amount, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(statement) }
            try bindText(id.uuidString, to: statement, at: 1)
            try bindText(cardType.code, to: statement, at: 2)
            try bindText(displayName, to: statement, at: 3)
            try bindText(cardType.issuerCode, to: statement, at: 4)
            try bindText(lastFour, to: statement, at: 5)
            try bindInt(cardType.legacyMonthlyPerformanceTargetAmount, to: statement, at: 6)
            try bindDouble(Date().timeIntervalSince1970, to: statement, at: 7)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteEventStoreError.statement(lastSQLiteMessage())
            }

            for (sortOrder, benefit) in cardType.benefits.enumerated() {
                try Self.upsertCardBenefit(
                    database: connection.pointer,
                    cardID: id,
                    benefit: benefit,
                    sortOrder: sortOrder
                )
            }
            for (sortOrder, label) in cardType.performanceExclusions.enumerated() {
                try Self.insertCardExclusion(
                    database: connection.pointer,
                    cardID: id,
                    kind: "performance",
                    label: label,
                    sortOrder: sortOrder
                )
            }
            for (sortOrder, label) in cardType.benefitExclusions.enumerated() {
                try Self.insertCardExclusion(
                    database: connection.pointer,
                    cardID: id,
                    kind: "benefit",
                    label: label,
                    sortOrder: sortOrder
                )
            }
            try commitTransaction()
        } catch {
            rollbackTransaction()
            throw error
        }
        guard let card = try managedCard(id: id) else {
            throw SQLiteEventStoreError.invalidStoredValue("created card")
        }
        return card
    }

    public func updateManagedCard(
        id: UUID,
        request: CardUpdateRequest
    ) throws -> ManagedCard? {
        let displayName = request.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastFour = request.lastFour.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !displayName.isEmpty,
            lastFour.count == 4,
            lastFour.allSatisfy(\.isNumber)
        else {
            throw ManagementStoreError.invalidInput
        }

        let statement = try prepare("""
            UPDATE cards
            SET display_name = ?, last_four = ?
            WHERE id = ?
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(displayName, to: statement, at: 1)
        try bindText(lastFour, to: statement, at: 2)
        try bindText(id.uuidString, to: statement, at: 3)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteEventStoreError.statement(lastSQLiteMessage())
        }
        guard sqlite3_changes(connection.pointer) > 0 else { return nil }
        return try managedCard(id: id)
    }

    public func monthlyOffsets(cardID: UUID, month: DashboardMonth) throws -> MonthlyOffsets? {
        guard let card = try managedCard(id: cardID) else { return nil }

        let performanceStatement = try prepare("""
            SELECT performance_offset_amount
            FROM card_month_offsets
            WHERE card_id = ? AND month = ?
            LIMIT 1
            """)
        defer { sqlite3_finalize(performanceStatement) }
        try bindText(cardID.uuidString, to: performanceStatement, at: 1)
        try bindText(month.identifier, to: performanceStatement, at: 2)
        let performanceResult = sqlite3_step(performanceStatement)
        let performanceOffsetAmount: Int
        if performanceResult == SQLITE_ROW {
            performanceOffsetAmount = Int(sqlite3_column_int64(performanceStatement, 0))
        } else if performanceResult == SQLITE_DONE {
            performanceOffsetAmount = 0
        } else {
            throw SQLiteEventStoreError.statement(lastSQLiteMessage())
        }

        let benefitStatement = try prepare("""
            SELECT benefit_id, offset_amount
            FROM card_benefit_offsets
            WHERE card_id = ? AND month = ?
            """)
        defer { sqlite3_finalize(benefitStatement) }
        try bindText(cardID.uuidString, to: benefitStatement, at: 1)
        try bindText(month.identifier, to: benefitStatement, at: 2)
        var storedBenefitOffsets: [UUID: Int] = [:]
        while true {
            let result = sqlite3_step(benefitStatement)
            if result == SQLITE_DONE { break }
            guard
                result == SQLITE_ROW,
                let benefitIDText = columnString(benefitStatement, at: 0),
                let benefitID = UUID(uuidString: benefitIDText)
            else {
                throw SQLiteEventStoreError.invalidStoredValue("monthly benefit offset")
            }
            storedBenefitOffsets[benefitID] = Int(sqlite3_column_int64(benefitStatement, 1))
        }

        return MonthlyOffsets(
            cardId: cardID,
            period: month.identifier,
            performanceOffsetAmount: performanceOffsetAmount,
            benefitOffsets: card.benefits.map {
                BenefitOffset(
                    benefitId: $0.id,
                    offsetAmount: storedBenefitOffsets[$0.id, default: 0]
                )
            }
        )
    }

    public func updateMonthlyOffsets(
        cardID: UUID,
        month: DashboardMonth,
        request: MonthlyOffsetsUpdateRequest
    ) throws -> MonthlyOffsets? {
        guard let card = try managedCard(id: cardID) else { return nil }
        let requestedBenefitIDs = request.benefitOffsets.map(\.benefitId)
        let allowedBenefitIDs = Set(card.benefits.map(\.id))
        guard
            Set(requestedBenefitIDs).count == requestedBenefitIDs.count,
            requestedBenefitIDs.allSatisfy(allowedBenefitIDs.contains)
        else {
            throw ManagementStoreError.invalidInput
        }

        try beginTransaction()
        do {
            let performanceStatement = try prepare("""
                INSERT INTO card_month_offsets (card_id, month, performance_offset_amount)
                VALUES (?, ?, ?)
                ON CONFLICT(card_id, month) DO UPDATE SET
                    performance_offset_amount = excluded.performance_offset_amount
                """)
            defer { sqlite3_finalize(performanceStatement) }
            try bindText(cardID.uuidString, to: performanceStatement, at: 1)
            try bindText(month.identifier, to: performanceStatement, at: 2)
            try bindInt(request.performanceOffsetAmount, to: performanceStatement, at: 3)
            guard sqlite3_step(performanceStatement) == SQLITE_DONE else {
                throw SQLiteEventStoreError.statement(lastSQLiteMessage())
            }

            let deleteStatement = try prepare("""
                DELETE FROM card_benefit_offsets
                WHERE card_id = ? AND month = ?
                """)
            defer { sqlite3_finalize(deleteStatement) }
            try bindText(cardID.uuidString, to: deleteStatement, at: 1)
            try bindText(month.identifier, to: deleteStatement, at: 2)
            guard sqlite3_step(deleteStatement) == SQLITE_DONE else {
                throw SQLiteEventStoreError.statement(lastSQLiteMessage())
            }

            for benefitOffset in request.benefitOffsets where benefitOffset.offsetAmount != 0 {
                let insertStatement = try prepare("""
                    INSERT INTO card_benefit_offsets (
                        card_id, month, benefit_id, offset_amount
                    ) VALUES (?, ?, ?, ?)
                    """)
                defer { sqlite3_finalize(insertStatement) }
                try bindText(cardID.uuidString, to: insertStatement, at: 1)
                try bindText(month.identifier, to: insertStatement, at: 2)
                try bindText(benefitOffset.benefitId.uuidString, to: insertStatement, at: 3)
                try bindInt(benefitOffset.offsetAmount, to: insertStatement, at: 4)
                guard sqlite3_step(insertStatement) == SQLITE_DONE else {
                    throw SQLiteEventStoreError.statement(lastSQLiteMessage())
                }
            }
            try commitTransaction()
        } catch {
            rollbackTransaction()
            throw error
        }
        return try monthlyOffsets(cardID: cardID, month: month)
    }

    public func managedTransactions(
        scope: String? = nil,
        cardID: UUID? = nil,
        filter: String? = nil,
        period: DateInterval? = nil
    ) throws -> [ManagedTransaction] {
        var clauses: [String] = []
        var bindings: [String] = []

        if scope == "unreviewed" {
            clauses.append("tr.transaction_id IS NULL")
        } else if scope != nil {
            throw ManagementStoreError.invalidInput
        }
        if let cardID {
            clauses.append("tc.card_id = ?")
            bindings.append(cardID.uuidString)
        }
        switch filter {
        case nil, "all":
            break
        case "approval", "cancellation":
            clauses.append("ct.transaction_kind = ?")
            clauses.append("COALESCE(tr.aggregation_excluded, 0) = 0")
            bindings.append(filter!)
        case "excluded":
            clauses.append("COALESCE(tr.aggregation_excluded, 0) = 1")
        default:
            throw ManagementStoreError.invalidInput
        }

        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let statement = try prepare("""
            SELECT ct.id, tc.card_id, c.display_name, c.last_four,
                   ct.captured_at, ct.month, ct.day, ct.hour, ct.minute,
                   ct.parse_status, ct.transaction_kind, ct.amount, ct.merchant,
                   tr.transaction_id, tr.performance, tr.memo,
                   COALESCE(tr.aggregation_excluded, 0)
            FROM canonical_transactions ct
            LEFT JOIN transaction_cards tc ON tc.transaction_id = ct.id
            LEFT JOIN cards c ON c.id = tc.card_id
            LEFT JOIN transaction_reviews tr ON tr.transaction_id = ct.id
            \(whereClause)
            ORDER BY ct.captured_at DESC, ct.id DESC
            """)
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bindings.enumerated() {
            try bindText(value, to: statement, at: Int32(offset + 1))
        }
        let transactions = try decodeManagedTransactions(from: statement)
        guard let period else { return transactions }
        return transactions
            .filter { $0.occurredAt >= period.start && $0.occurredAt < period.end }
            .sorted {
                if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
                if $0.capturedAt != $1.capturedAt { return $0.capturedAt > $1.capturedAt }
                return $0.id.uuidString > $1.id.uuidString
            }
    }

    public func managedTransaction(id: UUID) throws -> ManagedTransaction? {
        let statement = try prepare("""
            SELECT ct.id, tc.card_id, c.display_name, c.last_four,
                   ct.captured_at, ct.month, ct.day, ct.hour, ct.minute,
                   ct.parse_status, ct.transaction_kind, ct.amount, ct.merchant,
                   tr.transaction_id, tr.performance, tr.memo,
                   COALESCE(tr.aggregation_excluded, 0)
            FROM canonical_transactions ct
            LEFT JOIN transaction_cards tc ON tc.transaction_id = ct.id
            LEFT JOIN cards c ON c.id = tc.card_id
            LEFT JOIN transaction_reviews tr ON tr.transaction_id = ct.id
            WHERE ct.id = ?
            LIMIT 1
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(id.uuidString, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try decodeManagedTransaction(from: statement)
    }

    public func reviewTransaction(
        id: UUID,
        request: TransactionUpdateRequest
    ) throws -> ManagedTransaction? {
        guard let transaction = try managedTransaction(id: id) else { return nil }
        guard let assignedCardID = transaction.cardId else {
            throw ManagementStoreError.invalidInput
        }

        let performance: PerformanceDecision?
        let benefitIDs: [UUID]
        if request.aggregationExcluded {
            performance = nil
            benefitIDs = []
        } else {
            performance = request.review.performance
            guard performance != nil else {
                throw ManagementStoreError.invalidInput
            }
            benefitIDs = Array(Set(request.review.benefitIds))
            let allowedBenefitIDs = Set(
                try managedCard(id: assignedCardID)?.benefits.map(\.id) ?? []
            )
            guard benefitIDs.allSatisfy(allowedBenefitIDs.contains) else {
                throw ManagementStoreError.invalidInput
            }
        }

        try beginTransaction()
        do {
            let reviewStatement = try prepare("""
                INSERT INTO transaction_reviews (
                    transaction_id, performance, memo, aggregation_excluded, reviewed_at
                ) VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(transaction_id) DO UPDATE SET
                    performance = excluded.performance,
                    memo = excluded.memo,
                    aggregation_excluded = excluded.aggregation_excluded,
                    reviewed_at = excluded.reviewed_at
                """)
            defer { sqlite3_finalize(reviewStatement) }
            try bindText(id.uuidString, to: reviewStatement, at: 1)
            try bindOptionalText(performance?.rawValue, to: reviewStatement, at: 2)
            try bindText(request.review.memo, to: reviewStatement, at: 3)
            try bindInt(request.aggregationExcluded ? 1 : 0, to: reviewStatement, at: 4)
            try bindDouble(Date().timeIntervalSince1970, to: reviewStatement, at: 5)
            guard sqlite3_step(reviewStatement) == SQLITE_DONE else {
                throw SQLiteEventStoreError.statement(lastSQLiteMessage())
            }

            let deleteStatement = try prepare(
                "DELETE FROM transaction_benefits WHERE transaction_id = ?"
            )
            defer { sqlite3_finalize(deleteStatement) }
            try bindText(id.uuidString, to: deleteStatement, at: 1)
            guard sqlite3_step(deleteStatement) == SQLITE_DONE else {
                throw SQLiteEventStoreError.statement(lastSQLiteMessage())
            }

            for benefitID in benefitIDs {
                let insertStatement = try prepare("""
                    INSERT INTO transaction_benefits (transaction_id, benefit_id)
                    VALUES (?, ?)
                    """)
                defer { sqlite3_finalize(insertStatement) }
                try bindText(id.uuidString, to: insertStatement, at: 1)
                try bindText(benefitID.uuidString, to: insertStatement, at: 2)
                guard sqlite3_step(insertStatement) == SQLITE_DONE else {
                    throw SQLiteEventStoreError.statement(lastSQLiteMessage())
                }
            }
            try commitTransaction()
        } catch {
            rollbackTransaction()
            throw error
        }
        return try managedTransaction(id: id)
    }

    public func dashboard(cardID: UUID, month: DashboardMonth) throws -> CardDashboard? {
        guard let card = try managedCard(id: cardID) else { return nil }
        let previousMonth = try month.previous
        let previousCalculation = try monthlyCalculation(
            card: card,
            month: previousMonth,
            benefitDefinitions: []
        )
        let previousMonthPerformance = previousCalculation.performance.currentAmount

        let effectiveBenefits: [DashboardBenefitDefinition]
        let benefitLimit: DashboardBenefitLimit
        switch card.benefitLimitPolicy.type {
        case .perBenefit:
            effectiveBenefits = card.benefits.map { benefit in
                let eligible = previousMonthPerformance >=
                    (benefit.requiredPreviousMonthPerformanceAmount ?? 0)
                return DashboardBenefitDefinition(
                    id: benefit.id,
                    rateBasisPoints: benefit.rateBasisPoints,
                    maximumAmount: eligible ? benefit.maximumAmount : 0
                )
            }
            benefitLimit = DashboardBenefitLimit(
                type: .perBenefit,
                maximumAmount: nil,
                receivedAmount: nil,
                remainingAmount: nil
            )
        case .integrated:
            effectiveBenefits = card.benefits.map {
                DashboardBenefitDefinition(
                    id: $0.id,
                    rateBasisPoints: $0.rateBasisPoints,
                    maximumAmount: nil
                )
            }
            benefitLimit = DashboardBenefitLimit(
                type: .integrated,
                maximumAmount: 0,
                receivedAmount: 0,
                remainingAmount: 0
            )
        }

        let calculation = try monthlyCalculation(
            card: card,
            month: month,
            benefitDefinitions: effectiveBenefits
        )
        let resolvedLimit: DashboardBenefitLimit
        if card.benefitLimitPolicy.type == .integrated {
            let maximum = card.benefitLimitPolicy.tiers?
                .filter { previousMonthPerformance >= $0.minimumPreviousMonthPerformanceAmount }
                .max { $0.minimumPreviousMonthPerformanceAmount < $1.minimumPreviousMonthPerformanceAmount }?
                .maximumAmount ?? 0
            let received = max(0, min(maximum, calculation.benefits.reduce(0) {
                $0 + $1.calculationAmount
            }))
            resolvedLimit = DashboardBenefitLimit(
                type: .integrated,
                maximumAmount: maximum,
                receivedAmount: received,
                remainingAmount: max(0, maximum - received)
            )
        } else {
            resolvedLimit = benefitLimit
        }

        let progress = card.benefits.map { benefit in
            let value = calculation.benefits.first { $0.id == benefit.id }
            return BenefitProgress(
                id: benefit.id,
                label: benefit.label,
                calculationAmount: value?.calculationAmount ?? 0,
                receivedAmount: value?.receivedAmount ?? 0,
                maximumAmount: effectiveBenefits.first { $0.id == benefit.id }?.maximumAmount
            )
        }
        let performanceTarget = card.performanceThresholdAmounts
            .first { calculation.performance.currentAmount < $0 }
            ?? card.performanceThresholdAmounts.last
            ?? 1
        return CardDashboard(
            cardId: card.id,
            period: month.identifier,
            performance: PerformanceProgress(
                currentAmount: calculation.performance.currentAmount,
                targetAmount: performanceTarget,
                remainingAmount: max(
                    0,
                    performanceTarget - calculation.performance.currentAmount
                ),
                excludedAmount: calculation.performance.excludedAmount,
                unconfirmedAmount: calculation.performance.unconfirmedAmount,
                unconfirmedCount: calculation.performance.unconfirmedCount
            ),
            benefitLimit: resolvedLimit,
            benefits: progress,
            benefitUnconfirmedCount: calculation.benefitUnconfirmedCount
        )
    }

    private func monthlyCalculation(
        card: ManagedCard,
        month: DashboardMonth,
        benefitDefinitions: [DashboardBenefitDefinition]
    ) throws -> MonthlyDashboardCalculation {
        let period = try month.interval
        let transactions = try managedTransactions(cardID: card.id, period: period)
        let offsets = try monthlyOffsets(cardID: card.id, month: month)
        return MonthlyDashboardCalculator().calculate(
            period: period,
            benefits: benefitDefinitions,
            transactions: transactions.map {
                DashboardTransactionInput(
                    occurredAt: $0.occurredAt,
                    isReviewed: $0.reviewStatus == .reviewed,
                    aggregationExcluded: $0.aggregationExcluded,
                    kind: $0.kind == "cancellation" ? .cancellation :
                        $0.kind == "approval" ? .approval : nil,
                    amount: $0.amount,
                    performance: $0.performance == .included ? .included :
                        $0.performance == .excluded ? .excluded : nil,
                    benefitIDs: Set($0.benefitIds)
                )
            },
            performanceOffsetAmount: offsets?.performanceOffsetAmount ?? 0,
            benefitOffsetAmounts: Dictionary(
                uniqueKeysWithValues: offsets?.benefitOffsets.map {
                    ($0.benefitId, $0.offsetAmount)
                } ?? []
            )
        )
    }

    private func decodeCard(from statement: OpaquePointer) throws -> ManagedCard {
        guard
            let idText = columnString(statement, at: 0),
            let id = UUID(uuidString: idText),
            let cardTypeCode = columnString(statement, at: 1),
            let cardType = cardType(code: cardTypeCode),
            let displayName = columnString(statement, at: 2),
            let lastFour = columnString(statement, at: 3)
        else {
            throw SQLiteEventStoreError.invalidStoredValue("managed card")
        }
        return ManagedCard(
            id: id,
            cardTypeCode: cardTypeCode,
            displayName: displayName,
            issuerCode: cardType.issuerCode,
            lastFour: lastFour,
            performanceThresholdAmounts: cardType.performanceThresholdAmounts,
            benefitLimitPolicy: benefitLimitPolicy(for: cardType),
            performanceCalculationBasis: cardType.performanceCalculationBasis,
            benefits: benefits(cardTypeCode: cardTypeCode),
            performanceExclusions: cardType.performanceExclusions,
            benefitExclusions: cardType.benefitExclusions
        )
    }

    private func benefits(cardTypeCode: String) -> [CardBenefit] {
        guard let cardType = cardType(code: cardTypeCode) else { return [] }
        return cardType.benefits.map {
            CardBenefit(
                id: $0.id,
                label: $0.label,
                eligibleMerchants: $0.eligibleMerchants,
                minimumTransactionAmount: $0.minimumTransactionAmount,
                requiredPreviousMonthPerformanceAmount: $0.requiredPreviousMonthPerformanceAmount,
                rateBasisPoints: $0.rateBasisPoints,
                maximumAmount: $0.monthlyMaximumAmount,
                recurringPaymentOnly: $0.recurringPaymentOnly,
                exclusionNotes: $0.exclusionNotes
            )
        }
    }

    private func benefitLimitPolicy(for cardType: any CardTypeDefining) -> BenefitLimitPolicy {
        switch cardType.benefitLimitPolicy {
        case .perBenefit:
            return BenefitLimitPolicy(type: .perBenefit, tiers: nil)
        case .integrated(let tiers):
            return BenefitLimitPolicy(
                type: .integrated,
                tiers: tiers.map {
                    BenefitLimitTier(
                        minimumPreviousMonthPerformanceAmount:
                            $0.minimumPreviousMonthPerformanceAmount,
                        maximumAmount: $0.maximumAmount
                    )
                }
            )
        }
    }

    private func cardType(code: String) -> (any CardTypeDefining)? {
        cardTypes.first { $0.code == code }
    }

    private func decodeManagedTransactions(
        from statement: OpaquePointer
    ) throws -> [ManagedTransaction] {
        var values: [ManagedTransaction] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw SQLiteEventStoreError.statement(lastSQLiteMessage())
            }
            values.append(try decodeManagedTransaction(from: statement))
        }
        return values
    }

    private func decodeManagedTransaction(
        from statement: OpaquePointer
    ) throws -> ManagedTransaction {
        guard
            let idText = columnString(statement, at: 0),
            let id = UUID(uuidString: idText),
            let parseStatusText = columnString(statement, at: 9),
            let parseStatus = StoredParseStatus(rawValue: parseStatusText)
        else {
            throw SQLiteEventStoreError.invalidStoredValue("managed transaction")
        }
        let cardID = columnString(statement, at: 1).flatMap(UUID.init(uuidString:))
        let cardDisplayName = columnString(statement, at: 2)
        let cardLastFour = columnString(statement, at: 3)
        let capturedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
        let occurredAt = resolvedOccurredAt(
            capturedAt: capturedAt,
            month: nullableInt(statement, at: 5),
            day: nullableInt(statement, at: 6),
            hour: nullableInt(statement, at: 7),
            minute: nullableInt(statement, at: 8)
        )
        let reviewStatus: TransactionReviewStatus = columnString(statement, at: 13) == nil
            ? .unreviewed
            : .reviewed
        return ManagedTransaction(
            id: id,
            cardId: cardID,
            cardDisplayName: cardDisplayName,
            cardLastFour: cardLastFour,
            capturedAt: capturedAt,
            occurredAt: occurredAt,
            parseStatus: parseStatus,
            reviewStatus: reviewStatus,
            kind: columnString(statement, at: 10),
            amount: nullableInt(statement, at: 11),
            merchant: columnString(statement, at: 12),
            performance: columnString(statement, at: 14).flatMap(PerformanceDecision.init(rawValue:)),
            benefitIds: try benefitIDs(transactionID: id),
            memo: columnString(statement, at: 15) ?? "",
            aggregationExcluded: sqlite3_column_int64(statement, 16) != 0
        )
    }

    private func resolvedOccurredAt(
        capturedAt: Date,
        month: Int?,
        day: Int?,
        hour: Int?,
        minute: Int?
    ) -> Date {
        guard
            let month,
            let day,
            let partial = try? ParsedLocalDate(
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                timeZoneIdentifier: "Asia/Seoul"
            ),
            let resolved = try? DefaultTransactionDateResolver().resolve(
                partial,
                receivedAt: capturedAt
            )
        else {
            return capturedAt
        }
        return resolved.instant
    }

    private func benefitIDs(transactionID: UUID) throws -> [UUID] {
        let statement = try prepare("""
            SELECT benefit_id
            FROM transaction_benefits
            WHERE transaction_id = ?
            ORDER BY benefit_id ASC
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(transactionID.uuidString, to: statement, at: 1)
        var values: [UUID] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard
                result == SQLITE_ROW,
                let value = columnString(statement, at: 0),
                let id = UUID(uuidString: value)
            else {
                throw SQLiteEventStoreError.invalidStoredValue("transaction benefit")
            }
            values.append(id)
        }
        return values
    }

    private func transactionValue(id: UUID) throws -> StoredTransaction? {
        let statement = try prepare("""
            SELECT id, captured_at, original_message, parse_status,
                   transaction_kind, card_last4, amount, month, day, hour,
                   minute, merchant, account_balance, parser_version,
                   failure_kind, failure_reason
            FROM canonical_transactions
            WHERE id = ?
            LIMIT 1
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(id.uuidString, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try decodeTransaction(from: statement)
    }

    public func receipt(for eventId: UUID) -> StoredEventReceipt? {
        try? fetchReceipt(eventId: eventId)
    }

    private func route(
        message: String
    ) -> (cardType: (any CardTypeDefining)?, parseResult: ParseResult) {
        let matches = cardTypes.filter { $0.identifies(messageBody: message) }
        guard matches.count == 1, let cardType = matches.first else {
            let reason = matches.isEmpty
                ? "No card type identified the message."
                : "More than one card type identified the message."
            return (
                nil,
                .unsupported(ParseFailure(
                    kind: .unsupported,
                    originalMessage: message,
                    reason: reason,
                    parserVersion: "card-message-router-v1"
                ))
            )
        }
        return (cardType, cardType.parse(message))
    }

    // MARK: - Schema and transaction boundaries

    private static func configureAndCreateSchema(
        database: OpaquePointer,
        cardType: any CardTypeDefining
    ) throws {
        try execute("PRAGMA foreign_keys = ON", database: database)
        try execute("PRAGMA busy_timeout = 5000", database: database)
        try execute("PRAGMA journal_mode = WAL", database: database)
        try execute("PRAGMA synchronous = FULL", database: database)
        try execute("""
            CREATE TABLE IF NOT EXISTS canonical_transactions (
                id TEXT PRIMARY KEY NOT NULL,
                fingerprint TEXT NOT NULL,
                captured_at REAL NOT NULL,
                original_message TEXT NOT NULL,
                parse_status TEXT NOT NULL,
                transaction_kind TEXT,
                card_last4 TEXT,
                amount INTEGER,
                month INTEGER,
                day INTEGER,
                hour INTEGER,
                minute INTEGER,
                merchant TEXT,
                account_balance INTEGER,
                parser_version TEXT,
                failure_kind TEXT,
                failure_reason TEXT
            )
            """, database: database)
        try execute("""
            CREATE TABLE IF NOT EXISTS event_receipts (
                event_id TEXT PRIMARY KEY NOT NULL,
                transaction_id TEXT NOT NULL,
                captured_at REAL NOT NULL,
                status TEXT NOT NULL,
                disposition TEXT,
                rejection_reason TEXT,
                FOREIGN KEY(transaction_id) REFERENCES canonical_transactions(id)
            )
            """, database: database)
        try execute("""
            CREATE TABLE IF NOT EXISTS cards (
                id TEXT PRIMARY KEY NOT NULL,
                card_type_code TEXT NOT NULL,
                display_name TEXT NOT NULL,
                issuer_code TEXT NOT NULL,
                last_four TEXT NOT NULL,
                performance_target_amount INTEGER NOT NULL,
                created_at REAL NOT NULL
            )
            """, database: database)
        try ensureColumn(
            table: "cards",
            column: "card_type_code",
            definition: "TEXT NOT NULL DEFAULT \(sqlLiteral(cardType.code))",
            database: database
        )
        try execute("DROP INDEX IF EXISTS idx_cards_last_four", database: database)
        try execute("""
            CREATE UNIQUE INDEX IF NOT EXISTS idx_cards_type_last_four
            ON cards(card_type_code, last_four)
            """, database: database)
        try execute("""
            CREATE TABLE IF NOT EXISTS card_benefits (
                id TEXT PRIMARY KEY NOT NULL,
                card_id TEXT NOT NULL,
                label TEXT NOT NULL,
                rate_basis_points INTEGER NOT NULL,
                maximum_amount INTEGER NOT NULL,
                sort_order INTEGER NOT NULL,
                FOREIGN KEY(card_id) REFERENCES cards(id) ON DELETE CASCADE
            )
            """, database: database)
        try execute("""
            CREATE TABLE IF NOT EXISTS card_exclusions (
                card_id TEXT NOT NULL,
                kind TEXT NOT NULL CHECK(kind IN ('performance', 'benefit')),
                label TEXT NOT NULL,
                sort_order INTEGER NOT NULL,
                PRIMARY KEY(card_id, kind, sort_order),
                FOREIGN KEY(card_id) REFERENCES cards(id) ON DELETE CASCADE
            )
            """, database: database)
        try execute("""
            CREATE TABLE IF NOT EXISTS card_month_offsets (
                card_id TEXT NOT NULL,
                month TEXT NOT NULL,
                performance_offset_amount INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY(card_id, month),
                FOREIGN KEY(card_id) REFERENCES cards(id) ON DELETE CASCADE
            )
            """, database: database)
        try execute("""
            CREATE TABLE IF NOT EXISTS card_benefit_offsets (
                card_id TEXT NOT NULL,
                month TEXT NOT NULL,
                benefit_id TEXT NOT NULL,
                offset_amount INTEGER NOT NULL,
                PRIMARY KEY(card_id, month, benefit_id),
                FOREIGN KEY(card_id, month)
                    REFERENCES card_month_offsets(card_id, month) ON DELETE CASCADE,
                FOREIGN KEY(benefit_id) REFERENCES card_benefits(id)
            )
            """, database: database)
        try execute("""
            CREATE TABLE IF NOT EXISTS transaction_cards (
                transaction_id TEXT PRIMARY KEY NOT NULL,
                card_id TEXT NOT NULL,
                FOREIGN KEY(transaction_id) REFERENCES canonical_transactions(id) ON DELETE CASCADE,
                FOREIGN KEY(card_id) REFERENCES cards(id)
            )
            """, database: database)
        try execute("""
            CREATE TABLE IF NOT EXISTS transaction_reviews (
                transaction_id TEXT PRIMARY KEY NOT NULL,
                performance TEXT,
                memo TEXT NOT NULL DEFAULT '',
                aggregation_excluded INTEGER NOT NULL DEFAULT 0,
                reviewed_at REAL NOT NULL,
                FOREIGN KEY(transaction_id) REFERENCES canonical_transactions(id) ON DELETE CASCADE
            )
            """, database: database)
        try execute("""
            CREATE TABLE IF NOT EXISTS transaction_benefits (
                transaction_id TEXT NOT NULL,
                benefit_id TEXT NOT NULL,
                PRIMARY KEY(transaction_id, benefit_id),
                FOREIGN KEY(transaction_id) REFERENCES canonical_transactions(id) ON DELETE CASCADE,
                FOREIGN KEY(benefit_id) REFERENCES card_benefits(id)
            )
            """, database: database)
        try execute("""
            INSERT OR IGNORE INTO cards (
                id, card_type_code, display_name, issuer_code, last_four,
                performance_target_amount, created_at
            ) VALUES (
                '\(defaultCardID.uuidString)', \(sqlLiteral(cardType.code)),
                \(sqlLiteral(cardType.displayName)), \(sqlLiteral(cardType.issuerCode)), '4775',
                \(cardType.legacyMonthlyPerformanceTargetAmount), 0
            )
            """, database: database)
        for (sortOrder, benefit) in cardType.benefits.enumerated() {
            try upsertCardBenefit(
                database: database,
                cardID: defaultCardID,
                benefit: benefit,
                sortOrder: sortOrder
            )
        }
        for (sortOrder, label) in cardType.performanceExclusions.enumerated() {
            try insertCardExclusion(
                database: database,
                cardID: defaultCardID,
                kind: "performance",
                label: label,
                sortOrder: sortOrder
            )
        }
        for (sortOrder, label) in cardType.benefitExclusions.enumerated() {
            try insertCardExclusion(
                database: database,
                cardID: defaultCardID,
                kind: "benefit",
                label: label,
                sortOrder: sortOrder
            )
        }
        try execute("""
            INSERT OR IGNORE INTO transaction_cards (transaction_id, card_id)
            SELECT ct.id, c.id
            FROM canonical_transactions ct
            JOIN cards c
              ON c.last_four = ct.card_last4
             AND c.card_type_code = \(sqlLiteral(cardType.code))
            WHERE ct.parse_status = 'parsed'
            """, database: database)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_transactions_fingerprint_captured_at
            ON canonical_transactions(fingerprint, captured_at)
            """, database: database)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_transaction_cards_card_id
            ON transaction_cards(card_id)
            """, database: database)
        try execute("""
            CREATE INDEX IF NOT EXISTS idx_cards_card_type_code
            ON cards(card_type_code)
            """, database: database)
        try execute("PRAGMA optimize", database: database)
    }

    private static func insertCardExclusion(
        database: OpaquePointer,
        cardID: UUID,
        kind: String,
        label: String,
        sortOrder: Int
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            """
            INSERT OR IGNORE INTO card_exclusions (card_id, kind, label, sort_order)
            VALUES (?, ?, ?, ?)
            """,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw SQLiteEventStoreError.schema(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        let cardIDResult = cardID.uuidString.withCString {
            sqlite3_bind_text(statement, 1, $0, -1, sqliteTransient)
        }
        let kindResult = kind.withCString {
            sqlite3_bind_text(statement, 2, $0, -1, sqliteTransient)
        }
        let labelResult = label.withCString {
            sqlite3_bind_text(statement, 3, $0, -1, sqliteTransient)
        }
        guard
            cardIDResult == SQLITE_OK,
            kindResult == SQLITE_OK,
            labelResult == SQLITE_OK,
            sqlite3_bind_int64(statement, 4, sqlite3_int64(sortOrder)) == SQLITE_OK,
            sqlite3_step(statement) == SQLITE_DONE
        else {
            throw SQLiteEventStoreError.schema(String(cString: sqlite3_errmsg(database)))
        }
    }

    private static func upsertCardBenefit(
        database: OpaquePointer,
        cardID: UUID,
        benefit: CardTypeBenefitDefinition,
        sortOrder: Int
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            """
            INSERT INTO card_benefits (
                id, card_id, label, rate_basis_points, maximum_amount, sort_order
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                card_id = excluded.card_id,
                label = excluded.label,
                rate_basis_points = excluded.rate_basis_points,
                maximum_amount = excluded.maximum_amount,
                sort_order = excluded.sort_order
            """,
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw SQLiteEventStoreError.schema(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        let values = [benefit.id.uuidString, cardID.uuidString, benefit.label]
        for (offset, value) in values.enumerated() {
            let result = value.withCString {
                sqlite3_bind_text(statement, Int32(offset + 1), $0, -1, sqliteTransient)
            }
            guard result == SQLITE_OK else {
                throw SQLiteEventStoreError.schema(String(cString: sqlite3_errmsg(database)))
            }
        }
        guard
            sqlite3_bind_int64(statement, 4, sqlite3_int64(benefit.rateBasisPoints)) == SQLITE_OK,
            sqlite3_bind_int64(statement, 5, sqlite3_int64(benefit.monthlyMaximumAmount ?? 0)) == SQLITE_OK,
            sqlite3_bind_int64(statement, 6, sqlite3_int64(sortOrder)) == SQLITE_OK,
            sqlite3_step(statement) == SQLITE_DONE
        else {
            throw SQLiteEventStoreError.schema(String(cString: sqlite3_errmsg(database)))
        }
    }

    /// Backfills definition rows for cards created before their benefit policy
    /// was available. The rows exist to satisfy review/offset foreign keys;
    /// current labels and terms are always read from the card-type registry.
    private static func ensureBenefitDefinitions(
        database: OpaquePointer,
        cardTypes: [any CardTypeDefining]
    ) throws {
        for cardType in cardTypes where !cardType.benefits.isEmpty {
            var cardStatement: OpaquePointer?
            guard sqlite3_prepare_v2(
                database,
                "SELECT id FROM cards WHERE card_type_code = ? ORDER BY created_at ASC LIMIT 1",
                -1,
                &cardStatement,
                nil
            ) == SQLITE_OK, let cardStatement else {
                throw SQLiteEventStoreError.schema(String(cString: sqlite3_errmsg(database)))
            }
            defer { sqlite3_finalize(cardStatement) }
            let typeBind = cardType.code.withCString {
                sqlite3_bind_text(cardStatement, 1, $0, -1, sqliteTransient)
            }
            guard typeBind == SQLITE_OK else {
                throw SQLiteEventStoreError.schema(String(cString: sqlite3_errmsg(database)))
            }
            guard
                sqlite3_step(cardStatement) == SQLITE_ROW,
                let cardIDBytes = sqlite3_column_text(cardStatement, 0),
                let cardIDText = String(
                    validatingCString: UnsafeRawPointer(cardIDBytes)
                        .assumingMemoryBound(to: CChar.self)
                ),
                let cardID = UUID(uuidString: cardIDText)
            else { continue }

            for (sortOrder, benefit) in cardType.benefits.enumerated() {
                var benefitStatement: OpaquePointer?
                guard sqlite3_prepare_v2(
                    database,
                    "SELECT 1 FROM card_benefits WHERE id = ? LIMIT 1",
                    -1,
                    &benefitStatement,
                    nil
                ) == SQLITE_OK, let benefitStatement else {
                    throw SQLiteEventStoreError.schema(String(cString: sqlite3_errmsg(database)))
                }
                let benefitBind = benefit.id.uuidString.withCString {
                    sqlite3_bind_text(benefitStatement, 1, $0, -1, sqliteTransient)
                }
                guard benefitBind == SQLITE_OK else {
                    sqlite3_finalize(benefitStatement)
                    throw SQLiteEventStoreError.schema(String(cString: sqlite3_errmsg(database)))
                }
                let exists = sqlite3_step(benefitStatement) == SQLITE_ROW
                sqlite3_finalize(benefitStatement)
                if !exists {
                    try upsertCardBenefit(
                        database: database,
                        cardID: cardID,
                        benefit: benefit,
                        sortOrder: sortOrder
                    )
                }
            }
        }
    }

    private static func ensureColumn(
        table: String,
        column: String,
        definition: String,
        database: OpaquePointer
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "PRAGMA table_info(\(table))",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw SQLiteEventStoreError.schema(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: name) == column { return }
        }
        try execute(
            "ALTER TABLE \(table) ADD COLUMN \(column) \(definition)",
            database: database
        )
    }

    private static func sqlLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func beginTransaction() throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
    }

    private func commitTransaction() throws {
        do {
            try execute("COMMIT TRANSACTION")
        } catch {
            rollbackTransaction()
            throw SQLiteEventStoreError.transaction(errorMessage(for: error))
        }
    }

    private func rollbackTransaction() {
        try? execute("ROLLBACK TRANSACTION")
    }

    // MARK: - Writes and reads

    private func insertPendingTransaction(
        id: UUID,
        event: OutboxEvent,
        fingerprint: String
    ) throws {
        let statement = try prepare("""
            INSERT INTO canonical_transactions (
                id, fingerprint, captured_at, original_message, parse_status,
                transaction_kind, card_last4, amount, month, day, hour,
                minute, merchant, account_balance, parser_version,
                failure_kind, failure_reason
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }

        try bindText(id.uuidString, to: statement, at: 1)
        try bindText(fingerprint, to: statement, at: 2)
        try bindDouble(event.capturedAt.timeIntervalSince1970, to: statement, at: 3)
        try bindText(event.originalMessage, to: statement, at: 4)
        try bindText(StoredParseStatus.pending.rawValue, to: statement, at: 5)
        for index in 6...17 {
            try bindNull(to: statement, at: Int32(index))
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteEventStoreError.statement(lastSQLiteMessage())
        }
    }

    private func updateTransaction(id: UUID, parseResult: ParseResult) throws {
        let statement = try prepare("""
            UPDATE canonical_transactions
            SET parse_status = ?, transaction_kind = ?, card_last4 = ?,
                amount = ?, month = ?, day = ?, hour = ?, minute = ?,
                merchant = ?, account_balance = ?, parser_version = ?,
                failure_kind = ?, failure_reason = ?
            WHERE id = ?
            """)
        defer { sqlite3_finalize(statement) }

        switch parseResult {
        case let .success(transaction):
            try bindText(StoredParseStatus.parsed.rawValue, to: statement, at: 1)
            try bindText(transaction.kind.rawValue, to: statement, at: 2)
            try bindText(transaction.cardLast4, to: statement, at: 3)
            try bindInt(transaction.amount, to: statement, at: 4)
            try bindInt(transaction.month, to: statement, at: 5)
            try bindInt(transaction.day, to: statement, at: 6)
            try bindOptionalInt(transaction.hour, to: statement, at: 7)
            try bindOptionalInt(transaction.minute, to: statement, at: 8)
            try bindText(transaction.merchant, to: statement, at: 9)
            try bindOptionalInt(transaction.accountBalance, to: statement, at: 10)
            try bindText(transaction.parserVersion, to: statement, at: 11)
            try bindNull(to: statement, at: 12)
            try bindNull(to: statement, at: 13)
        case let .unsupported(failure), let .failed(failure):
            try bindText(StoredParseStatus.failed.rawValue, to: statement, at: 1)
            for index in 2...10 {
                try bindNull(to: statement, at: Int32(index))
            }
            try bindText(failure.parserVersion, to: statement, at: 11)
            try bindText(failure.kind.rawValue, to: statement, at: 12)
            try bindText(failure.reason, to: statement, at: 13)
        }
        try bindText(id.uuidString, to: statement, at: 14)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteEventStoreError.statement(lastSQLiteMessage())
        }
    }

    private func assignCard(
        transactionID: UUID,
        parseResult: ParseResult,
        cardType: (any CardTypeDefining)?
    ) throws {
        guard
            let cardType,
            case let .success(transaction) = parseResult
        else {
            return
        }

        let cardStatement = try prepare("""
            SELECT id, last_four FROM cards
            WHERE card_type_code = ?
            ORDER BY id ASC
            """)
        defer { sqlite3_finalize(cardStatement) }
        try bindText(cardType.code, to: cardStatement, at: 1)
        var matchingCardIDs: [UUID] = []
        while true {
            let result = sqlite3_step(cardStatement)
            if result == SQLITE_DONE { break }
            guard
                result == SQLITE_ROW,
                let idText = columnString(cardStatement, at: 0),
                let id = UUID(uuidString: idText),
                let lastFour = columnString(cardStatement, at: 1)
            else {
                throw SQLiteEventStoreError.invalidStoredValue("card assignment candidate")
            }
            if cardType.matches(
                parsedCardIdentifier: transaction.cardLast4,
                storedLastFour: lastFour
            ) {
                matchingCardIDs.append(id)
            }
        }
        guard matchingCardIDs.count == 1, let cardID = matchingCardIDs.first else {
            return
        }

        let statement = try prepare("""
            INSERT OR REPLACE INTO transaction_cards (transaction_id, card_id)
            VALUES (?, ?)
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(transactionID.uuidString, to: statement, at: 1)
        try bindText(cardID.uuidString, to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteEventStoreError.statement(lastSQLiteMessage())
        }
    }

    private func insertReceipt(
        eventId: UUID,
        transactionID: UUID,
        capturedAt: Date,
        status: SyncItemStatus,
        disposition: SyncDisposition?,
        rejectionReason: SyncRejectionReason?
    ) throws {
        let statement = try prepare("""
            INSERT INTO event_receipts (
                event_id, transaction_id, captured_at, status,
                disposition, rejection_reason
            ) VALUES (?, ?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(eventId.uuidString, to: statement, at: 1)
        try bindText(transactionID.uuidString, to: statement, at: 2)
        try bindDouble(capturedAt.timeIntervalSince1970, to: statement, at: 3)
        try bindText(status.rawValue, to: statement, at: 4)
        try bindOptionalText(disposition?.rawValue, to: statement, at: 5)
        try bindOptionalText(rejectionReason?.rawValue, to: statement, at: 6)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteEventStoreError.statement(lastSQLiteMessage())
        }
    }

    private func fetchTransactionID(
        fingerprint: String,
        capturedAt: Date
    ) throws -> UUID? {
        let statement = try prepare("""
            SELECT id
            FROM canonical_transactions
            WHERE fingerprint = ?
              AND ABS(captured_at - ?) <= 600.0
            ORDER BY ABS(captured_at - ?) ASC, id ASC
            LIMIT 1
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(fingerprint, to: statement, at: 1)
        let timestamp = capturedAt.timeIntervalSince1970
        try bindDouble(timestamp, to: statement, at: 2)
        try bindDouble(timestamp, to: statement, at: 3)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        guard let value = columnString(statement, at: 0), let id = UUID(uuidString: value) else {
            throw SQLiteEventStoreError.invalidStoredValue("transaction id")
        }
        return id
    }

    private func fetchReceipt(eventId: UUID) throws -> StoredEventReceipt? {
        let statement = try prepare("""
            SELECT event_id, transaction_id, captured_at, status,
                   disposition, rejection_reason
            FROM event_receipts
            WHERE event_id = ?
            LIMIT 1
            """)
        defer { sqlite3_finalize(statement) }
        try bindText(eventId.uuidString, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        guard
            let eventText = columnString(statement, at: 0),
            let storedEventID = UUID(uuidString: eventText),
            let transactionText = columnString(statement, at: 1),
            let transactionID = UUID(uuidString: transactionText),
            let statusText = columnString(statement, at: 3),
            let status = SyncItemStatus(rawValue: statusText)
        else {
            throw SQLiteEventStoreError.invalidStoredValue("event receipt")
        }
        let capturedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        let disposition = columnString(statement, at: 4).flatMap(SyncDisposition.init(rawValue:))
        let rejectionReason = columnString(statement, at: 5).flatMap(SyncRejectionReason.init(rawValue:))
        return StoredEventReceipt(
            eventId: storedEventID,
            transactionID: transactionID,
            capturedAt: capturedAt,
            status: status,
            disposition: disposition,
            rejectionReason: rejectionReason
        )
    }

    private func decodeTransaction(from statement: OpaquePointer) throws -> StoredTransaction {
        guard
            let idText = columnString(statement, at: 0),
            let id = UUID(uuidString: idText),
            let statusText = columnString(statement, at: 3),
            let parseStatus = StoredParseStatus(rawValue: statusText),
            let originalMessage = columnString(statement, at: 2)
        else {
            throw SQLiteEventStoreError.invalidStoredValue("canonical transaction")
        }

        let capturedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        let parsedTransaction: ParsedTransaction?
        let parseFailure: ParseFailure?
        switch parseStatus {
        case .parsed:
            guard
                let kindText = columnString(statement, at: 4),
                let kind = TransactionKind(rawValue: kindText),
                let cardLast4 = columnString(statement, at: 5),
                let merchant = columnString(statement, at: 11),
                let parserVersion = columnString(statement, at: 13)
            else {
                throw SQLiteEventStoreError.invalidStoredValue("parsed transaction")
            }
            parsedTransaction = ParsedTransaction(
                kind: kind,
                cardLast4: cardLast4,
                amount: Int(sqlite3_column_int64(statement, 6)),
                month: Int(sqlite3_column_int64(statement, 7)),
                day: Int(sqlite3_column_int64(statement, 8)),
                hour: nullableInt(statement, at: 9),
                minute: nullableInt(statement, at: 10),
                merchant: merchant,
                accountBalance: nullableInt(statement, at: 12),
                parserVersion: parserVersion,
                originalMessage: originalMessage
            )
            parseFailure = nil
        case .failed:
            guard
                let kindText = columnString(statement, at: 14),
                let kind = ParseFailure.Kind(rawValue: kindText),
                let reason = columnString(statement, at: 15),
                let parserVersion = columnString(statement, at: 13)
            else {
                throw SQLiteEventStoreError.invalidStoredValue("parse failure")
            }
            parsedTransaction = nil
            parseFailure = ParseFailure(
                kind: kind,
                originalMessage: originalMessage,
                reason: reason,
                parserVersion: parserVersion
            )
        case .pending:
            parsedTransaction = nil
            parseFailure = nil
        }

        return StoredTransaction(
            id: id,
            capturedAt: capturedAt,
            originalMessage: originalMessage,
            parseStatus: parseStatus,
            parsedTransaction: parsedTransaction,
            parseFailure: parseFailure
        )
    }

    // MARK: - SQLite primitives

    private static func execute(_ sql: String, database: OpaquePointer) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorPointer)
        defer {
            if let errorPointer {
                sqlite3_free(errorPointer)
            }
        }
        guard result == SQLITE_OK else {
            let message: String
            if let errorPointer {
                message = String(cString: errorPointer)
            } else {
                message = "sqlite3_exec returned \(result)"
            }
            throw SQLiteEventStoreError.schema(message)
        }
    }

    private func execute(_ sql: String) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteEventStoreError.schema(lastSQLiteMessage())
        }
    }

    private func scalarInt(sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteEventStoreError.statement(lastSQLiteMessage())
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        let database = connection.pointer
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteEventStoreError.statement(lastSQLiteMessage())
        }
        return statement
    }

    private func bindText(_ value: String, to statement: OpaquePointer, at index: Int32) throws {
        let bytes = Array(value.utf8)
        let result = bytes.withUnsafeBytes { rawBuffer in
            let pointer = rawBuffer.bindMemory(to: CChar.self).baseAddress
            return sqlite3_bind_text(
                statement,
                index,
                pointer,
                Int32(bytes.count),
                sqliteTransient
            )
        }
        guard result == SQLITE_OK else {
            throw SQLiteEventStoreError.bind(lastSQLiteMessage())
        }
    }

    private func bindOptionalText(_ value: String?, to statement: OpaquePointer, at index: Int32) throws {
        if let value {
            try bindText(value, to: statement, at: index)
        } else {
            try bindNull(to: statement, at: index)
        }
    }

    private func bindInt(_ value: Int, to statement: OpaquePointer, at index: Int32) throws {
        guard sqlite3_bind_int64(statement, index, Int64(value)) == SQLITE_OK else {
            throw SQLiteEventStoreError.bind(lastSQLiteMessage())
        }
    }

    private func bindOptionalInt(_ value: Int?, to statement: OpaquePointer, at index: Int32) throws {
        if let value {
            try bindInt(value, to: statement, at: index)
        } else {
            try bindNull(to: statement, at: index)
        }
    }

    private func bindDouble(_ value: Double, to statement: OpaquePointer, at index: Int32) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
            throw SQLiteEventStoreError.bind(lastSQLiteMessage())
        }
    }

    private func bindNull(to statement: OpaquePointer, at index: Int32) throws {
        guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
            throw SQLiteEventStoreError.bind(lastSQLiteMessage())
        }
    }

    private func columnString(_ statement: OpaquePointer, at index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func nullableInt(_ statement: OpaquePointer, at index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int64(statement, index))
    }

    private func lastSQLiteMessage() -> String {
        String(cString: sqlite3_errmsg(connection.pointer))
    }

    private func errorMessage(for error: Error) -> String {
        if let sqliteError = error as? SQLiteEventStoreError {
            switch sqliteError {
            case let .unableToOpenDatabase(message), let .schema(message),
                 let .statement(message), let .bind(message),
                 let .transaction(message), let .invalidStoredValue(message):
                return message
            }
        }
        return "database operation failed"
    }
}

private func normalizedFingerprint(for originalMessage: String) -> String {
    let normalizedLines = originalMessage
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    let normalized = normalizedLines.joined(separator: "\n")
    let digest = SHA256.hash(data: Data(normalized.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}
