import CryptoKit
import Foundation

/// toolsの初回展開・修復を行う。Flutter版 `ToolInstaller` に対応する。
///
/// SwiftUI版はmacOS専用のためWindows/Linux分岐は持たない。
/// `libwebp` はGitHub Releasesで配布されていないためGoogle Storageから取得する。
/// `Real-CUGAN` はGitHub Releasesから取得する。どちらも欠損時のみダウンロードする。
struct ToolInstaller: Sendable {
    static let executables = [
        "upscayl-bin",
        "cjxl",
        "avifenc",
        "jpegoptim",
        "pngoptim",
        "cwebp",
        "realcugan-ncnn-vulkan"
    ]

    /// `tools/` からの相対パス一覧。
    static let requiredRelativePaths = [
        "upscal/bin/upscayl-bin",
        "jpegoptim/bin/macos/jpegoptim",
        "pngoptim/bin/macos/pngoptim",
        "libjxl/bin/macos/cjxl",
        "libavif/bin/macos/avifenc",
        "libwebp/bin/macos/cwebp",
        "realcugan/bin/macos/realcugan-ncnn-vulkan"
    ]

    static let webpVersion = "1.6.0"
    static let webpBaseURL = "https://storage.googleapis.com/downloads.webmproject.org/releases/webp"

    static let realcuganVersion = "20220728"
    static let realcuganFullVersion = "realcugan-ncnn-vulkan-20220728"
    static let realcuganBaseURL = "https://github.com/nihui/realcugan-ncnn-vulkan/releases/download"

    let paths: AppPaths
    let runner: ProcessRunner

    /// 開発時にコピー元として使うtoolsディレクトリ候補。テスト用に注入できる。
    var devToolsCandidates: [URL]

    init(paths: AppPaths, runner: ProcessRunner = ProcessRunner(), devToolsCandidates: [URL]? = nil) {
        self.paths = paths
        self.runner = runner
        if let devToolsCandidates {
            self.devToolsCandidates = devToolsCandidates
        } else {
            self.devToolsCandidates = Self.defaultDevToolsCandidates()
        }
    }

