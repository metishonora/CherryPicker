import Foundation

public struct CardBenefit: Codable, Equatable, Sendable {
    public let id: UUID
    public let label: String
    public let rateBasisPoints: Int
    public let maximumAmount: Int

    public init(id: UUID, label: String, rateBasisPoints: Int, maximumAmount: Int) {
        self.id = id
        self.label = label
        self.rateBasisPoints = rateBasisPoints
        self.maximumAmount = maximumAmount
    }
}

public struct ManagedCard: Codable, Equatable, Sendable {
    public let id: UUID
    public let displayName: String
    public let issuerCode: String
    public let lastFour: String
    public let performanceTargetAmount: Int
    public let benefits: [CardBenefit]

    public init(
        id: UUID,
        displayName: String,
        issuerCode: String,
        lastFour: String,
        performanceTargetAmount: Int,
        benefits: [CardBenefit]
    ) {
        self.id = id
        self.displayName = displayName
        self.issuerCode = issuerCode
        self.lastFour = lastFour
        self.performanceTargetAmount = performanceTargetAmount
        self.benefits = benefits
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

public struct CardUpdateRequest: Codable, Equatable, Sendable {
    public let displayName: String
    public let issuerCode: String
    public let lastFour: String
    public let performanceTargetAmount: Int

    public init(
        displayName: String,
        issuerCode: String,
        lastFour: String,
        performanceTargetAmount: Int
    ) {
        self.displayName = displayName
        self.issuerCode = issuerCode
        self.lastFour = lastFour
        self.performanceTargetAmount = performanceTargetAmount
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
    public let cardId: UUID
    public let cardDisplayName: String
    public let cardLastFour: String
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
        cardId: UUID,
        cardDisplayName: String,
        cardLastFour: String,
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

    public init(currentAmount: Int, targetAmount: Int) {
        self.currentAmount = currentAmount
        self.targetAmount = targetAmount
    }
}

public struct BenefitProgress: Codable, Equatable, Sendable {
    public let id: UUID
    public let label: String
    public let receivedAmount: Int
    public let maximumAmount: Int

    public init(id: UUID, label: String, receivedAmount: Int, maximumAmount: Int) {
        self.id = id
        self.label = label
        self.receivedAmount = receivedAmount
        self.maximumAmount = maximumAmount
    }
}

public struct CardDashboard: Codable, Equatable, Sendable {
    public let cardId: UUID
    public let performance: PerformanceProgress
    public let benefits: [BenefitProgress]

    public init(
        cardId: UUID,
        performance: PerformanceProgress,
        benefits: [BenefitProgress]
    ) {
        self.cardId = cardId
        self.performance = performance
        self.benefits = benefits
    }
}

public struct DashboardResponse: Codable, Equatable, Sendable {
    public let dashboard: CardDashboard

    public init(dashboard: CardDashboard) {
        self.dashboard = dashboard
    }
}
