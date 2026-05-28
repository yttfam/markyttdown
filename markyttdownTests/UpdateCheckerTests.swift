import XCTest
@testable import markyttdown

@MainActor
final class UpdateCheckerTests: XCTestCase {
    func testTagParsingComparesAgainstZero() {
        let c = UpdateChecker.shared
        XCTAssertTrue(c.isNewer("v9.9.9-99"))
        XCTAssertFalse(c.isNewer("v0.0.0-0"))
    }

    func testInvalidTagReturnsFalse() {
        XCTAssertFalse(UpdateChecker.shared.isNewer("garbage"))
        XCTAssertFalse(UpdateChecker.shared.isNewer(""))
    }

    func testTagsAcceptWithOrWithoutBuildSuffix() {
        // Marketing-only tags (v9.9.9) should still parse and compare.
        XCTAssertTrue(UpdateChecker.shared.isNewer("v9.9.9"))
    }
}