    /// アプリバンドル内 `Resources/tools`、リポジトリ直下 `tools/`、カレントディレクトリ配下
    /// `tools/` を候補にする。配布ビルドはアプリ内の同梱物を最優先にし、開発ビルドは
    /// `Info.plist` の `DevToolsPath`（Xcodeが `$(SOURCE_ROOT)/../tools` に展開）を使う。
    /// カレントディレクトリは実行方法に依存するため最後に回す。
    static func defaultDevToolsCandidates() -> [URL] {
        var candidates: [URL] = []
        // Why not DevToolsPath を先頭にするか: 配布ビルドの Info.plist には
        // ビルドマシンのパスが残るため、ユーザー環境では実在しない。同梱物を先に探す。
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("tools", isDirectory: true))
        }
        let configuredDevToolsPath = Bundle.main.object(forInfoDictionaryKey: "DevToolsPath") as? String
        if let devPath = configuredDevToolsPath, !devPath.contains("$(") {
            // 配布ビルドの Info.plist にはビルドマシンのパスが残るため、実在する場合だけ使う。
            if FileManager.default.fileExists(atPath: devPath) {
                candidates.append(URL(fileURLWithPath: devPath, isDirectory: true))
            }
        }
        candidates.append(
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("tools", isDirectory: true))
        return candidates
    }

    /// 全バイナリが揃っているか。
    func isInstalled() -> Bool {
        let fm = FileManager.default
        for relative in Self.requiredRelativePaths {
            let url = paths.toolsURL.appendingPathComponent(relative, isDirectory: false)
            if !fm.fileExists(atPath: url.path) { return false }
        }
        // upscal/models が空でないことも確認する。
        guard let enumerator = fm.enumerator(at: paths.upscalModelsURL, includingPropertiesForKeys: nil) else {
            return false
        }
        for case let url as URL in enumerator {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                return true
            }
        }
        return false
    }

    /// Real-CUGANが使えるか。バイナリと有効なモデルペア（`models-*` 配下の
    /// `.param`/`.bin` ペア）が1つ以上揃っていること。`isInstalled()` はバイナリのみを
    /// 見るため、モデルの揃いまで検査したい場面で使う。
    func isRealCuganInstalled() -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.realCuganBinURL.path) else { return false }
        return !RealCUGANModels.catalog(in: paths.realCuganRootURL).isEmpty
    }

    /// 揃っていなければ修復する。進捗（0.0〜1.0と作業名）を報告する。
    func ensureInstalled(progress: @Sendable (Double, String) -> Void = { _, _ in }) async throws {
        AppLogger.shared.info(
            "tools check: base=\(paths.projectDirectoryURL.path) tools=\(paths.toolsURL.path)")
        AppLogger.shared.info(
            "tools check: candidates=\(devToolsCandidates.map(\.path).joined(separator: ", "))")
        if isInstalled() {
            AppLogger.shared.info("tools check: already installed")
            progress(1.0, "")
            return
        }
        AppLogger.shared.info("tools check: missing tools, repairing")
        do {
            try await repairMissingTools(progress: progress)
            guard isInstalled() else {
                throw AppError.toolMissing("tools repair did not complete")
            }
            AppLogger.shared.info("tools check: repair completed")
            progress(1.0, "")
        } catch {
            AppLogger.shared.error("tools repair failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// 不足分を修復する。ローカルのtoolsコピーを優先し、無ければダウンロードする。
    /// libwebpとReal-CUGANはネットワーク取得可能なため、ローカルに無ければダウンロードする。
    /// それ以外はローカルコピーのみで、無ければエラーにする。
    func repairMissingTools(progress: @Sendable (Double, String) -> Void = { _, _ in }) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.toolsURL, withIntermediateDirectories: true)
        // 欠損しているフォルダを確定し、中途半端に残ったフォルダは消してから修復する。
        let missingFolders: [String] = Self.toolBinaryChecks.compactMap { tool in
            let bin = paths.toolsURL.appendingPathComponent(tool.binary, isDirectory: false)
            guard fm.fileExists(atPath: bin.path) else { return tool.folder }
            return nil
        }
        AppLogger.shared.info("tools repair: missing folders=\(missingFolders.joined(separator: ","))")
        for folder in missingFolders {
            let dir = paths.toolsURL.appendingPathComponent(folder, isDirectory: true)
            if fm.fileExists(atPath: dir.path) {
                AppLogger.shared.warning("tools repair: removing partial folder \(dir.path)")
                try fm.removeItem(at: dir)
            }
        }
        // libwebpとReal-CUGANは開発用toolsコピーを優先し、無ければダウンロードする。
        let downloadable = Set(["libwebp", "realcugan"])
        let total = Double(max(missingFolders.count, 1))
        var done = 0.0
        for folder in missingFolders {
            if downloadable.contains(folder) {
                if copyFromDevTools(folder: folder) {
                    done += 1
                    progress(done / total, folder)
                    continue
                }
                AppLogger.shared.info("tools repair: downloading \(folder)")
                progress(done / total, folder)
                try await downloadTool(folder: folder)
                done += 1
                progress(done / total, folder)
                continue
            }
            // それ以外は開発用toolsからのコピーのみ。無ければエラーで再試行UIへ出す。
            guard copyFromDevTools(folder: folder) else {
                AppLogger.shared.error(
                    """
                    tools repair: no local source for \(folder); \
                    candidates=\(devToolsCandidates.map(\.path).joined(separator: ","))
                    """)
                let searched = devToolsCandidates.map(\.path).joined(separator: ", ")
                throw AppError.toolMissing(
                    "tools unavailable locally: \(folder) (searched: \(searched))")
            }
            done += 1
            progress(done / total, folder)
        }
    }

    /// ツールのバイナリ存在チェック一覧。上から順に起動時に検査する。
    static let toolBinaryChecks: [(folder: String, binary: String)] = [
        ("upscal", "upscal/bin/upscayl-bin"),
        ("jpegoptim", "jpegoptim/bin/macos/jpegoptim"),
        ("pngoptim", "pngoptim/bin/macos/pngoptim"),
        ("libjxl", "libjxl/bin/macos/cjxl"),
        ("libavif", "libavif/bin/macos/avifenc"),
        ("libwebp", "libwebp/bin/macos/cwebp"),
        ("realcugan", "realcugan/bin/macos/realcugan-ncnn-vulkan")
    ]
}

