import Foundation
import XCTest

@testable import CherryPickerServer
import CherryPickerCore

@available(macOS 14.0, *)
final class CandidateSimulationPersistenceTests: XCTestCase {
    func testTemplateReadsCanonicalApprovalFactsAndIgnoresExistingReviewDecisions()
        async throws
    {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let store = try SQLiteEventStore(databaseURL: databaseURL)

        let included = try await store.ingest(event(
            id: "00000000-0000-0000-0000-000000001301",
            capturedAt: "2026-08-03T18:01:00+09:00",
            marker: "체크승인",
            amount: "2,500원",
            occurredAt: "08/03 18:00",
            merchant: "Synthetic Alpha"
        ))
        let reviewedButStillSource = try await store.ingest(event(
            id: "00000000-0000-0000-0000-000000001302",
            capturedAt: "2026-08-07T09:01:00+09:00",
            marker: "체크승인",
            amount: "13,500원",
            occurredAt: "08/07 09:00",
            merchant: "Synthetic Reviewed"
        ))
        _ = try await store.ingest(event(
            id: "00000000-0000-0000-0000-000000001303",
            capturedAt: "2026-08-09T10:01:00+09:00",
            marker: "승인취소",
            amount: "4,000원",
            occurredAt: "08/09 10:00",
            merchant: "Synthetic Cancellation"
        ))
        _ = try await store.ingest(OutboxEvent(
            eventId: UUID(uuidString: "00000000-0000-0000-0000-000000001304")!,
            capturedAt: try date("2026-08-11T10:01:00+09:00"),
            originalMessage: "[Web발신]\nUnsupported synthetic message"
        ))
        _ = try await store.ingest(event(
            id: "00000000-0000-0000-0000-000000001305",
            capturedAt: "2026-07-31T23:51:00+09:00",
            marker: "체크승인",
            amount: "8,000원",
            occurredAt: "07/31 23:50",
            merchant: "Outside Month"
        ))

        _ = try await store.reviewTransaction(
            id: try XCTUnwrap(reviewedButStillSource.transactionID),
            request: TransactionUpdateRequest(
                review: TransactionReviewInput(
                    performance: nil,
                    benefitIds: [],
                    memo: "existing product review"
                ),
                aggregationExcluded: true
            )
        )

        let template = try await store.candidateSimulationTemplate(
            month: try DashboardMonth(identifier: "2026-08")
        )

        XCTAssertEqual(template.analysisMonth, "2026-08")
        XCTAssertEqual(
            template.transactions.map(\.id),
            [
                try XCTUnwrap(included.transactionID),
                try XCTUnwrap(reviewedButStillSource.transactionID)
            ]
        )
        XCTAssertEqual(template.transactions.map(\.amount), [2_500, 13_500])
        XCTAssertEqual(
            template.transactions.map(\.merchant),
            ["Synthetic Alpha", "Synthetic Reviewed"]
        )
        XCTAssertEqual(template.excluded.cancellations, 1)
        XCTAssertEqual(template.excluded.other, 1)
    }

