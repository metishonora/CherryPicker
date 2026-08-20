import Foundation

public struct CandidateCardPolicySource: Codable, Equatable, Sendable {
    public let name: String
    public let reference: String
    public let effectiveDate: Date
    public let structuredAt: Date

    public init(name: String, reference: String, effectiveDate: Date, structuredAt: Date) {
        self.name = name
        self.reference = reference
        self.effectiveDate = effectiveDate
        self.structuredAt = structuredAt
    }
}

public struct CandidateCardLimitGroup: Codable, Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

public struct CandidateCardPerformanceAssumption: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let previousMonthAmount: Int?
    public let isGrace: Bool
    public let limitGroupMaximumAmounts: [String: Int]

    public init(
        id: String,
        label: String,
        previousMonthAmount: Int?,
        isGrace: Bool,
        limitGroupMaximumAmounts: [String: Int]
    ) {
        self.id = id
        self.label = label
        self.previousMonthAmount = previousMonthAmount
        self.isGrace = isGrace
        self.limitGroupMaximumAmounts = limitGroupMaximumAmounts
    }
}

public enum CandidateCardRoundingDirection: String, Codable, Equatable, Sendable {
    case floor
    case nearest
    case ceiling
}

public struct CandidateCardRoundingRule: Codable, Equatable, Sendable {
    public let unit: Int
    public let direction: CandidateCardRoundingDirection

    public init(unit: Int, direction: CandidateCardRoundingDirection) {
        self.unit = unit
        self.direction = direction
    }
}

public struct CandidateCardBenefitDefinition: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let conditionSummary: String
    public let exclusionNotes: [String]
    public let rateBasisPoints: Int
    public let minimumTransactionAmount: Int?
    public let maximumTransactionAmount: Int?
    public let perTransactionMaximumBenefitAmount: Int?
    public let monthlyCountLimit: Int?
    public let limitGroupIDs: [String]
    public let priority: Int
    public let rounding: CandidateCardRoundingRule

    public init(
        id: String,
        label: String,
        conditionSummary: String,
        exclusionNotes: [String],
        rateBasisPoints: Int,
        minimumTransactionAmount: Int? = nil,
        maximumTransactionAmount: Int? = nil,
        perTransactionMaximumBenefitAmount: Int? = nil,
        monthlyCountLimit: Int? = nil,
        limitGroupIDs: [String] = [],
        priority: Int,
        rounding: CandidateCardRoundingRule
    ) {
        self.id = id
        self.label = label
        self.conditionSummary = conditionSummary
        self.exclusionNotes = exclusionNotes
        self.rateBasisPoints = rateBasisPoints
        self.minimumTransactionAmount = minimumTransactionAmount
        self.maximumTransactionAmount = maximumTransactionAmount
        self.perTransactionMaximumBenefitAmount = perTransactionMaximumBenefitAmount
        self.monthlyCountLimit = monthlyCountLimit
        self.limitGroupIDs = limitGroupIDs
        self.priority = priority
        self.rounding = rounding
    }
}

public enum CandidateCardBenefitStackingPolicy: String, Codable, Equatable, Sendable {
    case allEligible
    case highestPriorityOnly
}

public struct CandidateCardPolicyTemplate: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let snapshotID: UUID
    public let cardName: String
    public let issuerName: String
    public let productIdentifier: String
    public let source: CandidateCardPolicySource
    public let annualFeeAmount: Int
    public let performanceThresholdAmounts: [Int]
    public let limitGroups: [CandidateCardLimitGroup]
    public let performanceAssumptions: [CandidateCardPerformanceAssumption]
    public let benefits: [CandidateCardBenefitDefinition]
    public let stacking: CandidateCardBenefitStackingPolicy
    public let performanceExclusions: [String]
    public let benefitExclusions: [String]
    public let unsupportedPolicyConditions: [String]

    public init(
        schemaVersion: Int = CandidateCardPolicyTemplate.currentSchemaVersion,
        snapshotID: UUID,
        cardName: String,
        issuerName: String,
        productIdentifier: String,
        source: CandidateCardPolicySource,
        annualFeeAmount: Int,
        performanceThresholdAmounts: [Int],
        limitGroups: [CandidateCardLimitGroup],
        performanceAssumptions: [CandidateCardPerformanceAssumption],
        benefits: [CandidateCardBenefitDefinition],
        stacking: CandidateCardBenefitStackingPolicy,
        performanceExclusions: [String],
        benefitExclusions: [String],
        unsupportedPolicyConditions: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.snapshotID = snapshotID
        self.cardName = cardName
        self.issuerName = issuerName
        self.productIdentifier = productIdentifier
        self.source = source
        self.annualFeeAmount = annualFeeAmount
        self.performanceThresholdAmounts = performanceThresholdAmounts
        self.limitGroups = limitGroups
        self.performanceAssumptions = performanceAssumptions
        self.benefits = benefits
        self.stacking = stacking
        self.performanceExclusions = performanceExclusions
        self.benefitExclusions = benefitExclusions
        self.unsupportedPolicyConditions = unsupportedPolicyConditions
    }
}

public struct CandidateCardTransactionFact: Codable, Equatable, Sendable {
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

public enum CandidateCardPerformanceDecision: String, Codable, Equatable, Sendable {
    case included
    case excluded
}

public struct CandidateCardClassificationAlternative: Codable, Equatable, Sendable {
    public let id: String
    public let answerLabel: String?
    public let performance: CandidateCardPerformanceDecision
    public let performanceReason: String
    public let benefitIDs: [String]
    public let benefitReason: String

    public init(
        id: String,
        answerLabel: String? = nil,
        performance: CandidateCardPerformanceDecision,
        performanceReason: String,
        benefitIDs: [String],
        benefitReason: String
    ) {
        self.id = id
        self.answerLabel = answerLabel
        self.performance = performance
        self.performanceReason = performanceReason
        self.benefitIDs = benefitIDs
        self.benefitReason = benefitReason
    }
}

public struct CandidateCardTransactionClassification: Codable, Equatable, Sendable {
    public let transactionID: UUID
    public let question: String?
    public let alternatives: [CandidateCardClassificationAlternative]

    public init(
        transactionID: UUID,
        question: String? = nil,
        alternatives: [CandidateCardClassificationAlternative]
    ) {
        self.transactionID = transactionID
        self.question = question
        self.alternatives = alternatives
    }
}

public struct CandidateCardTransactionAnswer: Codable, Equatable, Sendable {
    public let transactionID: UUID
    public let alternativeID: String

    public init(transactionID: UUID, alternativeID: String) {
        self.transactionID = transactionID
        self.alternativeID = alternativeID
    }
}

public struct CandidateCardSimulationInput: Codable, Equatable, Sendable {
    public let selectedTransactionIDs: [UUID]
    public let answers: [CandidateCardTransactionAnswer]
    public let performanceAssumptionID: String

