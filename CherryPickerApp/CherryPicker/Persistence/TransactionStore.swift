import CryptoKit
import Foundation
import SwiftData

import CherryPickerCore

public enum SaveOutcome: Sendable, Equatable {
    case saved(UUID)
    case duplicate(UUID)

    public var id: UUID {
        switch self {
        case let .saved(id), let .duplicate(id):
            return id
        }
    }

    public var wasDuplicate: Bool {
        if case .duplicate = self { return true }
        return false
    }

    public var summary: String {
        switch self {
        case let .saved(id):
            return "거래 문자를 저장했습니다. (\(id.uuidString.prefix(8)))"
        case let .duplicate(id):
            return "같은 거래 문자가 이미 저장되어 중복을 건너뛰었습니다. (\(id.uuidString.prefix(8)))"
        }
    }
}

struct TransactionUserPatch: Equatable, Sendable {
    let kindRaw: String
    let amount: Int
    let merchant: String
    let year: Int
    let month: Int
    let day: Int
    let hour: Int?
    let minute: Int?
    let reviewStatusRaw: String
    let performanceDecisionRaw: String
    let benefitDecisionRaw: String
    let benefitAmount: Int?
    let userMemo: String
}

enum TransactionStoreError: Error, Equatable, Sendable {
    case transactionNotFound
    case invalidKind
    case invalidAmount
    case merchantRequired
    case invalidDate
    case invalidReviewStatus
    case invalidPerformanceDecision
    case invalidBenefitDecision
    case invalidBenefitAmount
}