// MARK: ネットワークからの取得
extension ToolInstaller {
    /// ネットワーク配布のあるツールをダウンロードして配置する。
    func downloadTool(folder: String) async throws {
        switch folder {
        case "libwebp": try await downloadLibwebp()
        case "realcugan": try await downloadRealcugan()
        default: throw AppError.toolMissing("no download source for \(folder)")
        }
    }

    /// GitHub ReleasesからReal-CUGANのZIPをダウンロードし、フォルダごと `tools/realcugan` へ配置する。
    /// 上流ZIPは `realcugan-ncnn-vulkan-<version>-macos/` 配下にバイナリ・`models-*`・LICENSEを持つ。
    func downloadRealcugan() async throws {
        let fm = FileManager.default
        let folderName = "realcugan-ncnn-vulkan-\(Self.realcuganVersion)-macos"
        let archiveName = "\(folderName).zip"
        guard let url = URL(string: "\(Self.realcuganBaseURL)/\(Self.realcuganVersion)/\(archiveName)") else {
            throw AppError.networkError("invalid realcugan URL")
        }
        AppLogger.shared.info("realcugan download: url=\(url.absoluteString)")
        let data = try await download(url: url)
        AppLogger.shared.info("realcugan download: received bytes=\(data.count) dest=\(paths.realCuganRootURL.path)")
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }
        let archive = tmpDir.appendingPathComponent(archiveName, isDirectory: false)
        try data.write(to: archive)
        // ZIPは /usr/bin/unzip で展開する（tar.gzのlibwebpと形式が異なる）。
        _ = try await runner.run(
            "/usr/bin/unzip", args: ["-q", archive.path, "-d", tmpDir.path], workingDirectory: nil)
        guard let extracted = findDirectory(named: folderName, under: tmpDir) else {
            throw AppError.toolMissing("\(folderName) not found in \(archiveName)")
        }
        AppLogger.shared.info("realcugan download: extracted=\(extracted.path)")
        // 配置後、モデル・バイナリが揃っていない場合は失敗扱いにする。
        try installRealCugan(from: extracted)
        guard isRealCuganInstalled() else {
            throw AppError.toolMissing("realcugan installation incomplete")
        }
    }

    /// 展開済みのReal-CUGANフォルダを `tools/realcugan` へ配置する。テストからも呼ぶ。
    func installRealCugan(from source: URL) throws {
        let fm = FileManager.default
        let dest = paths.realCuganRootURL
        // Why not: 親ディレクトリが無いとcopyItemが「ソース不在」の誤ったエラーを出すため先に作る。
        try fm.createDirectory(at: paths.toolsURL, withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: source, to: dest)
        let bin = paths.realCuganBinURL
        // Why not: 上流ZIPはバイナリがルート直下のフラット構造で、アプリが想定する
        // `bin/macos/` と一致しない。この場で正規化しないと、以降の存在チェックと
        // 実行権付与（bin/macos/を参照）がファイル不在のエラーで失敗する。
        let flatBin = dest.appendingPathComponent("realcugan-ncnn-vulkan", isDirectory: false)
        if fm.fileExists(atPath: flatBin.path) {
            if fm.fileExists(atPath: bin.path) {
                try fm.removeItem(at: flatBin)
            } else {
                try fm.createDirectory(
                    at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: flatBin, to: bin)
                AppLogger.shared.info("realcugan install: normalized \(flatBin.path) -> \(bin.path)")
            }
        }
        guard fm.fileExists(atPath: bin.path) else {
            throw AppError.toolMissing("realcugan-ncnn-vulkan not found in \(source.lastPathComponent)")
        }
        // Why not: unzipの権限は保持されるが、環境差で実行権が落ちると起動を妨げるため明示する。
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
        try Self.realcuganFullVersion
            .write(to: paths.realCuganRootURL.appendingPathComponent(".version"), atomically: true, encoding: .utf8)
        AppLogger.shared.info("realcugan install: binary=\(bin.path)")
    }
}

