import Foundation

/// A benefit policy owned by a card type rather than by a user's card instance.
public struct CardTypeBenefitDefinition: Equatable, Sendable {
    public let id: UUID
    public let code: String
    public let label: String
    public let rateBasisPoints: Int
    public let monthlyMaximumAmount: Int

    public init(
        id: UUID,
        code: String,
        label: String,
        rateBasisPoints: Int,
        monthlyMaximumAmount: Int
    ) {
        self.id = id
        self.code = code
        self.label = label
        self.rateBasisPoints = rateBasisPoints
        self.monthlyMaximumAmount = monthlyMaximumAmount
    }
}

/// Message trigger inputs exposed by a card type for capture automation.
///
/// Sender identifiers stay empty until a value has been confirmed on the
/// production phone. Body markers are sufficient for the confirmed fixtures.
public struct CardMessageIdentificationRules: Equatable, Sendable {
    public let senderIdentifiers: [String]
    public let cardBodyMarkers: [String]
    public let transactionBodyMarkers: [String]

    public init(
        senderIdentifiers: [String],
        cardBodyMarkers: [String],
        transactionBodyMarkers: [String]
    ) {
        self.senderIdentifiers = senderIdentifiers
        self.cardBodyMarkers = cardBodyMarkers
        self.transactionBodyMarkers = transactionBodyMarkers
    }

    public func matches(messageBody: String) -> Bool {
        let compactBody = messageBody.filter { !$0.isWhitespace }
        return cardBodyMarkers.contains(where: compactBody.contains)
            && transactionBodyMarkers.contains(where: compactBody.contains)
    }
}

/// Product boundary for behavior and policy that belongs to a kind of card.
public protocol CardTypeDefining: Sendable {
    var code: String { get }
    var displayName: String { get }
    var issuerCode: String { get }
    var messageIdentification: CardMessageIdentificationRules { get }
    var defaultMonthlyPerformanceTargetAmount: Int { get }
    var benefits: [CardTypeBenefitDefinition] { get }
    var performanceExclusions: [String] { get }
    var benefitExclusions: [String] { get }

    func identifies(messageBody: String) -> Bool
    func parse(_ originalMessage: String) -> ParseResult
}

/// The single card type supported by the MVP.
///
/// The benefit values still mirror the existing prototype seed. Replacing
/// them with verified product terms is a separate issue #9 work unit; keeping
/// them here makes this definition the only source that must change then.
public struct MGTheBetterCheckCardDefinition: CardTypeDefining {
    public let code = "mg.the-better-check"
    public let displayName = "MG 더나은 체크카드"
    public let issuerCode = "MG"
    public let messageIdentification = CardMessageIdentificationRules(
        senderIdentifiers: [],
        cardBodyMarkers: ["MG카드(", "MG체크카드(", "MG더나은카드(", "MG더나은체크카드("],
        transactionBodyMarkers: ["체크승인", "승인취소"]
    )
    public let defaultMonthlyPerformanceTargetAmount = 300_000
    public let benefits: [CardTypeBenefitDefinition] = [
        CardTypeBenefitDefinition(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000004775")!,
            code: "prototype-coffee",
            label: "커피 10% 할인",
            rateBasisPoints: 1_000,
            monthlyMaximumAmount: 5_000
        ),
        CardTypeBenefitDefinition(
            id: UUID(uuidString: "00000000-0000-0000-0002-000000004775")!,
            code: "prototype-convenience-store",
            label: "편의점 5% 할인",
            rateBasisPoints: 500,
            monthlyMaximumAmount: 5_000
        )
    ]
    public let performanceExclusions = [
        "세금 및 공과금",
        "아파트 관리비",
        "대학 등록금",
        "상품권·선불카드 충전"
    ]
    public let benefitExclusions = [
        "무이자 할부 거래",
        "상품권 및 기프트카드 구매",
        "포인트·쿠폰 사용분",
        "일부 임대매장 및 백화점 입점 매장"
    ]

    private let parser: MGCardMessageParser

    public init(parser: MGCardMessageParser = MGCardMessageParser()) {
        self.parser = parser
    }

    public func identifies(messageBody: String) -> Bool {
        messageIdentification.matches(messageBody: messageBody)
    }

    public func parse(_ originalMessage: String) -> ParseResult {
        parser.parse(originalMessage)
    }
}
