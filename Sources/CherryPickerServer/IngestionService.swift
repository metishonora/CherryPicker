import Foundation

/// Batch orchestration remains deliberately transport-neutral. An HTTP layer
/// can later adapt this actor without changing persistence or idempotency.
public actor IngestionService {
    private let store: SQLiteEventStore
    private let authorizer: TailscaleIdentityAuthorizer

    public init(
        store: SQLiteEventStore,
        authorizer: TailscaleIdentityAuthorizer
    ) {
        self.store = store
        self.authorizer = authorizer
    }

    public func ingest(
        _ request: BatchSyncRequest,
        login: String?
    ) async throws -> BatchSyncResponse {
        guard authorizer.isAuthorized(login: login) else {
            throw IngestionServiceError.unauthorized
        }

        var results: [SyncItemResult] = []
        results.reserveCapacity(request.events.count)
        for event in request.events {
            results.append(try await store.ingest(event))
        }
        return BatchSyncResponse(results: results)
    }
}
