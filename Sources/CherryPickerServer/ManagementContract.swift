import Foundation

public struct CardBenefit: Codable, Equatable, Sendable {
    public let id: UUID
    public let label: String
    public let eligibleMerchants: [String]
    public let minimumTransactionAmount: Int
    public let requiredPreviousMonthPerformanceAmount: Int?
    public let rateBasisPoints: Int
    public let maximumAmount: Int?
    public let recurringPaymentOnly: Bool
    public let exclusionNotes: [String]

    public init(
        id: UUID,
        label: String,
        eligibleMerchants: [String],
        minimumTransactionAmount: Int,
        requiredPreviousMonthPerformanceAmount: Int?,
        rateBasisPoints: Int,
        maximumAmount: Int?,
        recurringPaymentOnly: Bool,
        exclusionNotes: [String]
    ) {
        self.id = id
        self.label = label
        self.eligibleMerchants = eligibleMerchants
        self.minimumTransactionAmount = minimumTransactionAmount
        self.requiredPreviousMonthPerformanceAmount = requiredPreviousMonthPerformanceAmount
        self.rateBasisPoints = rateBasisPoints
        self.maximumAmount = maximumAmount
        self.recurringPaymentOnly = recurringPaymentOnly
        self.exclusionNotes = exclusionNotes
    }
}

public enum BenefitLimitPolicyKind: String, Codable, Equatable, Sendable {
    case perBenefit
    case integrated
}

public struct BenefitLimitTier: Codable, Equatable, Sendable {
    public let minimumPreviousMonthPerformanceAmount: Int
    public let maximumAmount: Int
}

public struct BenefitLimitPolicy: Codable, Equatable, Sendable {
    public let type: BenefitLimitPolicyKind
    public let tiers: [BenefitLimitTier]?
}

public struct ManagedCard: Codable, Equatable, Sendable {
    public let id: UUID
    public let cardTypeCode: String
    public let displayName: String
    public let issuerCode: String
    public let lastFour: String
    public let performanceThresholdAmounts: [Int]
    public let benefitLimitPolicy: BenefitLimitPolicy
    public let performanceCalculationBasis: String
    public let benefits: [CardBenefit]
    public let performanceExclusions: [String]
    public let benefitExclusions: [String]

    public init(
        id: UUID,
        cardTypeCode: String,
        displayName: String,
        issuerCode: String,
        lastFour: String,
        performanceThresholdAmounts: [Int],
        benefitLimitPolicy: BenefitLimitPolicy,
        performanceCalculationBasis: String,
        benefits: [CardBenefit],
        performanceExclusions: [String],
        benefitExclusions: [String]
    ) {
        self.id = id
        self.cardTypeCode = cardTypeCode
        self.displayName = displayName
        self.issuerCode = issuerCode
        self.lastFour = lastFour
        self.performanceThresholdAmounts = performanceThresholdAmounts
        self.benefitLimitPolicy = benefitLimitPolicy
        self.performanceCalculationBasis = performanceCalculationBasis
        self.benefits = benefits
        self.performanceExclusions = performanceExclusions
        self.benefitExclusions = benefitExclusions
    }
}

public struct CardsResponse: Codable, Equatable, Sendable {
    public let cards: [ManagedCard]

    public init(cards: [ManagedCard]) {
        self.cards = cards
    }
}

public struct CardResponse: Codable, Equatable, Sendable {
    public let card: ManagedCard

    public init(card: ManagedCard) {
        self.card = card
    }
}

public struct CardCreateRequest: Codable, Equatable, Sendable {
    public let cardTypeCode: String
    public let displayName: String
    public let lastFour: String

    public init(cardTypeCode: String, displayName: String, lastFour: String) {
        self.cardTypeCode = cardTypeCode
        self.displayName = displayName
        self.lastFour = lastFour
    }
}

public struct CardUpdateRequest: Codable, Equatable, Sendable {
    public let displayName: String
    /// Accepted for wire compatibility with the issue #5 client. The server
    /// derives issuer identity from `cardTypeCode` and does not persist this.
    public let issuerCode: String?
    public let lastFour: String
    public init(
        displayName: String,
        issuerCode: String? = nil,
        lastFour: String
    ) {
        self.displayName = displayName
        self.issuerCode = issuerCode
        self.lastFour = lastFour
    }
}

public struct BenefitOffset: Codable, Equatable, Sendable {
    public let benefitId: UUID
    public let offsetAmount: Int

    public init(benefitId: UUID, offsetAmount: Int) {
        self.benefitId = benefitId
        self.offsetAmount = offsetAmount
    }
}

public struct MonthlyOffsets: Codable, Equatable, Sendable {
    public let cardId: UUID
    public let period: String
    public let performanceOffsetAmount: Int
    public let benefitOffsets: [BenefitOffset]

    public init(
        cardId: UUID,
        period: String,
        performanceOffsetAmount: Int,
        benefitOffsets: [BenefitOffset]
    ) {
        self.cardId = cardId
        self.period = period
        self.performanceOffsetAmount = performanceOffsetAmount
        self.benefitOffsets = benefitOffsets
    }
}

public struct MonthlyOffsetsUpdateRequest: Codable, Equatable, Sendable {
    public let performanceOffsetAmount: Int
    public let benefitOffsets: [BenefitOffset]

    public init(performanceOffsetAmount: Int, benefitOffsets: [BenefitOffset]) {
        self.performanceOffsetAmount = performanceOffsetAmount
        self.benefitOffsets = benefitOffsets
    }
}

