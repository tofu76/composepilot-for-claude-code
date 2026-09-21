import ApplicationServices
import CoreGraphics

/// AXUIElement属性の取得を共通化するヘルパー。
/// ElementInspector/ElementMatcher/FocusTrackerから共通で利用する。
enum AXAttributes {
    static func raw(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return result == .success ? value : nil
    }

    /// Electron製アプリ(VSCode等)は、この属性をtrueにするまでWebコンテンツの
    /// アクセシビリティツリーを生成しない。これを設定しないと`AXFocusedUIElement`が
    /// 常に`kAXErrorNoValue`を返し、DOM属性も一切取得できない。
    ///
    /// 反映は非同期であり、設定直後の問い合わせはまだ失敗しうる。
    @discardableResult
    static func enableManualAccessibility(_ element: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// 取得失敗時の原因を知りたい場合に使う。調査キットの診断メッセージ用。
    static func copyWithError(
        _ element: AXUIElement, _ attribute: String
    ) -> (value: AnyObject?, error: AXError) {
        var value: AnyObject?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (result == .success ? value : nil, result)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        raw(element, attribute) as? String
    }

    static func stringArray(_ element: AXUIElement, _ attribute: String) -> [String]? {
        raw(element, attribute) as? [String]
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = raw(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> [Double]? {
        guard let value = raw(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue((value as! AXValue), .cgPoint, &point) else { return nil }
        return [Double(point.x), Double(point.y)]
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> [Double]? {
        guard let value = raw(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue((value as! AXValue), .cgSize, &size) else { return nil }
        return [Double(size.width), Double(size.height)]
    }
}
