import XCTest
@testable import CherryPickerCore

final class MGTheBetterCheckCardDefinitionTests: XCTestCase {
    private let definition = MGTheBetterCheckCardDefinition()

    func testDefinitionOwnsStableIdentityPolicyAndBenefits() throws {
        XCTAssertEqual(definition.code, "mg.the-better-check")
        XCTAssertEqual(definition.displayName, "MG 더나은 체크카드")
        XCTAssertEqual(definition.issuerCode, "MG")
        XCTAssertEqual(definition.defaultMonthlyPerformanceTargetAmount, 300_000)
        XCTAssertFalse(definition.benefits.isEmpty)
        XCTAssertEqual(Set(definition.benefits.map(\.code)).count, definition.benefits.count)
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
}
