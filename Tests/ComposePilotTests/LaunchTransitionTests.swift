import XCTest
@testable import ComposePilot

final class LaunchTransitionTests: XCTestCase {
    func testFreshInstallWhenNoStoredVersion() {
        XCTAssertEqual(LaunchTransition.evaluate(stored: nil, current: "2"), .freshInstall)
    }

    func testUnchangedWhenStoredMatchesCurrent() {
        XCTAssertEqual(LaunchTransition.evaluate(stored: "2", current: "2"), .unchanged)
    }

    func testUpdatedWhenStoredDiffersFromCurrent() {
        XCTAssertEqual(
            LaunchTransition.evaluate(stored: "2", current: "3"),
            .updated(from: "2", to: "3")
        )
    }
}
