import SwiftUI
import SwiftData

struct InboxView: View {
    @Query(
        sort: [SortDescriptor(\TransactionRecord.receivedAt, order: .reverse)]
    ) private var records: [TransactionRecord]
    @State private var filter: InboxFilter = .all

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView(
                        "저장된 거래가 없습니다",
                        systemImage: "tray",
                        description: Text("단축어에서 받은 카드 문자를 저장하면 여기에 표시됩니다.")
                    )
                } else if filteredRecords.isEmpty {
                    ContentUnavailableView(
                        "조건에 맞는 거래가 없습니다",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("다른 필터를 선택해보세요.")
                    )
                } else {
                    List(filteredRecords) { record in
                        NavigationLink {
                            TransactionDetailView(record: record)
                        } label: {
                            TransactionRow(record: record)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("거래 수집함")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("필터", selection: $filter) {
                            ForEach(InboxFilter.allCases) { filter in
                                Label(filter.title, systemImage: filter.systemImage)
                                    .tag(filter)
                            }
                        }
                    } label: {
                        Label(filter.title, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    private var filteredRecords: [TransactionRecord] {
        records.filter { record in
            switch filter {
            case .all:
                return true
            case .unreviewed:
                return record.reviewStatusRaw != ReviewStatus.reviewed.rawValue
            case .failed:
                return record.parseStatusRaw == ParseStatus.failed.rawValue
            case .approval:
                return record.kindRaw == "approval"
            case .cancellation:
                return record.kindRaw == "cancellation"
            }
        }
    }
}

private enum InboxFilter: String, CaseIterable, Identifiable {
    case all
    case unreviewed
    case failed
    case approval
    case cancellation

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "전체"
        case .unreviewed: "미확인"
        case .failed: "파싱 실패"
        case .approval: "승인"
        case .cancellation: "취소"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .unreviewed: "questionmark.circle"
        case .failed: "exclamationmark.triangle"
        case .approval: "checkmark.circle"
        case .cancellation: "arrow.uturn.backward.circle"
        }
    }
}

private struct TransactionDetailView: View {
    let record: TransactionRecord

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var kindRaw: String
    @State private var amountText: String
    @State private var merchant: String
    @State private var transactionDate: Date
    @State private var includesTime: Bool
    @State private var reviewStatusRaw: String
    @State private var performanceDecisionRaw: String
    @State private var benefitDecisionRaw: String
    @State private var benefitAmountText: String
    @State private var userMemo: String
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    init(record: TransactionRecord) {
        self.record = record
        _kindRaw = State(initialValue: record.kindRaw ?? "approval")
        _amountText = State(initialValue: record.amount.map(String.init) ?? "")
        _merchant = State(initialValue: record.merchant ?? "")
        _transactionDate = State(initialValue: Self.date(from: record))
        _includesTime = State(initialValue: record.hour != nil && record.minute != nil)
        _reviewStatusRaw = State(initialValue: record.reviewStatusRaw ?? ReviewStatus.unreviewed.rawValue)
        _performanceDecisionRaw = State(
            initialValue: record.performanceDecisionRaw ?? PerformanceDecision.undecided.rawValue
        )
        _benefitDecisionRaw = State(
            initialValue: record.benefitDecisionRaw ?? BenefitDecision.undecided.rawValue
        )
        _benefitAmountText = State(initialValue: record.benefitAmount.map(String.init) ?? "")
        _userMemo = State(initialValue: record.userMemo ?? "")
    }

    var body: some View {
        Form {
            Section("거래 정보") {
                Picker("종류", selection: $kindRaw) {
                    Text("승인").tag("approval")
                    Text("취소").tag("cancellation")
                }

                TextField("가맹점", text: $merchant)
                TextField("금액", text: $amountText)
                    .keyboardType(.numberPad)

                DatePicker("거래일", selection: $transactionDate, displayedComponents: .date)
                Toggle("시간 정보 있음", isOn: $includesTime)
                if includesTime {
                    DatePicker("거래 시각", selection: $transactionDate, displayedComponents: .hourAndMinute)
                }
            }

            Section("검토 및 판정") {
                Picker("검토 상태", selection: $reviewStatusRaw) {
                    Text("미확인").tag(ReviewStatus.unreviewed.rawValue)
                    Text("확인 완료").tag(ReviewStatus.reviewed.rawValue)
                }

                Picker("실적", selection: $performanceDecisionRaw) {
                    Text("미확인").tag(PerformanceDecision.undecided.rawValue)
                    Text("인정").tag(PerformanceDecision.included.rawValue)
                    Text("제외").tag(PerformanceDecision.excluded.rawValue)
                }

                Picker("혜택", selection: $benefitDecisionRaw) {
                    Text("미확인").tag(BenefitDecision.undecided.rawValue)
                    Text("받음").tag(BenefitDecision.received.rawValue)
                    Text("못 받음").tag(BenefitDecision.missed.rawValue)
                    Text("대상 아님").tag(BenefitDecision.notEligible.rawValue)
                }

                if benefitDecisionRaw == BenefitDecision.received.rawValue {
                    TextField("받은 혜택 금액", text: $benefitAmountText)
                        .keyboardType(.numberPad)
                }

                TextField("메모", text: $userMemo, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("파싱 결과") {
                LabeledContent("상태", value: statusLabel)
                if let reason = record.parseFailureReason, !reason.isEmpty {
                    LabeledContent("실패 이유") {
                        Text(localizedFailureReason(reason))
                            .multilineTextAlignment(.trailing)
                    }
                }
                LabeledContent("입력 길이", value: "\(record.originalMessage.count)자")
            }

            Section {
                DisclosureGroup("저장된 원문 보기") {
                    Text(record.originalMessage.isEmpty ? "(빈 문자열)" : record.originalMessage)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            } footer: {
                Text("원문에는 이름과 통장 잔액이 포함될 수 있어 기본적으로 숨깁니다.")
            }

            Section {
                Button("거래 삭제", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .navigationTitle("거래 검토")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("저장", action: save)
            }
        }
        .confirmationDialog(
            "이 거래를 삭제할까요?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive, action: delete)
        } message: {
            Text("삭제한 거래는 복구할 수 없습니다.")
        }
        .alert("저장할 수 없습니다", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "알 수 없는 오류가 발생했습니다.")
        }
    }

    private func save() {
        let amountDigits = amountText.filter(\.isNumber)
        guard let amount = Int(amountDigits), amount > 0 else {
            errorMessage = "금액을 1원 이상의 숫자로 입력해주세요."
            return
        }

        let trimmedMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMerchant.isEmpty else {
            errorMessage = "가맹점명을 입력해주세요."
            return
        }

        let components = Calendar.current.dateComponents(
            [.month, .day, .hour, .minute],
            from: transactionDate
        )
        record.kindRaw = kindRaw
        record.amount = amount
        record.merchant = trimmedMerchant
        record.month = components.month
        record.day = components.day
        record.hour = includesTime ? components.hour : nil
        record.minute = includesTime ? components.minute : nil
        record.reviewStatusRaw = reviewStatusRaw
        record.performanceDecisionRaw = performanceDecisionRaw
        record.benefitDecisionRaw = benefitDecisionRaw
        record.benefitAmount = benefitDecisionRaw == BenefitDecision.received.rawValue
            ? Int(benefitAmountText.filter(\.isNumber))
            : nil
        record.userMemo = userMemo.trimmingCharacters(in: .whitespacesAndNewlines)
        record.hasUserEdits = true
        record.updatedAt = .now

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        modelContext.delete(record)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func date(from record: TransactionRecord) -> Date {
        var components = Calendar.current.dateComponents([.year], from: record.receivedAt)
        components.month = record.month
        components.day = record.day
        components.hour = record.hour ?? 12
        components.minute = record.minute ?? 0
        return Calendar.current.date(from: components) ?? record.receivedAt
    }

    private var statusLabel: String {
        switch record.parseStatusRaw {
        case ParseStatus.parsed.rawValue:
            return "파싱 완료"
        case ParseStatus.pending.rawValue:
            return "처리 중"
        default:
            return "파싱 실패"
        }
    }

    private func localizedFailureReason(_ reason: String) -> String {
        switch reason {
        case "The message is empty.":
            return "입력된 문자 내용이 비어 있습니다."
        case "No supported MG approval or cancellation marker was found.":
            return "MG 체크승인 또는 승인취소 표시를 찾지 못했습니다."
        case "The MG card suffix (four digits) could not be read.":
            return "MG카드 끝 네 자리를 읽지 못했습니다."
        case "The transaction amount could not be read.":
            return "거래 금액을 읽지 못했습니다."
        case "The transaction amount is not a valid integer number of won.":
            return "거래 금액을 원 단위 정수로 변환하지 못했습니다."
        case "The transaction month and day could not be read.":
            return "거래 월과 일을 읽지 못했습니다."
        case "The merchant name could not be identified.":
            return "가맹점명을 찾지 못했습니다."
        default:
            return reason
        }
    }
}

private struct TransactionRow: View {
    let record: TransactionRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(merchantName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let amount = record.amount {
                        Text(amount, format: .number)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(record.kindRaw == "cancellation" ? .red : .primary)
                        Text("원")
                            .font(.subheadline)
                    }
                }

                HStack(spacing: 8) {
                    Text(kindLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(iconColor)
                    Text(record.receivedAt, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if record.parseStatusRaw == ParseStatus.failed.rawValue {
                        Text("파싱 실패")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    if record.reviewStatusRaw != ReviewStatus.reviewed.rawValue {
                        Text("미확인")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }

    private var merchantName: String {
        guard let merchant = record.merchant, !merchant.isEmpty else {
            return "가맹점 미확인"
        }
        return merchant
    }

    private var kindLabel: String {
        switch record.kindRaw {
        case "approval":
            return "승인"
        case "cancellation":
            return "취소"
        default:
            return "미확인"
        }
    }

    private var iconName: String {
        switch record.kindRaw {
        case "approval":
            return "checkmark.circle.fill"
        case "cancellation":
            return "arrow.uturn.backward.circle.fill"
        default:
            return "questionmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch record.kindRaw {
        case "approval":
            return .green
        case "cancellation":
            return .red
        default:
            return .secondary
        }
    }
}

#Preview {
    InboxView()
        .modelContainer(try! PersistenceController.makeModelContainer(inMemory: true))
}