    public init(
        selectedTransactionIDs: [UUID],
        answers: [CandidateCardTransactionAnswer],
        performanceAssumptionID: String
    ) {
        self.selectedTransactionIDs = selectedTransactionIDs
        self.answers = answers
        self.performanceAssumptionID = performanceAssumptionID
    }
}

public struct CandidateCardIntegerRange: Codable, Equatable, Sendable {
    public let minimum: Int
    public let maximum: Int

    public init(minimum: Int, maximum: Int) {
        self.minimum = minimum
        self.maximum = maximum
    }
}

public struct CandidateCardRateRange: Codable, Equatable, Sendable {
    public let minimum: Double
    public let maximum: Double

    public init(minimum: Double, maximum: Double) {
        self.minimum = minimum
        self.maximum = maximum
    }
}

public struct CandidateCardNextPerformanceThresholdResult: Codable, Equatable, Sendable {
    public let thresholdAmount: CandidateCardIntegerRange?
    public let remainingAmount: CandidateCardIntegerRange?
    public let includesNoNextThreshold: Bool

    public init(
        thresholdAmount: CandidateCardIntegerRange?,
        remainingAmount: CandidateCardIntegerRange?,
        includesNoNextThreshold: Bool
    ) {
        self.thresholdAmount = thresholdAmount
        self.remainingAmount = remainingAmount
        self.includesNoNextThreshold = includesNoNextThreshold
    }
}

public struct CandidateCardLimitGroupResult: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let maximumAmount: Int
    public let usedAmount: CandidateCardIntegerRange
    public let remainingAmount: CandidateCardIntegerRange

    public init(
        id: String,
        label: String,
        maximumAmount: Int,
        usedAmount: CandidateCardIntegerRange,
        remainingAmount: CandidateCardIntegerRange
    ) {
        self.id = id
        self.label = label
        self.maximumAmount = maximumAmount
        self.usedAmount = usedAmount
        self.remainingAmount = remainingAmount
    }
}

public struct CandidateCardTransactionBenefitResult: Codable, Equatable, Sendable {
    public let benefitID: String
    public let label: String
    public let rawBenefitAmount: CandidateCardIntegerRange
    public let appliedBenefitAmount: CandidateCardIntegerRange
    public let missedBenefitAmount: CandidateCardIntegerRange

    public init(
        benefitID: String,
        label: String,
        rawBenefitAmount: CandidateCardIntegerRange,
        appliedBenefitAmount: CandidateCardIntegerRange,
        missedBenefitAmount: CandidateCardIntegerRange
    ) {
        self.benefitID = benefitID
        self.label = label
        self.rawBenefitAmount = rawBenefitAmount
        self.appliedBenefitAmount = appliedBenefitAmount
        self.missedBenefitAmount = missedBenefitAmount
    }
}

public struct CandidateCardTransactionResult: Codable, Equatable, Sendable {
    public let transactionID: UUID
    public let isSelected: Bool
    public let rawBenefitAmount: CandidateCardIntegerRange
    public let appliedBenefitAmount: CandidateCardIntegerRange
    public let missedBenefitAmount: CandidateCardIntegerRange
    public let benefits: [CandidateCardTransactionBenefitResult]
    public let benefitBreakdownIsAdditive: Bool

    public init(
        transactionID: UUID,
        isSelected: Bool,
        rawBenefitAmount: CandidateCardIntegerRange,
        appliedBenefitAmount: CandidateCardIntegerRange,
        missedBenefitAmount: CandidateCardIntegerRange,
        benefits: [CandidateCardTransactionBenefitResult],
        benefitBreakdownIsAdditive: Bool
    ) {
        self.transactionID = transactionID
        self.isSelected = isSelected
        self.rawBenefitAmount = rawBenefitAmount
        self.appliedBenefitAmount = appliedBenefitAmount
        self.missedBenefitAmount = missedBenefitAmount
        self.benefits = benefits
        self.benefitBreakdownIsAdditive = benefitBreakdownIsAdditive
    }
}

public struct CandidateCardSimulationResult: Codable, Equatable, Sendable {
    public let calculatorVersion: String
    public let selectedTransactionCount: Int
    public let selectedTransactionAmount: Int
    public let performanceAmount: CandidateCardIntegerRange
    public let benefitAmount: CandidateCardIntegerRange
    public let pickingRatePercentage: CandidateCardRateRange?
    public let annualFeeMonthlyAmount: Int
    public let annualFeeAdjustedPickingRatePercentage: CandidateCardRateRange?
    public let nextPerformanceThreshold: CandidateCardNextPerformanceThresholdResult
    public let limitGroups: [CandidateCardLimitGroupResult]
    public let transactions: [CandidateCardTransactionResult]

    public init(
        calculatorVersion: String,
        selectedTransactionCount: Int,
        selectedTransactionAmount: Int,
        performanceAmount: CandidateCardIntegerRange,
        benefitAmount: CandidateCardIntegerRange,
        pickingRatePercentage: CandidateCardRateRange?,
        annualFeeMonthlyAmount: Int,
        annualFeeAdjustedPickingRatePercentage: CandidateCardRateRange?,
        nextPerformanceThreshold: CandidateCardNextPerformanceThresholdResult,
        limitGroups: [CandidateCardLimitGroupResult],
        transactions: [CandidateCardTransactionResult]
    ) {
        self.calculatorVersion = calculatorVersion
        self.selectedTransactionCount = selectedTransactionCount
        self.selectedTransactionAmount = selectedTransactionAmount
        self.performanceAmount = performanceAmount
        self.benefitAmount = benefitAmount
        self.pickingRatePercentage = pickingRatePercentage
        self.annualFeeMonthlyAmount = annualFeeMonthlyAmount
        self.annualFeeAdjustedPickingRatePercentage = annualFeeAdjustedPickingRatePercentage
        self.nextPerformanceThreshold = nextPerformanceThreshold
        self.limitGroups = limitGroups
        self.transactions = transactions
    }
}

public enum CandidateCardSimulationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case unsupportedPolicyConditions([String])
    case invalidPolicy(String)
    case duplicateIdentifier(kind: String, id: String)
    case missingIdentifier(kind: String, id: String)
    case unknownReference(kind: String, id: String)
    case duplicateTransactionFact(UUID)
    case duplicateClassification(UUID)
    case missingClassification(UUID)
    case classificationWithoutFact(UUID)
    case invalidClassification(UUID, String)
    case duplicateSelection(UUID)
    case unknownSelectedTransaction(UUID)
    case duplicateAnswer(UUID)
    case unknownAnswerTransaction(UUID)
    case invalidAnswer(UUID, String)
    case unknownPerformanceAssumption(String)
    case tooManyEvaluationStates(limit: Int)
    case arithmeticOverflow
}

/// Pure, deterministic calculation boundary for a single candidate-card snapshot.
public struct CandidateCardSimulationCalculator: Sendable {
    public static let calculatorVersion = "candidate-card-v1"
    public static let maximumEvaluationStateCount = 100_000
    static let maximumDensePerformanceBitCount = 10_000_000
    static let maximumSparsePerformanceAmountCount = 1_000_000

