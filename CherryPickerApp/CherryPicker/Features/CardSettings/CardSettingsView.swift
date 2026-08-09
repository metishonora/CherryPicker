import SwiftData
import SwiftUI

enum CardSettingsField: Hashable {
    case displayName
    case issuerCode
    case lastFour
    case performanceTarget
}

enum CardSettingsDraftError: Error, Equatable {
    case invalidFields(Set<CardSettingsField>)
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

    var invalidFields: Set<CardSettingsField> {
        var fields: Set<CardSettingsField> = []

        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.insert(.displayName)
        }
        if issuerCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields.insert(.issuerCode)
        }

        let normalizedLastFour = lastFour.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedLastFour.count != 4
            || !normalizedLastFour.utf8.allSatisfy({ (48...57).contains($0) }) {
            fields.insert(.lastFour)
        }

        if performanceTargetEnabled {
            let normalizedTarget = normalizedPerformanceTarget
            let targetIsValid = !normalizedTarget.isEmpty
                && normalizedTarget.utf8.allSatisfy({ (48...57).contains($0) })
                && (Int(normalizedTarget).map { $0 > 0 } ?? false)
            if !targetIsValid {
                fields.insert(.performanceTarget)
            }
        }

        return fields
    }

    func makeCommand() throws -> CardSaveCommand {
        let fields = invalidFields
        guard fields.isEmpty else {
            throw CardSettingsDraftError.invalidFields(fields)
        }

        let target = performanceTargetEnabled ? Int(normalizedPerformanceTarget) : nil

        return CardSaveCommand(
            id: id,
            displayName: displayName,
            issuerCode: issuerCode,
            lastFour: lastFour,
            performanceTargetAmount: target
        )
    }

    private var normalizedPerformanceTarget: String {
        performanceTargetText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
    }
}

struct CardSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var draft = CardSettingsDraft()
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var notice: CardSettingsNotice?
    @State private var highlightedFields: Set<CardSettingsField> = []
    @State private var highlightToken = UUID()
    @State private var isSaveMessageVisible = false
    @State private var saveMessageToken = UUID()
    @FocusState private var focusedField: CardSettingsField?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("카드 설정을 불러오는 중…")
                } else {
                    Form {
                        Section("카드 정보") {
                            LabeledContent {
                                TextField("필수", text: $draft.displayName)
                                    .multilineTextAlignment(.trailing)
                                    .fontWeight(.medium)
                                    .foregroundStyle(fieldColor(.displayName))
                                    .focused($focusedField, equals: .displayName)
                                    .cardSettingsInputBorder(
                                        isHighlighted: highlightedFields.contains(.displayName)
                                    )
                            } label: {
                                Text("표시 이름")
                                    .foregroundStyle(labelColor(.displayName))
                            }
                            LabeledContent {
                                TextField("필수", text: $draft.issuerCode)
                                    .textInputAutocapitalization(.characters)
                                    .autocorrectionDisabled()
                                    .multilineTextAlignment(.trailing)
                                    .fontWeight(.medium)
                                    .foregroundStyle(fieldColor(.issuerCode))
                                    .focused($focusedField, equals: .issuerCode)
                                    .cardSettingsInputBorder(
                                        isHighlighted: highlightedFields.contains(.issuerCode)
                                    )
                            } label: {
                                Text("카드사")
                                    .foregroundStyle(labelColor(.issuerCode))
                            }
                            LabeledContent {
                                TextField("필수", text: $draft.lastFour)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .fontWeight(.medium)
                                    .foregroundStyle(fieldColor(.lastFour))
                                    .focused($focusedField, equals: .lastFour)
                                    .cardSettingsInputBorder(
                                        isHighlighted: highlightedFields.contains(.lastFour)
                                    )
                            } label: {
                                Text("끝 네 자리")
                                    .foregroundStyle(labelColor(.lastFour))
                            }
                        }

                        Section {
                            Toggle("실적 기준 사용", isOn: $draft.performanceTargetEnabled)
                            if draft.performanceTargetEnabled {
                                HStack {
                                    TextField("기준 금액", text: $draft.performanceTargetText)
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.trailing)
                                        .foregroundStyle(fieldColor(.performanceTarget))
                                        .focused($focusedField, equals: .performanceTarget)
                                    Text("원")
                                        .foregroundStyle(.secondary)
                                }
                                .cardSettingsInputBorder(
                                    isHighlighted: highlightedFields.contains(.performanceTarget)
                                )
                            }
                        } header: {
                            Text("카드 공통 실적 기준")
                        } footer: {
                            Text("혜택 적용 여부 계산에 사용하는 카드 공통 기준입니다. 실적 조건이 없는 카드는 기준을 끄세요. 0원은 저장하지 않습니다.")
                        }

                        Section("실적 산정 기간") {
                            LabeledContent("기간", value: "매월 1일~말일")
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture {
                        focusedField = nil
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") {
                        focusedField = nil
                    }
                }
            }
        }
        .task { await load() }
        .overlay(alignment: .bottom) {
            if isSaveMessageVisible {
                Label("저장했습니다", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 4, y: 2)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
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
            highlightedFields = []
            focusedField = nil
            showSaveMessage()
        } catch {
            isSaveMessageVisible = false
            highlight(fields(for: error))
        }
    }

    private func fields(for error: Error) -> Set<CardSettingsField> {
        switch error {
        case let CardSettingsDraftError.invalidFields(fields):
            return fields
        case CardStoreError.targetMustBePositive:
            return [.performanceTarget]
        case CardStoreError.displayNameRequired:
            return [.displayName]
        case CardStoreError.issuerCodeRequired:
            return [.issuerCode]
        case CardStoreError.invalidLastFour:
            return [.lastFour]
        case CardStoreError.duplicateIssuerAndLastFour:
            return [.issuerCode, .lastFour]
        default:
            return []
        }
    }

    @MainActor
    private func highlight(_ fields: Set<CardSettingsField>) {
        guard !fields.isEmpty else { return }

        let token = UUID()
        highlightToken = token
        withAnimation(.easeInOut(duration: 0.15)) {
            highlightedFields = fields
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard highlightToken == token else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                highlightedFields = []
            }
        }
    }

    private func fieldColor(_ field: CardSettingsField) -> Color {
        highlightedFields.contains(field) ? .red : .primary
    }

    private func labelColor(_ field: CardSettingsField) -> Color {
        highlightedFields.contains(field) ? .red : .secondary
    }

    @MainActor
    private func showSaveMessage() {
        let token = UUID()
        saveMessageToken = token
        withAnimation(.easeOut(duration: 0.2)) {
            isSaveMessageVisible = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard saveMessageToken == token else { return }
            withAnimation(.easeIn(duration: 0.2)) {
                isSaveMessageVisible = false
            }
        }
    }
}

private extension View {
    func cardSettingsInputBorder(isHighlighted: Bool) -> some View {
        padding(.horizontal, 8)
            .padding(.vertical, 6)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isHighlighted ? Color.red : Color.clear,
                        lineWidth: 2
                    )
            }
            .animation(.easeInOut(duration: 0.15), value: isHighlighted)
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
