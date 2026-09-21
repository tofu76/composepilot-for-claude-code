import ApplicationServices

/// フォーカス中のAXUIElementが「VSCodeのAdd Commentダイアログ」かどうかを判定する。
///
/// 判定は3段階を上から順に試す:
/// - Level 0: 拡張機能のソースから確定した組み込みルール(`comment-textarea`)
/// - Level 1: ユーザーが調査キットで保存した既知良好シグネチャ
/// - Level 2: 役割+祖先要素のキーワード一致(シグネチャ未保存時のみ)
///
/// 汎用フォールバック(VSCode全体のテキスト欄に適用する緩いモード)は誤爆リスクが
/// 高いため実装しない。
///
/// メインスレッドからのみ呼ばれる前提(FocusTrackerのAXObserverコールバックとポーリング)。
/// 既知良好シグネチャはファイル更新日時をキーにキャッシュする。
enum ElementMatcher {
    static func matches(_ element: AXUIElement) -> Bool {
        if matchesBuiltInRule(element) { return true }
        if let known = knownGoodTopElement() {
            return matchesSignature(element, known)
        }
        return matchesHeuristic(element)
    }

    /// テキスト入力欄とみなす役割。全レベルの前提条件として使う。
    private static let textInputRoles: Set<String> = ["AXTextArea", "AXTextField"]

    // MARK: - Level 0: 拡張機能のソースから確定した組み込みルール

    /// 計画プレビューのコメント欄のDOM id。
    ///
    /// Claude Code拡張の計画プレビューは、`extension.js`に**手書きのHTMLテンプレート**として
    /// 埋め込まれたwebview(`createWebviewPanel("claudePlanPreview", ...)`)であり、
    /// バンドラが生成するハッシュ付きクラス名(例: `messageInput_cKsPxg`)とは異なり
    /// id属性がそのまま残る。実際に拡張2.1.273/2.1.276/2.1.278の3バージョンで同一だった。
    /// そのため調査キットによる採取を待たず、この値を既定の判定材料として組み込む。
    static let planCommentDOMIdentifier = "comment-textarea"

    /// 同じテンプレート内の`placeholder`属性の値。`AXDOMIdentifier`が取得できない場合の二重化。
    static let planCommentPlaceholder = "Add your feedback."

    private static func matchesBuiltInRule(_ element: AXUIElement) -> Bool {
        guard let role = AXAttributes.string(element, kAXRoleAttribute as String),
              textInputRoles.contains(role) else {
            return false
        }
        if AXAttributes.string(element, "AXDOMIdentifier") == Self.planCommentDOMIdentifier {
            return true
        }
        let placeholder = AXAttributes.string(element, "AXPlaceholderValue")
            ?? AXAttributes.string(element, kAXDescriptionAttribute as String)
        return placeholder == Self.planCommentPlaceholder
    }

    // MARK: - Level 1: 既知良好シグネチャとの照合

    private static var cachedSignature: InspectedElement?
    private static var cachedSignatureModificationDate: Date?

    private static func knownGoodTopElement() -> InspectedElement? {
        let url = ConfigStore.knownGoodSignatureURL()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modificationDate = attributes[.modificationDate] as? Date else {
            cachedSignature = nil
            cachedSignatureModificationDate = nil
            return nil
        }
        if let cached = cachedSignature, cachedSignatureModificationDate == modificationDate {
            return cached
        }
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(InspectionSnapshot.self, from: data),
              let top = snapshot.elements.first(where: { $0.depth == 0 }) else {
            return nil
        }
        cachedSignature = top
        cachedSignatureModificationDate = modificationDate
        return top
    }

    private static func matchesSignature(_ element: AXUIElement, _ known: InspectedElement) -> Bool {
        guard AXAttributes.string(element, kAXRoleAttribute as String) == known.role else {
            return false
        }

        if let knownDomID = known.domIdentifier, !knownDomID.isEmpty {
            return AXAttributes.string(element, "AXDOMIdentifier") == knownDomID
        }

        // VSCodeのDOMクラス名はビルド毎のハッシュを含むため(例: "messageInput_cKsPxg")、
        // 拡張機能の更新で必ず変化する。一方AXDescription(例: "Message input")は
        // 人間向けラベルで安定しているため、クラス名より優先して照合する。
        if let knownDescription = known.elementDescription, !knownDescription.isEmpty {
            return AXAttributes.string(element, kAXDescriptionAttribute as String) == knownDescription
        }

        let knownClasses = Set(known.domClassList ?? [])
        guard !knownClasses.isEmpty else { return false }
        let domClasses = Set(AXAttributes.stringArray(element, "AXDOMClassList") ?? [])

        // Jaccard係数で比較する。分母を和集合にすることで、候補側に余分なクラスが
        // 多数付いている別コントロール(既知側クラスの上位集合)を弾く。
        let union = domClasses.union(knownClasses)
        guard !union.isEmpty else { return false }
        let intersection = domClasses.intersection(knownClasses)
        return Double(intersection.count) / Double(union.count) >= 0.6
    }

    // MARK: - Level 2: 既知良好シグネチャが無い場合の緩いフォールバック

    /// 祖先探索をここで打ち切る役割。ウィンドウ/アプリのタイトルは
    /// 「開いているファイル名」等を含むため(例: "CLAUDE.md — MyProject")、
    /// キーワード照合に含めるとVSCode内の全テキスト欄が誤マッチしてしまう。
    private static let ancestorWalkStopRoles: Set<String> = [
        "AXWindow", "AXApplication", "AXSheet", "AXDrawer",
    ]

    private static func matchesHeuristic(_ element: AXUIElement) -> Bool {
        guard let role = AXAttributes.string(element, kAXRoleAttribute as String),
              textInputRoles.contains(role) else {
            return false
        }
        let keywords = ConfigStore.level2Keywords()
        guard !keywords.isEmpty else { return false }

        var current: AXUIElement? = element
        var depth = 0
        while let el = current, depth < 8 {
            if let role = AXAttributes.string(el, kAXRoleAttribute as String),
               ancestorWalkStopRoles.contains(role) {
                return false
            }

            let candidates = [
                AXAttributes.string(el, kAXTitleAttribute as String),
                AXAttributes.string(el, kAXDescriptionAttribute as String),
                AXAttributes.string(el, "AXPlaceholderValue"),
            ].compactMap { $0 }

            for candidate in candidates {
                for keyword in keywords where candidate.localizedCaseInsensitiveContains(keyword) {
                    return true
                }
            }
            current = AXAttributes.element(el, kAXParentAttribute as String)
            depth += 1
        }
        return false
    }
}
