import Foundation

/// The two transaction kinds currently understood by CherryPicker.
public enum TransactionKind: String, Codable, Equatable, Sendable {
    case approval
    case cancellation
}

/// Values extracted from an MG card message.
///
/// The original message is deliberately part of the value. A caller can save a
/// parse result without having to keep a second, separately associated copy of
/// the message. The year is not present in the card message and is therefore
/// intentionally not guessed by this parser.
public struct ParsedTransaction: Codable, Equatable, Sendable {
    public let kind: TransactionKind
    public let cardLast4: String
    public let amount: Int
    public let month: Int
    public let day: Int
    public let hour: Int?
    public let minute: Int?
    public let merchant: String
    public let accountBalance: Int?
    public let parserVersion: String
    public let originalMessage: String

    public init(
        kind: TransactionKind,
        cardLast4: String,
        amount: Int,
        month: Int,
        day: Int,
        hour: Int? = nil,
        minute: Int? = nil,
        merchant: String,
        accountBalance: Int? = nil,
        parserVersion: String,
        originalMessage: String
    ) {
        self.kind = kind
        self.cardLast4 = cardLast4
        self.amount = amount
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.merchant = merchant
        self.accountBalance = accountBalance
        self.parserVersion = parserVersion
        self.originalMessage = originalMessage
    }

    /// A descriptive alias for clients that prefer the full field name.
    public var cardLastFour: String { cardLast4 }

    /// Another commonly used alias for the card suffix.
    public var lastFourDigits: String { cardLast4 }

    /// Whether the parsed value has a complete time-of-day.
    public var hasTime: Bool { hour != nil && minute != nil }
}

/// Details retained when a message cannot be turned into a transaction.
public struct ParseFailure: Error, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case unsupported
        case failed
    }

    public let kind: Kind
    public let originalMessage: String
    public let reason: String
    public let parserVersion: String

    public init(
        kind: Kind,
        originalMessage: String,
        reason: String,
        parserVersion: String
    ) {
        self.kind = kind
        self.originalMessage = originalMessage
        self.reason = reason
        self.parserVersion = parserVersion
    }
}

/// A non-throwing parse outcome. Unknown formats are represented explicitly so
/// callers can persist the source message and let a user correct it later.
public enum ParseResult: Codable, Equatable, Sendable {
    case success(ParsedTransaction)
    case unsupported(ParseFailure)
    case failed(ParseFailure)

    public var transaction: ParsedTransaction? {
        guard case let .success(transaction) = self else { return nil }
        return transaction
    }

    public var failure: ParseFailure? {
        switch self {
        case .success:
            return nil
        case let .unsupported(failure), let .failed(failure):
            return failure
        }
    }

    public var originalMessage: String {
        if let transaction {
            return transaction.originalMessage
        }
        return failure?.originalMessage ?? ""
    }

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey {
        case outcome
        case transaction
        case failure
    }

    private enum Outcome: String, Codable {
        case success
        case unsupported
        case failed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let outcome = try container.decode(Outcome.self, forKey: .outcome)
        switch outcome {
        case .success:
            self = .success(try container.decode(ParsedTransaction.self, forKey: .transaction))
        case .unsupported:
            self = .unsupported(try container.decode(ParseFailure.self, forKey: .failure))
        case .failed:
            self = .failed(try container.decode(ParseFailure.self, forKey: .failure))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .success(transaction):
            try container.encode(Outcome.success, forKey: .outcome)
            try container.encode(transaction, forKey: .transaction)
        case let .unsupported(failure):
            try container.encode(Outcome.unsupported, forKey: .outcome)
            try container.encode(failure, forKey: .failure)
        case let .failed(failure):
            try container.encode(Outcome.failed, forKey: .outcome)
            try container.encode(failure, forKey: .failure)
        }
    }
}

/// A typed throwing counterpart for integrations that use Swift's `Result` or
/// `throws` conventions. `MGCardMessageParser.parse(_:)` itself is non-throwing.
public enum ParseError: Error, Equatable, Sendable {
    case unsupported(ParseFailure)
    case failed(ParseFailure)
}
