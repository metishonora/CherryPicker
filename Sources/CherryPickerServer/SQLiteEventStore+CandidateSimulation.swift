import Foundation
import SQLite3
import CherryPickerCore

private let candidateSQLiteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
)

extension SQLiteEventStore {
    /// Build the import template from canonical facts only. No product review,
    /// card assignment, benefit assignment, or aggregation exclusion is read.
    public func candidateSimulationTemplate(
        month: DashboardMonth
    ) throws -> CandidateSimulationTemplateResponse {
        let database = candidateSimulationDatabase
        var statement: OpaquePointer?
        let sql = """
            SELECT id, captured_at, parse_status, transaction_kind, amount,
                   month, day, hour, minute, merchant
            FROM canonical_transactions
            ORDER BY captured_at ASC, id ASC
            """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw candidateStatementError(database)
        }
        defer { sqlite3_finalize(statement) }

        let period = try month.interval
        var transactions: [CandidateSimulationSourceTransaction] = []
        var cancellationCount = 0
        var otherCount = 0

        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else {
                throw candidateStatementError(database)
            }

            guard
                let idText = candidateColumnString(statement, at: 0),
                let id = UUID(uuidString: idText),
                let status = candidateColumnString(statement, at: 2)
            else {
                throw SQLiteEventStoreError.invalidStoredValue(
                    "candidate simulation source transaction"
                )
            }
            let capturedAt = Date(
                timeIntervalSince1970: sqlite3_column_double(statement, 1)
            )
            let occurredAt = candidateOccurredAt(
                capturedAt: capturedAt,
                month: candidateNullableInt(statement, at: 5),
                day: candidateNullableInt(statement, at: 6),
                hour: candidateNullableInt(statement, at: 7),
                minute: candidateNullableInt(statement, at: 8)
            )
            guard occurredAt >= period.start, occurredAt < period.end else {
                continue
            }