    public init() {}

    public func calculate(
        policy: CandidateCardPolicyTemplate,
        facts: [CandidateCardTransactionFact],
        classifications: [CandidateCardTransactionClassification],
        input: CandidateCardSimulationInput
    ) throws -> CandidateCardSimulationResult {
        let validated = try validate(
            policy: policy,
            facts: facts,
            classifications: classifications,
            input: input
        )
        let evaluation = try evaluateAllAlternatives(policy: policy, validated: validated)
        let performance = try evaluatePerformance(policy: policy, validated: validated)

        return try makeResult(
            policy: policy,
            validated: validated,
            evaluation: evaluation,
            performance: performance
        )
    }
}

private extension CandidateCardSimulationCalculator {
    struct ValidatedInput {
        let sortedFacts: [CandidateCardTransactionFact]
        let classifications: [UUID: CandidateCardTransactionClassification]
        let selectedIDs: Set<UUID>
        let answers: [UUID: String]
        let assumption: CandidateCardPerformanceAssumption
    }

    struct AmountBounds {
        var minimum: Int
        var maximum: Int

        init(exact value: Int) {
            minimum = value
            maximum = value
        }

        init(minimum: Int, maximum: Int) {
            self.minimum = minimum
            self.maximum = maximum
        }

        mutating func merge(_ other: AmountBounds) {
            minimum = Swift.min(minimum, other.minimum)
            maximum = Swift.max(maximum, other.maximum)
        }
    }

    struct BenefitAmountBounds {
        var raw: AmountBounds
        var applied: AmountBounds
        var missed: AmountBounds

        init(raw: Int, applied: Int) {
            self.raw = AmountBounds(exact: raw)
            self.applied = AmountBounds(exact: applied)
            missed = AmountBounds(exact: raw - applied)
        }

        mutating func merge(_ other: BenefitAmountBounds) {
            raw.merge(other.raw)
            applied.merge(other.applied)
            missed.merge(other.missed)
        }
    }

    struct TransactionAmountBounds {
        var raw: AmountBounds
        var applied: AmountBounds
        var missed: AmountBounds
        var benefits: [String: BenefitAmountBounds]

        init(raw: Int, applied: Int, benefits: [String: BenefitAmountBounds]) {
            self.raw = AmountBounds(exact: raw)
            self.applied = AmountBounds(exact: applied)
            missed = AmountBounds(exact: raw - applied)
            self.benefits = benefits
        }

        mutating func merge(_ other: TransactionAmountBounds) {
            raw.merge(other.raw)
            applied.merge(other.applied)
            missed.merge(other.missed)
            for benefitID in Set(benefits.keys).union(other.benefits.keys) {
                let lhs = benefits[benefitID] ?? BenefitAmountBounds(raw: 0, applied: 0)
                let rhs = other.benefits[benefitID] ?? BenefitAmountBounds(raw: 0, applied: 0)
                var merged = lhs
                merged.merge(rhs)
                benefits[benefitID] = merged
            }
        }
    }

    struct ExactTransactionAmounts {
        let raw: Int
        let applied: Int
        let benefits: [String: BenefitAmountBounds]
    }

    struct EvaluationStateKey: Hashable {
        let limitGroupUsedAmounts: [Int]
        let benefitCounts: [Int]
    }

    struct ClassificationOutcome: Hashable {
        let performance: String
        let benefitIDs: [String]
    }

    struct EvaluationAccumulator {
        var benefitAmount: AmountBounds
        var transactions: [UUID: TransactionAmountBounds]

        mutating func merge(_ other: EvaluationAccumulator) {
            benefitAmount.merge(other.benefitAmount)
            for (transactionID, otherAmounts) in other.transactions {
                if var amounts = transactions[transactionID] {
                    amounts.merge(otherAmounts)
                    transactions[transactionID] = amounts
                } else {
                    transactions[transactionID] = otherAmounts
                }
            }
        }
    }

    struct EvaluationSummary {
        let benefitAmount: AmountBounds
        let limitGroupUsedAmounts: [String: AmountBounds]
        let transactionAmounts: [UUID: TransactionAmountBounds]
    }

    struct PerformanceEvaluation {
        let amount: AmountBounds
        let nextThreshold: CandidateCardNextPerformanceThresholdResult
    }

