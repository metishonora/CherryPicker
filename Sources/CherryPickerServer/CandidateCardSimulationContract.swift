import Foundation
import CherryPickerCore

/// Canonical approval fields exposed to candidate-card classification.
///
/// Raw message bodies, card identifiers, balances, parser diagnostics, and
/// existing review decisions are intentionally absent from this boundary.
public struct CandidateSimulationSourceTransaction: Codable, Equatable, Sendable {
    public let id: UUID
    public let occurredAt: Date
    public let amount: Int
    public let merchant: String

    public init(id: UUID, occurredAt: Date, amount: Int, merchant: String) {
        self.id = id
        self.occurredAt = occurredAt
        self.amount = amount
        self.merchant = merchant
    }
}

public struct CandidateSimulationExclusionCounts: Codable, Equatable, Sendable {
    public let cancellations: Int
    public let other: Int

    public init(cancellations: Int, other: Int) {
        self.cancellations = cancellations
        self.other = other
    }
}

public struct CandidateSimulationTemplateResponse: Codable, Equatable, Sendable {
    public let analysisMonth: String
    public let transactions: [CandidateSimulationSourceTransaction]
    public let excluded: CandidateSimulationExclusionCounts

    public init(
        analysisMonth: String,
        transactions: [CandidateSimulationSourceTransaction],
        excluded: CandidateSimulationExclusionCounts
    ) {
        self.analysisMonth = analysisMonth
        self.transactions = transactions
        self.excluded = excluded
    }
}

public struct CandidateSimulationPutRequest: Codable, Equatable, Sendable {
    public let policy: CandidateCardPolicyTemplate
    public let analysisMonth: String
    public let defaultPerformanceAssumptionId: String
    public let classifications: [CandidateCardTransactionClassification]

    public init(
        policy: CandidateCardPolicyTemplate,
        analysisMonth: String,
        defaultPerformanceAssumptionId: String,
        classifications: [CandidateCardTransactionClassification]
    ) {
        self.policy = policy
        self.analysisMonth = analysisMonth
        self.defaultPerformanceAssumptionId = defaultPerformanceAssumptionId
        self.classifications = classifications
    }
}

public struct CandidateSimulationAnswer: Codable, Equatable, Sendable {
    public let transactionId: UUID
    public let alternativeId: String

    public init(transactionId: UUID, alternativeId: String) {
        self.transactionId = transactionId
        self.alternativeId = alternativeId
    }

    var coreValue: CandidateCardTransactionAnswer {
        CandidateCardTransactionAnswer(
            transactionID: transactionId,
            alternativeID: alternativeId
        )
    }

    init(_ value: CandidateCardTransactionAnswer) {
        self.init(
            transactionId: value.transactionID,
            alternativeId: value.alternativeID
        )
    }
}

public struct CandidateSimulationState: Codable, Equatable, Sendable {
    public let policyConfirmed: Bool
    public let questionsReviewed: Bool
    public let performanceAssumptionId: String
    public let selectedTransactionIds: [UUID]
    public let answers: [CandidateSimulationAnswer]

    public init(
        policyConfirmed: Bool,
        questionsReviewed: Bool,
        performanceAssumptionId: String,
        selectedTransactionIds: [UUID],
        answers: [CandidateSimulationAnswer]
    ) {
        self.policyConfirmed = policyConfirmed
        self.questionsReviewed = questionsReviewed
        self.performanceAssumptionId = performanceAssumptionId
        self.selectedTransactionIds = selectedTransactionIds
        self.answers = answers
    }

    var calculatorInput: CandidateCardSimulationInput {
        CandidateCardSimulationInput(
            selectedTransactionIDs: selectedTransactionIds,
            answers: answers.map(\.coreValue),
            performanceAssumptionID: performanceAssumptionId
        )
    }
}

public struct CandidateSimulationPatchRequest: Codable, Equatable, Sendable {
    public let draftId: UUID
    public let expectedState: CandidateSimulationState
    public let policyConfirmed: Bool?
    public let questionsReviewed: Bool?
    public let performanceAssumptionId: String?
    public let selectedTransactionIds: [UUID]?
    public let answers: [CandidateSimulationAnswer]?

    public init(
        draftId: UUID,
        expectedState: CandidateSimulationState,
        policyConfirmed: Bool? = nil,
        questionsReviewed: Bool? = nil,
        performanceAssumptionId: String? = nil,
        selectedTransactionIds: [UUID]? = nil,
        answers: [CandidateSimulationAnswer]? = nil
    ) {
        self.draftId = draftId
        self.expectedState = expectedState
        self.policyConfirmed = policyConfirmed
        self.questionsReviewed = questionsReviewed
        self.performanceAssumptionId = performanceAssumptionId
        self.selectedTransactionIds = selectedTransactionIds
        self.answers = answers
    }

