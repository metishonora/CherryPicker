import Foundation
import SwiftData

enum CherryPickerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [CherryPickerSchemaV1.self, CherryPickerSchemaV2.self]
    }

    static var stages: [MigrationStage] { [migrateV1ToV2] }

    private static let migrateV1ToV2 = MigrationStage.custom(
        fromVersion: CherryPickerSchemaV1.self,
        toVersion: CherryPickerSchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            let cards = try context.fetch(FetchDescriptor<CardRecord>())
            let defaultCard: CardRecord
            if let existing = cards.first(where: { $0.issuerCode == "MG" && $0.lastFour == "4775" }) {
                defaultCard = existing
            } else {
                defaultCard = CardRecord(
                    displayName: "MG 더나은 체크카드",
                    issuerCode: "MG",
                    lastFour: "4775",
                    performanceTargetAmount: 300_000
                )
                context.insert(defaultCard)
            }

            let transactions = try context.fetch(FetchDescriptor<TransactionRecord>())
            for transaction in transactions {
                transaction.createdAt = transaction.createdAt ?? transaction.receivedAt
                transaction.updatedAt = transaction.updatedAt ?? transaction.receivedAt
                backfillLegacyDate(transaction)
                backfillLegacyOverrides(transaction)
                if transaction.benefitAmount != nil, transaction.benefitUnitCode == nil {
                    transaction.benefitUnitCode = "legacyUnspecified"
                }
                if transaction.parsedCardLastFour == "4775" {
                    transaction.card = defaultCard
                    transaction.cardAssignmentSourceRaw = "migrationExactMatch"
                }
            }
            try context.save()
        }
    )

    private static func backfillLegacyDate(_ transaction: TransactionRecord) {
        guard let month = transaction.parsedMonth, let day = transaction.parsedDay else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let receivedYear = calendar.component(.year, from: transaction.receivedAt)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = receivedYear
        components.month = month
        components.day = day
        components.hour = transaction.parsedHour ?? 0
        components.minute = transaction.parsedMinute ?? 0

        transaction.resolvedYear = receivedYear
        transaction.resolvedMonth = month
        transaction.resolvedDay = day
        transaction.resolvedHour = transaction.parsedHour
        transaction.resolvedMinute = transaction.parsedMinute
        transaction.resolvedInstant = calendar.date(from: components)
        transaction.datePrecisionRaw = transaction.parsedHour == nil ? "day" : "minute"
        transaction.dateResolutionSourceRaw = "legacyReceivedYear"
        transaction.dateResolverVersion = "legacy-received-year-v1"
        transaction.dateTimeZoneIdentifier = "Asia/Seoul"
    }

    private static func backfillLegacyOverrides(_ transaction: TransactionRecord) {
        guard transaction.legacyHasUserEdits == true else { return }
        transaction.hasKindOverride = true
        transaction.kindOverrideRaw = transaction.parsedKindRaw
        transaction.hasAmountOverride = true
        transaction.amountOverride = transaction.parsedAmount
        transaction.hasDateOverride = true
        transaction.dateOverrideYear = transaction.resolvedYear
        transaction.dateOverrideMonth = transaction.parsedMonth
        transaction.dateOverrideDay = transaction.parsedDay
        transaction.dateOverrideHour = transaction.parsedHour
        transaction.dateOverrideMinute = transaction.parsedMinute
        transaction.dateOverridePrecisionRaw = transaction.parsedHour == nil ? "day" : "minute"
        transaction.hasMerchantOverride = true
        transaction.merchantOverride = transaction.parsedMerchant
    }
}

enum PersistenceController {
    static let schema = Schema(versionedSchema: CherryPickerSchemaV2.self)

    static func makeModelContainer(
        inMemory: Bool = false,
        url: URL? = nil
    ) throws -> ModelContainer {
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                schema: schema,
                url: url ?? defaultStoreURL,
                cloudKitDatabase: .none
            )
        }
        return try ModelContainer(
            for: schema,
            migrationPlan: CherryPickerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    static func makeV1ModelContainer(url: URL) throws -> ModelContainer {
        let v1Schema = Schema(versionedSchema: CherryPickerSchemaV1.self)
        let configuration = ModelConfiguration(
            schema: v1Schema,
            url: url,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: v1Schema, configurations: [configuration])
    }

    private static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }
}
