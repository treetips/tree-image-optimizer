import Foundation

/// `tools-info.json`（GitHub Releases で配布する tools のメタデータ）を表す型。
///
/// 各ツールのバージョン・取得先・SHA-256 を集約し、アプリ起動時の差分更新判定に使う。
/// アプリ本体の更新（`UpdateInfo`）とは独立して配布・取得される。
struct ToolsInfo: Codable, Equatable, Sendable {
    /// スキーマのバージョン。将来の形式変更に備えて保持する。
    var schemaVersion: Int
    /// ツール単位のメタデータ一覧。
    var tools: [ToolMetadata]

    /// ツール名でメタデータを引く。
    func metadata(for name: String) -> ToolMetadata? {
        tools.first { $0.name == name }
    }
}

/// 単一ツールのメタデータ。`tools-info.json` の `tools[]` 要素に対応する。
struct ToolMetadata: Codable, Equatable, Sendable {
    /// ツールの識別名。`ToolInstaller.toolBinaryChecks` の `folder` と一致させる
    /// （`upscal` / `jpegoptim` / `pngoptim` / `libjxl` / `libavif` / `libwebp` /
    /// `realcugan`）。
    var name: String
    /// ツールのバージョン。各ツールの `.version`（無いツールは `AppInfo` の定数）と
    /// 同じ表記・同じ正とする。
    var version: String
    /// ツール単位 ZIP のダウンロード URL。
    var url: String
    /// ツール単位 ZIP の期待 SHA-256（小文字 hex）。
    /// 空文字は「未設定」を意味し、検証をスキップする（ADR 0057 と同じ方針）。
    var sha256: String
    /// 必須ツールか。`true` なら起動時ブートストラップで欠損を修復し、
    /// `false` なら任意ツールとして扱う。
    var required: Bool
}

/// ローカルにインストール済みの tools 状態を記録する `.installed.json` の型。
///
/// 起動時の差分更新判定に使う。各ツールの「現在インストールされているバージョン」を
/// 名前をキーにして保持する。ファイルは `tools/.installed.json` に置く。
struct InstalledTools: Codable, Equatable, Sendable {
    /// ツール名 → インストール済みバージョン。
    var tools: [String: String]

    init(tools: [String: String] = [:]) {
        self.tools = tools
    }

    /// 指定ツールのインストール済みバージョン。未記録なら nil。
    func version(for name: String) -> String? {
        tools[name]
    }
}

/// `tools-info.json` と `.installed.json` の読み書きと差分判定を担うストア。
///
/// 既存の `ToolInstaller`（初回展開・修復）とは責務を分け、ここでは
/// 「配布メタデータの取得」と「ローカル記録の読み書き」だけを扱う。
/// 純粋な読み書きと判定に分け、テストしやすくする。
struct ToolsInfoStore: Sendable {
    let paths: AppPaths

    init(paths: AppPaths) {
        self.paths = paths
    }

    /// `tools-info.json` の取得先 URL。アプリ本体の `update-info.json` と同様に
    /// GitHub Releases の latest を参照する。`AppInfo.githubURL` から導出して
    /// 配布元の二重管理を避ける。
    static var toolsInfoURL: URL {
        AppInfo.githubURL.appending(path: "releases/latest/download/tools-info.json")
    }

    /// 同梱ツールのバージョン。`.installed.json` が無い環境（既存ユーザー）を
    /// マイグレーションする際の初期値。ツール名は `ToolMetadata.name` と一致させる。
    /// `AppInfo` の定数は `update-image-tools` スキルでツール側 `.version` と
    /// 常に一致させる運用のため、ここを正とする。
    static let bundledVersions: [String: String] = [
        "upscal": AppInfo.upscalBinVersion,
        "realcugan": AppInfo.realcuganVersion,
        "jpegoptim": AppInfo.jpegVersion,
        "pngoptim": AppInfo.pngVersion,
        "libjxl": AppInfo.jpegXlVersion,
        "libavif": AppInfo.av1Version,
        "libwebp": AppInfo.webpVersion
    ]

    /// ローカル記録 `.installed.json` の場所。
    var installedFileURL: URL {
        paths.toolsURL.appendingPathComponent(".installed.json", isDirectory: false)
    }

    /// ローカル記録を読み込む。ファイルが無ければ同梱ツールのバージョンで
    /// 初期化した記録を返す（既存ユーザーのマイグレーション）。
    func loadInstalled() -> InstalledTools {
        let fm = FileManager.default
        guard fm.fileExists(atPath: installedFileURL.path) else {
            // Why not 空を返すか: 既存ユーザーは .installed.json が無いため、
            // 空だと全ツールが「更新対象」と誤判定され、起動のたびに全件
            // 再ダウンロードされる。同梱バージョンで初期化して「更新なし」にする。
            return InstalledTools(tools: Self.bundledVersions)
        }
        do {
            let data = try Data(contentsOf: installedFileURL)
            return try JSONDecoder().decode(InstalledTools.self, from: data)
        } catch {
            // Why not 空を返すか: 破損・権限エラーを空と同一視すると全件再DLに
            // つながる。原因をログへ残し、同梱バージョンへフォールバックする。
            AppLogger.shared.error(
                "tools installed state read failed: \(installedFileURL.path) \(error.localizedDescription)")
            return InstalledTools(tools: Self.bundledVersions)
        }
    }

    /// ローカル記録を書き込む。親ディレクトリが無ければ作る。
    func saveInstalled(_ installed: InstalledTools) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: installedFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(installed)
        try data.write(to: installedFileURL, options: .atomic)
    }

    /// リモートの `tools-info.json` とローカル記録を突き合わせ、
    /// 「更新すべきツール」を返す。更新不要・差分なしなら空配列。
    /// - Parameters:
    ///   - info: リモートから取得した `tools-info.json`。
    ///   - installed: ローカルのインストール済み記録。
    /// - Returns: バージョンが異なる（または未記録の）ツールのメタデータ一覧。
    func updatesNeeded(info: ToolsInfo, installed: InstalledTools) -> [ToolMetadata] {
        info.tools.filter { tool in
            installed.version(for: tool.name) != tool.version
        }
    }
}