enum MessageFingerprint {
    static func normalized(_ rawMessage: String) -> String {
        let lineBreaksNormalized = rawMessage
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        return lineBreaksNormalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func sha256(_ normalizedMessage: String) -> String {
        let digest = SHA256.hash(data: Data(normalizedMessage.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Serializes local SwiftData writes and applies the ten-minute duplicate rule.
@ModelActor
public actor TransactionStore {
    public func save(rawMessage: String, receivedAt: Date = .now) throws -> SaveOutcome {
        _ = try seedDefaultCardIfNeeded()
        let normalizedMessage = MessageFingerprint.normalized(rawMessage)
        let normalizedHash = MessageFingerprint.sha256(normalizedMessage)

        // The MVP inbox is small, so fetching the hash column's records and
        // checking the time window in Swift keeps this code compatible with
        // SwiftData predicate macro changes across iOS releases.
        let descriptor = FetchDescriptor<TransactionRecord>(
            sortBy: [SortDescriptor(\TransactionRecord.receivedAt, order: .reverse)]
        )
        let existingRecords = try modelContext.fetch(descriptor)
        if let duplicate = existingRecords.first(where: {
            $0.normalizedMessageHash == normalizedHash
                && abs(receivedAt.timeIntervalSince($0.receivedAt)) <= 10 * 60
        }) {
            // A parser upgrade may refresh an untouched record, but once the
            // user has edited any transaction field their values are
            // authoritative and must not be overwritten by reprocessing.
            if duplicate.hasUserEdits != true
                && (duplicate.parseStatusRaw != ParseStatus.parsed.rawValue
                    || duplicate.parserVersion != MGCardMessageParser.currentParserVersion) {
                let parser = MGCardMessageParser()
                try apply(parser.parse(duplicate.originalMessage), to: duplicate)
                duplicate.updatedAt = receivedAt
                try modelContext.save()
            }
            return .duplicate(duplicate.id)
        }

        // Persist the raw message before attempting to parse it. This ensures
        // unsupported or malformed notifications remain available for review.
        let record = TransactionRecord(
            receivedAt: receivedAt,
            originalMessage: rawMessage,
            normalizedMessageHash: normalizedHash
        )
        modelContext.insert(record)
        try modelContext.save()

        let parser = MGCardMessageParser()
        try apply(parser.parse(rawMessage), to: record)
        try modelContext.save()
        return .saved(record.id)
    }

    func update(id: UUID, patch: TransactionUserPatch) throws {
        guard let record = try modelContext.fetch(FetchDescriptor<TransactionRecord>()).first(where: {
            $0.id == id
        }) else {
            throw TransactionStoreError.transactionNotFound
        }
        guard patch.kindRaw == "approval" || patch.kindRaw == "cancellation" else {
            throw TransactionStoreError.invalidKind
        }
        guard patch.amount > 0 else { throw TransactionStoreError.invalidAmount }

        let merchant = patch.merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !merchant.isEmpty else { throw TransactionStoreError.merchantRequired }
        guard ReviewStatus(rawValue: patch.reviewStatusRaw) != nil else {
            throw TransactionStoreError.invalidReviewStatus
        }
        guard PerformanceDecision(rawValue: patch.performanceDecisionRaw) != nil else {
            throw TransactionStoreError.invalidPerformanceDecision
        }
        guard BenefitDecision(rawValue: patch.benefitDecisionRaw) != nil else {
            throw TransactionStoreError.invalidBenefitDecision
        }
        if patch.benefitDecisionRaw == BenefitDecision.received.rawValue {
            guard let benefitAmount = patch.benefitAmount, benefitAmount >= 0 else {
                throw TransactionStoreError.invalidBenefitAmount
            }
        }

        do {
            _ = try ParsedLocalDate(
                year: patch.year,
                month: patch.month,
                day: patch.day,
                hour: patch.hour,
                minute: patch.minute,
                timeZoneIdentifier: "Asia/Seoul"
            )
        } catch {
            throw TransactionStoreError.invalidDate
        }

        record.hasKindOverride = true
        record.kindOverrideRaw = patch.kindRaw
        record.hasAmountOverride = true
        record.amountOverride = patch.amount
        record.hasMerchantOverride = true
        record.merchantOverride = merchant
        record.hasDateOverride = true
        record.dateOverrideYear = patch.year
        record.dateOverrideMonth = patch.month
        record.dateOverrideDay = patch.day
        record.dateOverrideHour = patch.hour
        record.dateOverrideMinute = patch.minute
        record.dateOverridePrecisionRaw = patch.hour == nil ? "day" : "minute"
        record.reviewStatusRaw = patch.reviewStatusRaw
        record.performanceDecisionRaw = patch.performanceDecisionRaw
        record.benefitDecisionRaw = patch.benefitDecisionRaw
        if patch.benefitDecisionRaw == BenefitDecision.received.rawValue {
            record.benefitAmount = patch.benefitAmount
            record.benefitUnitCode = "KRW"
        } else {
            record.benefitAmount = nil
            record.benefitUnitCode = nil
        }
        record.userMemo = patch.userMemo.trimmingCharacters(in: .whitespacesAndNewlines)
        record.updatedAt = .now
        try modelContext.save()
    }

    func delete(id: UUID) throws {
        guard let record = try modelContext.fetch(FetchDescriptor<TransactionRecord>()).first(where: {
            $0.id == id
        }) else {
            throw TransactionStoreError.transactionNotFound
        }
        modelContext.delete(record)
        try modelContext.save()
    }

    private func apply(_ result: ParseResult, to record: TransactionRecord) throws {
        switch result {
        case let .success(transaction):
            record.parseStatusRaw = ParseStatus.parsed.rawValue
            record.parsedKindRaw = transaction.kind.rawValue
            record.parsedCardLastFour = transaction.cardLast4
            record.parsedAmount = transaction.amount
            record.parsedMonth = transaction.month
            record.parsedDay = transaction.day
            record.parsedHour = transaction.hour
            record.parsedMinute = transaction.minute
            record.parsedMerchant = transaction.merchant
            record.parsedAccountBalance = transaction.accountBalance
            record.parserVersion = transaction.parserVersion
            record.parseFailureReason = nil
            try resolveDate(for: transaction, in: record)
            try assignCardIfUnambiguous(to: record)
        case let .unsupported(failure), let .failed(failure):
            record.parseStatusRaw = ParseStatus.failed.rawValue
            record.parsedKindRaw = nil
            record.parsedCardLastFour = nil
            record.parsedAmount = nil
            record.parsedMonth = nil
            record.parsedDay = nil
            record.parsedHour = nil
            record.parsedMinute = nil
            record.parsedMerchant = nil
            record.parsedAccountBalance = nil
            record.parserVersion = failure.parserVersion
            record.parseFailureReason = failure.reason
            clearResolvedDate(in: record)
            if record.cardAssignmentSourceRaw != "user" {
                record.card = nil
                record.cardAssignmentSourceRaw = nil
            }
        }
    }

    private func seedDefaultCardIfNeeded() throws -> CardRecord {
        let cards = try modelContext.fetch(FetchDescriptor<CardRecord>())
        if let existing = cards.first(where: { $0.issuerCode == "MG" && $0.lastFour == "4775" }) {
            return existing
        }
        let card = CardRecord(
            displayName: "MG 더나은 체크카드",
            issuerCode: "MG",
            lastFour: "4775",
            performanceTargetAmount: 300_000
        )
        modelContext.insert(card)
        try modelContext.save()
        return card
    }

    private func assignCardIfUnambiguous(to record: TransactionRecord) throws {
        guard record.cardAssignmentSourceRaw != "user", let suffix = record.parsedCardLastFour else {
            return
        }
        let matches = try modelContext.fetch(FetchDescriptor<CardRecord>()).filter {
            $0.issuerCode == "MG" && $0.lastFour == suffix
        }
        if matches.count == 1 {
            record.card = matches[0]
            record.cardAssignmentSourceRaw = "automaticExactMatch"
        } else {
            record.card = nil
            record.cardAssignmentSourceRaw = nil
        }
    }

    private func resolveDate(for parsed: ParsedTransaction, in record: TransactionRecord) throws {
        let partial = try ParsedLocalDate(
            month: parsed.month,
            day: parsed.day,
            hour: parsed.hour,
            minute: parsed.minute,
            timeZoneIdentifier: "Asia/Seoul"
        )
        let resolved = try DefaultTransactionDateResolver().resolve(partial, receivedAt: record.receivedAt)
        record.resolvedYear = resolved.localComponents.year
        record.resolvedMonth = resolved.localComponents.month
        record.resolvedDay = resolved.localComponents.day
        record.resolvedHour = parsed.hour
        record.resolvedMinute = parsed.minute
        record.resolvedInstant = resolved.instant
        record.datePrecisionRaw = resolved.precision.rawValue
        record.dateResolutionSourceRaw = resolved.source.rawValue
        record.dateResolverVersion = resolved.resolverVersion
        record.dateTimeZoneIdentifier = partial.timeZoneIdentifier
    }

    private func clearResolvedDate(in record: TransactionRecord) {
        record.resolvedYear = nil
        record.resolvedMonth = nil
        record.resolvedDay = nil
        record.resolvedHour = nil
        record.resolvedMinute = nil
        record.resolvedInstant = nil
        record.datePrecisionRaw = nil
        record.dateResolutionSourceRaw = nil
        record.dateResolverVersion = nil
        record.dateTimeZoneIdentifier = nil
    }
}
