import XCTest
@testable import LuminaCore

final class VersioningTests: XCTestCase {
    func testVersionParsingIgnoresTagPrefixAndBuildSuffix() {
        XCTAssertEqual(LuminaVersion("v0.1.15")?.description, "0.1.15")
        XCTAssertEqual(LuminaVersion("0.1.15-beta")?.description, "0.1.15")
        XCTAssertNil(LuminaVersion("development"))
    }

    func testVersionComparisonPadsMissingComponents() {
        XCTAssertGreaterThan(
            LuminaVersion("0.1.15")!,
            LuminaVersion("v0.1.14")!
        )
        XCTAssertEqual(
            LuminaVersion("0.1.15")!,
            LuminaVersion("0.1.15.0")!
        )
    }
}
