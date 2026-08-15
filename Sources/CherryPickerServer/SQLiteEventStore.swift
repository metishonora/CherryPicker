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
    private let connection: SQLiteConnection
    private let parser: MGCardMessageParser

    public init(
        databaseURL: URL,
        parser: MGCardMessageParser = MGCardMessageParser()
    ) throws {
        self.parser = parser

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
        try Self.configureAndCreateSchema(database: opened)
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
            let parseResult = parser.parse(event.originalMessage)
            try updateTransaction(id: transactionID, parseResult: parseResult)
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

    // MARK: - Schema and transaction boundaries

    private static func configureAndCreateSchema(database: OpaquePointer) throws {
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
            CREATE INDEX IF NOT EXISTS idx_transactions_fingerprint_captured_at
            ON canonical_transactions(fingerprint, captured_at)
            """, database: database)
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
