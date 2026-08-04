import AppIntents
import Foundation

struct SaveCardMessageIntent: AppIntent {
    static let title: LocalizedStringResource = "거래 문자 저장"
    static let description = IntentDescription(
        "받은 MG카드 승인 또는 승인취소 문자를 저장하고 거래 정보를 추출합니다."
    )
    static let isDiscoverable = true
    static let openAppWhenRun = false

    /// A message body supplied by a Shortcuts message automation.
    @Parameter(
        title: "문자 원문",
        description: "저장할 카드 문자 전체를 입력합니다."
    )
    var rawMessage: String

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try PersistenceController.makeModelContainer()
        let store = TransactionStore(modelContainer: container)
        let outcome = try await store.save(rawMessage: rawMessage, receivedAt: .now)
        return .result(dialog: IntentDialog(stringLiteral: outcome.summary))
    }
}

struct CherryPickerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveCardMessageIntent(),
            phrases: [
                "거래 문자를 \(.applicationName)에 저장",
                "카드 문자를 \(.applicationName)에 저장"
            ],
            shortTitle: "거래 문자 저장",
            systemImageName: "tray.and.arrow.down"
        )
    }
}
