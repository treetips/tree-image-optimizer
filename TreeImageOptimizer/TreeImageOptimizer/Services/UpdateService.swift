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
        for i in 0..<3 {
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

/// インストール処理の段階。この順に進む。
enum UpdateInstallPhase: Int, Sendable, Equatable, Comparable {
    case downloading = 0
    case verifying = 1
    case extracting = 2
    case installing = 3

    static func < (lhs: UpdateInstallPhase, rhs: UpdateInstallPhase) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// サイドナビの「インストール中」カードに表示する進捗。
struct UpdateInstallProgress: Sendable, Equatable {
    var phase: UpdateInstallPhase
    /// 0...1。nilの段階は不確定表示にする。
    var fraction: Double?
    var receivedBytes: Int64
    var totalBytes: Int64

    /// 受信バイト数から進捗率を求める。総バイト数が不明ならnilを返す。
    /// サーバーが Content-Length を返さない場合に0%固定へ丸めないため。
    static func downloadFraction(received: Int64, total: Int64) -> Double? {
        guard total > 0 else { return nil }
        return min(max(Double(received) / Double(total), 0), 1)
    }

    static func downloading(received: Int64, total: Int64) -> UpdateInstallProgress {
        UpdateInstallProgress(
            phase: .downloading,
            fraction: downloadFraction(received: received, total: total),
            receivedBytes: received,
            totalBytes: total
        )
    }

    /// バイト進捗を持たない段階（検証・展開・コピー）の不確定表示。
    static func indeterminate(_ phase: UpdateInstallPhase) -> UpdateInstallProgress {
        UpdateInstallProgress(phase: phase, fraction: nil, receivedBytes: 0, totalBytes: 0)
    }
}

/// 自前アップデート処理。Flutter版 `UpdaterService` に対応する。
/// 配布ZIPのダウンロード・検証・展開と、`/Applications` への適用まで行う。
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
    /// 進捗はダウンロードの受信バイト数（Content-Length基準）で通知する。
    /// - Returns: 展開先ディレクトリ内の `.app` パス。
    func downloadAndPrepare(
        info: UpdateInfo,
        runner: ProcessRunner = ProcessRunner(),
        onProgress: @escaping @Sendable (UpdateInstallProgress) -> Void = { _ in }
    ) async throws -> URL {
        guard let url = URL(string: info.url) else {
            throw AppError.networkError("Invalid update URL: \(info.url)")
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tree-image-optimizer-update", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.path) {
            try fm.removeItem(at: dir)
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let zip = dir.appendingPathComponent("update.zip", isDirectory: false)

        AppLogger.shared.info("update download start: \(info.url)")
        let downloader = UpdateDownloader(destination: zip, onProgress: onProgress)
        try await downloader.download(from: url)

        // 検証・展開・コピーはバイト単位の進捗APIが無いため不確定表示にする。
        onProgress(.indeterminate(.verifying))
        let digest = try sha256(of: zip)
        guard digest == info.sha256.lowercased() else {
            throw AppError.verificationFailed("SHA-256 mismatch: expected \(info.sha256), got \(digest)")
        }

        onProgress(.indeterminate(.extracting))
        _ = try await runner.run("/usr/bin/unzip", args: ["-o", zip.path, "-d", dir.path], workingDirectory: nil)
        guard let app = findAppBundle(under: dir, maxDepth: 2) else {
            throw AppError.fileNotFound(".app bundle not found in archive")
        }
        AppLogger.shared.info("update download finish: \(app.path)")
        return app
    }

    /// ファイルを読みながらSHA-256を計算する。
    /// 数百MBのZIPを丸ごとメモリへ載せないため、`SHA256.hash(data:)` ではなく逐次更新する。
    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func findAppBundle(under directory: URL, maxDepth: Int) -> URL? {
        var results: [URL] = []
        collectAppBundles(under: directory, depth: 0, maxDepth: maxDepth, into: &results)
        return results.sorted { $0.path < $1.path }.first
    }

    /// 再起動用のステージング先。実行中の `/Applications` のバンドルを先に置換しない。
    static func stagingDestination(for preparedApp: URL, paths: AppPaths = AppPaths()) -> URL {
        paths.updatesDirectoryURL.appendingPathComponent(preparedApp.lastPathComponent, isDirectory: false)
    }

    /// 展開済みアプリをユーザーの Application Support へ退避し、再起動まで保持する。
    /// 実行中のバンドルは `restart` で置換するため、待機中も Bundle.main の資源を読める。
    @discardableResult
    func stageForRestart(preparedApp: URL, paths: AppPaths = AppPaths()) throws -> URL {
        let destination = Self.stagingDestination(for: preparedApp, paths: paths)
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: preparedApp, to: destination)
        return destination
    }

    /// 前回の再起動で不要になったステージングアプリを起動時に掃除する。
    /// 再起動直後ではなく次回起動時とし、起動処理を優先して不要なコピーの削除を後回しにする。
    func cleanupStagedUpdate(paths: AppPaths = AppPaths()) {
        let directory = paths.updatesDirectoryURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        do {
            try fm.removeItem(at: directory)
        } catch {
            AppLogger.shared.error(
                "failed to clean staged update: \(error.localizedDescription) (\(directory.path))")
        }
    }

    /// インストール先。`/Applications/<展開名.app>` に固定する。
    static func installDestination(for preparedApp: URL) -> URL {
        URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent(preparedApp.lastPathComponent, isDirectory: false)
    }

    /// 展開済みの `.app` をインストール先に反映する。
    /// 既存の同名アプリがあればゴミ箱に移動してからコピーする。
    /// - Returns: インストール先の `.app` パス。
    @discardableResult
    func applyUpdate(preparedApp: URL, destination: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: preparedApp.path) else {
            throw AppError.fileNotFound(preparedApp.path)
        }
        var trashedAppURL: NSURL?
        if fm.fileExists(atPath: destination.path) {
            try fm.trashItem(at: destination, resultingItemURL: &trashedAppURL)
        } else {
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        do {
            try fm.copyItem(at: preparedApp, to: destination)
        } catch {
            // コピー失敗で実行中アプリの居場所を失わないよう、部分コピーを消してから戻す。
            if fm.fileExists(atPath: destination.path) {
                do {
                    try fm.removeItem(at: destination)
                } catch {
                    AppLogger.shared.error(
                        "failed to remove partial app: \(error.localizedDescription) (\(destination.path))")
                }
            }
            if let trashedAppURL {
                let trashedURL = trashedAppURL as URL
                if fm.fileExists(atPath: trashedURL.path) {
                    do {
                        try fm.moveItem(at: trashedURL, to: destination)
                    } catch {
                        AppLogger.shared.error(
                            "failed to restore previous app: \(error.localizedDescription) (\(destination.path))")
                    }
                }
            }
            throw error
        }
        return destination
    }

    private func collectAppBundles(under directory: URL, depth: Int, maxDepth: Int, into results: inout [URL]) {
        guard depth <= maxDepth else { return }
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey]
            )
        else { return }
        for url in contents {
            if url.pathExtension == "app" {
                results.append(url)
            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                collectAppBundles(under: url, depth: depth + 1, maxDepth: maxDepth, into: &results)
            }
        }
    }
}

