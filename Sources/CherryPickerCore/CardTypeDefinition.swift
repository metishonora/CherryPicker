import Foundation

/// A benefit policy owned by a card type rather than by a user's card instance.
public struct CardTypeBenefitDefinition: Equatable, Sendable {
    public let id: UUID
    public let code: String
    public let label: String
    public let eligibleMerchants: [String]
    public let minimumTransactionAmount: Int
    public let requiredPreviousMonthPerformanceAmount: Int?
    public let rateBasisPoints: Int
    public let monthlyMaximumAmount: Int?
    public let recurringPaymentOnly: Bool
    public let exclusionNotes: [String]

    public init(
        id: UUID,
        code: String,
        label: String,
        eligibleMerchants: [String],
        minimumTransactionAmount: Int,
        requiredPreviousMonthPerformanceAmount: Int?,
        rateBasisPoints: Int,
        monthlyMaximumAmount: Int?,
        recurringPaymentOnly: Bool = false,
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
        self.recurringPaymentOnly = recurringPaymentOnly
        self.exclusionNotes = exclusionNotes
    }
}

public struct PerformanceBenefitTier: Equatable, Sendable {
    public let minimumPreviousMonthPerformanceAmount: Int
    public let maximumAmount: Int

    public init(minimumPreviousMonthPerformanceAmount: Int, maximumAmount: Int) {
        self.minimumPreviousMonthPerformanceAmount = minimumPreviousMonthPerformanceAmount
        self.maximumAmount = maximumAmount
    }
}

public enum CardTypeBenefitLimitPolicy: Equatable, Sendable {
    case perBenefit
    case integrated(tiers: [PerformanceBenefitTier])
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
    /// Retained only as a database compatibility default for the retired column.
    var legacyMonthlyPerformanceTargetAmount: Int { get }
    /// Fixed, ordered performance thresholds used to derive the next visible goal.
    /// These belong to the card policy and are never editable per card instance.
    var performanceThresholdAmounts: [Int] { get }
    var benefitLimitPolicy: CardTypeBenefitLimitPolicy { get }
    var performanceCalculationBasis: String { get }
    var benefits: [CardTypeBenefitDefinition] { get }
    var performanceExclusions: [String] { get }
    var benefitExclusions: [String] { get }

    func identifies(messageBody: String) -> Bool
    func parse(_ originalMessage: String) -> ParseResult
    func matches(parsedCardIdentifier: String, storedLastFour: String) -> Bool
}

public extension CardTypeDefining {
    func matches(parsedCardIdentifier: String, storedLastFour: String) -> Bool {
        parsedCardIdentifier == storedLastFour
    }
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
        senderIdentifiers: ["1599-9000"],
        cardBodyMarkers: ["MG카드(", "MG체크카드(", "MG더나은카드(", "MG더나은체크카드("],
        transactionBodyMarkers: ["체크승인", "승인취소"]
    )
    public let legacyMonthlyPerformanceTargetAmount = 300_000
    public let performanceThresholdAmounts = [300_000]
    public let benefitLimitPolicy = CardTypeBenefitLimitPolicy.perBenefit
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

