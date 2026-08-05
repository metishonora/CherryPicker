import Foundation

public enum CardPolicyError: Error, Equatable, Sendable {
    case targetMustBePositive
    case invalidTimeZone(String)
    case invalidLocalDate
    case unresolvedPeriod
}

public struct PerformanceRequirement: Equatable, Sendable {
    public let monthlyTargetAmount: Int?

    public init(monthlyTargetAmount: Int?) throws {
        if let monthlyTargetAmount, monthlyTargetAmount <= 0 {
            throw CardPolicyError.targetMustBePositive
        }
        self.monthlyTargetAmount = monthlyTargetAmount
    }

    public var isEnabled: Bool { monthlyTargetAmount != nil }
}

public enum PerformancePeriodRule: Equatable, Sendable {
    case calendarMonth(timeZoneIdentifier: String)
}

public protocol PerformancePeriodResolving: Sendable {
    func period(containing date: Date, rule: PerformancePeriodRule) throws -> DateInterval
}

public struct DefaultPerformancePeriodResolver: PerformancePeriodResolving {
    public init() {}

    public func period(containing date: Date, rule: PerformancePeriodRule) throws -> DateInterval {
        switch rule {
        case let .calendarMonth(timeZoneIdentifier):
            guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
                throw CardPolicyError.invalidTimeZone(timeZoneIdentifier)
            }

            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let components = calendar.dateComponents([.year, .month], from: date)
            guard
                let start = calendar.date(from: components),
                let end = calendar.date(byAdding: .month, value: 1, to: start)
            else {
                throw CardPolicyError.unresolvedPeriod
            }
            return DateInterval(start: start, end: end)
        }
    }
}