// MARK: ローカルコピー
extension ToolInstaller {
    /// 開発用toolsからフォルダをコピーする。成功したらtrue。
    @discardableResult
    func copyFromDevTools(folder: String) -> Bool {
        let fm = FileManager.default
        for candidate in devToolsCandidates {
            let src = candidate.appendingPathComponent(folder, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: src.path, isDirectory: &isDir), isDir.boolValue else {
                AppLogger.shared.info("tools copy: source not found \(src.path)")
                continue
            }
            let dest = paths.toolsURL.appendingPathComponent(folder, isDirectory: true)
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: src, to: dest)
                try makeExecutable(in: dest)
                AppLogger.shared.info("tools copy: \(src.path) -> \(dest.path)")
                return true
            } catch {
                AppLogger.shared.error(
                    "tools copy failed: \(src.path) -> \(dest.path): \(error.localizedDescription)")
                continue
            }
        }
        return false
    }

    func makeExecutable(in directory: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in enumerator {
            if Self.executables.contains(url.lastPathComponent) {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
        }
    }

    // MARK: ネットワーク取得
    /// 現在のアーキテクチャに応じたlibwebpアーカイブ名。
    static func libwebpArchiveName(version: String, platform: String, arch: String) -> String {
        let a = arch.lowercased()
        if platform == "windows" {
            return "libwebp-\(version)-windows-x64.zip"
        }
        if platform == "linux" {
            if a.contains("aarch64") || a.contains("arm64") {
                return "libwebp-\(version)-linux-aarch64.tar.gz"
            }
            return "libwebp-\(version)-linux-x86-64.tar.gz"
        }
        if a.contains("x86_64") {
            return "libwebp-\(version)-mac-x86-64.tar.gz"
        }
        return "libwebp-\(version)-mac-arm64.tar.gz"
    }

    func downloadLibwebp() async throws {
        var sysinfo = utsname()
        uname(&sysinfo)
        let arch = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        let name = Self.libwebpArchiveName(version: Self.webpVersion, platform: "macos", arch: arch)
        guard let url = URL(string: "\(Self.webpBaseURL)/\(name)") else {
            throw AppError.networkError("invalid libwebp URL")
        }
        AppLogger.shared.info("libwebp download: arch=\(arch) url=\(url.absoluteString)")
        let data = try await download(url: url)
        AppLogger.shared.info("libwebp download: received bytes=\(data.count) dest=\(paths.cwebpBinURL.path)")
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let archive = tmpDir.appendingPathComponent(name, isDirectory: false)
        try data.write(to: archive)
        // Why not: ダウンロード先を文字列で組み立てると AppPaths の実行パスとずれる恐れがあるため、
        // 実行時と同じ `cwebpBinURL` から配置先を導出する。
        let dest = paths.cwebpBinURL
        try FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        // tar.gz を /usr/bin/tar で展開し、*/bin/cwebp を配置する。
        _ = try await runner.run(
            "/usr/bin/tar", args: ["-xzf", archive.path, "-C", tmpDir.path], workingDirectory: nil)
        guard let cwebp = findFile(named: "cwebp", under: tmpDir) else {
            throw AppError.toolMissing("cwebp not found in \(name)")
        }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: cwebp, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        AppLogger.shared.info("libwebp install: source=\(cwebp.path) binary=\(dest.path)")
    }

    func findFile(named name: String, under directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator {
            if url.lastPathComponent == name { return url }
        }
        return nil
    }

    /// 配下から指定名のディレクトリを探す。Real-CUGANのZIP展開フォルダ特定に使う。
    func findDirectory(named name: String, under directory: URL) -> URL? {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey])
        else { return nil }
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            if values?.isDirectory == true && url.lastPathComponent == name { return url }
        }
        return nil
    }

    func download(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                AppLogger.shared.error(
                    "download failed: url=\(url.absoluteString) status=\(statusCode.map(String.init) ?? "unknown")")
                throw AppError.networkError("download failed: \(url)")
            }
            return data
        } catch let error as AppError {
            throw error
        } catch {
            AppLogger.shared.error(
                "download error: url=\(url.absoluteString) error=\(error.localizedDescription)")
            throw AppError.networkError("\(error)")
        }
    }

    /// SHA-256 hexを計算する。
    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
