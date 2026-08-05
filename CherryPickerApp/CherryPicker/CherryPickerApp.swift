import SwiftUI
import SwiftData

@main
struct CherryPickerApp: App {
    private let modelContainer: ModelContainer
    private let persistenceErrorMessage: String?

    init() {
        do {
            modelContainer = try PersistenceController.makeModelContainer()
            persistenceErrorMessage = nil
        } catch {
            // An in-memory fallback keeps the diagnostic UI available if a
            // device's local store is temporarily unavailable. Keep the error
            // visible in the UI so the fallback cannot be mistaken for an
            // empty persistent inbox.
            do {
                modelContainer = try PersistenceController.makeModelContainer(inMemory: true)
                persistenceErrorMessage = String(describing: error)
            } catch {
                // ModelContainer construction is expected to succeed for the
                // bundled schema. Keep the failure explicit if the platform
                // cannot create even an in-memory store.
                fatalError("Unable to create CherryPicker model container: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if let persistenceErrorMessage {
                PersistenceUnavailableView(details: persistenceErrorMessage)
            } else {
                RootView()
            }
        }
        .modelContainer(modelContainer)
    }
}

private struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var seedingErrorMessage: String?

    var body: some View {
        TabView {
            Tab("거래", systemImage: "tray.full") {
                InboxView()
            }

            Tab("설정", systemImage: "creditcard") {
                CardSettingsView()
            }
        }
        .task {
            do {
                let store = CardStore(modelContainer: modelContext.container)
                _ = try await store.seedDefaultCardIfNeeded()
            } catch {
                seedingErrorMessage = error.localizedDescription
            }
        }
        .alert("기본 카드 설정을 만들 수 없습니다", isPresented: Binding(
            get: { seedingErrorMessage != nil },
            set: { if !$0 { seedingErrorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(seedingErrorMessage ?? "알 수 없는 오류가 발생했습니다.")
        }
    }
}

private struct PersistenceUnavailableView: View {
    let details: String

    var body: some View {
        ContentUnavailableView(
            "로컬 저장소를 사용할 수 없습니다",
            systemImage: "externaldrive.badge.xmark",
            description: Text(
                "거래 데이터를 불러오지 못했습니다. 앱을 다시 실행하거나 저장소 상태를 확인하세요.\n\n오류: \(details)"
            )
        )
    }
}
