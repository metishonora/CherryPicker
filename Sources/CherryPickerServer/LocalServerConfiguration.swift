import Foundation

public enum LocalServerConfigurationError: Error, Equatable, Sendable {
    case missingAllowedLogin
    case invalidPort
}

/// Non-sensitive local server configuration shared by the executable and
/// contract tests. Values are never printed by this type.
public struct LocalServerConfiguration: Equatable, Sendable {
    public let allowedLogin: String
    public let databaseURL: URL
    public let port: Int

    public init(allowedLogin: String, databaseURL: URL, port: Int) {
        self.allowedLogin = allowedLogin
        self.databaseURL = databaseURL
        self.port = port
    }

    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> LocalServerConfiguration {
        guard let configuredLogin = environment["CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN"] else {
            throw LocalServerConfigurationError.missingAllowedLogin
        }
        let allowedLogin = configuredLogin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !allowedLogin.isEmpty else {
            throw LocalServerConfigurationError.missingAllowedLogin
        }

        let port: Int
        if let configuredPort = environment["CHERRYPICKER_PORT"] {
            guard let parsedPort = Int(configuredPort), (1...65_535).contains(parsedPort) else {
                throw LocalServerConfigurationError.invalidPort
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
            databaseURL = homeDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("CherryPicker", isDirectory: true)
                .appendingPathComponent("cherrypicker.sqlite", isDirectory: false)
        }

        return LocalServerConfiguration(
            allowedLogin: allowedLogin,
            databaseURL: databaseURL,
            port: port
        )
    }
}
