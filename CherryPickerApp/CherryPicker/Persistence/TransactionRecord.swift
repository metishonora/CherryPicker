import Foundation
import SwiftData

/// The persistence representation of one received card notification.
///
/// The raw message is kept even when parsing fails. User-facing views should
/// intentionally choose which fields to expose; in particular, the original
/// message and account balance are diagnostic data and are not shown in the
/// default inbox list.
@Model
public final class TransactionRecord {
    @Attribute(.unique)
    public var id: UUID
    public var receivedAt: Date
    public var originalMessage: String
    public var normalizedMessageHash: String

    public var parseStatusRaw: String
    public var kindRaw: String?
    public var cardLast4: String?
    public var amount: Int?
    public var month: Int?
    public var day: Int?
    public var hour: Int?
    public var minute: Int?
    public var merchant: String?
    public var accountBalance: Int?
    public var parserVersion: String?
    public var parseFailureReason: String?

    // These fields are optional to keep adding them migration-safe for records
    // created by an earlier model version. New records receive the defaults in
    // the initializer below, while migrated records may remain nil until they
    // are next edited.
    public var reviewStatusRaw: String?
    public var performanceDecisionRaw: String?
    public var benefitDecisionRaw: String?
    public var benefitAmount: Int?
    public var userMemo: String?
    public var hasUserEdits: Bool?
    public var updatedAt: Date?

    public init(
        id: UUID = UUID(),
        receivedAt: Date,
        originalMessage: String,
        normalizedMessageHash: String,
        parseStatusRaw: String = ParseStatus.pending.rawValue,
        kindRaw: String? = nil,
        cardLast4: String? = nil,
        amount: Int? = nil,
        month: Int? = nil,
        day: Int? = nil,
        hour: Int? = nil,
        minute: Int? = nil,
        merchant: String? = nil,
        accountBalance: Int? = nil,
        parserVersion: String? = nil,
        parseFailureReason: String? = nil,
        reviewStatusRaw: String? = nil,
        performanceDecisionRaw: String? = nil,
        benefitDecisionRaw: String? = nil,
        benefitAmount: Int? = nil,
        userMemo: String? = nil,
        hasUserEdits: Bool? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.receivedAt = receivedAt
        self.originalMessage = originalMessage
        self.normalizedMessageHash = normalizedMessageHash
        self.parseStatusRaw = parseStatusRaw
        self.kindRaw = kindRaw
        self.cardLast4 = cardLast4
        self.amount = amount
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.merchant = merchant
        self.accountBalance = accountBalance
        self.parserVersion = parserVersion
        self.parseFailureReason = parseFailureReason
        self.reviewStatusRaw = reviewStatusRaw ?? ReviewStatus.unreviewed.rawValue
        self.performanceDecisionRaw = performanceDecisionRaw ?? PerformanceDecision.undecided.rawValue
        self.benefitDecisionRaw = benefitDecisionRaw ?? BenefitDecision.undecided.rawValue
        self.benefitAmount = benefitAmount
        self.userMemo = userMemo
        self.hasUserEdits = hasUserEdits ?? false
        self.updatedAt = updatedAt ?? receivedAt
    }
}

public enum ParseStatus: String, Codable, Sendable {
    case pending
    case parsed
    case failed
}

/// Whether a transaction has been reviewed by the user.
public enum ReviewStatus: String, Codable, Equatable, Sendable {
    case unreviewed
    case reviewed
}

/// The user's decision about whether a transaction counts toward card
/// performance requirements.
public enum PerformanceDecision: String, Codable, Equatable, Sendable {
    case undecided
    case included
    case excluded
}

/// The user's decision about the benefit received for a transaction.
public enum BenefitDecision: String, Codable, Equatable, Sendable {
    case undecided
    case received
    case missed
    case notEligible
}
