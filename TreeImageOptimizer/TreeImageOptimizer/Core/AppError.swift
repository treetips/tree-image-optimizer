import Foundation

/// アプリ全体のエラー型。UI表示文言はここに集約する。
enum AppError: LocalizedError, Equatable {
    case toolMissing(String)
    case processFailed(executable: String, exitCode: Int32, output: String)
    case invalidSettings(String)
    case fileNotFound(String)
    case networkError(String)
    case verificationFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .toolMissing(let name):
            return "必要なツールが見つかりません: \(name)"
        case .processFailed(let executable, let exitCode, let output):
            return "コマンドの実行に失敗しました: \(executable) (exit=\(exitCode))\n\(output)"
        case .invalidSettings(let reason):
            return "設定が不正です: \(reason)"
        case .fileNotFound(let path):
            return "ファイルが見つかりません: \(path)"
        case .networkError(let reason):
            return "通信に失敗しました: \(reason)"
        case .verificationFailed(let reason):
            return "検証に失敗しました: \(reason)"
        case .cancelled:
            return "キャンセルされました"
        }
    }
}
