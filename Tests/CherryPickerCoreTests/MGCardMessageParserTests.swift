import XCTest
@testable import CherryPickerCore

final class MGCardMessageParserTests: XCTestCase {
    private let parser = MGCardMessageParser()

    func testApprovalMessage() throws {
        let message = """
        [Web발신]
        MG카드(4775)체크승인
        김*겸님
        2,500원
        08/03 18:00
        씨유(CU)삼성백암점
        통장잔액426,905원
        """

        let transaction = try XCTUnwrap(parser.parse(message).transaction)
        XCTAssertEqual(transaction.kind, .approval)
        XCTAssertEqual(transaction.cardLast4, "4775")
        XCTAssertEqual(transaction.amount, 2_500)
        XCTAssertEqual(transaction.month, 8)
        XCTAssertEqual(transaction.day, 3)
        XCTAssertEqual(transaction.hour, 18)
        XCTAssertEqual(transaction.minute, 0)
        XCTAssertEqual(transaction.merchant, "씨유(CU)삼성백암점")
        XCTAssertEqual(transaction.accountBalance, 426_905)
        XCTAssertFalse(transaction.parserVersion.isEmpty)
        XCTAssertEqual(transaction.originalMessage, message)
    }

    func testCancellationMessage() throws {
        let message = """
        [Web발신]
        [승인취소]
        MG체크카드(4775).김*겸님.
        3,800원.
        08/03.취소완료.
        네이버페이
        """

        let transaction = try XCTUnwrap(parser.parse(message).transaction)
        XCTAssertEqual(transaction.kind, .cancellation)
        XCTAssertEqual(transaction.cardLast4, "4775")
        XCTAssertEqual(transaction.amount, 3_800)
        XCTAssertEqual(transaction.month, 8)
        XCTAssertEqual(transaction.day, 3)
        XCTAssertNil(transaction.hour)
        XCTAssertNil(transaction.minute)
        XCTAssertEqual(transaction.merchant, "네이버페이")
        XCTAssertNil(transaction.accountBalance)
        XCTAssertEqual(transaction.originalMessage, message)
    }

    func testSecondApprovalMessage() throws {
        let message = """
        [Web발신]
        MG카드(4775)체크승인
        김*겸님
        7,700원
        08/03 16:40
        네이버페이
        통장잔액425,605원
        """

        let transaction = try XCTUnwrap(parser.parse(message).transaction)
        XCTAssertEqual(transaction.kind, .approval)
        XCTAssertEqual(transaction.amount, 7_700)
        XCTAssertEqual(transaction.month, 8)
        XCTAssertEqual(transaction.day, 3)
        XCTAssertEqual(transaction.hour, 16)
        XCTAssertEqual(transaction.minute, 40)
        XCTAssertEqual(transaction.merchant, "네이버페이")
        XCTAssertEqual(transaction.accountBalance, 425_605)
    }

    func testUnknownMessageIsExplicitlyUnsupportedAndPreservesInput() {
        let message = "[Web발신]\n알 수 없는 카드 알림"

        let result = parser.parse(message)
        guard case let .unsupported(failure) = result else {
            return XCTFail("Expected an unsupported result, got \(result)")
        }
        XCTAssertEqual(failure.kind, .unsupported)
        XCTAssertEqual(failure.originalMessage, message)
        XCTAssertFalse(failure.reason.isEmpty)
    }

    func testCRLFWhitespaceAndPeriodVariants() throws {
        let message = "  [Web발신] \r\n MG 카드 ( 4775 ) 체크 승인 \r\n 김*겸님 \r\n 1.234원. \r\n 8 / 3 7:05. \r\n 네이버페이 \r\n 통장잔액 9,876원.  "

        let transaction = try XCTUnwrap(parser.parse(message).transaction)
        XCTAssertEqual(transaction.kind, .approval)
        XCTAssertEqual(transaction.cardLast4, "4775")
        XCTAssertEqual(transaction.amount, 1_234)
        XCTAssertEqual(transaction.month, 8)
        XCTAssertEqual(transaction.day, 3)
        XCTAssertEqual(transaction.hour, 7)
        XCTAssertEqual(transaction.minute, 5)
        XCTAssertEqual(transaction.merchant, "네이버페이")
        XCTAssertEqual(transaction.accountBalance, 9_876)
    }

    func testShortcutFlattenedApprovalMessage() throws {
        let message = "[Web발신] MG카드(4775)체크승인 김*겸님 2,500원 08/03 18:00 씨유(CU)삼성백암점 통장잔액426,905원"

        let transaction = try XCTUnwrap(parser.parse(message).transaction)
        XCTAssertEqual(transaction.kind, .approval)
        XCTAssertEqual(transaction.cardLast4, "4775")
        XCTAssertEqual(transaction.amount, 2_500)
        XCTAssertEqual(transaction.month, 8)
        XCTAssertEqual(transaction.day, 3)
        XCTAssertEqual(transaction.hour, 18)
        XCTAssertEqual(transaction.minute, 0)
        XCTAssertEqual(transaction.merchant, "씨유(CU)삼성백암점")
        XCTAssertEqual(transaction.accountBalance, 426_905)
    }

    func testShortcutFlattenedCancellationMessage() throws {
        let message = "[Web발신] [승인취소] MG체크카드(4775).김*겸님. 3,800원. 08/03.취소완료. 네이버페이"

        let transaction = try XCTUnwrap(parser.parse(message).transaction)
        XCTAssertEqual(transaction.kind, .cancellation)
        XCTAssertEqual(transaction.cardLast4, "4775")
        XCTAssertEqual(transaction.amount, 3_800)
        XCTAssertEqual(transaction.month, 8)
        XCTAssertEqual(transaction.day, 3)
        XCTAssertNil(transaction.hour)
        XCTAssertNil(transaction.minute)
        XCTAssertEqual(transaction.merchant, "네이버페이")
        XCTAssertNil(transaction.accountBalance)
    }

    func testMalformedRecognizedMessageIsFailedResult() {
        let message = "[Web발신]\nMG카드(4775)체크승인\n금액을 알 수 없음"

        guard case let .failed(failure) = parser.parse(message) else {
            return XCTFail("Expected a failed result")
        }
        XCTAssertEqual(failure.kind, .failed)
        XCTAssertEqual(failure.originalMessage, message)
    }

    func testResultAndThrowingAPIsUseTypedFailure() {
        let message = "지원하지 않는 알림"
        guard case let .failure(.unsupported(failure)) = parser.parseResult(message) else {
            return XCTFail("Expected a typed unsupported failure")
        }
        XCTAssertEqual(failure.originalMessage, message)
        XCTAssertThrowsError(try parser.parseThrowing(message)) { error in
            guard case ParseError.unsupported = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
