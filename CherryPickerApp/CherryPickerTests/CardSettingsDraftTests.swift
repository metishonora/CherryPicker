import XCTest

@testable import CherryPicker

final class CardSettingsDraftTests: XCTestCase {
    func testDisabledTargetMapsToNoTargetEvenWhenTextContainsZero() throws {
        var draft = CardSettingsDraft()
        draft.displayName = "MG 더나은 체크카드"
        draft.issuerCode = "MG"
        draft.lastFour = "4775"
        draft.performanceTargetEnabled = false
        draft.performanceTargetText = "0"

        XCTAssertNil(try draft.makeCommand().performanceTargetAmount)
    }

    func testEnabledTargetParsesFormattedPositiveAmount() throws {
        var draft = CardSettingsDraft()
        draft.displayName = "MG 더나은 체크카드"
        draft.issuerCode = "MG"
        draft.lastFour = "4775"
        draft.performanceTargetEnabled = true
        draft.performanceTargetText = "300,000"

        XCTAssertEqual(try draft.makeCommand().performanceTargetAmount, 300_000)
    }

    func testEnabledTargetRejectsZeroOrEmptyAmount() {
        var draft = CardSettingsDraft()
        draft.performanceTargetEnabled = true

        draft.performanceTargetText = "0"
        XCTAssertThrowsError(try draft.makeCommand())

        draft.performanceTargetText = ""
        XCTAssertThrowsError(try draft.makeCommand())
    }

    func testEnabledTargetRejectsSignedOrUnitSuffixedInput() {
        var draft = CardSettingsDraft()
        draft.performanceTargetEnabled = true

        draft.performanceTargetText = "-1"
        XCTAssertThrowsError(try draft.makeCommand())

        draft.performanceTargetText = "30만원"
        XCTAssertThrowsError(try draft.makeCommand())
    }
}
