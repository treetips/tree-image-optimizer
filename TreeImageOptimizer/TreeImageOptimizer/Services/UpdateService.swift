import CryptoKit
import Foundation

/// GitHub Releases配置のアップデート情報。Flutter版 `UpdateInfo` に対応する。
struct UpdateInfo: Codable, Equatable {
    var version: String
    var build: Int
    var url: String
    var sha256: String

    /// セマンティックバージョン→ビルド番号の順で比較する。
    func isNewerThan(currentVersion: String, currentBuild: Int) -> Bool {
        let current = currentVersion.split(separator: ".").compactMap { Int($0) }
        let remote = version.split(separator: ".").compactMap { Int($0) }
        for i in 0 ..< 3 {
            let c = i < current.count ? current[i] : 0
            let n = i < remote.count ? remote[i] : 0
            if n > c { return true }
            if n < c { return false }
        }
        return build > currentBuild
    }
}

enum UpdateCheckResult: Sendable {
    case latest
    case available(UpdateInfo)
    case failed(String)
}

/// 自前アップデート処理。Flutter版 `UpdaterService` に対応する。
/// フェーズ3では確認・ダウンロード・検証まで実装し、適用（差し替え・再起動）は
/// 配布方式確定後に行う。
struct UpdateService: Sendable {
    /// `update-info.json` を取得してバージョン比較する。
    func checkForUpdate(url: URL, currentVersion: String, currentBuild: Int) async -> UpdateCheckResult {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failed("HTTPエラー")
            }
            let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
            if info.isNewerThan(currentVersion: currentVersion, currentBuild: currentBuild) {
                return .available(info)
            }
            return .latest
        } catch {
            return .failed("\(error)")
        }
    }

    /// ZIPをダウンロードしSHA-256検証して一時ディレクトリに展開する。
    /// - Returns: 展開先ディレクトリ内の `.app` パス。
    func downloadAndPrepare(info: UpdateInfo, runner: ProcessRunner = ProcessRunner()) async throws -> URL {
        var request = URLRequest(url: URL(string: info.url)!)
        request.timeoutInterval = 300
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.networkError("Download failed: \(info.url)")
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == info.sha256.lowercased() else {
            throw AppError.verificationFailed("SHA-256 mismatch: expected \(info.sha256), got \(digest)")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tree-image-optimizer-update", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let zip = dir.appendingPathComponent("update.zip", isDirectory: false)
        try data.write(to: zip, options: .atomic)
        _ = try await runner.run("/usr/bin/unzip", args: ["-o", zip.path, "-d", dir.path], workingDirectory: nil)
        guard let app = findAppBundle(under: dir, maxDepth: 2) else {
            throw AppError.fileNotFound(".app bundle not found in archive")
        }
        return app
    }

    func findAppBundle(under directory: URL, maxDepth: Int) -> URL? {
        var results: [URL] = []
        collectAppBundles(under: directory, depth: 0, maxDepth: maxDepth, into: &results)
        return results.sorted { $0.path < $1.path }.first
    }

    private func collectAppBundles(under directory: URL, depth: Int, maxDepth: Int, into results: inout [URL]) {
        guard depth <= maxDepth else { return }
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }
        for url in contents {
            if url.pathExtension == "app" {
                results.append(url)
            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                collectAppBundles(under: url, depth: depth + 1, maxDepth: maxDepth, into: &results)
            }
        }
    }
}