    func applying(to state: CandidateSimulationState) -> CandidateSimulationState {
        CandidateSimulationState(
            policyConfirmed: policyConfirmed ?? state.policyConfirmed,
            questionsReviewed: questionsReviewed ?? state.questionsReviewed,
            performanceAssumptionId:
                performanceAssumptionId ?? state.performanceAssumptionId,
            selectedTransactionIds:
                selectedTransactionIds ?? state.selectedTransactionIds,
            answers: answers ?? state.answers
        )
    }
}

public struct CandidateSimulation: Codable, Equatable, Sendable {
    public let id: UUID
    public let policy: CandidateCardPolicyTemplate
    public let month: String
    public let facts: [CandidateCardTransactionFact]
    public let classifications: [CandidateCardTransactionClassification]
    public let excluded: CandidateSimulationExclusionCounts
    public let state: CandidateSimulationState
    public let calculatorVersion: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        policy: CandidateCardPolicyTemplate,
        month: String,
        facts: [CandidateCardTransactionFact],
        classifications: [CandidateCardTransactionClassification],
        excluded: CandidateSimulationExclusionCounts,
        state: CandidateSimulationState,
        calculatorVersion: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.policy = policy
        self.month = month
        self.facts = facts
        self.classifications = classifications
        self.excluded = excluded
        self.state = state
        self.calculatorVersion = calculatorVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CandidateSimulationResponse: Codable, Equatable, Sendable {
    public let simulation: CandidateSimulation
    public let calculation: CandidateCardSimulationResult

    public init(
        simulation: CandidateSimulation,
        calculation: CandidateCardSimulationResult
    ) {
        self.simulation = simulation
        self.calculation = calculation
    }
}

struct StoredCandidateSimulationInput: Codable, Equatable, Sendable {
    let facts: [CandidateCardTransactionFact]
    let classifications: [CandidateCardTransactionClassification]
    let defaultPerformanceAssumptionId: String
}

enum CandidateSimulationServiceError: Error, Equatable, Sendable {
    case invalidInput
    case notFound
}

@available(macOS 14.0, *)
struct CandidateSimulationService: Sendable {
    private let store: SQLiteEventStore
    private let codec: OutboxJSONCodec
    private let calculator = CandidateCardSimulationCalculator()

    init(store: SQLiteEventStore, codec: OutboxJSONCodec) {
        self.store = store
        self.codec = codec
    }

    func template(month: DashboardMonth) async throws -> CandidateSimulationTemplateResponse {
        try await store.candidateSimulationTemplate(month: month)
    }

    func current() async throws -> CandidateSimulationResponse {
        guard let stored = try await store.currentCandidateSimulationDraft() else {
            throw CandidateSimulationServiceError.notFound
        }
        return try response(from: stored)
    }

    func replace(
        request: CandidateSimulationPutRequest,
        now: Date = Date()
    ) async throws -> CandidateSimulationResponse {
        let month: DashboardMonth
        do {
            month = try DashboardMonth(identifier: request.analysisMonth)
        } catch {
            throw CandidateSimulationServiceError.invalidInput
        }
        let template = try await store.candidateSimulationTemplate(month: month)
        let facts = template.transactions.map {
            CandidateCardTransactionFact(
                id: $0.id,
                occurredAt: $0.occurredAt,
                amount: $0.amount,
                merchant: $0.merchant
            )
        }
        guard hasExactClassifications(
            facts: facts,
            classifications: request.classifications
        ) else {
            throw CandidateSimulationServiceError.invalidInput
        }

        let storedInput = StoredCandidateSimulationInput(
            facts: facts,
            classifications: request.classifications,
            defaultPerformanceAssumptionId: request.defaultPerformanceAssumptionId
        )
        let state = CandidateSimulationState(
            policyConfirmed: false,
            questionsReviewed: false,
            performanceAssumptionId: request.defaultPerformanceAssumptionId,
            selectedTransactionIds: [],
            answers: []
        )
        _ = try calculator.calculate(
            policy: request.policy,
            facts: facts,
            classifications: request.classifications,
            input: state.calculatorInput
        )

        let stored = try await store.replaceCandidateSimulationDraft(
            draftID: UUID(),
            policySnapshotID: request.policy.snapshotID,
            policySchemaVersion: request.policy.schemaVersion,
            policyJSON: try codec.encode(request.policy),
            month: month,
            calculatorVersion: CandidateCardSimulationCalculator.calculatorVersion,
            inputJSON: try codec.encode(storedInput),
            stateJSON: try codec.encode(state),
            excluded: template.excluded,
            now: now
        )
        return try response(from: stored)
    }

