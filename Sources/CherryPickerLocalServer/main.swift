import CherryPickerServer
import Darwin
import Foundation
import Hummingbird

@main
@available(macOS 14.0, *)
private struct CherryPickerLocalServer {
    private enum StartupError: Error {
        case databaseUnavailable
        case applicationUnavailable
    }

    static func main() async throws {
        _ = umask(0o077)
        let configuration = try LocalServerConfiguration.fromEnvironment()
        let fileManager = FileManager.default
        let parentDirectory = configuration.databaseURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: parentDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw StartupError.databaseUnavailable
        }

        let store: SQLiteEventStore
        do {
            store = try SQLiteEventStore(databaseURL: configuration.databaseURL)
        } catch {
            throw StartupError.databaseUnavailable
        }

        let application: CherryPickerHTTPApplication
        do {
            application = try CherryPickerHTTPApplication(
                store: store,
                authorizer: TailscaleIdentityAuthorizer(
                    allowedLogin: configuration.allowedLogin
                ),
                codec: OutboxJSONCodec(),
                port: configuration.port
            )
        } catch {
            throw StartupError.applicationUnavailable
        }

        // CherryPickerHTTPApplication pins the listener to 127.0.0.1.  No
        // configuration values are printed, and no request-body logging is
        // installed by this executable.
        try await application.application.runService()
    }
}
