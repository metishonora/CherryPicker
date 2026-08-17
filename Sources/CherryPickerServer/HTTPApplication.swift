import Foundation
import Hummingbird

/// Hummingbird adapter for the CherryPicker local product server.
///
/// The application is assembled as a value so tests can exercise the exact
/// routes in-process with HummingbirdTesting.  Persistence, authorization, and
/// wire encoding are injected rather than discovered from process globals.
@available(macOS 14.0, *)
public struct CherryPickerHTTPApplication {
    public let application: Application<RouterResponder<BasicRequestContext>>

    private static let maxBatchBodyBytes = 1_048_576

    public init(
        store: SQLiteEventStore,
        authorizer: TailscaleIdentityAuthorizer,
        codec: OutboxJSONCodec,
        port: Int = 8765
    ) throws {
        let ingestion = IngestionService(store: store, authorizer: authorizer)
        let router = Router()

        router.get("/healthz") { _, _ -> EditedResponse<String> in
            EditedResponse(status: .ok, response: "ok")
        }

        router.post("/api/v1/events/batch") { request, _ async -> EditedResponse<String> in
            let login = Self.tailscaleLogin(from: request)
            guard authorizer.isAuthorized(login: login) else {
                return Self.unauthorizedResponse()
            }

            do {
                // Authentication deliberately happens before consuming or
                // decoding the body.  Unauthorized requests cannot influence
                // parser or persistence state.
                let body = try await request.body.collect(upTo: Self.maxBatchBodyBytes)
                let decoded = try codec.decode(
                    BatchSyncRequest.self,
                    from: Data(body.readableBytesView)
                )
                let result = try await ingestion.ingest(decoded, login: login)
                let responseData = try codec.encode(result)
                return Self.jsonResponse(status: .ok, data: responseData)
            } catch IngestionServiceError.unauthorized {
                return Self.unauthorizedResponse()
            } catch {
                // Keep malformed input and storage failures generic.  In
                // particular, do not serialize Error descriptions or payloads.
                if error is SQLiteEventStoreError {
                    return Self.internalErrorResponse()
                }
                return Self.badRequestResponse()
            }
        }

        router.get("/api/v1/cards") { request, _ async -> EditedResponse<String> in
            guard authorizer.isAuthorized(login: Self.tailscaleLogin(from: request)) else {
                return Self.unauthorizedResponse()
            }
            do {
                return Self.jsonResponse(
                    status: .ok,
                    data: try codec.encode(
                        CardsResponse(cards: try await store.managedCards())
                    )
                )
            } catch {
                return Self.internalErrorResponse()
            }
        }

        router.put("/api/v1/cards/:id") { request, context async -> EditedResponse<String> in
            guard authorizer.isAuthorized(login: Self.tailscaleLogin(from: request)) else {
                return Self.unauthorizedResponse()
            }
            guard Self.hasValidCSRFHeader(request) else {
                return Self.forbiddenResponse()
            }
            guard let id = context.parameters.get("id", as: UUID.self) else {
                return Self.badRequestResponse()
            }
            do {
                let body = try await request.body.collect(upTo: Self.maxBatchBodyBytes)
                let update = try codec.decode(
                    CardUpdateRequest.self,
                    from: Data(body.readableBytesView)
                )
                guard let card = try await store.updateManagedCard(id: id, request: update) else {
                    return Self.notFoundResponse()
                }
                return Self.jsonResponse(
                    status: .ok,
                    data: try codec.encode(CardResponse(card: card))
                )
            } catch ManagementStoreError.invalidInput {
                return Self.badRequestResponse()
            } catch is DecodingError {
                return Self.badRequestResponse()
            } catch {
                return Self.internalErrorResponse()
            }
        }

        router.get("/api/v1/cards/:id/transactions") { request, context async -> EditedResponse<String> in
            guard authorizer.isAuthorized(login: Self.tailscaleLogin(from: request)) else {
                return Self.unauthorizedResponse()
            }
            guard let id = context.parameters.get("id", as: UUID.self) else {
                return Self.badRequestResponse()
            }
            let filter = request.uri.queryParameters["filter"].map(String.init)
            do {
                guard try await store.managedCard(id: id) != nil else {
                    return Self.notFoundResponse()
                }
                let transactions = try await store.managedTransactions(
                    cardID: id,
                    filter: filter
                )
                return Self.jsonResponse(
                    status: .ok,
                    data: try codec.encode(TransactionsResponse(transactions: transactions))
                )
            } catch ManagementStoreError.invalidInput {
                return Self.badRequestResponse()
            } catch {
                return Self.internalErrorResponse()
            }
        }

        router.get("/api/v1/cards/:id/dashboard") { request, context async -> EditedResponse<String> in
            guard authorizer.isAuthorized(login: Self.tailscaleLogin(from: request)) else {
                return Self.unauthorizedResponse()
            }
            guard let id = context.parameters.get("id", as: UUID.self) else {
                return Self.badRequestResponse()
            }
            do {
                guard let dashboard = try await store.dashboard(cardID: id) else {
                    return Self.notFoundResponse()
                }
                return Self.jsonResponse(
                    status: .ok,
                    data: try codec.encode(DashboardResponse(dashboard: dashboard))
                )
            } catch {
                return Self.internalErrorResponse()
            }
        }

        router.get("/api/v1/transactions") { request, _ async -> EditedResponse<String> in
            guard authorizer.isAuthorized(login: Self.tailscaleLogin(from: request)) else {
                return Self.unauthorizedResponse()
            }

            do {
                if let scope = request.uri.queryParameters["scope"].map(String.init) {
                    let transactions = try await store.managedTransactions(scope: scope)
                    return Self.jsonResponse(
                        status: .ok,
                        data: try codec.encode(TransactionsResponse(transactions: transactions))
                    )
                }
                let transactions = try await store.safeTransactions()
                return Self.jsonResponse(
                    status: .ok,
                    data: try codec.encode(SafeTransactionsResponse(transactions: transactions))
                )
            } catch ManagementStoreError.invalidInput {
                return Self.badRequestResponse()
            } catch {
                return Self.internalErrorResponse()
            }
        }

        router.get("/api/v1/transactions/:id") { request, context async -> EditedResponse<String> in
            guard authorizer.isAuthorized(login: Self.tailscaleLogin(from: request)) else {
                return Self.unauthorizedResponse()
            }
            guard let id = context.parameters.get("id", as: UUID.self) else {
                return Self.badRequestResponse()
            }
            do {
                guard let transaction = try await store.managedTransaction(id: id) else {
                    return Self.notFoundResponse()
                }
                return Self.jsonResponse(
                    status: .ok,
                    data: try codec.encode(TransactionResponse(transaction: transaction))
                )
            } catch {
                return Self.internalErrorResponse()
            }
        }

        router.patch("/api/v1/transactions/:id") { request, context async -> EditedResponse<String> in
            guard authorizer.isAuthorized(login: Self.tailscaleLogin(from: request)) else {
                return Self.unauthorizedResponse()
            }
            guard Self.hasValidCSRFHeader(request) else {
                return Self.forbiddenResponse()
            }
            guard let id = context.parameters.get("id", as: UUID.self) else {
                return Self.badRequestResponse()
            }
            do {
                let body = try await request.body.collect(upTo: Self.maxBatchBodyBytes)
                let data = Data(body.readableBytesView)
                guard
                    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    object["effectiveValues"] == nil
                else {
                    return Self.badRequestResponse()
                }
                let update = try codec.decode(TransactionUpdateRequest.self, from: data)
                guard let transaction = try await store.reviewTransaction(id: id, request: update) else {
                    return Self.notFoundResponse()
                }
                return Self.jsonResponse(
                    status: .ok,
                    data: try codec.encode(TransactionResponse(transaction: transaction))
                )
            } catch ManagementStoreError.invalidInput {
                return Self.badRequestResponse()
            } catch is DecodingError {
                return Self.badRequestResponse()
            } catch {
                return Self.internalErrorResponse()
            }
        }

        router.get("/") { request, _ async -> EditedResponse<String> in
            guard authorizer.isAuthorized(login: Self.tailscaleLogin(from: request)) else {
                return Self.unauthorizedResponse()
            }

            do {
                let transactions = try await store.safeTransactions()
                let receipts = try await store.safeEventReceipts()
                return Self.htmlResponse(
                    ProductWebPage.render(transactions: transactions, receipts: receipts)
                )
            } catch {
                return Self.internalErrorResponse()
            }
        }

        self.application = Application(
            router: router,
            configuration: .init(address: .hostname("127.0.0.1", port: port))
        )
    }

