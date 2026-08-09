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
        var draft = validDraft()

        draft.performanceTargetText = "0"
        XCTAssertEqual(draft.invalidFields, [.performanceTarget])

        draft.performanceTargetText = ""
        XCTAssertEqual(draft.invalidFields, [.performanceTarget])
    }

    func testEnabledTargetRejectsSignedOrUnitSuffixedInput() {
        var draft = validDraft()

        draft.performanceTargetText = "-1"
        XCTAssertEqual(draft.invalidFields, [.performanceTarget])

        draft.performanceTargetText = "30만원"
        XCTAssertEqual(draft.invalidFields, [.performanceTarget])
    }

    func testInvalidFieldsIdentifiesEveryMalformedInput() {
        var draft = CardSettingsDraft()
        draft.displayName = "   "
        draft.issuerCode = ""
        draft.lastFour = "123"
        draft.performanceTargetEnabled = true
        draft.performanceTargetText = "0"

        XCTAssertEqual(
            draft.invalidFields,
            [.displayName, .issuerCode, .lastFour, .performanceTarget]
        )
    }

    func testDisabledPerformanceTargetIsNotInvalid() {
        var draft = CardSettingsDraft()
        draft.displayName = "MG 더나은 체크카드"
        draft.issuerCode = "MG"
        draft.lastFour = "4775"
        draft.performanceTargetEnabled = false
        draft.performanceTargetText = "0"

        XCTAssertTrue(draft.invalidFields.isEmpty)
    }

    private func validDraft() -> CardSettingsDraft {
        var draft = CardSettingsDraft()
        draft.displayName = "MG 더나은 체크카드"
        draft.issuerCode = "MG"
        draft.lastFour = "4775"
        draft.performanceTargetEnabled = true
        draft.performanceTargetText = "300000"
        return draft
    }
}