public struct MonthlyOffsetsResponse: Codable, Equatable, Sendable {
    public let monthlyOffsets: MonthlyOffsets

    public init(monthlyOffsets: MonthlyOffsets) {
        self.monthlyOffsets = monthlyOffsets
    }
}

public enum TransactionReviewStatus: String, Codable, Equatable, Sendable {
    case unreviewed
    case reviewed
}

public enum PerformanceDecision: String, Codable, Equatable, Sendable {
    case included
    case excluded
}

public struct ManagedTransaction: Codable, Equatable, Sendable {
    public let id: UUID
    public let cardId: UUID?
    public let cardDisplayName: String?
    public let cardLastFour: String?
    public let capturedAt: Date
    public let occurredAt: Date
    public let parseStatus: StoredParseStatus
    public let reviewStatus: TransactionReviewStatus
    public let kind: String?
    public let amount: Int?
    public let merchant: String?
    public let performance: PerformanceDecision?
    public let benefitIds: [UUID]
    public let memo: String
    public let aggregationExcluded: Bool

    public init(
        id: UUID,
        cardId: UUID?,
        cardDisplayName: String?,
        cardLastFour: String?,
        capturedAt: Date,
        occurredAt: Date,
        parseStatus: StoredParseStatus,
        reviewStatus: TransactionReviewStatus,
        kind: String?,
        amount: Int?,
        merchant: String?,
        performance: PerformanceDecision?,
        benefitIds: [UUID],
        memo: String,
        aggregationExcluded: Bool
    ) {
        self.id = id
        self.cardId = cardId
        self.cardDisplayName = cardDisplayName
        self.cardLastFour = cardLastFour
        self.capturedAt = capturedAt
        self.occurredAt = occurredAt
        self.parseStatus = parseStatus
        self.reviewStatus = reviewStatus
        self.kind = kind
        self.amount = amount
        self.merchant = merchant
        self.performance = performance
        self.benefitIds = benefitIds
        self.memo = memo
        self.aggregationExcluded = aggregationExcluded
    }
}

public struct TransactionsResponse: Codable, Equatable, Sendable {
    public let transactions: [ManagedTransaction]

    public init(transactions: [ManagedTransaction]) {
        self.transactions = transactions
    }
}

public struct TransactionResponse: Codable, Equatable, Sendable {
    public let transaction: ManagedTransaction

    public init(transaction: ManagedTransaction) {
        self.transaction = transaction
    }
}

public struct TransactionReviewInput: Codable, Equatable, Sendable {
    public let performance: PerformanceDecision?
    public let benefitIds: [UUID]
    public let memo: String

    public init(
        performance: PerformanceDecision?,
        benefitIds: [UUID],
        memo: String
    ) {
        self.performance = performance
        self.benefitIds = benefitIds
        self.memo = memo
    }
}

public struct TransactionUpdateRequest: Codable, Equatable, Sendable {
    public let review: TransactionReviewInput
    public let aggregationExcluded: Bool

    public init(review: TransactionReviewInput, aggregationExcluded: Bool) {
        self.review = review
        self.aggregationExcluded = aggregationExcluded
    }
}

public struct PerformanceProgress: Codable, Equatable, Sendable {
    public let currentAmount: Int
    public let targetAmount: Int
    public let remainingAmount: Int
    public let excludedAmount: Int
    public let unconfirmedAmount: Int
    public let unconfirmedCount: Int

    public init(
        currentAmount: Int,
        targetAmount: Int,
        remainingAmount: Int,
        excludedAmount: Int,
        unconfirmedAmount: Int,
        unconfirmedCount: Int
    ) {
        self.currentAmount = currentAmount
        self.targetAmount = targetAmount
        self.remainingAmount = remainingAmount
        self.excludedAmount = excludedAmount
        self.unconfirmedAmount = unconfirmedAmount
        self.unconfirmedCount = unconfirmedCount
    }
}

public struct BenefitProgress: Codable, Equatable, Sendable {
    public let id: UUID
    public let label: String
    public let calculationAmount: Int
    public let receivedAmount: Int
    public let maximumAmount: Int?

    public init(
        id: UUID,
        label: String,
        calculationAmount: Int,
        receivedAmount: Int,
        maximumAmount: Int?
    ) {
        self.id = id
        self.label = label
        self.calculationAmount = calculationAmount
        self.receivedAmount = receivedAmount
        self.maximumAmount = maximumAmount
    }
}

public struct DashboardBenefitLimit: Codable, Equatable, Sendable {
    public let type: BenefitLimitPolicyKind
    public let maximumAmount: Int?
    public let receivedAmount: Int?
    public let remainingAmount: Int?
}

public struct CardDashboard: Codable, Equatable, Sendable {
    public let cardId: UUID
    public let period: String
    public let performance: PerformanceProgress
    public let benefitLimit: DashboardBenefitLimit
    public let benefits: [BenefitProgress]
    public let benefitUnconfirmedCount: Int

    public init(
        cardId: UUID,
        period: String,
        performance: PerformanceProgress,
        benefitLimit: DashboardBenefitLimit,
        benefits: [BenefitProgress],
        benefitUnconfirmedCount: Int
    ) {
        self.cardId = cardId
        self.period = period
        self.performance = performance
        self.benefitLimit = benefitLimit
        self.benefits = benefits
        self.benefitUnconfirmedCount = benefitUnconfirmedCount
    }
}

public struct DashboardResponse: Codable, Equatable, Sendable {
    public let dashboard: CardDashboard

    public init(dashboard: CardDashboard) {
        self.dashboard = dashboard
    }
}