    func validate(
        policy: CandidateCardPolicyTemplate,
        facts: [CandidateCardTransactionFact],
        classifications: [CandidateCardTransactionClassification],
        input: CandidateCardSimulationInput
    ) throws -> ValidatedInput {
        guard policy.schemaVersion == CandidateCardPolicyTemplate.currentSchemaVersion else {
            throw CandidateCardSimulationError.unsupportedSchemaVersion(policy.schemaVersion)
        }
        guard policy.unsupportedPolicyConditions.isEmpty else {
            throw CandidateCardSimulationError.unsupportedPolicyConditions(
                policy.unsupportedPolicyConditions
            )
        }
        try requireText(policy.cardName, field: "cardName")
        try requireText(policy.issuerName, field: "issuerName")
        try requireText(policy.productIdentifier, field: "productIdentifier")
        try requireText(policy.source.name, field: "source.name")
        try requireText(policy.source.reference, field: "source.reference")
        for exclusion in policy.performanceExclusions {
            try requireText(exclusion, field: "performanceExclusions")
        }
        for exclusion in policy.benefitExclusions {
            try requireText(exclusion, field: "benefitExclusions")
        }
        guard policy.annualFeeAmount >= 0 else {
            throw CandidateCardSimulationError.invalidPolicy("annualFeeAmount")
        }
        guard policy.performanceThresholdAmounts.allSatisfy({ $0 > 0 }) else {
            throw CandidateCardSimulationError.invalidPolicy("performanceThresholdAmounts")
        }
        guard policy.performanceThresholdAmounts == policy.performanceThresholdAmounts.sorted(),
              Set(policy.performanceThresholdAmounts).count == policy.performanceThresholdAmounts.count
        else {
            throw CandidateCardSimulationError.invalidPolicy("performanceThresholdAmounts")
        }

        let limitGroups = try uniqueByID(
            policy.limitGroups,
            kind: "limitGroup",
            id: \CandidateCardLimitGroup.id
        )
        for group in policy.limitGroups {
            try requireText(group.id, field: "limitGroup.id")
            try requireText(group.label, field: "limitGroup.label")
        }

        let assumptions = try uniqueByID(
            policy.performanceAssumptions,
            kind: "performanceAssumption",
            id: \CandidateCardPerformanceAssumption.id
        )
        guard !assumptions.isEmpty else {
            throw CandidateCardSimulationError.invalidPolicy("performanceAssumptions")
        }
        let expectedGroupIDs = Set(limitGroups.keys)
        guard policy.performanceAssumptions.filter(\.isGrace).count <= 1 else {
            throw CandidateCardSimulationError.invalidPolicy("multiple grace assumptions")
        }
        for assumption in policy.performanceAssumptions {
            try requireText(assumption.id, field: "performanceAssumption.id")
            try requireText(assumption.label, field: "performanceAssumption.label")
            if assumption.isGrace, assumption.previousMonthAmount != nil {
                throw CandidateCardSimulationError.invalidPolicy("grace.previousMonthAmount")
            }
            if !assumption.isGrace, assumption.previousMonthAmount == nil {
                throw CandidateCardSimulationError.invalidPolicy("performanceAssumption.previousMonthAmount")
            }
            if let amount = assumption.previousMonthAmount, amount < 0 {
                throw CandidateCardSimulationError.invalidPolicy("previousMonthAmount")
            }
            let actualGroupIDs = Set(assumption.limitGroupMaximumAmounts.keys)
            if let missing = expectedGroupIDs.subtracting(actualGroupIDs).sorted().first {
                throw CandidateCardSimulationError.missingIdentifier(
                    kind: "performanceAssumption.limitGroup",
                    id: missing
                )
            }
            if let unknown = actualGroupIDs.subtracting(expectedGroupIDs).sorted().first {
                throw CandidateCardSimulationError.unknownReference(
                    kind: "performanceAssumption.limitGroup",
                    id: unknown
                )
            }
            guard assumption.limitGroupMaximumAmounts.values.allSatisfy({ $0 >= 0 }) else {
                throw CandidateCardSimulationError.invalidPolicy("limitGroupMaximumAmount")
            }
        }

        let benefits = try uniqueByID(
            policy.benefits,
            kind: "benefit",
            id: \CandidateCardBenefitDefinition.id
        )
        for benefit in policy.benefits {
            try validate(benefit: benefit, knownLimitGroupIDs: expectedGroupIDs)
        }

        var factByID: [UUID: CandidateCardTransactionFact] = [:]
        for fact in facts {
            guard factByID.updateValue(fact, forKey: fact.id) == nil else {
                throw CandidateCardSimulationError.duplicateTransactionFact(fact.id)
            }
            guard fact.amount > 0 else {
                throw CandidateCardSimulationError.invalidPolicy("transaction.amount")
            }
            try requireText(fact.merchant, field: "transaction.merchant")
        }

        var classificationByID: [UUID: CandidateCardTransactionClassification] = [:]
        for classification in classifications {
            guard classificationByID.updateValue(classification, forKey: classification.transactionID) == nil else {
                throw CandidateCardSimulationError.duplicateClassification(classification.transactionID)
            }
            guard factByID[classification.transactionID] != nil else {
                throw CandidateCardSimulationError.classificationWithoutFact(classification.transactionID)
            }
            try validate(classification: classification, knownBenefitIDs: Set(benefits.keys))
        }
        if let missing = facts.first(where: { classificationByID[$0.id] == nil }) {
            throw CandidateCardSimulationError.missingClassification(missing.id)
        }

        var selectedIDs: Set<UUID> = []
        for id in input.selectedTransactionIDs {
            guard selectedIDs.insert(id).inserted else {
                throw CandidateCardSimulationError.duplicateSelection(id)
            }
            guard factByID[id] != nil else {
                throw CandidateCardSimulationError.unknownSelectedTransaction(id)
            }
        }

        var answers: [UUID: String] = [:]
        for answer in input.answers {
            guard answers.updateValue(answer.alternativeID, forKey: answer.transactionID) == nil else {
                throw CandidateCardSimulationError.duplicateAnswer(answer.transactionID)
            }
            guard let classification = classificationByID[answer.transactionID] else {
                throw CandidateCardSimulationError.unknownAnswerTransaction(answer.transactionID)
            }
            guard classification.question != nil, classification.alternatives.count > 1 else {
                throw CandidateCardSimulationError.invalidAnswer(
                    answer.transactionID,
                    answer.alternativeID
                )
            }
            guard classification.alternatives.contains(where: { $0.id == answer.alternativeID }) else {
                throw CandidateCardSimulationError.invalidAnswer(
                    answer.transactionID,
                    answer.alternativeID
                )
            }
        }

        guard let assumption = assumptions[input.performanceAssumptionID] else {
            throw CandidateCardSimulationError.unknownPerformanceAssumption(
                input.performanceAssumptionID
            )
        }

        return ValidatedInput(
            sortedFacts: facts.sorted(by: factSort),
            classifications: classificationByID,
            selectedIDs: selectedIDs,
            answers: answers,
            assumption: assumption
        )
    }

    func validate(
        benefit: CandidateCardBenefitDefinition,
        knownLimitGroupIDs: Set<String>
    ) throws {
        try requireText(benefit.id, field: "benefit.id")
        try requireText(benefit.label, field: "benefit.label")
        try requireText(benefit.conditionSummary, field: "benefit.conditionSummary")
        for note in benefit.exclusionNotes {
            try requireText(note, field: "benefit.exclusionNotes")
        }
        guard (0...10_000).contains(benefit.rateBasisPoints) else {
            throw CandidateCardSimulationError.invalidPolicy("benefit.rateBasisPoints")
        }
        if let minimum = benefit.minimumTransactionAmount, minimum < 0 {
            throw CandidateCardSimulationError.invalidPolicy("benefit.minimumTransactionAmount")
        }
        if let maximum = benefit.maximumTransactionAmount, maximum < 0 {
            throw CandidateCardSimulationError.invalidPolicy("benefit.maximumTransactionAmount")
        }
        if let minimum = benefit.minimumTransactionAmount,
           let maximum = benefit.maximumTransactionAmount,
           minimum > maximum {
            throw CandidateCardSimulationError.invalidPolicy("benefit.transactionAmountRange")
        }
        if let maximum = benefit.perTransactionMaximumBenefitAmount, maximum < 0 {
            throw CandidateCardSimulationError.invalidPolicy("benefit.perTransactionMaximumBenefitAmount")
        }
        if let count = benefit.monthlyCountLimit, count <= 0 {
            throw CandidateCardSimulationError.invalidPolicy("benefit.monthlyCountLimit")
        }
        guard benefit.priority >= 0 else {
            throw CandidateCardSimulationError.invalidPolicy("benefit.priority")
        }
        guard benefit.rounding.unit > 0 else {
            throw CandidateCardSimulationError.invalidPolicy("benefit.rounding.unit")
        }
        guard Set(benefit.limitGroupIDs).count == benefit.limitGroupIDs.count else {
            var seen: Set<String> = []
            let duplicate = benefit.limitGroupIDs.first { !seen.insert($0).inserted } ?? ""
            throw CandidateCardSimulationError.duplicateIdentifier(
                kind: "benefit.limitGroup",
                id: duplicate
            )
        }
        if let unknown = Set(benefit.limitGroupIDs).subtracting(knownLimitGroupIDs).sorted().first {
            throw CandidateCardSimulationError.unknownReference(
                kind: "benefit.limitGroup",
                id: unknown
            )
        }
    }

