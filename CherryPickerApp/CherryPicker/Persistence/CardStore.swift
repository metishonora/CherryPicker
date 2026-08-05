import Foundation
import SwiftData

import CherryPickerCore

struct CardSnapshot: Equatable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let issuerCode: String
    let lastFour: String
    let performanceTargetAmount: Int?
    let periodRuleKindRaw: String
    let timeZoneIdentifier: String
    let createdAt: Date
    let updatedAt: Date
}

struct CardSaveCommand: Equatable, Sendable {
    let id: UUID?
    let displayName: String
    let issuerCode: String
    let lastFour: String
    let performanceTargetAmount: Int?

    init(
        id: UUID? = nil,
        displayName: String,
        issuerCode: String,
        lastFour: String,
        performanceTargetAmount: Int?
    ) {
        self.id = id
        self.displayName = displayName
        self.issuerCode = issuerCode
        self.lastFour = lastFour
        self.performanceTargetAmount = performanceTargetAmount
    }
}

enum CardStoreError: Error, Equatable, Sendable {
    case displayNameRequired
    case issuerCodeRequired
    case invalidLastFour
    case targetMustBePositive
    case duplicateIssuerAndLastFour
    case cardNotFound
}

@ModelActor
actor CardStore {
    func cards() throws -> [CardSnapshot] {
        try modelContext.fetch(
            FetchDescriptor<CardRecord>(sortBy: [SortDescriptor(\CardRecord.createdAt)])
        ).map(Self.snapshot)
    }

    func seedDefaultCardIfNeeded() throws -> CardSnapshot {
        let existing = try modelContext.fetch(FetchDescriptor<CardRecord>()).first {
            $0.issuerCode == "MG" && $0.lastFour == "4775"
        }
        if let existing { return Self.snapshot(existing) }
        return try save(CardSaveCommand(
            displayName: "MG 더나은 체크카드",
            issuerCode: "MG",
            lastFour: "4775",
            performanceTargetAmount: 300_000
        ))
    }

    func save(_ command: CardSaveCommand) throws -> CardSnapshot {
        let displayName = command.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { throw CardStoreError.displayNameRequired }

        let issuerCode = command.issuerCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !issuerCode.isEmpty else { throw CardStoreError.issuerCodeRequired }

        let lastFour = command.lastFour.trimmingCharacters(in: .whitespacesAndNewlines)
        guard lastFour.count == 4, lastFour.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw CardStoreError.invalidLastFour
        }

        do {
            _ = try PerformanceRequirement(monthlyTargetAmount: command.performanceTargetAmount)
        } catch {
            throw CardStoreError.targetMustBePositive
        }

        let allCards = try modelContext.fetch(FetchDescriptor<CardRecord>())
        guard !allCards.contains(where: {
            $0.id != command.id && $0.issuerCode.uppercased() == issuerCode && $0.lastFour == lastFour
        }) else {
            throw CardStoreError.duplicateIssuerAndLastFour
        }

        let now = Date.now
        let record: CardRecord
        if let id = command.id {
            guard let existing = allCards.first(where: { $0.id == id }) else {
                throw CardStoreError.cardNotFound
            }
            record = existing
        } else {
            record = CardRecord(
                displayName: displayName,
                issuerCode: issuerCode,
                lastFour: lastFour,
                performanceTargetAmount: command.performanceTargetAmount,
                createdAt: now,
                updatedAt: now
            )
            modelContext.insert(record)
        }

        record.displayName = displayName
        record.issuerCode = issuerCode
        record.lastFour = lastFour
        record.performanceTargetAmount = command.performanceTargetAmount
        record.periodRuleKindRaw = "calendarMonth"
        record.timeZoneIdentifier = "Asia/Seoul"
        record.updatedAt = now
        try backfillUnassignedTransactions()
        try modelContext.save()
        return Self.snapshot(record)
    }

    func delete(id: UUID) throws {
        let cards = try modelContext.fetch(FetchDescriptor<CardRecord>())
        guard let card = cards.first(where: { $0.id == id }) else {
            throw CardStoreError.cardNotFound
        }
        modelContext.delete(card)
        try modelContext.save()
    }

    private func backfillUnassignedTransactions() throws {
        let cards = try modelContext.fetch(FetchDescriptor<CardRecord>())
        let transactions = try modelContext.fetch(FetchDescriptor<TransactionRecord>())
        for transaction in transactions where transaction.card == nil {
            guard let suffix = transaction.parsedCardLastFour else { continue }
            let matches = cards.filter { $0.issuerCode == "MG" && $0.lastFour == suffix }
            guard matches.count == 1 else { continue }
            transaction.card = matches[0]
            transaction.cardAssignmentSourceRaw = "backfillExactMatch"
        }
    }

    private static func snapshot(_ record: CardRecord) -> CardSnapshot {
        CardSnapshot(
            id: record.id,
            displayName: record.displayName,
            issuerCode: record.issuerCode,
            lastFour: record.lastFour,
            performanceTargetAmount: record.performanceTargetAmount,
            periodRuleKindRaw: record.periodRuleKindRaw,
            timeZoneIdentifier: record.timeZoneIdentifier,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }
}
