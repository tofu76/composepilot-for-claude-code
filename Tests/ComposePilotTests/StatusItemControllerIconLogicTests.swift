import XCTest
@testable import ComposePilot

/// `StatusItemController.iconName`の回帰テスト。
/// 「起動直後/設定トグル操作後もアイコンが常に非活性表示のままになる」不具合の原因は、
/// この判定ロジックへ最新状態が伝わっていなかったことだった。ロジック自体は
/// 元々正しかったため、ここではロジック単体の網羅性を担保する。
final class StatusItemControllerIconLogicTests: XCTestCase {
    func testOffWhenNotRunningRegardlessOfEnabledOrDetection() {
        XCTAssertEqual(
            StatusItemController.iconName(isRunning: false, isEnabled: true, isTargetDetected: true),
            "StatusOff"
        )
        XCTAssertEqual(
            StatusItemController.iconName(isRunning: false, isEnabled: false, isTargetDetected: false),
            "StatusOff"
        )
    }

    func testOffWhenRunningButDisabled() {
        XCTAssertEqual(
            StatusItemController.iconName(isRunning: true, isEnabled: false, isTargetDetected: true),
            "StatusOff"
        )
    }

    func testWatchingWhenRunningAndEnabledButNoTargetDetected() {
        XCTAssertEqual(
            StatusItemController.iconName(isRunning: true, isEnabled: true, isTargetDetected: false),
            "StatusWatching"
        )
    }

    func testActiveWhenRunningAndEnabledAndTargetDetected() {
        XCTAssertEqual(
            StatusItemController.iconName(isRunning: true, isEnabled: true, isTargetDetected: true),
            "StatusActive"
        )
    }
}
