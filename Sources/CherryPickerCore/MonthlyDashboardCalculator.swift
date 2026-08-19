import Foundation

public enum DashboardMonthError: Error, Equatable, Sendable {
    case invalidIdentifier
    case unresolvedInterval
}

/// A calendar month interpreted in the product time zone.
public struct DashboardMonth: Equatable, Sendable {
    public static let timeZoneIdentifier = "Asia/Seoul"

    public let year: Int
    public let month: Int

    public init(identifier: String) throws {
        let parts = identifier.split(separator: "-", omittingEmptySubsequences: false)
        guard
            parts.count == 2,
            parts[0].count == 4,
            parts[1].count == 2,
            parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            (1...9999).contains(year),
            (1...12).contains(month)
        else {
            throw DashboardMonthError.invalidIdentifier
        }
        self.year = year
        self.month = month
    }

    public init(containing date: Date) throws {
        var calendar = Calendar(identifier: .gregorian)
        guard let timeZone = TimeZone(identifier: Self.timeZoneIdentifier) else {
            throw DashboardMonthError.unresolvedInterval
        }
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else {
            throw DashboardMonthError.unresolvedInterval
        }
        self.year = year
        self.month = month
    }

    public var identifier: String {
        String(format: "%04d-%02d", year, month)
    }

    public var previous: DashboardMonth {
        get throws {
            try DashboardMonth(
                identifier: month == 1
                    ? String(format: "%04d-12", year - 1)
                    : String(format: "%04d-%02d", year, month - 1)
            )
        }
    }

    public var interval: DateInterval {
        get throws {
            var calendar = Calendar(identifier: .gregorian)
            guard let timeZone = TimeZone(identifier: Self.timeZoneIdentifier) else {
                throw DashboardMonthError.unresolvedInterval
            }
            calendar.timeZone = timeZone
            guard
                let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                let end = calendar.date(byAdding: .month, value: 1, to: start)
            else {
                throw DashboardMonthError.unresolvedInterval
            }
            return DateInterval(start: start, end: end)
        }
    }
}

public struct DashboardBenefitDefinition: Equatable, Sendable {
    public let id: UUID
    public let rateBasisPoints: Int
    public let maximumAmount: Int?

    public init(id: UUID, rateBasisPoints: Int, maximumAmount: Int?) {
        self.id = id
        self.rateBasisPoints = rateBasisPoints
        self.maximumAmount = maximumAmount
    }
}

public enum DashboardTransactionKind: Equatable, Sendable {
    case approval
    case cancellation
}

public enum DashboardPerformanceDecision: Equatable, Sendable {
    case included
    case excluded
}

public struct DashboardTransactionInput: Equatable, Sendable {
    public let occurredAt: Date
    public let isReviewed: Bool
    public let aggregationExcluded: Bool
    public let kind: DashboardTransactionKind?
    public let amount: Int?
    public let performance: DashboardPerformanceDecision?
    public let benefitIDs: Set<UUID>

    public init(
        occurredAt: Date,
        isReviewed: Bool,
        aggregationExcluded: Bool,
        kind: DashboardTransactionKind?,
        amount: Int?,
        performance: DashboardPerformanceDecision?,
        benefitIDs: Set<UUID>
    ) {
        self.occurredAt = occurredAt
        self.isReviewed = isReviewed
        self.aggregationExcluded = aggregationExcluded
        self.kind = kind
        self.amount = amount
        self.performance = performance
        self.benefitIDs = benefitIDs
    }
}

public struct DashboardPerformanceCalculation: Equatable, Sendable {
    public let currentAmount: Int
    public let excludedAmount: Int
    public let unconfirmedAmount: Int
    public let unconfirmedCount: Int
}

public struct DashboardBenefitCalculation: Equatable, Sendable {
    public let id: UUID
    public let calculationAmount: Int
    public let receivedAmount: Int
}

public struct MonthlyDashboardCalculation: Equatable, Sendable {
    public let performance: DashboardPerformanceCalculation
    public let benefits: [DashboardBenefitCalculation]
    public let benefitUnconfirmedCount: Int
}

/// Pure derived-state boundary for one card and one calendar month.
public struct MonthlyDashboardCalculator: Sendable {
    public init() {}

    public func calculate(
        period: DateInterval,
        benefits: [DashboardBenefitDefinition],
        transactions: [DashboardTransactionInput],
        performanceOffsetAmount: Int = 0,
        benefitOffsetAmounts: [UUID: Int] = [:]
    ) -> MonthlyDashboardCalculation {
        var currentAmount = 0
        var excludedAmount = 0
        var unconfirmedAmount = 0
        var unconfirmedCount = 0
        var benefitUnconfirmedCount = 0
        var rawBenefitAmounts = Dictionary(uniqueKeysWithValues: benefits.map { ($0.id, 0) })

        for transaction in transactions where contains(transaction.occurredAt, in: period) {
            guard !transaction.aggregationExcluded else { continue }

            guard transaction.isReviewed else {
                unconfirmedCount += 1
                benefitUnconfirmedCount += 1
                unconfirmedAmount += transaction.amount ?? 0
                continue
            }

            guard let amount = transaction.amount else { continue }
            let sign = transaction.kind == .cancellation ? -1 : 1
            switch transaction.performance {
            case .included:
                currentAmount += sign * amount
            case .excluded:
                excludedAmount += sign * amount
            case nil:
                break
            }

            for benefitID in transaction.benefitIDs {
                guard let benefit = benefits.first(where: { $0.id == benefitID }) else { continue }
                rawBenefitAmounts[benefitID, default: 0] +=
                    sign * amount * benefit.rateBasisPoints / 10_000
            }
        }

        let adjustedCurrentAmount = currentAmount + performanceOffsetAmount
        return MonthlyDashboardCalculation(
            performance: DashboardPerformanceCalculation(
                currentAmount: adjustedCurrentAmount,
                excludedAmount: excludedAmount,
                unconfirmedAmount: unconfirmedAmount,
                unconfirmedCount: unconfirmedCount
            ),
            benefits: benefits.map { benefit in
                let adjustedAmount = rawBenefitAmounts[benefit.id, default: 0]
                    + benefitOffsetAmounts[benefit.id, default: 0]
                return DashboardBenefitCalculation(
                    id: benefit.id,
                    calculationAmount: adjustedAmount,
                    receivedAmount: max(0, benefit.maximumAmount.map {
                        min($0, adjustedAmount)
                    } ?? adjustedAmount)
                )
            },
            benefitUnconfirmedCount: benefitUnconfirmedCount
        )
    }

    private func contains(_ date: Date, in period: DateInterval) -> Bool {
        date >= period.start && date < period.end
    }
}