    // MARK: - Responses

    private static func jsonResponse(
        status: HTTPResponse.Status,
        data: Data
    ) -> EditedResponse<String> {
        EditedResponse(
            status: status,
            headers: contentHeaders("application/json; charset=utf-8"),
            response: String(decoding: data, as: UTF8.self)
        )
    }

    private static func htmlResponse(_ html: String) -> EditedResponse<String> {
        EditedResponse(
            status: .ok,
            headers: contentHeaders("text/html; charset=utf-8"),
            response: html
        )
    }

    private static func unauthorizedResponse() -> EditedResponse<String> {
        jsonResponse(status: .unauthorized, data: Data(#"{"error":"unauthorized"}"#.utf8))
    }

    private static func forbiddenResponse() -> EditedResponse<String> {
        jsonResponse(status: .forbidden, data: Data(#"{"error":"forbidden"}"#.utf8))
    }

    private static func notFoundResponse() -> EditedResponse<String> {
        jsonResponse(status: .notFound, data: Data(#"{"error":"not_found"}"#.utf8))
    }

    private static func badRequestResponse() -> EditedResponse<String> {
        jsonResponse(status: .badRequest, data: Data(#"{"error":"bad_request"}"#.utf8))
    }

    private static func internalErrorResponse() -> EditedResponse<String> {
        jsonResponse(
            status: .internalServerError,
            data: Data(#"{"error":"internal_server_error"}"#.utf8)
        )
    }

    private static func contentHeaders(_ contentType: String) -> HTTPFields {
        var headers: HTTPFields = [:]
        headers[.contentType] = contentType
        return headers
    }

    // MARK: - Identity and HTML

    private static func tailscaleLogin(from request: Request) -> String? {
        // HTTPFields performs case-insensitive field-name matching.  The
        // contextual name initializer avoids making the HTTPTypes package a
        // direct dependency of CherryPickerServer.
        request.headers[.init("Tailscale-User-Login")!]
    }

    private static func hasValidCSRFHeader(_ request: Request) -> Bool {
        request.headers[.init("X-CherryPicker-CSRF")!] == "same-origin"
    }

}
