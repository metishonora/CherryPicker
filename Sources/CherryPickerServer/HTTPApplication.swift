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

        router.get("/api/v1/transactions") { request, _ async -> EditedResponse<String> in
            guard authorizer.isAuthorized(login: Self.tailscaleLogin(from: request)) else {
                return Self.unauthorizedResponse()
            }

            do {
                let transactions = try await store.safeTransactions()
                let responseData = try codec.encode(
                    SafeTransactionsResponse(transactions: transactions)
                )
                return Self.jsonResponse(status: .ok, data: responseData)
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
                return Self.htmlResponse(Self.renderHTML(transactions, receipts: receipts))
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

    private static func renderHTML(
        _ transactions: [SafeTransaction],
        receipts: [SafeEventReceipt]
    ) -> String {
        let dateFormatter = ISO8601DateFormatter()
        let rows = transactions.map { transaction in
            let id = htmlEscape(transaction.id.uuidString)
            let capturedAt = htmlEscape(dateFormatter.string(from: transaction.capturedAt))
            let parseStatus = htmlEscape(transaction.parseStatus.rawValue)
            let kind = htmlEscape(transaction.summary.kind ?? "review-needed")
            let amount = transaction.summary.amount.map(String.init).map(htmlEscape) ?? "—"
            let merchant = htmlEscape(transaction.summary.merchant ?? "—")
            let review = transaction.summary.reviewNeeded ? "review-needed" : "ready"
            return """
            <li data-transaction-id="\(id)">
              <span class="captured-at">\(capturedAt)</span>
              <span class="parse-status">parseStatus: \(parseStatus)</span>
              <span class="summary">summary: kind=\(kind), amount=\(amount), merchant=\(merchant), \(review)</span>
            </li>
            """
        }.joined()
        let syncRows = receipts.map { receipt in
            let eventID = htmlEscape(receipt.eventId.uuidString)
            let transactionID = htmlEscape(receipt.transactionID.uuidString)
            let capturedAt = htmlEscape(dateFormatter.string(from: receipt.capturedAt))
            let status = htmlEscape(receipt.status.rawValue)
            let disposition = receipt.disposition.map { htmlEscape($0.rawValue) } ?? "—"
            return """
            <li data-event-id="\(eventID)">
              <span class="sync-captured-at">\(capturedAt)</span>
              <span class="sync-result">syncResult: status=\(status), disposition=\(disposition), transactionId=\(transactionID)</span>
            </li>
            """
        }.joined()

        return """
        <!doctype html>
        <html lang="en">
          <head><meta charset="utf-8"><title>CherryPicker</title></head>
          <body>
            <h1>Transactions</h1>
            <p>parseStatus and summary</p>
            <ul>\(rows)</ul>
            <section id="sync-results">
              <h2>syncResult</h2>
              <ul>\(syncRows)</ul>
            </section>
          </body>
        </html>
        """
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
