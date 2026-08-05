import Foundation

public enum TransactionDatePrecision: String, Codable, Equatable, Sendable {
    case day
    case minute
}

public struct ParsedLocalDate: Equatable, Sendable {
    public let year: Int?
    public let month: Int
    public let day: Int
    public let hour: Int?
    public let minute: Int?
    public let calendarIdentifier: Calendar.Identifier
    public let timeZoneIdentifier: String
    public let precision: TransactionDatePrecision

    public init(
        year: Int? = nil,
        month: Int,
        day: Int,
        hour: Int? = nil,
        minute: Int? = nil,
        calendarIdentifier: Calendar.Identifier = .gregorian,
        timeZoneIdentifier: String
    ) throws {
        guard (hour == nil) == (minute == nil) else {
            throw CardPolicyError.invalidLocalDate
        }
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw CardPolicyError.invalidTimeZone(timeZoneIdentifier)
        }

        var calendar = Calendar(identifier: calendarIdentifier)
        calendar.timeZone = timeZone
        var validation = DateComponents()
        validation.calendar = calendar
        validation.timeZone = timeZone
        validation.year = year ?? 2000
        validation.month = month
        validation.day = day
        validation.hour = hour ?? 0
        validation.minute = minute ?? 0
        guard let candidate = calendar.date(from: validation) else {
            throw CardPolicyError.invalidLocalDate
        }
        let roundTrip = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: candidate)
        guard
            roundTrip.year == validation.year,
            roundTrip.month == month,
            roundTrip.day == day,
            roundTrip.hour == validation.hour,
            roundTrip.minute == validation.minute
        else {
            throw CardPolicyError.invalidLocalDate
        }

        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.calendarIdentifier = calendarIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
        self.precision = hour == nil ? .day : .minute
    }
}

public enum TransactionDateResolutionSource: String, Codable, Equatable, Sendable {
    case inferred
    case legacyReceivedYear
    case user
}

public struct ResolvedTransactionDate: Equatable, Sendable {
    public let localComponents: DateComponents
    public let instant: Date
    public let precision: TransactionDatePrecision
    public let source: TransactionDateResolutionSource
    public let resolverVersion: String

    public init(
        localComponents: DateComponents,
        instant: Date,
        precision: TransactionDatePrecision,
        source: TransactionDateResolutionSource,
        resolverVersion: String
    ) {
        self.localComponents = localComponents
        self.instant = instant
        self.precision = precision
        self.source = source
        self.resolverVersion = resolverVersion
    }
}

public protocol TransactionDateResolving: Sendable {
    func resolve(_ partial: ParsedLocalDate, receivedAt: Date) throws -> ResolvedTransactionDate
}

public struct DefaultTransactionDateResolver: TransactionDateResolving {
    public static let currentVersion = "nearest-past-local-date-v1"

    public init() {}

    public func resolve(_ partial: ParsedLocalDate, receivedAt: Date) throws -> ResolvedTransactionDate {
        guard let timeZone = TimeZone(identifier: partial.timeZoneIdentifier) else {
            throw CardPolicyError.invalidTimeZone(partial.timeZoneIdentifier)
        }
        var calendar = Calendar(identifier: partial.calendarIdentifier)
        calendar.timeZone = timeZone

        let receivedComponents = calendar.dateComponents([.year, .month, .day], from: receivedAt)
        guard
            let receivedYear = receivedComponents.year,
            let receivedMonth = receivedComponents.month,
            let receivedDay = receivedComponents.day
        else {
            throw CardPolicyError.invalidLocalDate
        }

        let inferredYear: Int
        if let explicitYear = partial.year {
            inferredYear = explicitYear
        } else if (partial.month, partial.day) > (receivedMonth, receivedDay) {
            inferredYear = receivedYear - 1
        } else {
            inferredYear = receivedYear
        }

        var resolvedComponents = DateComponents()
        resolvedComponents.calendar = calendar
        resolvedComponents.timeZone = timeZone
        resolvedComponents.year = inferredYear
        resolvedComponents.month = partial.month
        resolvedComponents.day = partial.day
        resolvedComponents.hour = partial.hour ?? 0
        resolvedComponents.minute = partial.minute ?? 0

        guard let instant = calendar.date(from: resolvedComponents) else {
            throw CardPolicyError.invalidLocalDate
        }
        let roundTrip = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: instant
        )
        guard
            roundTrip.year == inferredYear,
            roundTrip.month == partial.month,
            roundTrip.day == partial.day,
            roundTrip.hour == resolvedComponents.hour,
            roundTrip.minute == resolvedComponents.minute
        else {
            throw CardPolicyError.invalidLocalDate
        }
        return ResolvedTransactionDate(
            localComponents: resolvedComponents,
            instant: instant,
            precision: partial.precision,
            source: partial.year == nil ? .inferred : .user,
            resolverVersion: Self.currentVersion
        )
    }
}
