import XCTest
@testable import ComposePilot

final class SubmitModifierTests: XCTestCase {
    func testDefaultIsControl() {
        XCTAssertEqual(SubmitModifier.default, .control)
    }

    func testFlagMapping() {
        XCTAssertEqual(SubmitModifier.control.flag, .maskControl)
        XCTAssertEqual(SubmitModifier.command.flag, .maskCommand)
        XCTAssertEqual(SubmitModifier.option.flag, .maskAlternate)
    }

    func testDisplayNameMapping() {
        XCTAssertEqual(SubmitModifier.control.displayName, "Ctrl+Enter")
        XCTAssertEqual(SubmitModifier.command.displayName, "Cmd+Enter")
        XCTAssertEqual(SubmitModifier.option.displayName, "Option+Enter")
    }

    func testRawValueRoundTripsForAllCases() {
        for modifier in SubmitModifier.allCases {
            XCTAssertEqual(SubmitModifier(rawValue: modifier.rawValue), modifier)
        }
    }
}
