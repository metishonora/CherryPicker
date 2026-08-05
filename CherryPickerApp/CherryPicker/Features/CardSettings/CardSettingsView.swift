import SwiftData
import SwiftUI

enum CardSettingsDraftError: Error, Equatable {
    case invalidTarget
}

struct CardSettingsDraft: Equatable {
    var id: UUID?
    var displayName = ""
    var issuerCode = ""
    var lastFour = ""
    var performanceTargetEnabled = true
    var performanceTargetText = ""

    init() {}

    init(card: CardSnapshot) {
        id = card.id
        displayName = card.displayName
        issuerCode = card.issuerCode
        lastFour = card.lastFour
        performanceTargetEnabled = card.performanceTargetAmount != nil
        performanceTargetText = card.performanceTargetAmount.map(String.init) ?? ""
    }

    func makeCommand() throws -> CardSaveCommand {
        let target: Int?
        if performanceTargetEnabled {
            let normalized = performanceTargetText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: "")
            guard !normalized.isEmpty,
                  normalized.utf8.allSatisfy({ (48...57).contains($0) }),
                  let parsed = Int(normalized),
                  parsed > 0 else {
                throw CardSettingsDraftError.invalidTarget
            }
            target = parsed
        } else {
            target = nil
        }

        return CardSaveCommand(
            id: id,
            displayName: displayName,
            issuerCode: issuerCode,
            lastFour: lastFour,
            performanceTargetAmount: target
        )
    }
}

struct CardSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var draft = CardSettingsDraft()
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var notice: CardSettingsNotice?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("카드 설정을 불러오는 중…")
                } else {
                    Form {
                        Section("카드 정보") {
                            TextField("표시 이름", text: $draft.displayName)
                            TextField("카드사", text: $draft.issuerCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                            TextField("끝 네 자리", text: $draft.lastFour)
                                .keyboardType(.numberPad)
                        }

                        Section {
                            Toggle("실적 기준 사용", isOn: $draft.performanceTargetEnabled)
                            if draft.performanceTargetEnabled {
                                HStack {
                                    TextField("기준 금액", text: $draft.performanceTargetText)
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.trailing)
                                    Text("원")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } header: {
                            Text("카드 공통 실적 기준")
                        } footer: {
                            Text("혜택 적용 여부 계산에 사용하는 카드 공통 기준입니다. 실적 조건이 없는 카드는 기준을 끄세요. 0원은 저장하지 않습니다.")
                        }

                        Section("실적 산정 기간") {
                            LabeledContent("기간", value: "매월 1일~말일")
                            LabeledContent("기준 시간대", value: "대한민국 표준시")
                        }
                    }
                }
            }
            .navigationTitle("카드 설정")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        Task { await save() }
                    }
                    .disabled(isLoading || isSaving)
                }
            }
        }
        .task { await load() }
        .alert(item: $notice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("확인"))
            )
        }
    }

    @MainActor
    private func load() async {
        do {
            let store = CardStore(modelContainer: modelContext.container)
            let cards = try await store.cards()
            let card: CardSnapshot
            if let existing = cards.first {
                card = existing
            } else {
                card = try await store.seedDefaultCardIfNeeded()
            }
            draft = CardSettingsDraft(card: card)
            isLoading = false
        } catch {
            isLoading = false
            notice = CardSettingsNotice(
                title: "설정을 불러올 수 없습니다",
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let command = try draft.makeCommand()
            let store = CardStore(modelContainer: modelContext.container)
            let saved = try await store.save(command)
            draft = CardSettingsDraft(card: saved)
            notice = CardSettingsNotice(title: "저장했습니다", message: "카드 설정이 기기에 저장되었습니다.")
        } catch {
            notice = CardSettingsNotice(title: "저장할 수 없습니다", message: message(for: error))
        }
    }

    private func message(for error: Error) -> String {
        switch error {
        case CardSettingsDraftError.invalidTarget, CardStoreError.targetMustBePositive:
            return "목표 금액을 1원 이상의 숫자로 입력해주세요."
        case CardStoreError.displayNameRequired:
            return "표시 이름을 입력해주세요."
        case CardStoreError.issuerCodeRequired:
            return "카드사를 입력해주세요."
        case CardStoreError.invalidLastFour:
            return "카드 끝 네 자리를 숫자 네 자리로 입력해주세요."
        case CardStoreError.duplicateIssuerAndLastFour:
            return "같은 카드사와 끝 네 자리를 가진 카드가 이미 있습니다."
        default:
            return error.localizedDescription
        }
    }
}

private struct CardSettingsNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

#Preview {
    CardSettingsView()
        .modelContainer(try! PersistenceController.makeModelContainer(inMemory: true))
}
