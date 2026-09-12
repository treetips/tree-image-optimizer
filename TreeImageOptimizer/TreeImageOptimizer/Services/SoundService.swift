import AVFoundation
import Foundation

/// サウンドの一覧取得と再生。Flutter版 `SoundService` に対応する。
final class SoundService: Sendable {
    let bundledBaseURL: URL?
    let userBaseURL: URL

    init(bundledBaseURL: URL? = nil, userBaseURL: URL? = nil, paths: AppPaths = AppPaths()) {
        self.bundledBaseURL = bundledBaseURL
        if let userBaseURL {
            self.userBaseURL = userBaseURL
        } else {
            self.userBaseURL = paths.userSoundsURL
        }
    }

    /// 同梱サウンドの基準ディレクトリ候補。
    func bundledBaseCandidates() -> [URL] {
        if let bundledBaseURL { return [bundledBaseURL] }
        var candidates: [URL] = []
        // アプリバンドル同梱のassetsを最優先にする。
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("assets/sounds", isDirectory: true))
        }
        let fm = FileManager.default
        let dev = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("assets/sounds", isDirectory: true)
        candidates.append(dev)
        return candidates
    }

    /// 成功・失敗それぞれの選択肢を返す。上部に同梱、その後にユーザー配置。
    func listSounds(success: Bool) -> [SoundOption] {
        let folder = success ? "success" : "error"
        return listBundled(folder: folder) + listUser(folder: folder)
    }

    func listBundled(folder: String) -> [SoundOption] {
        for base in bundledBaseCandidates() {
            let dir = base.appendingPathComponent(folder, isDirectory: true)
            let files = listSoundFiles(in: dir)
            if !files.isEmpty {
                return files.map {
                    SoundOption(name: $0.lastPathComponent, isBundled: true)
                }.sorted { $0.name < $1.name }
            }
        }
        return []
    }

    func listUser(folder: String) -> [SoundOption] {
        let dir = userBaseURL.appendingPathComponent(folder, isDirectory: true)
        return listSoundFiles(in: dir).map {
            SoundOption(name: $0.lastPathComponent, isBundled: false)
        }.sorted { $0.name < $1.name }
    }

    /// 選択中のサウンドが一覧に無い場合は先頭で補正する。
    func resolveSelected(_ current: String, options: [SoundOption]) -> String {
        if options.isEmpty { return current }
        if options.contains(where: { $0.name == current }) { return current }
        return options[0].name
    }

    /// 再生。AVAudioPlayerを保持して再生終了まで破棄しない呼び出し元で使う。
    func makePlayer(for option: SoundOption, userDirectory: URL? = nil) -> AVAudioPlayer? {
        let url: URL
        if option.isBundled {
            guard let found = findBundled(name: option.name) else { return nil }
            url = found
        } else {
            let base = userDirectory ?? userBaseURL
            // success/error両方を探す
            let candidates = ["success", "error"].map { base.appendingPathComponent($0, isDirectory: true).appendingPathComponent(option.name, isDirectory: false) }
            guard let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
                return nil
            }
            url = found
        }
        return try? AVAudioPlayer(contentsOf: url)
    }

    private func findBundled(name: String) -> URL? {
        for base in bundledBaseCandidates() {
            for folder in ["success", "error"] {
                let url = base.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(name, isDirectory: false)
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }

    private func listSoundFiles(in dir: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        let exts = ["mp3", "wav", "flac", "aac", "ogg"]
        return contents.filter { url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            return values?.isRegularFile == true && exts.contains(url.pathExtension.lowercased())
        }
    }
}
