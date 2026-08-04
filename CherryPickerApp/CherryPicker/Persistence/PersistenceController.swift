import SwiftData

/// Creates the local-only SwiftData container shared by the app and its App
/// Intents. No CloudKit configuration or network service is used.
enum PersistenceController {
    static let schema = Schema([TransactionRecord.self])

    static func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
