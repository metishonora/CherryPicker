import XCTest
@testable import CherryPickerCore

final class MGPlusSHanaCardDefinitionTests: XCTestCase {
    private let definition = MGPlusSHanaCardDefinition()

    func testDefinitionOwnsStableIdentityAndConfirmedSender() {
        XCTAssertEqual(definition.code, "hana.mg-plus-s")
        XCTAssertEqual(definition.displayName, "MG+S 하나카드")
        XCTAssertEqual(definition.performanceThresholdAmounts, [300_000, 600_000, 1_000_000])
        XCTAssertEqual(definition.messageIdentification.senderIdentifiers, ["1800-1111"])
        XCTAssertEqual(
            definition.messageIdentification.transactionBodyMarkers,
            ["승인", "취소"]
        )
        XCTAssertEqual(
            MGTheBetterCheckCardDefinition().messageIdentification.senderIdentifiers,
            ["1599-9000"]
        )
    }

    func testDefinitionIdentifiesOnlyMGPlusBodyAmongKnownApprovalFormats() {
        XCTAssertTrue(definition.identifies(messageBody: mgPlusApproval))
        XCTAssertTrue(definition.identifies(messageBody: mgPlusCancellation))
        XCTAssertFalse(definition.identifies(messageBody: wonderApproval))
        XCTAssertFalse(definition.identifies(messageBody: betterCheckApproval))

        let betterCheck = MGTheBetterCheckCardDefinition()
        XCTAssertTrue(betterCheck.identifies(messageBody: betterCheckApproval))
        XCTAssertFalse(betterCheck.identifies(messageBody: mgPlusApproval))
        XCTAssertFalse(betterCheck.identifies(messageBody: wonderApproval))
    }

    func testParserExtractsConfirmedApprovalAndCancellationFields() throws {
        let parsed = try XCTUnwrap(definition.parse(mgPlusApproval).transaction)
        XCTAssertEqual(parsed.kind, .approval)
        XCTAssertEqual(parsed.cardLast4, "1*3*")
        XCTAssertEqual(parsed.amount, 12_340)
        XCTAssertEqual(parsed.month, 1)
        XCTAssertEqual(parsed.day, 15)
        XCTAssertEqual(parsed.hour, 12)
        XCTAssertEqual(parsed.minute, 34)
        XCTAssertEqual(parsed.merchant, "합성상점")
        XCTAssertNil(parsed.accountBalance)

        let cancellation = try XCTUnwrap(definition.parse(mgPlusCancellation).transaction)
        XCTAssertEqual(cancellation.kind, .cancellation)
        XCTAssertEqual(cancellation.cardLast4, "1*3*")
        XCTAssertEqual(cancellation.amount, 13_100)
        XCTAssertEqual(cancellation.month, 1)
        XCTAssertEqual(cancellation.day, 16)
        XCTAssertEqual(cancellation.hour, 9)
        XCTAssertEqual(cancellation.minute, 0)
        XCTAssertEqual(cancellation.merchant, "합성취소가맹점")
        XCTAssertNil(cancellation.accountBalance)

        let guessedCancellation = definition.parse(
            "[Web발신] MG+ 하나1*3*승인취소 홍*동 12,340원 01/16 합성취소가맹점"
        )
        XCTAssertFalse(guessedCancellation.isSuccess)
        XCTAssertEqual(guessedCancellation.failure?.kind, .unsupported)
    }

    func testMaskedIdentifierRequiresTheStoredFirstAndThirdDigits() {
        XCTAssertTrue(definition.matches(
            parsedCardIdentifier: "1*3*",
            storedLastFour: "1234"
        ))
        XCTAssertTrue(definition.matches(
            parsedCardIdentifier: "1*3*",
            storedLastFour: "1938"
        ))
        XCTAssertFalse(definition.matches(
            parsedCardIdentifier: "1*3*",
            storedLastFour: "1294"
        ))
        XCTAssertFalse(definition.matches(
            parsedCardIdentifier: "1*3*",
            storedLastFour: "12*4"
        ))
    }

    private var mgPlusApproval: String {
        """
        [Web발신]
        MG+ 하나1*3*승인 홍*동 12,340원 일시불 01/15 12:34 합성상점 누적123,456원
        """
    }

    private var wonderApproval: String {
        "[Web발신] 하나9*8*승인 홍*동 5,200원 일시불 01/15 12:45 합성멤버십 누적98,765원"
    }

    private var mgPlusCancellation: String {
        """
        [Web발신]
        MG+ 하나1*3*취소 홍*동 13,100원 일시불 01/16 09:00 합성취소가맹점 누적123,456원
        """
    }

    private var betterCheckApproval: String {
        "[Web발신] MG카드(4775)체크승인 2,500원 01/15 12:40 합성기존가맹점"
    }
}
