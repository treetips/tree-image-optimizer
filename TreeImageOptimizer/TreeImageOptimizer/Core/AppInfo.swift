import AppKit
import Foundation

/// ツールバージョン定数。
enum AppInfo {
    static let upscalBinVersion = "upscayl-bin-20251207-174704"
    static let jpegVersion = "v1.5.6"
    static let pngVersion = "v0.5.4"
    static let jpegXlVersion = "v0.12.0"
    static let av1Version = "v1.4.2"
    static let webpVersion = "1.6.0"

    static let githubURL = URL(string: "https://github.com/treetips/tree-image-optimizer")!
    static let updateInfoURL = URL(
        string: "https://github.com/treetips/tree-image-optimizer/releases/latest/download/update-info.json"
    )!

    /// アプリ本体のバージョン（Bundleから取得）。
    static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    /// About画面に表示するアプリアイコン。同梱の `assets/images/icon-tree-01.png` を読む。
    static var appIconImage: NSImage? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("assets/images/icon-tree-01.png", isDirectory: false) else { return nil }
        return NSImage(contentsOf: url)
    }

    static var toolVersions: [(binary: String, version: String)] {
        [
            ("upscal-bin", upscalBinVersion),
            ("upscal models", ""),
            ("JPEG (jpegoptim)", jpegVersion),
            ("PNG (pngoptim)", pngVersion),
            ("JPEG XL (libjxl)", jpegXlVersion),
            ("AV1 (libavif)", av1Version),
            ("WebP (libwebp)", webpVersion),
        ]
    }
}
