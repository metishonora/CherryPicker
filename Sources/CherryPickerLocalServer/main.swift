import CherryPickerServer
import Darwin
import Foundation
import Hummingbird

@main
@available(macOS 14.0, *)
private struct CherryPickerLocalServer {
    private enum StartupError: Error {
        case missingAllowedLogin
        case invalidPort
        case databaseUnavailable
        case applicationUnavailable
    }

    private struct Configuration {
        let allowedLogin: String
        let databaseURL: URL
        let port: Int

        static func fromEnvironment(
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) throws -> Configuration {
            guard let configuredLogin = environment["CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN"] else {
                throw StartupError.missingAllowedLogin
            }
            let allowedLogin = configuredLogin.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !allowedLogin.isEmpty else {
                throw StartupError.missingAllowedLogin
            }

            let port: Int
            if let configuredPort = environment["CHERRYPICKER_PORT"] {
                guard let parsedPort = Int(configuredPort), (1...65_535).contains(parsedPort) else {
                    throw StartupError.invalidPort
                }
                port = parsedPort
            } else {
                port = 8765
            }

            let databaseURL: URL
            if let configuredPath = environment["CHERRYPICKER_DB_PATH"],
               !configuredPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                databaseURL = URL(fileURLWithPath: configuredPath, isDirectory: false)
            } else {
                databaseURL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library", isDirectory: true)
                    .appendingPathComponent("Application Support", isDirectory: true)
                    .appendingPathComponent("CherryPickerSpike", isDirectory: true)
                    .appendingPathComponent("events.sqlite", isDirectory: false)
            }

            return Configuration(
                allowedLogin: allowedLogin,
                databaseURL: databaseURL,
                port: port
            )
        }
    }

    static func main() async throws {
        _ = umask(0o077)
        let configuration = try Configuration.fromEnvironment()
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