            guard status == StoredParseStatus.parsed.rawValue else {
                otherCount += 1
                continue
            }
            switch candidateColumnString(statement, at: 3) {
            case TransactionKind.cancellation.rawValue:
                cancellationCount += 1
            case TransactionKind.approval.rawValue:
                guard
                    let amount = candidateNullableInt(statement, at: 4),
                    amount > 0,
                    let merchant = candidateColumnString(statement, at: 9),
                    !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    otherCount += 1
                    continue
                }
                transactions.append(
                    CandidateSimulationSourceTransaction(
                        id: id,
                        occurredAt: occurredAt,
                        amount: amount,
                        merchant: merchant
                    )
                )
            default:
                otherCount += 1
            }
        }

        transactions.sort {
            if $0.occurredAt != $1.occurredAt {
                return $0.occurredAt < $1.occurredAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        return CandidateSimulationTemplateResponse(
            analysisMonth: month.identifier,
            transactions: transactions,
            excluded: CandidateSimulationExclusionCounts(
                cancellations: cancellationCount,
                other: otherCount
            )
        )
    }

    func currentCandidateSimulationDraft() throws -> StoredCandidateSimulationDraft? {
        let database = candidateSimulationDatabase
        var statement: OpaquePointer?
        let sql = """
            SELECT d.id, d.policy_snapshot_id, p.schema_version, p.policy_json,
                   d.analysis_month, d.calculator_version, d.input_json,
                   d.state_json, d.excluded_cancellation_count,
                   d.excluded_other_count, d.created_at, d.updated_at
            FROM candidate_card_simulation_drafts d
            JOIN candidate_card_policy_snapshots p ON p.id = d.policy_snapshot_id
            WHERE d.active = 1
            LIMIT 1
            """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw candidateStatementError(database)
        }
        defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else {
            throw candidateStatementError(database)
        }
        return try decodeCandidateDraft(statement)
    }

    @discardableResult
    func replaceCandidateSimulationDraft(
        draftID: UUID,
        policySnapshotID: UUID,
        policySchemaVersion: Int,
        policyJSON: Data,
        month: DashboardMonth,
        calculatorVersion: String,
        inputJSON: Data,
        stateJSON: Data,
        excluded: CandidateSimulationExclusionCounts,
        now: Date = Date()
    ) throws -> StoredCandidateSimulationDraft {
        guard
            policySchemaVersion > 0,
            !policyJSON.isEmpty,
            !calculatorVersion.isEmpty,
            !inputJSON.isEmpty,
            !stateJSON.isEmpty,
            excluded.cancellations >= 0,
            excluded.other >= 0
        else {
            throw ManagementStoreError.invalidInput
        }

        let database = candidateSimulationDatabase
        try candidateExecute("BEGIN IMMEDIATE TRANSACTION", database: database)
        do {
            try insertOrVerifyPolicySnapshot(
                id: policySnapshotID,
                schemaVersion: policySchemaVersion,
                policyJSON: policyJSON,
                createdAt: now,
                database: database
            )
            try candidateExecute(
                "UPDATE candidate_card_simulation_drafts SET active = 0 WHERE active = 1",
                database: database
            )

            var statement: OpaquePointer?
            let sql = """
                INSERT INTO candidate_card_simulation_drafts (
                    id, policy_snapshot_id, analysis_month, calculator_version,
                    input_json, state_json, excluded_cancellation_count,
                    excluded_other_count, active, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
                """
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let statement else {
                throw candidateStatementError(database)
            }
            defer { sqlite3_finalize(statement) }
            try candidateBindText(draftID.uuidString, statement, 1, database)
            try candidateBindText(policySnapshotID.uuidString, statement, 2, database)
            try candidateBindText(month.identifier, statement, 3, database)
            try candidateBindText(calculatorVersion, statement, 4, database)
            try candidateBindData(inputJSON, statement, 5, database)
            try candidateBindData(stateJSON, statement, 6, database)
            try candidateBindInt(excluded.cancellations, statement, 7, database)
            try candidateBindInt(excluded.other, statement, 8, database)
            try candidateBindDouble(now.timeIntervalSince1970, statement, 9, database)
            try candidateBindDouble(now.timeIntervalSince1970, statement, 10, database)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw candidateStatementError(database)
            }
            try candidateExecute("COMMIT TRANSACTION", database: database)
        } catch {
            try? candidateExecute("ROLLBACK TRANSACTION", database: database)
            throw error
        }

        guard let stored = try currentCandidateSimulationDraft() else {
            throw SQLiteEventStoreError.invalidStoredValue(
                "current candidate simulation draft"
            )
        }
        return stored
    }

    @discardableResult
    func updateCandidateSimulationState(
        draftID: UUID,
        expectedStateJSON: Data,
        stateJSON: Data,
        now: Date = Date()
    ) throws -> StoredCandidateSimulationDraft? {
        guard !expectedStateJSON.isEmpty, !stateJSON.isEmpty else {
            throw ManagementStoreError.invalidInput
        }
        let database = candidateSimulationDatabase
        var statement: OpaquePointer?
        let sql = """
            UPDATE candidate_card_simulation_drafts
            SET state_json = ?, updated_at = ?
            WHERE id = ? AND active = 1 AND state_json = ?
            """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw candidateStatementError(database)
        }
        defer { sqlite3_finalize(statement) }
        try candidateBindData(stateJSON, statement, 1, database)
        try candidateBindDouble(now.timeIntervalSince1970, statement, 2, database)
        try candidateBindText(draftID.uuidString, statement, 3, database)
        try candidateBindData(expectedStateJSON, statement, 4, database)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw candidateStatementError(database)
        }
        guard sqlite3_changes(database) == 1 else { return nil }
        return try currentCandidateSimulationDraft()
    }

    private func insertOrVerifyPolicySnapshot(
        id: UUID,
        schemaVersion: Int,
        policyJSON: Data,
        createdAt: Date,
        database: OpaquePointer
    ) throws {
        var insert: OpaquePointer?
        let sql = """
            INSERT OR IGNORE INTO candidate_card_policy_snapshots (
                id, schema_version, policy_json, created_at
            ) VALUES (?, ?, ?, ?)
            """
        guard sqlite3_prepare_v2(database, sql, -1, &insert, nil) == SQLITE_OK,
              let insert else {
            throw candidateStatementError(database)
        }
        defer { sqlite3_finalize(insert) }
        try candidateBindText(id.uuidString, insert, 1, database)
        try candidateBindInt(schemaVersion, insert, 2, database)
        try candidateBindData(policyJSON, insert, 3, database)
        try candidateBindDouble(createdAt.timeIntervalSince1970, insert, 4, database)
        guard sqlite3_step(insert) == SQLITE_DONE else {
            throw candidateStatementError(database)
        }

        var verify: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT schema_version, policy_json FROM candidate_card_policy_snapshots WHERE id = ?",
            -1,
            &verify,
            nil
        ) == SQLITE_OK, let verify else {
            throw candidateStatementError(database)
        }
        defer { sqlite3_finalize(verify) }
        try candidateBindText(id.uuidString, verify, 1, database)
        guard
            sqlite3_step(verify) == SQLITE_ROW,
            Int(sqlite3_column_int64(verify, 0)) == schemaVersion,
            candidateColumnData(verify, at: 1) == policyJSON
        else {
            throw ManagementStoreError.invalidInput
        }
    }

    private func decodeCandidateDraft(
        _ statement: OpaquePointer
    ) throws -> StoredCandidateSimulationDraft {
        guard
            let idText = candidateColumnString(statement, at: 0),
            let id = UUID(uuidString: idText),
            let policyIDText = candidateColumnString(statement, at: 1),
            let policyID = UUID(uuidString: policyIDText),
            let policyJSON = candidateColumnData(statement, at: 3),
            let month = candidateColumnString(statement, at: 4),
            let calculatorVersion = candidateColumnString(statement, at: 5),
            let inputJSON = candidateColumnData(statement, at: 6),
            let stateJSON = candidateColumnData(statement, at: 7)
        else {
            throw SQLiteEventStoreError.invalidStoredValue(
                "candidate simulation draft"
            )
        }
        return StoredCandidateSimulationDraft(
            id: id,
            policySnapshotID: policyID,
            policySchemaVersion: Int(sqlite3_column_int64(statement, 2)),
            policyJSON: policyJSON,
            analysisMonth: month,
            calculatorVersion: calculatorVersion,
            inputJSON: inputJSON,
            stateJSON: stateJSON,
            excluded: CandidateSimulationExclusionCounts(
                cancellations: Int(sqlite3_column_int64(statement, 8)),
                other: Int(sqlite3_column_int64(statement, 9))
            ),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 10)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 11))
        )
    }
}

