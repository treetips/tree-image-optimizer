import Foundation

/// ツール単位 ZIP の差分更新を行う。ADR 0064 で分離した tools 配布の実行側。
///
/// `tools-info.json` の取得・差分判定は `ToolsInfoStore` が担い、ここでは
/// 判定で挙がった各ツールの download → SHA-256 検証 → 展開 → 配置 →
/// `.installed.json` 更新までを行う。アプリ本体の更新（`UpdateService`）とは独立する。
struct ToolsUpdateService: Sendable {
    let paths: AppPaths
    let runner: ProcessRunner

    init(paths: AppPaths, runner: ProcessRunner = ProcessRunner()) {
        self.paths = paths
        self.runner = runner
    }

    /// ストアを生成する。差分判定・記録の読み書きは `ToolsInfoStore` に委ねる。
    private var store: ToolsInfoStore {
        ToolsInfoStore(paths: paths)
    }

    /// `tools-info.json` を取得して `ToolsInfo` にデコードする。
    /// 再試行・キャッシュ無効化済みの `ToolInstaller.download` を再利用する。
    func fetchToolsInfo() async throws -> ToolsInfo {
        AppLogger.shared.info("tools update: fetch info start \(ToolsInfoStore.toolsInfoURL)")
        let data = try await ToolInstaller(paths: paths, runner: runner)
            .download(url: ToolsInfoStore.toolsInfoURL)
        do {
            let info = try JSONDecoder().decode(ToolsInfo.self, from: data)
            AppLogger.shared.info("tools update: fetch info ok tools=\(info.tools.count)")
            return info
        } catch {
            AppLogger.shared.error("tools update: decode info failed \(error.localizedDescription)")
            throw AppError.networkError(
                "tools-info.json の解析に失敗しました: \(error.localizedDescription)")
        }
    }

    /// リモートの `tools-info.json` と突き合わせ、差分のあるツールだけを更新する。
    /// - Parameters:
    ///   - info: `fetchToolsInfo()` で取得したメタデータ。
    ///   - installed: 現在のインストール済み記録（未更新の基準）。
    ///   - onProgress: 進捗通知。0.0〜1.0 と対象ツール名。
    /// - Returns: 更新反映後のインストール済み記録。
    func updateTools(
        info: ToolsInfo,
        installed: InstalledTools,
        onProgress: @escaping @Sendable (Double, String) -> Void = { _, _ in }
    ) async throws -> InstalledTools {
        let targets = store.updatesNeeded(info: info, installed: installed)
        AppLogger.shared.info(
            "tools update: targets=\(targets.map(\.name).joined(separator: ","))")
        guard !targets.isEmpty else {
            onProgress(1.0, "")
            return installed
        }

        // 更新対象が0件でも分母を確実に1以上にして除算を安全に保つ。
        let total = Double(max(targets.count, 1))
        var updated = installed

        for (index, tool) in targets.enumerated() {
            let fraction = Double(index) / total
            onProgress(fraction, tool.name)
            try await install(tool: tool)
            // ツール単位で記録へ反映。途中で失敗してもここまでの確定分は次回起動で
            // 差分判定され、未完了のツールだけが再度更新対象になる（ADR 0064）。
            updated.tools[tool.name] = tool.version
            onProgress(Double(index + 1) / total, tool.name)
        }

        try store.saveInstalled(updated)
        AppLogger.shared.info("tools update: completed count=\(targets.count)")
        return updated
    }

    /// 単一ツールの ZIP を download → 検証 → 展開 → 配置する。
    private func install(tool: ToolMetadata) async throws {
        guard let url = URL(string: tool.url) else {
            throw AppError.networkError("invalid tool URL: \(tool.url)")
        }
        AppLogger.shared.info("tools update: install start name=\(tool.name) url=\(tool.url)")
        let installer = ToolInstaller(paths: paths, runner: runner)
        let data = try await installer.download(url: url)
        AppLogger.shared.info("tools update: received bytes=\(data.count) name=\(tool.name)")
        // 実行権を付与し得るバイナリを配置する前に改ざんを検出する
        // （ToolInstaller と同じ方針）。
        try installer.verifyArchive(data: data, expected: tool.sha256, name: tool.name)

        // ZIP は `<name>/`（ツール名のディレクトリ）をルートに含むため、
        // 展開後のルート一つだけを配置する（release.yml の ditto --keepParent と対応）。
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "tree-image-optimizer-tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let archive = tmpDir.appendingPathComponent("\(tool.name).zip", isDirectory: false)
        try data.write(to: archive)
        _ = try await runner.run(
            "/usr/bin/unzip", args: ["-q", archive.path, "-d", tmpDir.path], workingDirectory: nil)

        guard let root = installer.findDirectory(named: tool.name, under: tmpDir) else {
            throw AppError.toolMissing("\(tool.name) not found in archive")
        }
        try place(extractedRoot: root, name: tool.name, installer: installer)
        AppLogger.shared.info("tools update: install ok name=\(tool.name) version=\(tool.version)")
    }

    /// 展開済みのツールフォルダを `tools/<name>` へ「全削除してから置く」。
    private func place(extractedRoot source: URL, name: String, installer: ToolInstaller) throws {
        let fm = FileManager.default
        let dest = paths.toolsURL.appendingPathComponent(name, isDirectory: true)
        // Why not 親ディレクトリを作らないか: 未作成だと copyItem/removeItem が
        // 「ソース・移動先不在」をまとめて出すため、先に作って失敗を分離する。
        try fm.createDirectory(at: paths.toolsURL, withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) {
            // 中断時の不完全な配置を上書きせず全削除してから置き、次回起動の
            // 存在チェック・バージョン不一致検知が確実に働くようにする。
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: source, to: dest)
        try installer.makeExecutable(in: dest)
    }
}
