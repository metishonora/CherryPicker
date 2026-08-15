import Foundation
import CherryPickerCore

/// The JSON object written by the iPhone outbox and accepted by the local
/// server. `capturedAt` is the immutable device capture time; it is never
/// replaced by a server receipt time.
public struct OutboxEvent: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let eventId: UUID
    public let capturedAt: Date
    public let originalMessage: String

    public init(
        schemaVersion: Int = OutboxEvent.currentSchemaVersion,
        eventId: UUID,
        capturedAt: Date,
        originalMessage: String
    ) {
        self.schemaVersion = schemaVersion
        self.eventId = eventId
        self.capturedAt = capturedAt
        self.originalMessage = originalMessage
    }
}

public struct BatchSyncRequest: Codable, Equatable, Sendable {
    public let events: [OutboxEvent]

    public init(events: [OutboxEvent]) {
        self.events = events
    }
}

public enum SyncItemStatus: String, Codable, Equatable, Sendable {
    case accepted
    case duplicate
    case rejected
}

public enum SyncDisposition: String, Codable, Equatable, Sendable {
    case stored
    case transactionDuplicate
    case parseFailed
}

public enum SyncRejectionReason: String, Codable, Equatable, Sendable {
    case unsupportedSchemaVersion
    case emptyOriginalMessage
}

public struct SyncItemResult: Codable, Equatable, Sendable {
    public let eventId: UUID
    public let status: SyncItemStatus
    public let disposition: SyncDisposition?
    public let transactionID: UUID?
    public let rejectionReason: SyncRejectionReason?

    private enum CodingKeys: String, CodingKey {
        case eventId
        case status
        case disposition
        case transactionID = "transactionId"
        case rejectionReason
    }

    public init(
        eventId: UUID,
        status: SyncItemStatus,
        disposition: SyncDisposition? = nil,
        transactionID: UUID? = nil,
        rejectionReason: SyncRejectionReason? = nil
    ) {
        self.eventId = eventId
        self.status = status
        self.disposition = disposition
        self.transactionID = transactionID
        self.rejectionReason = rejectionReason
    }
}

public struct BatchSyncResponse: Codable, Equatable, Sendable {
    public let results: [SyncItemResult]

    public init(results: [SyncItemResult]) {
        self.results = results
    }
}

/// Codable boundary used by both Shortcut payloads and server responses.
/// Sorted keys make fixture bytes stable while ISO-8601 keeps the wire format
/// readable and independent of a server's locale or time zone.
public struct OutboxJSONCodec: Sendable {
    public init() {}

    public func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    public func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}

public enum StoredParseStatus: String, Codable, Equatable, Sendable {
    case pending
    case parsed
    case failed
}

/// Canonical transaction data retained by the server. The original message
/// lives in this canonical row exactly once; parsed/failure metadata never
/// serializes a second copy of it.
public struct StoredTransaction: Codable, Equatable, Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let originalMessage: String
    public let parseStatus: StoredParseStatus
    public let parsedTransaction: ParsedTransaction?
    public let parseFailure: ParseFailure?

    public init(
        id: UUID,
        capturedAt: Date,
        originalMessage: String,
        parseStatus: StoredParseStatus,
        parsedTransaction: ParsedTransaction? = nil,
        parseFailure: ParseFailure? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.originalMessage = originalMessage
        self.parseStatus = parseStatus
        self.parsedTransaction = parsedTransaction
        self.parseFailure = parseFailure
    }
}

/// Public-safe transaction fields for the authenticated product status page.
///
/// This intentionally has no original message, card suffix, account balance,
/// parser failure reason, or other raw payload fields.  The HTTP layer should
/// use this value rather than serializing ``StoredTransaction`` directly.
public struct SafeTransactionSummary: Codable, Equatable, Sendable {
    public let kind: String?
    public let amount: Int?
    public let merchant: String?
    public let reviewNeeded: Bool

    public init(
        kind: String? = nil,
        amount: Int? = nil,
        merchant: String? = nil,
        reviewNeeded: Bool
    ) {
        self.kind = kind
        self.amount = amount
        self.merchant = merchant
        self.reviewNeeded = reviewNeeded
    }
}

/// A redacted transaction row suitable for the authenticated report page.
public struct SafeTransaction: Codable, Equatable, Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let parseStatus: StoredParseStatus
    public let summary: SafeTransactionSummary

    public init(
        id: UUID,
        capturedAt: Date,
        parseStatus: StoredParseStatus,
        summary: SafeTransactionSummary
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.parseStatus = parseStatus
        self.summary = summary
    }
}

public struct SafeTransactionsResponse: Codable, Equatable, Sendable {
    public let transactions: [SafeTransaction]

    public init(transactions: [SafeTransaction]) {
        self.transactions = transactions
    }
}

/// Receipt fields approved for the authenticated sync-results report.
///
/// Rejection reasons and all request payload fields stay out of this type.
public struct SafeEventReceipt: Codable, Equatable, Sendable {
    public let eventId: UUID
    public let transactionID: UUID
    public let capturedAt: Date
    public let status: SyncItemStatus
    public let disposition: SyncDisposition?

    private enum CodingKeys: String, CodingKey {
        case eventId
        case transactionID = "transactionId"
        case capturedAt
        case status
        case disposition
    }

    public init(
        eventId: UUID,
        transactionID: UUID,
        capturedAt: Date,
        status: SyncItemStatus,
        disposition: SyncDisposition?
    ) {
        self.eventId = eventId
        self.transactionID = transactionID
        self.capturedAt = capturedAt
        self.status = status
        self.disposition = disposition
    }
}

/// Receipt metadata is intentionally separate from `StoredTransaction` and
/// contains no original message body.
public struct StoredEventReceipt: Codable, Equatable, Sendable {
    public let eventId: UUID
    public let transactionID: UUID
    public let capturedAt: Date
    public let status: SyncItemStatus
    public let disposition: SyncDisposition?
    public let rejectionReason: SyncRejectionReason?

    private enum CodingKeys: String, CodingKey {
        case eventId
        case transactionID = "transactionId"
        case capturedAt
        case status
        case disposition
        case rejectionReason
    }

    public init(
        eventId: UUID,
        transactionID: UUID,
        capturedAt: Date,
        status: SyncItemStatus,
        disposition: SyncDisposition?,
        rejectionReason: SyncRejectionReason? = nil
    ) {
        self.eventId = eventId
        self.transactionID = transactionID
        self.capturedAt = capturedAt
        self.status = status
        self.disposition = disposition
        self.rejectionReason = rejectionReason
    }
}

public struct TailscaleIdentityAuthorizer: Equatable, Sendable {
    private let allowedLogin: String

    public init(allowedLogin: String) {
        self.allowedLogin = allowedLogin
    }

    public func isAuthorized(login: String?) -> Bool {
        guard !allowedLogin.isEmpty, let login, !login.isEmpty else { return false }
        return login == allowedLogin
    }
}

public enum IngestionServiceError: Error, Equatable, Sendable {
    case unauthorized
}
