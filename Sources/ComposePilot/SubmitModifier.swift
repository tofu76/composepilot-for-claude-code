import CoreGraphics

/// 「送信」として扱う修飾キー。素のEnterは常に非送信(Shift付与)にするため、
/// 明示的に送信したいときに押す修飾キーをユーザーが選べるようにする。
///
/// なぜこの3種なのか: 拡張機能側のハンドラは`!e.shiftKey`だけを条件にしているため、
/// **Shift以外の修飾キーならどれを押しても送信経路に入る**。したがってControl / Command /
/// Option のいずれでも「その修飾キーを外して素のEnterとして流す」という同じ実装で成立する。
/// Shiftは改行として扱われるため送信には使えず、選択肢に含めない。
enum SubmitModifier: String, CaseIterable {
    case control
    case command
    case option

    /// 既定値。既存の`Chat`コンテキストのキーバインド(`ctrl+enter: chat:submit`)と
    /// 揃えるため、Controlを既定にする。
    static let `default` = SubmitModifier.control

    var flag: CGEventFlags {
        switch self {
        case .control: return .maskControl
        case .command: return .maskCommand
        case .option: return .maskAlternate
        }
    }

    var displayName: String {
        switch self {
        case .control: return "Ctrl+Enter"
        case .command: return "Cmd+Enter"
        case .option: return "Option+Enter"
        }
    }
}
