import XCTest
@testable import ComposePilot

/// `ConfigStore`は`UserDefaults.standard`をデフォルトで使うが、テスト用に
/// 隔離された`UserDefaults(suiteName:)`へ差し替えることで、実際のユーザー設定を
/// 汚さずに検証する。
final class ConfigStoreTests: XCTestCase {
    private var suiteName: String!
    private var originalDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ComposePilotTests.\(UUID().uuidString)"
        originalDefaults = ConfigStore.defaults
        ConfigStore.defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        ConfigStore.defaults = originalDefaults
        super.tearDown()
    }

    func testIsEnabledDefaultsToTrueWhenUnset() {
        XCTAssertTrue(ConfigStore.isEnabled())
    }

    func testSetEnabledRoundTrips() {
        ConfigStore.setEnabled(false)
        XCTAssertFalse(ConfigStore.isEnabled())

        ConfigStore.setEnabled(true)
        XCTAssertTrue(ConfigStore.isEnabled())
    }

    func testSetEnabledPostsChangeNotification() {
        let expectation = expectation(forNotification: ConfigStore.didChangeNotification, object: nil)
        ConfigStore.setEnabled(false)
        wait(for: [expectation], timeout: 1)
    }

    func testSubmitModifierDefaultsToControlWhenUnset() {
        XCTAssertEqual(ConfigStore.submitModifier(), .control)
    }

    func testSubmitModifierRoundTrips() {
        ConfigStore.setSubmitModifier(.command)
        XCTAssertEqual(ConfigStore.submitModifier(), .command)
    }

    func testSubmitModifierFallsBackToDefaultOnInvalidStoredValue() {
        ConfigStore.defaults.set("not-a-real-modifier", forKey: "ComposePilot.submitModifier")
        XCTAssertEqual(ConfigStore.submitModifier(), .default)
    }

    func testTargetBundleIDsDefaultsToVSCode() {
        XCTAssertEqual(ConfigStore.targetBundleIDs(), ["com.microsoft.VSCode"])
    }

    func testSetTargetBundleIDsTrimsDedupesAndDropsEmpty() {
        ConfigStore.setTargetBundleIDs([" com.example.a ", "com.example.b", "com.example.a", ""])
        XCTAssertEqual(ConfigStore.targetBundleIDs(), ["com.example.a", "com.example.b"])
    }

    func testLevel2KeywordsDefaultsToPlanCommentPlaceholder() {
        XCTAssertEqual(ConfigStore.level2Keywords(), [ElementMatcher.planCommentPlaceholder])
    }

    func testSetLevel2KeywordsRoundTrips() {
        ConfigStore.setLevel2Keywords(["foo", "bar"])
        XCTAssertEqual(ConfigStore.level2Keywords(), ["foo", "bar"])
    }

    func testHasCompletedOnboardingDefaultsToFalse() {
        XCTAssertFalse(ConfigStore.hasCompletedOnboarding())
    }

    func testSetCompletedOnboardingRoundTrips() {
        ConfigStore.setCompletedOnboarding(true)
        XCTAssertTrue(ConfigStore.hasCompletedOnboarding())
    }

    func testLastSeenBundleVersionDefaultsToNil() {
        XCTAssertNil(ConfigStore.lastSeenBundleVersion())
    }

    func testSetLastSeenBundleVersionRoundTrips() {
        ConfigStore.setLastSeenBundleVersion("3")
        XCTAssertEqual(ConfigStore.lastSeenBundleVersion(), "3")
    }
}
