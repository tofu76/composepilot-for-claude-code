import AppKit
import ApplicationServices

/// フォーカス中のUI要素1件分のAX属性スナップショット。
/// Level1/Level2判定(ElementMatcher)に使う値の採取・比較に使う。
struct InspectedElement: Codable, Equatable {
    let depth: Int
    let role: String?
    let subrole: String?
    let roleDescription: String?
    let title: String?
    let elementDescription: String?
    let value: String?
    let placeholder: String?
    let domClassList: [String]?
    let domIdentifier: String?
    let identifier: String?
    let position: [Double]?
    let size: [Double]?
}

struct InspectionSnapshot: Codable {
    let timestamp: String
    let inspectedBundleID: String?
    let inspectedAppName: String?
    let elements: [InspectedElement]
    /// `elements`が空の場合にその理由を記録する。権限不足とフォーカス要素なしを
    /// 区別できないと調査時に原因の切り分けができないため。
    let diagnostic: String?
}

/// 調査対象アプリの指定方法。
///
/// 既定はbundle IDによる直接指定。フロントアプリ依存にすると、メニューバーから
/// 実行した場合は自アプリ、ターミナルから実行した場合はターミナル自身を
/// 調査してしまうため。
enum InspectionTarget {
    case frontmost
    case bundleID(String)

    func resolve() -> NSRunningApplication? {
        switch self {
        case .frontmost:
            return NSWorkspace.shared.frontmostApplication
        case .bundleID(let identifier):
            return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first
        }
    }
}

enum ElementInspector {
    /// 直近に採取したスナップショット(「既知良好として保存」「差分表示」から参照する)
    private(set) static var lastSnapshot: InspectionSnapshot?

    private static func inspect(_ element: AXUIElement, depth: Int) -> InspectedElement {
        var value: String?
        if let raw = AXAttributes.string(element, kAXValueAttribute as String) {
            value = raw.count > 200 ? String(raw.prefix(200)) + "…" : raw
        }
        return InspectedElement(
            depth: depth,
            role: AXAttributes.string(element, kAXRoleAttribute as String),
            subrole: AXAttributes.string(element, kAXSubroleAttribute as String),
            roleDescription: AXAttributes.string(element, kAXRoleDescriptionAttribute as String),
            title: AXAttributes.string(element, kAXTitleAttribute as String),
            elementDescription: AXAttributes.string(element, kAXDescriptionAttribute as String),
            value: value,
            placeholder: AXAttributes.string(element, "AXPlaceholderValue"),
            domClassList: AXAttributes.stringArray(element, "AXDOMClassList"),
            domIdentifier: AXAttributes.string(element, "AXDOMIdentifier"),
            identifier: AXAttributes.string(element, kAXIdentifierAttribute as String),
            position: AXAttributes.point(element, kAXPositionAttribute as String),
            size: AXAttributes.size(element, kAXSizeAttribute as String)
        )
    }

    /// 既定の調査対象。設定されている対象アプリの先頭を使う。
    /// 対象アプリを空にしていても調査自体はできるよう、既定値へフォールバックする。
    static var defaultTarget: InspectionTarget {
        .bundleID(ConfigStore.targetBundleIDs().first ?? ConfigStore.defaultTargetBundleIDs[0])
    }

    /// 対象アプリのフォーカス中要素から祖先方向に`maxDepth`階層まで遡ってAX属性を採取する。
    @discardableResult
    static func captureFocusedElementChain(
        target: InspectionTarget = ElementInspector.defaultTarget,
        maxDepth: Int = 10
    ) -> InspectionSnapshot {
        let app = target.resolve()
        var elements: [InspectedElement] = []
        var diagnostic: String?

        if let pid = app?.processIdentifier {
            let appElement = AXUIElementCreateApplication(pid)
            // VSCode(Electron)はこれを設定するまでWebコンテンツのアクセシビリティツリーを
            // 生成しない。反映は非同期なので、失敗したら少し待って再試行する。
            AXAttributes.enableManualAccessibility(appElement)

            var focused = AXAttributes.copyWithError(appElement, kAXFocusedUIElementAttribute as String)
            var attempt = 0
            while focused.value == nil, attempt < 3 {
                Thread.sleep(forTimeInterval: 0.5)
                focused = AXAttributes.copyWithError(appElement, kAXFocusedUIElementAttribute as String)
                attempt += 1
            }

            if let value = focused.value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                var current: AXUIElement? = (value as! AXUIElement)
                var depth = 0
                while let el = current, depth < maxDepth {
                    elements.append(inspect(el, depth: depth))
                    current = AXAttributes.element(el, kAXParentAttribute as String)
                    depth += 1
                }
            } else {
                diagnostic = Self.describe(axError: focused.error)
            }
        } else {
            diagnostic = "対象アプリが起動していません。"
        }

