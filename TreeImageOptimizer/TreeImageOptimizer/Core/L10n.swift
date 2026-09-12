import Foundation

/// 明示的な言語指定で文字列を解決する。
/// SwiftUIの `.environment(\.locale)` が届かない箇所（メニュー・通知・
/// ダイアログ文言・モデル表示）でも設定言語に従わせるために使う。
/// BCP 47（"ja-JP"/"en-US"/""）と言語コード（"ja"/"en"）の両方を受け付ける。
enum L10n {
    static func string(_ key: String, language: String) -> String {
        let lower = language.lowercased()
        let code: String?
        if lower.hasPrefix("ja") {
            code = "ja"
        } else if lower.hasPrefix("en") {
            code = "en"
        } else {
            code = nil
        }
        guard let code,
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