/// `URLSessionDownloadTask` の受信バイト数を通知するダウンローダ。
/// `URLSession.download(for:)` は進捗を取得できないためdelegateで受ける。
/// 進捗は1%単位に間引き、SwiftUIの状態更新を毎バイト起こさないようにする。
private final class UpdateDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (UpdateInstallProgress) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var transferError: Error?
    private var lastPercent = -1

    init(destination: URL, onProgress: @escaping @Sendable (UpdateInstallProgress) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func download(from url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 60 * 30
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            lock.lock()
            self.session = session
            lock.unlock()
            // 再実行時に壊れたキャッシュを使い回さないよう、常に取り直す。
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            session.downloadTask(with: request).resume()
        }
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesExpectedToWrite <= 0 {
            // Content-Lengthが無い場合は0%固定にせず、不確定表示へ一度だけ切り替える。
            guard lastPercent != 0 else { return }
            lastPercent = 0
            onProgress(.downloading(received: totalBytesWritten, total: totalBytesExpectedToWrite))
            return
        }
        let percent = Int((Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) * 100).rounded(.down))
        guard percent != lastPercent else { return }
        lastPercent = percent
        onProgress(.downloading(received: totalBytesWritten, total: totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            transferError = AppError.networkError("Download failed: HTTP \(http.statusCode)")
            return
        }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            // 受信済みの一時ファイルを動かすだけなので、ここは同期で終わらせる。
            // このdelegateを抜けるとURLSessionが一時ファイルを削除するため。
            try fm.moveItem(at: location, to: destination)
        } catch {
            transferError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // sessionがdelegate（self）を保持し続けるため、完了時に必ず無効化して解放する。
        session.invalidateAndCancel()
        finish(error ?? transferError)
    }

    private func finish(_ error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        self.session = nil
        lock.unlock()
        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