        let formatter = ISO8601DateFormatter()
        let snapshot = InspectionSnapshot(
            timestamp: formatter.string(from: Date()),
            inspectedBundleID: app?.bundleIdentifier,
            inspectedAppName: app?.localizedName,
            elements: elements,
            diagnostic: diagnostic
        )
        lastSnapshot = snapshot
        return snapshot
    }

    /// 採取・JSON保存・クリップボードコピーまで一括で行う。保存先URLを返す。
    @discardableResult
    static func runInspectionAndSave(
        target: InspectionTarget = ElementInspector.defaultTarget
    ) -> URL? {
        let snapshot = captureFocusedElementChain(target: target)

        guard let data = encode(snapshot) else { return nil }

        if let json = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(json, forType: .string)
        }

        let dir = ConfigStore.inspectionsDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeTimestamp = snapshot.timestamp.replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("\(safeTimestamp).json")
        try? data.write(to: url)
        return url
    }

    private static func describe(axError: AXError) -> String {
        switch axError {
        case .success:
            return "フォーカス中の要素がありません(対象アプリ内で何も入力欄が選択されていない状態)。"
        case .apiDisabled:
            return "アクセシビリティAPIが拒否されました(このバイナリに対する許可が必要)。"
        case .notImplemented:
            return "対象アプリがアクセシビリティAPIに応答しません。"
        case .noValue, .attributeUnsupported:
            return "対象アプリがフォーカス要素を報告していません"
                + "(Electronのアクセシビリティツリー生成が有効化されていない、"
                + "または入力欄にフォーカスがない状態)。"
        case .cannotComplete:
            return "対象アプリへの問い合わせがタイムアウトしました。"
        case .invalidUIElement:
            return "対象アプリのUI要素参照が無効です。"
        default:
            return "AXエラー: \(axError.rawValue)"
        }
    }

    static func encode(_ snapshot: InspectionSnapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(snapshot)
    }

    // MARK: - 既知良好シグネチャ(継続メンテナンス用)

    /// 直近の採取結果のフォーカス要素(depth 0)を「既知良好シグネチャ」として保存する。
    /// Claude Code拡張のUI変更でElementMatcherの判定が壊れた際、再度これを更新して
    /// 差分を確認しながらElementMatcherの判定値を直すために使う。
    @discardableResult
    static func saveLastSnapshotAsKnownGood() -> Bool {
        guard let snapshot = lastSnapshot, !snapshot.elements.isEmpty,
              let data = encode(snapshot) else {
            return false
        }

        let dir = ConfigStore.appSupportDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (try? data.write(to: ConfigStore.knownGoodSignatureURL())) != nil
    }

    /// 直近の採取結果と保存済みの既知良好シグネチャを、フォーカス要素(depth 0)の
    /// 主要フィールドで比較し、差分を人間が読めるテキストで返す。
    static func diffAgainstKnownGood() -> String {
        guard let latest = lastSnapshot?.elements.first(where: { $0.depth == 0 }) else {
            return "直近の採取結果がありません。先に「フォーカス要素を調査」を実行してください。"
        }
        guard let data = try? Data(contentsOf: ConfigStore.knownGoodSignatureURL()),
              let known = try? JSONDecoder().decode(InspectionSnapshot.self, from: data),
              let knownTop = known.elements.first(where: { $0.depth == 0 }) else {
            return "既知良好シグネチャが未保存です。まず「現在の要素を既知良好として保存」を実行してください。"
        }

        var diffs: [String] = []
        func compare<T: Equatable>(_ name: String, _ a: T, _ b: T) {
            if a != b {
                diffs.append("・\(name): \(b) → \(a)")
            }
        }
        compare("role", latest.role, knownTop.role)
        compare("subrole", latest.subrole, knownTop.subrole)
        compare("domClassList", latest.domClassList ?? [], knownTop.domClassList ?? [])
        compare("domIdentifier", latest.domIdentifier, knownTop.domIdentifier)
        compare("identifier", latest.identifier, knownTop.identifier)
        compare("placeholder", latest.placeholder, knownTop.placeholder)
        compare("title", latest.title, knownTop.title)
        compare("elementDescription", latest.elementDescription, knownTop.elementDescription)

        return diffs.isEmpty
            ? "既知良好シグネチャとの差分はありません。"
            : "既知良好シグネチャとの差分:\n" + diffs.joined(separator: "\n")
    }
}
