import XCTest
@testable import CherryPickerCore

final class MGTheBetterCheckCardDefinitionTests: XCTestCase {
    private let definition = MGTheBetterCheckCardDefinition()

    func testDefinitionOwnsStableIdentityPolicyAndBenefits() throws {
        XCTAssertEqual(definition.code, "mg.the-better-check")
        XCTAssertEqual(definition.displayName, "MG 더나은 체크카드")
        XCTAssertEqual(definition.issuerCode, "MG")
        XCTAssertEqual(definition.performanceThresholdAmounts, [300_000])
        XCTAssertEqual(definition.benefits.count, 3)
        XCTAssertEqual(Set(definition.benefits.map(\.code)).count, definition.benefits.count)
    }

    func testDefinitionOwnsVerifiedCashbackTerms() throws {
        let simplePay = try benefit(code: "simple-pay-cashback")
        XCTAssertEqual(simplePay.label, "간편결제 20% 할인캐시백")
        XCTAssertEqual(simplePay.eligibleMerchants, ["네이버페이", "카카오페이", "페이코"])
        XCTAssertEqual(simplePay.minimumTransactionAmount, 10_000)

        let onlineShopping = try benefit(code: "online-shopping-cashback")
        XCTAssertEqual(onlineShopping.label, "온라인 쇼핑 20% 할인캐시백")
        XCTAssertEqual(
            onlineShopping.eligibleMerchants,
            ["쿠팡", "무신사", "지그재그", "W컨셉", "에이블리"]
        )
        XCTAssertEqual(onlineShopping.minimumTransactionAmount, 10_000)

        let coffee = try benefit(code: "coffee-cashback")
        XCTAssertEqual(coffee.label, "커피 20% 할인캐시백")
        XCTAssertEqual(
            coffee.eligibleMerchants,
            ["스타벅스", "투썸플레이스", "커피빈", "메가커피", "빽다방", "컴포즈커피"]
        )
        XCTAssertEqual(coffee.minimumTransactionAmount, 5_000)
        XCTAssertEqual(
            coffee.exclusionNotes,
            ["백화점·할인점·아울렛·쇼핑몰·공항·호텔 등 입점매장 제외"]
        )

        for benefit in definition.benefits {
            XCTAssertEqual(benefit.rateBasisPoints, 2_000)
            XCTAssertEqual(benefit.requiredPreviousMonthPerformanceAmount, 300_000)
            XCTAssertEqual(benefit.monthlyMaximumAmount, 6_000)
        }
    }

    func testDefinitionOwnsVerifiedPerformanceAndCashbackExclusions() {
        XCTAssertEqual(definition.performanceCalculationBasis, "‘더나은’ 정상 이용금액")
        XCTAssertEqual(definition.performanceExclusions, [
            "해외가맹점 이용금액(CD·ATM 인출 포함)",
            "소액신용결제 및 후불교통 이용금액"
        ])
        XCTAssertEqual(definition.benefitExclusions, [
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
        ])
    }

    func testDefinitionIdentifiesAndParsesKnownApprovalAndCancellationBodies() throws {
        let approval = """
        [Web발신]
        MG카드(4775)체크승인
        김*겸님
        2,500원
        08/03 18:00
        씨유(CU)삼성백암점
        통장잔액426,905원
        """
        let cancellation = """
        [Web발신]
        [승인취소]
        MG체크카드(4775).김*겸님.
        3,800원.
        08/03.취소완료.
        네이버페이
        """

        XCTAssertTrue(definition.identifies(messageBody: approval))
        XCTAssertTrue(definition.identifies(messageBody: cancellation))
        XCTAssertEqual(try XCTUnwrap(definition.parse(approval).transaction).kind, .approval)
        XCTAssertEqual(try XCTUnwrap(definition.parse(cancellation).transaction).kind, .cancellation)
    }

    func testDefinitionIdentifiesMalformedKnownMessageWithoutClaimingUnknownMessages() {
        XCTAssertTrue(definition.identifies(
            messageBody: "[Web발신]\nMG카드(4775)체크승인\n금액을 알 수 없음"
        ))
        XCTAssertFalse(definition.identifies(messageBody: "[Web발신]\n알 수 없는 카드 알림"))
    }

    func testDefinitionOwnsParserVersion() throws {
        let definition = MGTheBetterCheckCardDefinition(
            parser: MGCardMessageParser(parserVersion: "definition-owned-parser")
        )
        let message = "[Web발신] MG카드(4775)체크승인 2,500원 08/03 18:00 네이버페이"

        XCTAssertEqual(
            try XCTUnwrap(definition.parse(message).transaction).parserVersion,
            "definition-owned-parser"
        )
    }

    private func benefit(code: String) throws -> CardTypeBenefitDefinition {
        try XCTUnwrap(definition.benefits.first { $0.code == code })
    }
}
