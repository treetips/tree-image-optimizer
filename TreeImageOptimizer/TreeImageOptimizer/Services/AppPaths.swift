import Foundation

/// アプリの各種パスを提供する。Flutter版 `PathService` に対応する。
///
/// SwiftUI版はmacOS専用のため、`bin/<os>` のOS分岐は持たない。
/// `tools/<name>/bin/macos/<bin>` 固定で解決する。
struct AppPaths: Sendable {
    /// テスト用に基準ディレクトリを差し替える。`nil` の場合は実環境を使う。
    var baseURL: URL?

    /// `~/Library/Application Support/tree-image-optimizer`。
    /// テスト時は `baseURL` をそのまま基準にする。
    var projectDirectoryURL: URL {
        if let baseURL {
            return baseURL
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Application Support/tree-image-optimizer", isDirectory: true)
    }

    /// `~/.config/tree-image-optimizer`。設定ファイル・ユーザー配置資産の基準。
    /// テスト時は `baseURL/.config/tree-image-optimizer` を使う。
    var configDirectoryURL: URL {
        if baseURL != nil {
            return projectDirectoryURL
                .appendingPathComponent(".config/tree-image-optimizer", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/tree-image-optimizer", isDirectory: true)
    }

    /// 設定ファイル `settings.json`。
    var settingsFileURL: URL {
        configDirectoryURL.appendingPathComponent("settings.json", isDirectory: false)
    }

    /// ユーザー配置の壁紙ディレクトリ。
    var userWallpaperURL: URL {
        configDirectoryURL.appendingPathComponent("wallpaper", isDirectory: true)
    }

    /// ユーザー配置のサウンド基準ディレクトリ。
    var userSoundsURL: URL {
        configDirectoryURL.appendingPathComponent("sounds", isDirectory: true)
    }

    /// `<基準>/logs`。
    var logsURL: URL {
        projectDirectoryURL.appendingPathComponent("logs", isDirectory: true)
    }

    /// `<基準>/tools`。
    var toolsURL: URL {
        projectDirectoryURL.appendingPathComponent("tools", isDirectory: true)
    }

    var upscalBinURL: URL {
        toolsURL.appendingPathComponent("upscal/bin/upscayl-bin", isDirectory: false)
    }

    var upscalModelsURL: URL {
        toolsURL.appendingPathComponent("upscal/models", isDirectory: true)
    }

    var jpegoptimBinURL: URL {
        toolsURL.appendingPathComponent("jpegoptim/bin/macos/jpegoptim", isDirectory: false)
    }

    var pngoptimBinURL: URL {
        toolsURL.appendingPathComponent("pngoptim/bin/macos/pngoptim", isDirectory: false)
    }

    var cjxlBinURL: URL {
        toolsURL.appendingPathComponent("libjxl/bin/macos/cjxl", isDirectory: false)
    }

    var avifencBinURL: URL {
        toolsURL.appendingPathComponent("libavif/bin/macos/avifenc", isDirectory: false)
    }

    var cwebpBinURL: URL {
        toolsURL.appendingPathComponent("libwebp/bin/macos/cwebp", isDirectory: false)
    }
}