private func candidateOccurredAt(
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
            timeZoneIdentifier: DashboardMonth.timeZoneIdentifier
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

private func candidateExecute(_ sql: String, database: OpaquePointer) throws {
    var errorPointer: UnsafeMutablePointer<CChar>?
    let result = sqlite3_exec(database, sql, nil, nil, &errorPointer)
    defer { if let errorPointer { sqlite3_free(errorPointer) } }
    guard result == SQLITE_OK else {
        let message = errorPointer.map { String(cString: $0) }
            ?? "sqlite3_exec returned \(result)"
        throw SQLiteEventStoreError.statement(message)
    }
}

private func candidateBindText(
    _ value: String,
    _ statement: OpaquePointer,
    _ index: Int32,
    _ database: OpaquePointer
) throws {
    let result = value.withCString {
        sqlite3_bind_text(statement, index, $0, -1, candidateSQLiteTransient)
    }
    guard result == SQLITE_OK else { throw candidateBindError(database) }
}

private func candidateBindData(
    _ value: Data,
    _ statement: OpaquePointer,
    _ index: Int32,
    _ database: OpaquePointer
) throws {
    try candidateBindText(String(decoding: value, as: UTF8.self), statement, index, database)
}

private func candidateBindInt(
    _ value: Int,
    _ statement: OpaquePointer,
    _ index: Int32,
    _ database: OpaquePointer
) throws {
    guard sqlite3_bind_int64(statement, index, Int64(value)) == SQLITE_OK else {
        throw candidateBindError(database)
    }
}

private func candidateBindDouble(
    _ value: Double,
    _ statement: OpaquePointer,
    _ index: Int32,
    _ database: OpaquePointer
) throws {
    guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
        throw candidateBindError(database)
    }
}

private func candidateColumnString(_ statement: OpaquePointer, at index: Int32) -> String? {
    guard let value = sqlite3_column_text(statement, index) else { return nil }
    return String(cString: value)
}

private func candidateColumnData(_ statement: OpaquePointer, at index: Int32) -> Data? {
    candidateColumnString(statement, at: index).map { Data($0.utf8) }
}

private func candidateNullableInt(_ statement: OpaquePointer, at index: Int32) -> Int? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
    return Int(sqlite3_column_int64(statement, index))
}

private func candidateStatementError(_ database: OpaquePointer) -> SQLiteEventStoreError {
    .statement(String(cString: sqlite3_errmsg(database)))
}

private func candidateBindError(_ database: OpaquePointer) -> SQLiteEventStoreError {
    .bind(String(cString: sqlite3_errmsg(database)))
}