    func patch(
        request: CandidateSimulationPatchRequest,
        now: Date = Date()
    ) async throws -> CandidateSimulationResponse {
        guard let stored = try await store.currentCandidateSimulationDraft() else {
            throw CandidateSimulationServiceError.notFound
        }
        let decoded = try decode(stored)
        guard request.draftId == stored.id,
            request.expectedState == decoded.state
        else {
            // A page must patch the exact draft generation and state it rendered.
            // The store-level compare-and-swap below protects the second race
            // window after this check.
            throw CandidateSimulationServiceError.invalidInput
        }
        let state = request.applying(to: decoded.state)
        guard hasValidWorkflowState(state) else {
            throw CandidateSimulationServiceError.invalidInput
        }
        let calculation = try calculator.calculate(
            policy: decoded.policy,
            facts: decoded.input.facts,
            classifications: decoded.input.classifications,
            input: state.calculatorInput
        )
        let stateJSON = try codec.encode(state)
        guard let updated = try await store.updateCandidateSimulationState(
            draftID: stored.id,
            expectedStateJSON: stored.stateJSON,
            stateJSON: stateJSON,
            now: now
        ) else {
            // The current generation or its state changed after this request
            // read it. Fail closed instead of overwriting a newer PUT/PATCH.
            throw CandidateSimulationServiceError.invalidInput
        }
        return try response(
            from: updated,
            decoded: (decoded.policy, decoded.input, state),
            calculation: calculation
        )
    }

    private func response(
        from stored: StoredCandidateSimulationDraft
    ) throws -> CandidateSimulationResponse {
        let decoded = try decode(stored)
        guard hasValidWorkflowState(decoded.state) else {
            throw SQLiteEventStoreError.invalidStoredValue(
                "candidate simulation workflow state"
            )
        }
        let calculation = try calculator.calculate(
            policy: decoded.policy,
            facts: decoded.input.facts,
            classifications: decoded.input.classifications,
            input: decoded.state.calculatorInput
        )
        return try response(
            from: stored,
            decoded: (decoded.policy, decoded.input, decoded.state),
            calculation: calculation
        )
    }

    private func response(
        from stored: StoredCandidateSimulationDraft,
        decoded: (
            policy: CandidateCardPolicyTemplate,
            input: StoredCandidateSimulationInput,
            state: CandidateSimulationState
        ),
        calculation: CandidateCardSimulationResult
    ) throws -> CandidateSimulationResponse {
        guard
            stored.calculatorVersion == CandidateCardSimulationCalculator.calculatorVersion,
            calculation.calculatorVersion == stored.calculatorVersion,
            decoded.policy.snapshotID == stored.policySnapshotID,
            decoded.policy.schemaVersion == stored.policySchemaVersion,
            (try? DashboardMonth(identifier: stored.analysisMonth))?.identifier
                == stored.analysisMonth
        else {
            throw SQLiteEventStoreError.invalidStoredValue(
                "candidate simulation contract"
            )
        }
        return CandidateSimulationResponse(
            simulation: CandidateSimulation(
                id: stored.id,
                policy: decoded.policy,
                month: stored.analysisMonth,
                facts: decoded.input.facts,
                classifications: decoded.input.classifications,
                excluded: stored.excluded,
                state: decoded.state,
                calculatorVersion: stored.calculatorVersion,
                createdAt: stored.createdAt,
                updatedAt: stored.updatedAt
            ),
            calculation: calculation
        )
    }

    private func decode(
        _ stored: StoredCandidateSimulationDraft
    ) throws -> (
        policy: CandidateCardPolicyTemplate,
        input: StoredCandidateSimulationInput,
        state: CandidateSimulationState
    ) {
        (
            try codec.decode(CandidateCardPolicyTemplate.self, from: stored.policyJSON),
            try codec.decode(StoredCandidateSimulationInput.self, from: stored.inputJSON),
            try codec.decode(CandidateSimulationState.self, from: stored.stateJSON)
        )
    }

    private func hasExactClassifications(
        facts: [CandidateCardTransactionFact],
        classifications: [CandidateCardTransactionClassification]
    ) -> Bool {
        let factIDs = facts.map(\.id)
        let classificationIDs = classifications.map(\.transactionID)
        return Set(factIDs).count == factIDs.count
            && Set(classificationIDs).count == classificationIDs.count
            && Set(factIDs) == Set(classificationIDs)
    }

    private func hasValidWorkflowState(_ state: CandidateSimulationState) -> Bool {
        (!state.questionsReviewed || state.policyConfirmed)
            && (state.answers.isEmpty || state.policyConfirmed)
            && (state.selectedTransactionIds.isEmpty || state.questionsReviewed)
    }
}

/// Persistence representation intentionally stores calculator inputs and UI
/// state, never a derived calculation. HTTP code decodes and recalculates this
/// record whenever it is returned.
struct StoredCandidateSimulationDraft: Equatable, Sendable {
    let id: UUID
    let policySnapshotID: UUID
    let policySchemaVersion: Int
    let policyJSON: Data
    let analysisMonth: String
    let calculatorVersion: String
    let inputJSON: Data
    let stateJSON: Data
    let excluded: CandidateSimulationExclusionCounts
    let createdAt: Date
    let updatedAt: Date
}
