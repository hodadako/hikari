import XCTest
@testable import HikariCore

final class VersioningTests: XCTestCase {
    func testVersionParsingIgnoresTagPrefixAndBuildSuffix() {
        XCTAssertEqual(HikariVersion("v0.1.15")?.description, "0.1.15")
        XCTAssertEqual(HikariVersion("0.1.15-beta")?.description, "0.1.15")
        XCTAssertNil(HikariVersion("development"))
    }

    func testVersionComparisonPadsMissingComponents() {
        XCTAssertGreaterThan(
            HikariVersion("0.1.15")!,
            HikariVersion("v0.1.14")!
        )
        XCTAssertEqual(
            HikariVersion("0.1.15")!,
            HikariVersion("0.1.15.0")!
        )
    }
}
