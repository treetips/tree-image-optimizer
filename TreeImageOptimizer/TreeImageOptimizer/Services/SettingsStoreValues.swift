import Foundation

/// `SettingsStore` が読み込んだJSONの不正値を補正するための型変換・検証ヘルパー群。
/// `resolveScreen` / `resolveBatch` / `resolveEasy` から使う。
/// クラス本体の行数制限（type_body_length）を守るためextensionに分離する。
extension SettingsStore {
    func boolValue(_ value: Any?, fallback: Bool, mark: () -> Void) -> Bool {
        if let value = value as? Bool { return value }
        mark()
        return fallback
    }

    func languageValue(_ value: Any?, fallback: String, mark: () -> Void) -> String {
        if let value = value as? String { return value }
        mark()
        return fallback
    }

    func appearanceValue(_ value: Any?, fallback: String, mark: () -> Void) -> String {
        if let value = value as? String, AppearanceMode(rawValue: value) != nil { return value }
        mark()
        return fallback
    }

    func fontSizeValue(_ value: Any?, fallback: String, mark: () -> Void) -> String {
        if let value = value as? String, FontSizeOption(rawValue: value) != nil { return value }
        mark()
        return fallback
    }

    func optionalPath(_ value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty { return value }
        return nil
    }

    func stringValue(_ value: Any?, fallback: String, mark: () -> Void) -> String {
        if let value = value as? String, !value.isEmpty { return value }
        mark()
        return fallback
    }

    func intValue(_ value: Any?, min: Int, max: Int, fallback: Int, mark: () -> Void) -> Int {
        if let value = value as? Int {
            let clamped = Swift.min(Swift.max(value, min), max)
            if clamped != value { mark() }
            return clamped
        }
        mark()
        return fallback
    }

    func doubleValue(_ value: Any?, min: Double, max: Double, fallback: Double, mark: () -> Void) -> Double {
        var parsed: Double?
        if let value = value as? Double {
            parsed = value
        } else if let value = value as? Int {
            parsed = Double(value)
        } else if let value = value as? String {
            parsed = Double(value)
        }
        guard let parsed else {
            mark()
            return fallback
        }
        let clamped = Swift.min(Swift.max(parsed, min), max)
        if clamped != parsed { mark() }
        return clamped
    }

    func colorValue(_ value: Any?, fallback: String, mark: () -> Void) -> String {
        if let value = value as? String, Self.isValidColor(value) { return value }
        mark()
        return fallback
    }

    static func isValidColor(_ hex: String) -> Bool {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6 || h.count == 8 else { return false }
        return UInt(h, radix: 16) != nil
    }
}
