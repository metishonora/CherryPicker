import Foundation
import XCTest

@testable import CherryPickerServer

final class LocalServerConfigurationTests: XCTestCase {
    func testDefaultConfigurationUsesProductDatabasePath() throws {
        let homeDirectory = URL(fileURLWithPath: "/Users/fixture", isDirectory: true)

        let configuration = try LocalServerConfiguration.fromEnvironment(
            ["CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN": " owner@example.test "],
            homeDirectory: homeDirectory
        )

        XCTAssertEqual(configuration.allowedLogin, "owner@example.test")
        XCTAssertEqual(configuration.port, 8765)
        XCTAssertEqual(
            configuration.databaseURL.path,
            "/Users/fixture/Library/Application Support/CherryPicker/cherrypicker.sqlite"
        )
    }

    func testExplicitDatabaseAndPortOverrideDefaults() throws {
        let configuration = try LocalServerConfiguration.fromEnvironment(
            [
                "CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN": "owner@example.test",
                "CHERRYPICKER_DB_PATH": "/private/tmp/cherrypicker-test.sqlite",
                "CHERRYPICKER_PORT": "9876"
            ],
            homeDirectory: URL(fileURLWithPath: "/Users/fixture", isDirectory: true)
        )

        XCTAssertEqual(configuration.port, 9876)
        XCTAssertEqual(configuration.databaseURL.path, "/private/tmp/cherrypicker-test.sqlite")
    }

    func testMissingOrBlankLoginFailsClosed() {
        XCTAssertThrowsError(
            try LocalServerConfiguration.fromEnvironment(
                [:],
                homeDirectory: URL(fileURLWithPath: "/Users/fixture", isDirectory: true)
            )
        ) { error in
            XCTAssertEqual(error as? LocalServerConfigurationError, .missingAllowedLogin)
        }

        XCTAssertThrowsError(
            try LocalServerConfiguration.fromEnvironment(
                ["CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN": "   "],
                homeDirectory: URL(fileURLWithPath: "/Users/fixture", isDirectory: true)
            )
        ) { error in
            XCTAssertEqual(error as? LocalServerConfigurationError, .missingAllowedLogin)
        }
    }

    func testInvalidPortFailsClosed() {
        XCTAssertThrowsError(
            try LocalServerConfiguration.fromEnvironment(
                [
                    "CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN": "owner@example.test",
                    "CHERRYPICKER_PORT": "0"
                ],
                homeDirectory: URL(fileURLWithPath: "/Users/fixture", isDirectory: true)
            )
        ) { error in
            XCTAssertEqual(error as? LocalServerConfigurationError, .invalidPort)
        }
    }
}