    func validate(
        classification: CandidateCardTransactionClassification,
        knownBenefitIDs: Set<String>
    ) throws {
        guard !classification.alternatives.isEmpty else {
            throw CandidateCardSimulationError.invalidClassification(
                classification.transactionID,
                "alternatives"
            )
        }
        var alternativeIDs: Set<String> = []
        for alternative in classification.alternatives {
            try requireText(alternative.id, field: "classification.alternative.id")
            guard alternativeIDs.insert(alternative.id).inserted else {
                throw CandidateCardSimulationError.invalidClassification(
                    classification.transactionID,
                    "duplicate alternative id"
                )
            }
            try requireText(alternative.performanceReason, field: "performanceReason")
            try requireText(alternative.benefitReason, field: "benefitReason")
            guard Set(alternative.benefitIDs).count == alternative.benefitIDs.count else {
                throw CandidateCardSimulationError.invalidClassification(
                    classification.transactionID,
                    "duplicate benefit id"
                )
            }
            if let unknown = Set(alternative.benefitIDs).subtracting(knownBenefitIDs).sorted().first {
                throw CandidateCardSimulationError.unknownReference(
                    kind: "classification.benefit",
                    id: unknown
                )
            }
        }
        if classification.alternatives.count > 1 {
            guard let question = classification.question, !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CandidateCardSimulationError.invalidClassification(
                    classification.transactionID,
                    "question"
                )
            }
            var answerLabels: Set<String> = []
            for alternative in classification.alternatives {
                guard let label = alternative.answerLabel,
                      !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw CandidateCardSimulationError.invalidClassification(
                        classification.transactionID,
                        "answerLabel"
                    )
                }
                let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
                guard answerLabels.insert(normalizedLabel).inserted else {
                    throw CandidateCardSimulationError.invalidClassification(
                        classification.transactionID,
                        "duplicate answerLabel"
                    )
                }
            }
            let computationalOutcomes = Set(classification.alternatives.map {
                ClassificationOutcome(
                    performance: $0.performance.rawValue,
                    benefitIDs: $0.benefitIDs.sorted()
                )
            })
            guard computationalOutcomes.count > 1 else {
                throw CandidateCardSimulationError.invalidClassification(
                    classification.transactionID,
                    "alternatives do not change calculation"
                )
            }
        } else {
            guard classification.question == nil else {
                throw CandidateCardSimulationError.invalidClassification(
                    classification.transactionID,
                    "question requires multiple alternatives"
                )
            }
            guard classification.alternatives[0].answerLabel == nil else {
                throw CandidateCardSimulationError.invalidClassification(
                    classification.transactionID,
                    "answerLabel requires multiple alternatives"
                )
            }
        }
    }

    func evaluateAllAlternatives(
        policy: CandidateCardPolicyTemplate,
        validated: ValidatedInput
    ) throws -> EvaluationSummary {
        let benefitsByID = Dictionary(uniqueKeysWithValues: policy.benefits.map { ($0.id, $0) })
        let benefitIndexes = Dictionary(
            uniqueKeysWithValues: policy.benefits.enumerated().map { ($0.element.id, $0.offset) }
        )
        let limitGroupIndexes = Dictionary(
            uniqueKeysWithValues: policy.limitGroups.enumerated().map { ($0.element.id, $0.offset) }
        )
        let limitGroupMaximumAmounts = policy.limitGroups.map {
            validated.assumption.limitGroupMaximumAmounts[$0.id] ?? 0
        }
        let initialKey = EvaluationStateKey(
            limitGroupUsedAmounts: Array(repeating: 0, count: policy.limitGroups.count),
            benefitCounts: Array(repeating: 0, count: policy.benefits.count)
        )
        let initialAccumulator = EvaluationAccumulator(
            benefitAmount: AmountBounds(exact: 0),
            transactions: [:]
        )
        var states: [EvaluationStateKey: EvaluationAccumulator] = [initialKey: initialAccumulator]

        for fact in validated.sortedFacts where validated.selectedIDs.contains(fact.id) {
            guard let classification = validated.classifications[fact.id] else {
                throw CandidateCardSimulationError.missingClassification(fact.id)
            }
            let alternatives: [CandidateCardClassificationAlternative]
            if let answer = validated.answers[fact.id] {
                alternatives = classification.alternatives.filter { $0.id == answer }
            } else {
                alternatives = classification.alternatives
            }

            var nextStates: [EvaluationStateKey: EvaluationAccumulator] = [:]
            for (state, accumulator) in states {
                for alternative in alternatives {
                    let transition = try transition(
                        policy: policy,
                        fact: fact,
                        alternative: alternative,
                        state: state,
                        benefitsByID: benefitsByID,
                        benefitIndexes: benefitIndexes,
                        limitGroupIndexes: limitGroupIndexes,
                        limitGroupMaximumAmounts: limitGroupMaximumAmounts
                    )
                    let nextState = EvaluationStateKey(
                        limitGroupUsedAmounts: transition.state.limitGroupUsedAmounts,
                        benefitCounts: transition.state.benefitCounts
                    )
                    var nextAccumulator = accumulator
                    nextAccumulator.benefitAmount = try adding(
                        nextAccumulator.benefitAmount,
                        transition.amounts.applied
                    )
                    nextAccumulator.transactions[fact.id] = TransactionAmountBounds(
                        raw: transition.amounts.raw,
                        applied: transition.amounts.applied,
                        benefits: transition.amounts.benefits
                    )

                    if var existing = nextStates[nextState] {
                        existing.merge(nextAccumulator)
                        nextStates[nextState] = existing
                    } else {
                        nextStates[nextState] = nextAccumulator
                    }
                    guard nextStates.count <= Self.maximumEvaluationStateCount else {
                        throw CandidateCardSimulationError.tooManyEvaluationStates(
                            limit: Self.maximumEvaluationStateCount
                        )
                    }
                }
            }
            states = nextStates
        }

        var benefit = AmountBounds(exact: 0)
        var didSetTotals = false
        var limitGroupAmounts: [String: AmountBounds] = [:]
        var transactions: [UUID: TransactionAmountBounds] = [:]
        for (state, accumulator) in states {
            if didSetTotals {
                benefit.merge(accumulator.benefitAmount)
            } else {
                benefit = accumulator.benefitAmount
                didSetTotals = true
            }
            for (index, group) in policy.limitGroups.enumerated() {
                let exact = AmountBounds(exact: state.limitGroupUsedAmounts[index])
                if var existing = limitGroupAmounts[group.id] {
                    existing.merge(exact)
                    limitGroupAmounts[group.id] = existing
                } else {
                    limitGroupAmounts[group.id] = exact
                }
            }
            for (transactionID, otherAmounts) in accumulator.transactions {
                if var amounts = transactions[transactionID] {
                    amounts.merge(otherAmounts)
                    transactions[transactionID] = amounts
                } else {
                    transactions[transactionID] = otherAmounts
                }
            }
        }

        return EvaluationSummary(
            benefitAmount: benefit,
            limitGroupUsedAmounts: limitGroupAmounts,
            transactionAmounts: transactions
        )
    }

    func evaluatePerformance(
        policy: CandidateCardPolicyTemplate,
        validated: ValidatedInput
    ) throws -> PerformanceEvaluation {
        var mandatoryAmount = 0
        var optionalAmounts: [Int] = []

        for fact in validated.sortedFacts where validated.selectedIDs.contains(fact.id) {
            guard let classification = validated.classifications[fact.id] else {
                throw CandidateCardSimulationError.missingClassification(fact.id)
            }
            let alternatives: [CandidateCardClassificationAlternative]
            if let answer = validated.answers[fact.id] {
                alternatives = classification.alternatives.filter { $0.id == answer }
            } else {
                alternatives = classification.alternatives
            }
            let decisions = Set(alternatives.map(\.performance))
            if decisions == [.included] {
                mandatoryAmount = try adding(mandatoryAmount, fact.amount)
            } else if decisions.contains(.included), decisions.contains(.excluded) {
                optionalAmounts.append(fact.amount)
            }
        }

        let maximumAmount = try optionalAmounts.reduce(mandatoryAmount, adding)
        return PerformanceEvaluation(
            amount: AmountBounds(minimum: mandatoryAmount, maximum: maximumAmount),
            nextThreshold: try nextThreshold(
                mandatoryAmount: mandatoryAmount,
                optionalAmounts: optionalAmounts,
                maximumAmount: maximumAmount,
                thresholds: policy.performanceThresholdAmounts
            )
        )
    }

    func transition(
        policy: CandidateCardPolicyTemplate,
        fact: CandidateCardTransactionFact,
        alternative: CandidateCardClassificationAlternative,
        state: EvaluationStateKey,
        benefitsByID: [String: CandidateCardBenefitDefinition],
        benefitIndexes: [String: Int],
        limitGroupIndexes: [String: Int],
        limitGroupMaximumAmounts: [Int]
    ) throws -> (state: EvaluationStateKey, amounts: ExactTransactionAmounts) {
        let candidates = try chosenBenefits(
            policy: policy,
            benefitIDs: alternative.benefitIDs,
            amount: fact.amount,
            benefits: benefitsByID
        )
        var usedAmounts = state.limitGroupUsedAmounts
        var counts = state.benefitCounts
        var rawForTransaction = 0
        var appliedForTransaction = 0
        var benefitAmounts: [String: BenefitAmountBounds] = [:]

        for (benefit, rawAmount) in candidates {
            rawForTransaction = try adding(rawForTransaction, rawAmount)
            guard let benefitIndex = benefitIndexes[benefit.id] else { continue }
            let currentCount = counts[benefitIndex]
            if let countLimit = benefit.monthlyCountLimit {
                counts[benefitIndex] = min(countLimit, currentCount + 1)
            }

            var applicableAmount = rawAmount
            if benefit.monthlyCountLimit.map({ currentCount >= $0 }) ?? false {
                applicableAmount = 0
            } else {
                for groupID in benefit.limitGroupIDs {
                    guard let groupIndex = limitGroupIndexes[groupID] else { continue }
                    applicableAmount = min(
                        applicableAmount,
                        limitGroupMaximumAmounts[groupIndex] - usedAmounts[groupIndex]
                    )
                }
                applicableAmount = max(0, applicableAmount)
            }
            appliedForTransaction = try adding(appliedForTransaction, applicableAmount)
            for groupID in benefit.limitGroupIDs {
                guard let groupIndex = limitGroupIndexes[groupID] else { continue }
                usedAmounts[groupIndex] = try adding(
                    usedAmounts[groupIndex],
                    applicableAmount
                )
            }
            benefitAmounts[benefit.id] = BenefitAmountBounds(
                raw: rawAmount,
                applied: applicableAmount
            )
        }

        return (
            EvaluationStateKey(
                limitGroupUsedAmounts: usedAmounts,
                benefitCounts: counts
            ),
            ExactTransactionAmounts(
                raw: rawForTransaction,
                applied: appliedForTransaction,
                benefits: benefitAmounts
            )
        )
    }

    func makeResult(
        policy: CandidateCardPolicyTemplate,
        validated: ValidatedInput,
        evaluation: EvaluationSummary,
        performance: PerformanceEvaluation
    ) throws -> CandidateCardSimulationResult {
        let selectedFacts = validated.sortedFacts.filter { validated.selectedIDs.contains($0.id) }
        let selectedAmount = try selectedFacts.reduce(0) { try adding($0, $1.amount) }
        let performanceRange = integerRange(performance.amount)
        let benefitRange = integerRange(evaluation.benefitAmount)
        let annualFeeMonthlyAmount = policy.annualFeeAmount / 12

        let pickingRate: CandidateCardRateRange?
        let annualFeeRate: CandidateCardRateRange?
        if selectedAmount == 0 {
            pickingRate = nil
            annualFeeRate = nil
        } else {
            pickingRate = CandidateCardRateRange(
                minimum: percentage(benefitRange.minimum, denominator: selectedAmount),
                maximum: percentage(benefitRange.maximum, denominator: selectedAmount)
            )
            annualFeeRate = CandidateCardRateRange(
                minimum: percentage(
                    try subtracting(benefitRange.minimum, annualFeeMonthlyAmount),
                    denominator: selectedAmount
                ),
                maximum: percentage(
                    try subtracting(benefitRange.maximum, annualFeeMonthlyAmount),
                    denominator: selectedAmount
                )
            )
        }

        let limitGroupResults = policy.limitGroups.map { group in
            let maximum = validated.assumption.limitGroupMaximumAmounts[group.id] ?? 0
            let used = integerRange(
                evaluation.limitGroupUsedAmounts[group.id] ?? AmountBounds(exact: 0)
            )
            return CandidateCardLimitGroupResult(
                id: group.id,
                label: group.label,
                maximumAmount: maximum,
                usedAmount: used,
                remainingAmount: CandidateCardIntegerRange(
                    minimum: maximum - used.maximum,
                    maximum: maximum - used.minimum
                )
            )
        }

        let transactionResults = try validated.sortedFacts.map { fact in
            if validated.selectedIDs.contains(fact.id) {
                let amounts = evaluation.transactionAmounts[fact.id]
                    ?? TransactionAmountBounds(raw: 0, applied: 0, benefits: [:])
                return transactionResult(
                    policy: policy,
                    transactionID: fact.id,
                    isSelected: true,
                    amounts: amounts
                )
            }

            guard let classification = validated.classifications[fact.id] else {
                throw CandidateCardSimulationError.missingClassification(fact.id)
            }
            let previewAlternatives: [CandidateCardClassificationAlternative]
            if let answer = validated.answers[fact.id] {
                previewAlternatives = classification.alternatives.filter { $0.id == answer }
            } else {
                previewAlternatives = classification.alternatives
            }
            let benefits = Dictionary(uniqueKeysWithValues: policy.benefits.map { ($0.id, $0) })
            var previewAmounts: TransactionAmountBounds?
            for alternative in previewAlternatives {
                let candidates = try chosenBenefits(
                    policy: policy,
                    benefitIDs: alternative.benefitIDs,
                    amount: fact.amount,
                    benefits: benefits
                )
                var raw = 0
                var benefitAmounts: [String: BenefitAmountBounds] = [:]
                for (benefit, rawAmount) in candidates {
                    raw = try adding(raw, rawAmount)
                    benefitAmounts[benefit.id] = BenefitAmountBounds(raw: rawAmount, applied: 0)
                }
                let alternativeAmounts = TransactionAmountBounds(
                    raw: raw,
                    applied: 0,
                    benefits: benefitAmounts
                )
                if var existing = previewAmounts {
                    existing.merge(alternativeAmounts)
                    previewAmounts = existing
                } else {
                    previewAmounts = alternativeAmounts
                }
            }
            return transactionResult(
                policy: policy,
                transactionID: fact.id,
                isSelected: false,
                amounts: previewAmounts
                    ?? TransactionAmountBounds(raw: 0, applied: 0, benefits: [:])
            )
        }

        return CandidateCardSimulationResult(
            calculatorVersion: Self.calculatorVersion,
            selectedTransactionCount: selectedFacts.count,
            selectedTransactionAmount: selectedAmount,
            performanceAmount: performanceRange,
            benefitAmount: benefitRange,
            pickingRatePercentage: pickingRate,
            annualFeeMonthlyAmount: annualFeeMonthlyAmount,
            annualFeeAdjustedPickingRatePercentage: annualFeeRate,
            nextPerformanceThreshold: performance.nextThreshold,
            limitGroups: limitGroupResults,
            transactions: transactionResults
        )
    }

    func transactionResult(
        policy: CandidateCardPolicyTemplate,
        transactionID: UUID,
        isSelected: Bool,
        amounts: TransactionAmountBounds
    ) -> CandidateCardTransactionResult {
        let benefitsByID = Dictionary(uniqueKeysWithValues: policy.benefits.map { ($0.id, $0) })
        let benefitResults = amounts.benefits.keys.compactMap { benefitID -> CandidateCardTransactionBenefitResult? in
            guard let benefit = benefitsByID[benefitID], let benefitAmounts = amounts.benefits[benefitID] else {
                return nil
            }
            return CandidateCardTransactionBenefitResult(
                benefitID: benefitID,
                label: benefit.label,
                rawBenefitAmount: integerRange(benefitAmounts.raw),
                appliedBenefitAmount: integerRange(benefitAmounts.applied),
                missedBenefitAmount: integerRange(benefitAmounts.missed)
            )
        }.sorted {
            guard let lhs = benefitsByID[$0.benefitID], let rhs = benefitsByID[$1.benefitID] else {
                return $0.benefitID < $1.benefitID
            }
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.id < rhs.id
        }
        return CandidateCardTransactionResult(
            transactionID: transactionID,
            isSelected: isSelected,
            rawBenefitAmount: integerRange(amounts.raw),
            appliedBenefitAmount: integerRange(amounts.applied),
            missedBenefitAmount: integerRange(amounts.missed),
            benefits: benefitResults,
            benefitBreakdownIsAdditive: benefitBreakdownIsAdditive(
                benefits: benefitResults,
                transaction: amounts
            )
        )
    }

    func benefitBreakdownIsAdditive(
        benefits: [CandidateCardTransactionBenefitResult],
        transaction: TransactionAmountBounds
    ) -> Bool {
        func sum(
            _ values: [CandidateCardIntegerRange]
        ) -> CandidateCardIntegerRange? {
            var minimum = 0
            var maximum = 0
            for value in values {
                let (nextMinimum, minimumOverflow) = minimum.addingReportingOverflow(value.minimum)
                let (nextMaximum, maximumOverflow) = maximum.addingReportingOverflow(value.maximum)
                guard !minimumOverflow, !maximumOverflow else { return nil }
                minimum = nextMinimum
                maximum = nextMaximum
            }
            return CandidateCardIntegerRange(minimum: minimum, maximum: maximum)
        }

        return sum(benefits.map(\.rawBenefitAmount)) == integerRange(transaction.raw)
            && sum(benefits.map(\.appliedBenefitAmount)) == integerRange(transaction.applied)
            && sum(benefits.map(\.missedBenefitAmount)) == integerRange(transaction.missed)
    }

    func chosenBenefits(
        policy: CandidateCardPolicyTemplate,
        benefitIDs: [String],
        amount: Int,
        benefits: [String: CandidateCardBenefitDefinition]
    ) throws -> [(CandidateCardBenefitDefinition, Int)] {
        var candidates: [(CandidateCardBenefitDefinition, Int)] = []
        for id in benefitIDs {
            guard let benefit = benefits[id] else { continue }
            if let minimum = benefit.minimumTransactionAmount, amount < minimum { continue }
            if let maximum = benefit.maximumTransactionAmount, amount > maximum { continue }
            let raw = try rawBenefit(amount: amount, benefit: benefit)
            candidates.append((benefit, raw))
        }
        candidates.sort {
            if $0.0.priority != $1.0.priority { return $0.0.priority < $1.0.priority }
            return $0.0.id < $1.0.id
        }
        if policy.stacking == .highestPriorityOnly {
            return candidates.first.map { [$0] } ?? []
        }
        return candidates
    }

    func rawBenefit(amount: Int, benefit: CandidateCardBenefitDefinition) throws -> Int {
        let (product, productOverflow) = Int64(amount).multipliedReportingOverflow(
            by: Int64(benefit.rateBasisPoints)
        )
        guard !productOverflow else { throw CandidateCardSimulationError.arithmeticOverflow }
        let (divisor, divisorOverflow) = Int64(10_000).multipliedReportingOverflow(
            by: Int64(benefit.rounding.unit)
        )
        guard !divisorOverflow, divisor > 0 else {
            throw CandidateCardSimulationError.arithmeticOverflow
        }

        let quotient = product / divisor
        let remainder = product % divisor
        let roundedUnits: Int64
        switch benefit.rounding.direction {
        case .floor:
            roundedUnits = quotient
        case .nearest:
            let halfRoundedUp = divisor / 2 + divisor % 2
            roundedUnits = quotient + (remainder >= halfRoundedUp ? 1 : 0)
        case .ceiling:
            roundedUnits = quotient + (remainder > 0 ? 1 : 0)
        }
        let (rounded, roundedOverflow) = roundedUnits.multipliedReportingOverflow(
            by: Int64(benefit.rounding.unit)
        )
        guard !roundedOverflow, let value = Int(exactly: rounded) else {
            throw CandidateCardSimulationError.arithmeticOverflow
        }
        return min(value, benefit.perTransactionMaximumBenefitAmount ?? value)
    }

    func nextThreshold(
        mandatoryAmount: Int,
        optionalAmounts: [Int],
        maximumAmount: Int,
        thresholds: [Int]
    ) throws -> CandidateCardNextPerformanceThresholdResult {
        guard let highestThreshold = thresholds.last else {
            return CandidateCardNextPerformanceThresholdResult(
                thresholdAmount: nil,
                remainingAmount: nil,
                includesNoNextThreshold: true
            )
        }
        guard mandatoryAmount < highestThreshold else {
            return CandidateCardNextPerformanceThresholdResult(
                thresholdAmount: nil,
                remainingAmount: nil,
                includesNoNextThreshold: true
            )
        }
        if optionalAmounts.isEmpty {
            let threshold = thresholds.first { $0 > mandatoryAmount } ?? highestThreshold
            return CandidateCardNextPerformanceThresholdResult(
                thresholdAmount: CandidateCardIntegerRange(
                    minimum: threshold,
                    maximum: threshold
                ),
                remainingAmount: CandidateCardIntegerRange(
                    minimum: threshold - mandatoryAmount,
                    maximum: threshold - mandatoryAmount
                ),
                includesNoNextThreshold: false
            )
        }

        let divisor = optionalAmounts.reduce(0, greatestCommonDivisor)
        let scale = max(1, divisor)
        let maximumIndex = (highestThreshold - 1 - mandatoryAmount) / scale
        let shifts = optionalAmounts.map { $0 / scale }.filter { $0 <= maximumIndex }

        var minimumThreshold: Int?
        var maximumThreshold: Int?
        var minimumRemaining: Int?
        var maximumRemaining: Int?
        var thresholdIndex = 0
        func record(index: Int) {
            let amount = mandatoryAmount + index * scale
            while thresholds[thresholdIndex] <= amount {
                thresholdIndex += 1
            }
            let threshold = thresholds[thresholdIndex]
            let remaining = threshold - amount
            minimumThreshold = minimumThreshold.map { min($0, threshold) } ?? threshold
            maximumThreshold = maximumThreshold.map { max($0, threshold) } ?? threshold
            minimumRemaining = minimumRemaining.map { min($0, remaining) } ?? remaining
            maximumRemaining = maximumRemaining.map { max($0, remaining) } ?? remaining
        }

        let bitCount = maximumIndex + 1
        let combinationUpperBound: Int
        if optionalAmounts.count >= Int.bitWidth - 1 {
            combinationUpperBound = Int.max
        } else {
            combinationUpperBound = 1 << optionalAmounts.count
        }
        let sparseIsSmaller = combinationUpperBound <= Self.maximumSparsePerformanceAmountCount
            && combinationUpperBound <= max(1, bitCount / 64)
        if bitCount <= Self.maximumDensePerformanceBitCount, !sparseIsSmaller {
            var words = [UInt64](repeating: 0, count: (bitCount + 63) / 64)
            words[0] = 1
            for shift in shifts where shift > 0 {
                let wordShift = shift / 64
                let bitShift = shift % 64
                guard wordShift < words.count else { continue }
                for destination in stride(
                    from: words.count - 1,
                    through: wordShift,
                    by: -1
                ) {
                    let source = destination - wordShift
                    var shifted = words[source] << bitShift
                    if bitShift > 0, source > 0 {
                        shifted |= words[source - 1] >> (64 - bitShift)
                    }
                    words[destination] |= shifted
                }
            }
            let validBitsInLastWord = bitCount % 64
            if validBitsInLastWord > 0 {
                words[words.count - 1] &= (UInt64(1) << validBitsInLastWord) - 1
            }
            for index in 0...maximumIndex {
                let mask = UInt64(1) << (index % 64)
                if words[index / 64] & mask != 0 {
                    record(index: index)
                }
            }
        } else {
            // Very large thresholds use a sparse exact representation. If even
            // that grows beyond the safety bound, answering ambiguous
            // performance questions reduces the state space deterministically.
            var reachable: Set<Int> = [0]
            for shift in shifts where shift > 0 {
                var additions: [Int] = []
                additions.reserveCapacity(reachable.count)
                for index in reachable {
                    let (next, overflow) = index.addingReportingOverflow(shift)
                    if !overflow, next <= maximumIndex {
                        additions.append(next)
                    }
                }
                reachable.formUnion(additions)
                guard reachable.count <= Self.maximumSparsePerformanceAmountCount else {
                    throw CandidateCardSimulationError.tooManyEvaluationStates(
                        limit: Self.maximumSparsePerformanceAmountCount
                    )
                }
            }
            for index in reachable.sorted() {
                record(index: index)
            }
        }

        return CandidateCardNextPerformanceThresholdResult(
            thresholdAmount: minimumThreshold.map {
                CandidateCardIntegerRange(minimum: $0, maximum: maximumThreshold ?? $0)
            },
            remainingAmount: minimumRemaining.map {
                CandidateCardIntegerRange(minimum: $0, maximum: maximumRemaining ?? $0)
            },
            includesNoNextThreshold: maximumAmount >= highestThreshold
        )
    }

    func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
        var a = lhs
        var b = rhs
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return a
    }

    func factSort(_ lhs: CandidateCardTransactionFact, _ rhs: CandidateCardTransactionFact) -> Bool {
        if lhs.occurredAt != rhs.occurredAt { return lhs.occurredAt < rhs.occurredAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    func percentage(_ numerator: Int, denominator: Int) -> Double {
        Double(numerator) / Double(denominator) * 100
    }

    func integerRange(_ values: [Int]) -> CandidateCardIntegerRange {
        CandidateCardIntegerRange(
            minimum: values.min() ?? 0,
            maximum: values.max() ?? 0
        )
    }

    func integerRange(_ bounds: AmountBounds) -> CandidateCardIntegerRange {
        CandidateCardIntegerRange(minimum: bounds.minimum, maximum: bounds.maximum)
    }

    func adding(_ bounds: AmountBounds, _ amount: Int) throws -> AmountBounds {
        AmountBounds(
            minimum: try adding(bounds.minimum, amount),
            maximum: try adding(bounds.maximum, amount)
        )
    }

    func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else { throw CandidateCardSimulationError.arithmeticOverflow }
        return sum
    }

    func subtracting(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (difference, overflow) = lhs.subtractingReportingOverflow(rhs)
        guard !overflow else { throw CandidateCardSimulationError.arithmeticOverflow }
        return difference
    }

    func requireText(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CandidateCardSimulationError.invalidPolicy(field)
        }
    }

    func uniqueByID<Element>(
        _ values: [Element],
        kind: String,
        id: KeyPath<Element, String>
    ) throws -> [String: Element] {
        var result: [String: Element] = [:]
        for value in values {
            let identifier = value[keyPath: id]
            guard result.updateValue(value, forKey: identifier) == nil else {
                throw CandidateCardSimulationError.duplicateIdentifier(kind: kind, id: identifier)
            }
        }
        return result
    }
}
