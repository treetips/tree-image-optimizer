import Foundation

/// 壁紙選択の特別な値。
enum WallpaperSelection {
    /// プルダウン先頭の「背景無し」。画像を表示しない。
    static let noneName = "背景無し"
}

/// 壁紙の一覧取得。Flutter版の壁紙サービスに対応する。
struct WallpaperService: Sendable {
    let bundledBaseURL: URL?
    let userBaseURL: URL

    init(bundledBaseURL: URL? = nil, userBaseURL: URL? = nil, paths: AppPaths = AppPaths()) {
        self.bundledBaseURL = bundledBaseURL
        if let userBaseURL {
            self.userBaseURL = userBaseURL
        } else {
            self.userBaseURL = paths.userWallpaperURL
        }
    }

    func bundledBaseCandidates() -> [URL] {
        if let bundledBaseURL { return [bundledBaseURL] }
        var candidates: [URL] = []
        // アプリバンドル同梱のassetsを最優先にする。
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("assets/images/wallpaper", isDirectory: true))
        }
        let fm = FileManager.default
        candidates.append(URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("assets/images/wallpaper", isDirectory: true))
        return candidates
    }

    /// 上部に同梱、その後にユーザー配置。各グループ内でファイル名ソートする。
    func listWallpapers() -> [WallpaperOption] {
        listBundled() + listUser()
    }

    func listBundled() -> [WallpaperOption] {
        for base in bundledBaseCandidates() {
            let files = listWallpaperFiles(in: base)
            if !files.isEmpty {
                return files.map {
                    WallpaperOption(name: $0.lastPathComponent, isBundled: true)
                }.sorted { $0.name < $1.name }
            }
        }
        return []
    }

    func listUser() -> [WallpaperOption] {
        listWallpaperFiles(in: userBaseURL).map {
            WallpaperOption(name: $0.lastPathComponent, isBundled: false)
        }.sorted { $0.name < $1.name }
    }

    /// 選択中の壁紙が一覧に無い場合や参照不可の場合は同梱先頭にフォールバックする。
    /// 「背景無し」はファイル存在確認なしでそのまま通す。
    func resolveSelected(_ current: String, options: [WallpaperOption]) -> String {
        if current == WallpaperSelection.noneName { return current }
        if options.isEmpty { return current }
        if options.contains(where: { $0.name == current }) {
            if let matched = options.first(where: { $0.name == current }), !matched.isBundled {
                let url = userBaseURL.appendingPathComponent(matched.name, isDirectory: false)
                if !FileManager.default.fileExists(atPath: url.path) {
                    return fallback(in: options)
                }
            }
            return current
        }
        return fallback(in: options)
    }

    private func fallback(in options: [WallpaperOption]) -> String {
        if let first = options.first(where: { $0.isBundled }) { return first.name }
        return options[0].name
    }

    /// 表示用URLを解決する。同梱はアセットパス、ユーザーは絶対パス。
    func fileURL(for name: String) -> URL? {
        for base in bundledBaseCandidates() {
            let url = base.appendingPathComponent(name, isDirectory: false)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        let url = userBaseURL.appendingPathComponent(name, isDirectory: false)
        if FileManager.default.fileExists(atPath: url.path) { return url }
        return nil
    }

    private func listWallpaperFiles(in dir: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        return contents.filter { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { return false }
            return ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased())
        }
    }
}
