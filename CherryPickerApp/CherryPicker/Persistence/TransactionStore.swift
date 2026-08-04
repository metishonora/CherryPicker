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
                apply(parser.parse(duplicate.originalMessage), to: duplicate)
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
        apply(parser.parse(rawMessage), to: record)
        try modelContext.save()
        return .saved(record.id)
    }

    private func apply(_ result: ParseResult, to record: TransactionRecord) {
        switch result {
        case let .success(transaction):
            record.parseStatusRaw = ParseStatus.parsed.rawValue
            record.kindRaw = transaction.kind.rawValue
            record.cardLast4 = transaction.cardLast4
            record.amount = transaction.amount
            record.month = transaction.month
            record.day = transaction.day
            record.hour = transaction.hour
            record.minute = transaction.minute
            record.merchant = transaction.merchant
            record.accountBalance = transaction.accountBalance
            record.parserVersion = transaction.parserVersion
            record.parseFailureReason = nil
        case let .unsupported(failure), let .failed(failure):
            record.parseStatusRaw = ParseStatus.failed.rawValue
            record.kindRaw = nil
            record.cardLast4 = nil
            record.amount = nil
            record.month = nil
            record.day = nil
            record.hour = nil
            record.minute = nil
            record.merchant = nil
            record.accountBalance = nil
            record.parserVersion = failure.parserVersion
            record.parseFailureReason = failure.reason
        }
    }
}
