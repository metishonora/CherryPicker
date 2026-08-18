import Foundation

/// A benefit policy owned by a card type rather than by a user's card instance.
public struct CardTypeBenefitDefinition: Equatable, Sendable {
    public let id: UUID
    public let code: String
    public let label: String
    public let eligibleMerchants: [String]
    public let minimumTransactionAmount: Int
    public let requiredPreviousMonthPerformanceAmount: Int
    public let rateBasisPoints: Int
    public let monthlyMaximumAmount: Int
    public let exclusionNotes: [String]

    public init(
        id: UUID,
        code: String,
        label: String,
        eligibleMerchants: [String],
        minimumTransactionAmount: Int,
        requiredPreviousMonthPerformanceAmount: Int,
        rateBasisPoints: Int,
        monthlyMaximumAmount: Int,
        exclusionNotes: [String] = []
    ) {
        self.id = id
        self.code = code
        self.label = label
        self.eligibleMerchants = eligibleMerchants
        self.minimumTransactionAmount = minimumTransactionAmount
        self.requiredPreviousMonthPerformanceAmount = requiredPreviousMonthPerformanceAmount
        self.rateBasisPoints = rateBasisPoints
        self.monthlyMaximumAmount = monthlyMaximumAmount
        self.exclusionNotes = exclusionNotes
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
    var performanceCalculationBasis: String { get }
    var benefits: [CardTypeBenefitDefinition] { get }
    var performanceExclusions: [String] { get }
    var benefitExclusions: [String] { get }

    func identifies(messageBody: String) -> Bool
    func parse(_ originalMessage: String) -> ParseResult
}

/// The single card type supported by the MVP.
///
/// Benefit terms are the verified values supplied for issue #9. Eligibility
/// remains a user decision in the MVP review flow; these values describe the
/// policy and drive the displayed calculation rate and monthly cap.
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
    public let performanceCalculationBasis = "‘더나은’ 정상 이용금액"
    public let benefits: [CardTypeBenefitDefinition] = [
        CardTypeBenefitDefinition(
            id: UUID(uuidString: "00000000-0000-0000-0001-000000004775")!,
            code: "simple-pay-cashback",
            label: "간편결제 20% 할인캐시백",
            eligibleMerchants: ["네이버페이", "카카오페이", "페이코"],
            minimumTransactionAmount: 10_000,
            requiredPreviousMonthPerformanceAmount: 300_000,
            rateBasisPoints: 2_000,
            monthlyMaximumAmount: 6_000
        ),
        CardTypeBenefitDefinition(
            id: UUID(uuidString: "00000000-0000-0000-0002-000000004775")!,
            code: "online-shopping-cashback",
            label: "온라인 쇼핑 20% 할인캐시백",
            eligibleMerchants: ["쿠팡", "무신사", "지그재그", "W컨셉", "에이블리"],
            minimumTransactionAmount: 10_000,
            requiredPreviousMonthPerformanceAmount: 300_000,
            rateBasisPoints: 2_000,
            monthlyMaximumAmount: 6_000
        ),
        CardTypeBenefitDefinition(
            id: UUID(uuidString: "00000000-0000-0000-0003-000000004775")!,
            code: "coffee-cashback",
            label: "커피 20% 할인캐시백",
            eligibleMerchants: [
                "스타벅스", "투썸플레이스", "커피빈", "메가커피", "빽다방", "컴포즈커피"
            ],
            minimumTransactionAmount: 5_000,
            requiredPreviousMonthPerformanceAmount: 300_000,
            rateBasisPoints: 2_000,
            monthlyMaximumAmount: 6_000,
            exclusionNotes: [
                "백화점·할인점·아울렛·쇼핑몰·공항·호텔 등 입점매장 제외"
            ]
        )
    ]
    public let performanceExclusions = [
        "해외가맹점 이용금액(CD·ATM 인출 포함)",
        "소액신용결제 및 후불교통 이용금액"
    ]
    public let benefitExclusions = [
        "해외가맹점 이용금액(CD·ATM 인출 포함)",
        "소액신용결제 및 후불교통 이용금액",
        "국세·지방세·관세·공공요금",
        "공공기관 운영시설",
        "상품권",
        "포인트 및 적립금 충전",
        "선불카드 구매·충전·이용(선불교통카드 포함)",
        "MD상품 구입",
        "대학·대학원 등록금",
        "택시·대중교통 이용금액(버스·철도 포함)",
        "자동차 판매 업종(국산차·수입차·위탁판매·중고차·이륜차 포함)"
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