    func testDraftAndImmutablePolicySurviveRestartAndStoreNoCalculation()
        async throws
    {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let draftID = UUID(uuidString: "00000000-0000-0000-0000-000000001310")!
        let policyID = UUID(uuidString: "00000000-0000-0000-0000-000000001311")!
        let policyJSON = Data(#"{"name":"Synthetic Candidate"}"#.utf8)
        let inputJSON = Data(#"{"facts":[],"classifications":[]}"#.utf8)
        let stateJSON = Data(#"{"selectedTransactionIds":[]}"#.utf8)
        let createdAt = try date("2026-08-20T12:00:00+09:00")

        do {
            let store = try SQLiteEventStore(databaseURL: databaseURL)
            let stored = try await store.replaceCandidateSimulationDraft(
                draftID: draftID,
                policySnapshotID: policyID,
                policySchemaVersion: 1,
                policyJSON: policyJSON,
                month: try DashboardMonth(identifier: "2026-08"),
                calculatorVersion: "candidate-card-v1",
                inputJSON: inputJSON,
                stateJSON: stateJSON,
                excluded: CandidateSimulationExclusionCounts(cancellations: 2, other: 1),
                now: createdAt
            )
            XCTAssertEqual(stored.id, draftID)
        }

        let reopened = try SQLiteEventStore(databaseURL: databaseURL)
        let reopenedValue = try await reopened.currentCandidateSimulationDraft()
        let stored = try XCTUnwrap(reopenedValue)
        XCTAssertEqual(stored.id, draftID)
        XCTAssertEqual(stored.policySnapshotID, policyID)
        XCTAssertEqual(stored.policySchemaVersion, 1)
        XCTAssertEqual(stored.policyJSON, policyJSON)
        XCTAssertEqual(stored.analysisMonth, "2026-08")
        XCTAssertEqual(stored.calculatorVersion, "candidate-card-v1")
        XCTAssertEqual(stored.inputJSON, inputJSON)
        XCTAssertEqual(stored.stateJSON, stateJSON)
        XCTAssertEqual(stored.excluded, .init(cancellations: 2, other: 1))
        XCTAssertEqual(stored.createdAt, createdAt)
        XCTAssertEqual(stored.updatedAt, createdAt)

        let databaseBytes = try Data(contentsOf: databaseURL)
        XCTAssertFalse(
            String(decoding: databaseBytes, as: UTF8.self).contains("calculation_json")
        )
    }

    func testPolicyConflictAndMissingDraftStateUpdateLeaveCurrentDraftUnchanged()
        async throws
    {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let store = try SQLiteEventStore(databaseURL: databaseURL)
        let draftID = UUID(uuidString: "00000000-0000-0000-0000-000000001320")!
        let policyID = UUID(uuidString: "00000000-0000-0000-0000-000000001321")!
        let originalState = Data(#"{"selectedTransactionIds":[]}"#.utf8)
        _ = try await store.replaceCandidateSimulationDraft(
            draftID: draftID,
            policySnapshotID: policyID,
            policySchemaVersion: 1,
            policyJSON: Data(#"{"name":"Original"}"#.utf8),
            month: try DashboardMonth(identifier: "2026-08"),
            calculatorVersion: "candidate-card-v1",
            inputJSON: Data(#"{"facts":[]}"#.utf8),
            stateJSON: originalState,
            excluded: .init(cancellations: 0, other: 0),
            now: try date("2026-08-20T12:00:00+09:00")
        )

        do {
            _ = try await store.replaceCandidateSimulationDraft(
                draftID: UUID(),
                policySnapshotID: policyID,
                policySchemaVersion: 1,
                policyJSON: Data(#"{"name":"Mutated"}"#.utf8),
                month: try DashboardMonth(identifier: "2026-08"),
                calculatorVersion: "candidate-card-v1",
                inputJSON: Data(#"{"facts":[]}"#.utf8),
                stateJSON: Data(#"{"selectedTransactionIds":["bad"]}"#.utf8),
                excluded: .init(cancellations: 0, other: 0)
            )
            XCTFail("An immutable policy ID must reject different policy bytes")
        } catch ManagementStoreError.invalidInput {
            // Expected.
        }

        let missing = try await store.updateCandidateSimulationState(
            draftID: UUID(),
            expectedStateJSON: originalState,
            stateJSON: Data(#"{"selectedTransactionIds":["missing"]}"#.utf8)
        )
        XCTAssertNil(missing)
        let currentValue = try await store.currentCandidateSimulationDraft()
        let unchanged = try XCTUnwrap(currentValue)
        XCTAssertEqual(unchanged.id, draftID)
        XCTAssertEqual(unchanged.policyJSON, Data(#"{"name":"Original"}"#.utf8))
        XCTAssertEqual(unchanged.stateJSON, originalState)
    }

    func testSamePolicyMonthCreatesFreshGenerationAndStaleUpdatesCannotMutateCurrent()
        async throws
    {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabaseFiles(at: databaseURL) }
        let store = try SQLiteEventStore(databaseURL: databaseURL)
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000001325")!
        let policyID = UUID(uuidString: "00000000-0000-0000-0000-000000001326")!
        let firstDate = try date("2026-08-20T12:00:00+09:00")
        let resetDate = try date("2026-08-20T12:05:00+09:00")
        let policyJSON = Data(#"{"name":"Stable"}"#.utf8)
        let firstState = Data(#"{"selectedTransactionIds":["old"]}"#.utf8)

        _ = try await store.replaceCandidateSimulationDraft(
            draftID: firstID,
            policySnapshotID: policyID,
            policySchemaVersion: 1,
            policyJSON: policyJSON,
            month: try DashboardMonth(identifier: "2026-08"),
            calculatorVersion: "candidate-card-v1",
            inputJSON: Data(#"{"version":1}"#.utf8),
            stateJSON: firstState,
            excluded: .init(cancellations: 1, other: 2),
            now: firstDate
        )
        let resetID = UUID(uuidString: "00000000-0000-0000-0000-000000001329")!
        let resetState = Data(#"{"selectedTransactionIds":[]}"#.utf8)
        let reset = try await store.replaceCandidateSimulationDraft(
            draftID: resetID,
            policySnapshotID: policyID,
            policySchemaVersion: 1,
            policyJSON: policyJSON,
            month: try DashboardMonth(identifier: "2026-08"),
            calculatorVersion: "candidate-card-v1",
            inputJSON: Data(#"{"version":2}"#.utf8),
            stateJSON: resetState,
            excluded: .init(cancellations: 0, other: 0),
            now: resetDate
        )
        XCTAssertEqual(reset.id, resetID)
        XCTAssertEqual(reset.createdAt, resetDate)
        XCTAssertEqual(reset.updatedAt, resetDate)
        XCTAssertEqual(reset.inputJSON, Data(#"{"version":2}"#.utf8))
        XCTAssertEqual(reset.stateJSON, resetState)

        let staleGenerationUpdate = try await store.updateCandidateSimulationState(
            draftID: firstID,
            expectedStateJSON: firstState,
            stateJSON: Data(#"{"selectedTransactionIds":["stale-generation"]}"#.utf8)
        )
        XCTAssertNil(staleGenerationUpdate)
        let afterStaleGeneration = try await store.currentCandidateSimulationDraft()
        XCTAssertEqual(afterStaleGeneration?.id, resetID)
        XCTAssertEqual(afterStaleGeneration?.stateJSON, resetState)

        let winningState = Data(#"{"selectedTransactionIds":["winner"]}"#.utf8)
        let winningUpdate = try await store.updateCandidateSimulationState(
            draftID: resetID,
            expectedStateJSON: resetState,
            stateJSON: winningState,
            now: try date("2026-08-20T12:06:00+09:00")
        )
        XCTAssertEqual(winningUpdate?.stateJSON, winningState)
        let staleStateUpdate = try await store.updateCandidateSimulationState(
            draftID: resetID,
            expectedStateJSON: resetState,
            stateJSON: Data(#"{"selectedTransactionIds":["loser"]}"#.utf8)
        )
        XCTAssertNil(staleStateUpdate)
        let afterStaleState = try await store.currentCandidateSimulationDraft()
        XCTAssertEqual(afterStaleState?.id, resetID)
        XCTAssertEqual(afterStaleState?.stateJSON, winningState)

        let replacementID = UUID(uuidString: "00000000-0000-0000-0000-000000001327")!
        let replacementPolicyID = UUID(
            uuidString: "00000000-0000-0000-0000-000000001328"
        )!
        let replacement = try await store.replaceCandidateSimulationDraft(
            draftID: replacementID,
            policySnapshotID: replacementPolicyID,
            policySchemaVersion: 1,
            policyJSON: Data(#"{"name":"Replacement"}"#.utf8),
            month: try DashboardMonth(identifier: "2026-07"),
            calculatorVersion: "candidate-card-v1",
            inputJSON: Data(#"{"version":1}"#.utf8),
            stateJSON: Data(#"{"selectedTransactionIds":[]}"#.utf8),
            excluded: .init(cancellations: 0, other: 0),
            now: try date("2026-08-20T12:10:00+09:00")
        )
        XCTAssertEqual(replacement.id, replacementID)
        let current = try await store.currentCandidateSimulationDraft()
        XCTAssertEqual(current?.id, replacementID)
        XCTAssertEqual(current?.policySnapshotID, replacementPolicyID)
    }

    private func event(
        id: String,
        capturedAt: String,
        marker: String,
        amount: String,
        occurredAt: String,
        merchant: String
    ) async throws -> OutboxEvent {
        OutboxEvent(
            eventId: UUID(uuidString: id)!,
            capturedAt: try date(capturedAt),
            originalMessage: """
                [Web발신]
                MG카드(4775)\(marker)
                \(amount)
                \(occurredAt)
                \(merchant)
                """
        )
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CandidateSimulationPersistenceTests-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private func removeDatabaseFiles(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
    }
}
