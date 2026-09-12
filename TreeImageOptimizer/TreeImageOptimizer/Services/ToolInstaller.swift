import CryptoKit
import Foundation

/// toolsの初回展開・修復を行う。Flutter版 `ToolInstaller` に対応する。
///
/// SwiftUI版はmacOS専用のためWindows/Linux分岐は持たない。
/// `libwebp` はGitHub Releasesで配布されていないためGoogle Storageから取得する。
struct ToolInstaller: Sendable {
    static let executables = [
        "upscayl-bin",
        "cjxl",
        "avifenc",
        "jpegoptim",
        "pngoptim",
        "cwebp",
    ]

    /// `tools/` からの相対パス一覧。
    static let requiredRelativePaths = [
        "upscal/bin/upscayl-bin",
        "jpegoptim/bin/macos/jpegoptim",
        "pngoptim/bin/macos/pngoptim",
        "libjxl/bin/macos/cjxl",
        "libavif/bin/macos/avifenc",
        "libwebp/bin/macos/cwebp",
    ]

    static let webpVersion = "1.6.0"
    static let webpBaseURL = "https://storage.googleapis.com/downloads.webmproject.org/releases/webp"

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

    /// リポジトリ直下 `tools/` とアプリバンドル内 `Resources/tools` を候補にする。
    /// 開発ビルドでは `Info.plist` の `DevToolsPath`（Xcodeが `$(SOURCE_ROOT)/../tools`
    /// に展開）を最優先にする。カレントディレクトリは実行方法に依存するため当てにしない。
    static func defaultDevToolsCandidates() -> [URL] {
        var candidates: [URL] = []
        if let devPath = Bundle.main.object(forInfoDictionaryKey: "DevToolsPath") as? String,
           !devPath.contains("$(")
        {
            candidates.append(URL(fileURLWithPath: devPath, isDirectory: true))
        }
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("tools", isDirectory: true))
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("tools", isDirectory: true))
        }
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

    /// 揃っていなければ修復する。進捗（0.0〜1.0と作業名）を報告する。
    func ensureInstalled(progress: @Sendable (Double, String) -> Void = { _, _ in }) async throws {
        if isInstalled() {
            progress(1.0, "")
            return
        }
        try await repairMissingTools(progress: progress)
        guard isInstalled() else {
            throw AppError.toolMissing("tools repair did not complete")
        }
        progress(1.0, "")
    }

    /// 不足分を修復する。ローカルのtoolsコピーを優先し、無ければダウンロードする。
    func repairMissingTools(progress: @Sendable (Double, String) -> Void = { _, _ in }) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.toolsURL, withIntermediateDirectories: true)
        var missingFolders: [String] = []
        let checks: [(name: String, folder: String, binary: String)] = [
            ("upscal", "upscal", "upscal/bin/upscayl-bin"),
            ("jpegoptim", "jpegoptim", "jpegoptim/bin/macos/jpegoptim"),
            ("pngoptim", "pngoptim", "pngoptim/bin/macos/pngoptim"),
            ("libjxl", "libjxl", "libjxl/bin/macos/cjxl"),
            ("libavif", "libavif", "libavif/bin/macos/avifenc"),
            ("libwebp", "libwebp", "libwebp/bin/macos/cwebp"),
        ]
        for check in checks {
            let bin = paths.toolsURL.appendingPathComponent(check.binary, isDirectory: false)
            if fm.fileExists(atPath: bin.path) { continue }
            missingFolders.append(check.folder)
            let folder = paths.toolsURL.appendingPathComponent(check.folder, isDirectory: true)
            if fm.fileExists(atPath: folder.path) {
                try fm.removeItem(at: folder)
            }
        }
        // libwebpはGoogle Storageから分離して取得する。
        let libwebpMissing = missingFolders.contains("libwebp")
        let othersMissing = missingFolders.filter { $0 != "libwebp" }
        let total = Double(max(missingFolders.count, 1))
        var done = 0.0
        if !othersMissing.isEmpty {
            var restored = false
            for folder in othersMissing {
                if copyFromDevTools(folder: folder) {
                    restored = true
                    break
                }
            }
            if !restored {
                // 単一ZIPのダウンロードはフェーズ3の配布基盤で扱う。
                // 現時点ではローカルに無ければエラーにする。
                throw AppError.toolMissing("tools unavailable locally: \(othersMissing.joined(separator: ","))")
            }
            for folder in othersMissing {
                let dest = paths.toolsURL.appendingPathComponent(folder, isDirectory: true)
                if !fm.fileExists(atPath: dest.path) {
                    _ = copyFromDevTools(folder: folder)
                }
                done += 1
                progress(done / total, folder)
            }
        }
        if libwebpMissing {
            if !copyFromDevTools(folder: "libwebp") {
                progress(done / total, "libwebp")
                try await downloadLibwebp()
            }
            done += 1
            progress(done / total, "libwebp")
        }
    }

    /// 開発用toolsからフォルダをコピーする。成功したらtrue。
    @discardableResult
    func copyFromDevTools(folder: String) -> Bool {
        let fm = FileManager.default
        for candidate in devToolsCandidates {
            let src = candidate.appendingPathComponent(folder, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: src.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let dest = paths.toolsURL.appendingPathComponent(folder, isDirectory: true)
            do {
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: src, to: dest)
                try makeExecutable(in: dest)
                return true
            } catch {
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

    // MARK: - Download

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
        let data = try await download(url: url)
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let archive = tmpDir.appendingPathComponent(name, isDirectory: false)
        try data.write(to: archive)
        let binDir = paths.toolsURL.appendingPathComponent("libwebp/bin/macos", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        // tar.gz を /usr/bin/tar で展開し、*/bin/cwebp を配置する。
        _ = try await runner.run("/usr/bin/tar", args: ["-xzf", archive.path, "-C", tmpDir.path], workingDirectory: nil)
        guard let cwebp = findFile(named: "cwebp", under: tmpDir) else {
            throw AppError.toolMissing("cwebp not found in \(name)")
        }
        let dest = binDir.appendingPathComponent("cwebp", isDirectory: false)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: cwebp, to: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
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

    func download(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw AppError.networkError("download failed: \(url)")
            }
            return data
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.networkError("\(error)")
        }
    }

    /// SHA-256 hexを計算する。
    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