/// MG+S 하나카드 definition used by ingestion and owned-card creation.
///
/// Benefit aggregation for this card uses one performance-tiered integrated
/// cap shared by all three benefit definitions.
public struct MGPlusSHanaCardDefinition: CardTypeDefining {
    public let code = "hana.mg-plus-s"
    public let displayName = "MG+S 하나카드"
    public let issuerCode = "HANA"
    public let messageIdentification = CardMessageIdentificationRules(
        senderIdentifiers: ["1800-1111"],
        cardBodyMarkers: ["MG+하나"],
        transactionBodyMarkers: ["승인"]
    )
    public let legacyMonthlyPerformanceTargetAmount = 300_000
    public let performanceThresholdAmounts = [300_000, 600_000, 1_000_000]
    public let benefitLimitPolicy = CardTypeBenefitLimitPolicy.integrated(tiers: [
        PerformanceBenefitTier(minimumPreviousMonthPerformanceAmount: 0, maximumAmount: 0),
        PerformanceBenefitTier(minimumPreviousMonthPerformanceAmount: 300_000, maximumAmount: 15_000),
        PerformanceBenefitTier(minimumPreviousMonthPerformanceAmount: 600_000, maximumAmount: 30_000),
        PerformanceBenefitTier(minimumPreviousMonthPerformanceAmount: 1_000_000, maximumAmount: 60_000)
    ])
    public let performanceCalculationBasis = "전월 정상 이용금액"
    public let benefits: [CardTypeBenefitDefinition] = [
        CardTypeBenefitDefinition(
            id: UUID(uuidString: "00000000-0000-0012-0001-000000000001")!,
            code: "simple-pay-statement-discount",
            label: "간편결제 10% 청구할인",
            eligibleMerchants: ["네이버페이", "카카오페이", "토스페이", "SSG페이", "11pay", "스마일페이"],
            minimumTransactionAmount: 10_000,
            requiredPreviousMonthPerformanceAmount: nil,
            rateBasisPoints: 1_000,
            monthlyMaximumAmount: nil
        ),
        CardTypeBenefitDefinition(
            id: UUID(uuidString: "00000000-0000-0012-0002-000000000002")!,
            code: "streaming-statement-discount",
            label: "영상 스트리밍 50% 청구할인",
            eligibleMerchants: ["유튜브", "디즈니플러스", "Wavve", "넷플릭스", "티빙"],
            minimumTransactionAmount: 0,
            requiredPreviousMonthPerformanceAmount: nil,
            rateBasisPoints: 5_000,
            monthlyMaximumAmount: nil,
            recurringPaymentOnly: true
        ),
        CardTypeBenefitDefinition(
            id: UUID(uuidString: "00000000-0000-0012-0003-000000000003")!,
            code: "digital-membership-statement-discount",
            label: "디지털 멤버십 50% 청구할인",
            eligibleMerchants: ["네이버플러스멤버십", "컬리멤버스", "쿠팡와우멤버십"],
            minimumTransactionAmount: 0,
            requiredPreviousMonthPerformanceAmount: nil,
            rateBasisPoints: 5_000,
            monthlyMaximumAmount: nil,
            recurringPaymentOnly: true
        )
    ]
    public let performanceExclusions = [
        "국세 및 지방세",
        "수도요금 및 전기요금",
        "우편요금, 과태료, 범칙금과 벌금",
        "국가, 공공기관 또는 공공단체가 부과하는 부담금",
        "도시가스 요금",
        "아파트관리비",
        "국민연금, 고용보험료, 산재보험료와 건강보험료",
        "스쿨뱅킹",
        "초·중·고 학교 납입금",
        "대학 및 대학원 등록금",
        "상품권 및 기프트카드 구매",
        "선불카드 및 선불전자지급수단 충전금액(하나머니 등)",
        "부동산 임대료"
    ]
    public let benefitExclusions = [
        "국세",
        "지방세",
        "그 외 공과금(우편요금, 과태료, 범칙금, 벌금, 국가·공공기관·공공단체가 부과하는 부담금)",
        "국민연금, 고용보험료, 산재보험료와 건강보험료 납부 금액",
        "수도요금",
        "스쿨뱅킹",
        "초·중·고 학교 납입금",
        "대학등록금",
        "대학원등록금",
        "상품권 및 기프트카드 구매",
        "선불카드 및 선불전자지급수단(하나머니 등) 충전 금액",
        "부동산 임대료",
        "무이자 할부 및 부분 무이자 할부 이용금액 전체"
    ]

    private let parser: MGPlusSHanaCardMessageParser

    public init(parser: MGPlusSHanaCardMessageParser = MGPlusSHanaCardMessageParser()) {
        self.parser = parser
    }

    public func identifies(messageBody: String) -> Bool {
        let compactBody = messageBody.filter { !$0.isWhitespace }
        return compactBody.contains("MG+하나") && compactBody.contains("승인")
    }

    public func parse(_ originalMessage: String) -> ParseResult {
        parser.parse(originalMessage)
    }

    public func matches(parsedCardIdentifier: String, storedLastFour: String) -> Bool {
        guard storedLastFour.count == 4, storedLastFour.allSatisfy(\.isNumber) else {
            return false
        }
        let digits = Array(storedLastFour)
        return parsedCardIdentifier == "\(digits[0])*\(digits[2])*"
    }
}
