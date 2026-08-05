import Foundation
import SwiftData

enum CherryPickerSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [TransactionRecord.self] }

    @Model
    final class TransactionRecord {
        @Attribute(.unique) var id: UUID
        var receivedAt: Date
        var originalMessage: String
        var normalizedMessageHash: String
        var parseStatusRaw: String
        var kindRaw: String?
        var cardLast4: String?
        var amount: Int?
        var month: Int?
        var day: Int?
        var hour: Int?
        var minute: Int?
        var merchant: String?
        var accountBalance: Int?
        var parserVersion: String?
        var parseFailureReason: String?
        var reviewStatusRaw: String?
        var performanceDecisionRaw: String?
        var benefitDecisionRaw: String?
        var benefitAmount: Int?
        var userMemo: String?
        var hasUserEdits: Bool?
        var updatedAt: Date?

        init(
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
}

enum CherryPickerSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [CardRecord.self, TransactionRecord.self] }

    @Model
    final class CardRecord {
        #Unique<CardRecord>([\.issuerCode, \.lastFour])

        @Attribute(.unique) var id: UUID
        var displayName: String
        var issuerCode: String
        var lastFour: String
        var performanceTargetAmount: Int?
        var periodRuleKindRaw: String
        var timeZoneIdentifier: String
        var createdAt: Date
        var updatedAt: Date
        @Relationship(deleteRule: .nullify, inverse: \TransactionRecord.card)
        var transactions: [TransactionRecord]

        init(
            id: UUID = UUID(),
            displayName: String,
            issuerCode: String,
            lastFour: String,
            performanceTargetAmount: Int?,
            periodRuleKindRaw: String = "calendarMonth",
            timeZoneIdentifier: String = "Asia/Seoul",
            createdAt: Date = .now,
            updatedAt: Date = .now
        ) {
            self.id = id
            self.displayName = displayName
            self.issuerCode = issuerCode
            self.lastFour = lastFour
            self.performanceTargetAmount = performanceTargetAmount
            self.periodRuleKindRaw = periodRuleKindRaw
            self.timeZoneIdentifier = timeZoneIdentifier
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.transactions = []
        }
    }

    @Model
    final class TransactionRecord {
        @Attribute(.unique) var id: UUID
        var receivedAt: Date
        var createdAt: Date?
        var originalMessage: String
        var normalizedMessageHash: String

        var parseStatusRaw: String
        @Attribute(originalName: "kindRaw") var parsedKindRaw: String?
        @Attribute(originalName: "cardLast4") var parsedCardLastFour: String?
        @Attribute(originalName: "amount") var parsedAmount: Int?
        @Attribute(originalName: "month") var parsedMonth: Int?
        @Attribute(originalName: "day") var parsedDay: Int?
        @Attribute(originalName: "hour") var parsedHour: Int?
        @Attribute(originalName: "minute") var parsedMinute: Int?
        @Attribute(originalName: "merchant") var parsedMerchant: String?
        @Attribute(originalName: "accountBalance") var parsedAccountBalance: Int?
        var parserVersion: String?
        var parseFailureReason: String?

        @Attribute(originalName: "hasUserEdits") var legacyHasUserEdits: Bool?
        var hasKindOverride: Bool = false
        var kindOverrideRaw: String?
        var hasAmountOverride: Bool = false
        var amountOverride: Int?
        var hasDateOverride: Bool = false
        var dateOverrideYear: Int?
        var dateOverrideMonth: Int?
        var dateOverrideDay: Int?
        var dateOverrideHour: Int?
        var dateOverrideMinute: Int?
        var dateOverridePrecisionRaw: String?
        var hasMerchantOverride: Bool = false
        var merchantOverride: String?

        var resolvedYear: Int?
        var resolvedMonth: Int?
        var resolvedDay: Int?
        var resolvedHour: Int?
        var resolvedMinute: Int?
        var resolvedInstant: Date?
        var datePrecisionRaw: String?
        var dateResolutionSourceRaw: String?
        var dateResolverVersion: String?
        var dateTimeZoneIdentifier: String?

        var cardAssignmentSourceRaw: String?
        var card: CardRecord?
        var linkedApproval: TransactionRecord?
        @Relationship(deleteRule: .nullify, inverse: \TransactionRecord.linkedApproval)
        var linkedCancellations: [TransactionRecord] = []

        var reviewStatusRaw: String?
        var performanceDecisionRaw: String?
        var benefitDecisionRaw: String?
        var benefitAmount: Int?
        var benefitUnitCode: String?
        var userMemo: String?
        var updatedAt: Date?

        init(
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
            self.createdAt = receivedAt
            self.originalMessage = originalMessage
            self.normalizedMessageHash = normalizedMessageHash
            self.parseStatusRaw = parseStatusRaw
            self.parsedKindRaw = kindRaw
            self.parsedCardLastFour = cardLast4
            self.parsedAmount = amount
            self.parsedMonth = month
            self.parsedDay = day
            self.parsedHour = hour
            self.parsedMinute = minute
            self.parsedMerchant = merchant
            self.parsedAccountBalance = accountBalance
            self.parserVersion = parserVersion
            self.parseFailureReason = parseFailureReason
            self.legacyHasUserEdits = hasUserEdits ?? false
            self.reviewStatusRaw = reviewStatusRaw ?? ReviewStatus.unreviewed.rawValue
            self.performanceDecisionRaw = performanceDecisionRaw ?? PerformanceDecision.undecided.rawValue
            self.benefitDecisionRaw = benefitDecisionRaw ?? BenefitDecision.undecided.rawValue
            self.benefitAmount = benefitAmount
            self.userMemo = userMemo
            self.updatedAt = updatedAt ?? receivedAt

            if hasUserEdits == true {
                hasKindOverride = true
                kindOverrideRaw = kindRaw
                hasAmountOverride = true
                amountOverride = amount
                hasDateOverride = true
                dateOverrideMonth = month
                dateOverrideDay = day
                dateOverrideHour = hour
                dateOverrideMinute = minute
                dateOverridePrecisionRaw = hour == nil ? "day" : "minute"
                hasMerchantOverride = true
                merchantOverride = merchant
            }
        }

        var kindRaw: String? {
            get { hasKindOverride ? kindOverrideRaw : parsedKindRaw }
            set {
                hasKindOverride = true
                kindOverrideRaw = newValue
            }
        }

        var cardLast4: String? { parsedCardLastFour }

        var amount: Int? {
            get { hasAmountOverride ? amountOverride : parsedAmount }
            set {
                hasAmountOverride = true
                amountOverride = newValue
            }
        }

        var month: Int? { hasDateOverride ? dateOverrideMonth : (resolvedMonth ?? parsedMonth) }
        var day: Int? { hasDateOverride ? dateOverrideDay : (resolvedDay ?? parsedDay) }
        var hour: Int? { hasDateOverride ? dateOverrideHour : (resolvedHour ?? parsedHour) }
        var minute: Int? { hasDateOverride ? dateOverrideMinute : (resolvedMinute ?? parsedMinute) }

        var merchant: String? {
            get { hasMerchantOverride ? merchantOverride : parsedMerchant }
            set {
                hasMerchantOverride = true
                merchantOverride = newValue
            }
        }

        var accountBalance: Int? { parsedAccountBalance }

        var hasUserEdits: Bool? {
            get { hasKindOverride || hasAmountOverride || hasDateOverride || hasMerchantOverride }
            set { legacyHasUserEdits = newValue }
        }
    }
}

typealias CardRecord = CherryPickerSchemaV2.CardRecord
typealias TransactionRecord = CherryPickerSchemaV2.TransactionRecord

enum ParseStatus: String, Codable, Sendable {
    case pending
    case parsed
    case failed
}

enum ReviewStatus: String, Codable, Equatable, Sendable {
    case unreviewed
    case reviewed
}

enum PerformanceDecision: String, Codable, Equatable, Sendable {
    case undecided
    case included
    case excluded
}

enum BenefitDecision: String, Codable, Equatable, Sendable {
    case undecided
    case received
    case missed
    case notEligible
}
