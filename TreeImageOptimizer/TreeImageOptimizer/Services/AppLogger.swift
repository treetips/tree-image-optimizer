import Foundation
import OSLog

/// `logs/app.yyyyMMdd.log` へ追記するファイルロガー。
///
/// ADR 0007 の要件に従い、コマンドの実行内容と失敗理由をファイルへ残す。
/// OSLog だけでは `log show` を知らないと追えないため、起動時に `configure` して
/// アプリからの調査をログファイルだけで完結させる。
/// 30日を超えたファイルは起動時と日付が変わった最初の書き込みで削除する。
final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    private let lock = NSLock()
    private var directoryURL: URL?
    private var retentionDays = 30
    private var lastPrunedDay: String?
    private let osLogger = Logger(
        subsystem: "com.treeimageoptimizer.TreeImageOptimizer",
        category: "file"
    )

    /// 出力先を設定する。アプリ起動時に一度だけ呼ぶ。
    func configure(directoryURL: URL, retentionDays: Int = 30) {
        lock.lock()
        defer { lock.unlock() }
        self.directoryURL = directoryURL
        self.retentionDays = max(1, retentionDays)
        self.lastPrunedDay = nil
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            pruneLocked(now: Date())
        } catch {
            osLogger.error(
                """
                failed to prepare log directory \(directoryURL.path, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """)
        }
    }

    func info(_ message: String) {
        write(level: "INFO", message)
    }

    func warning(_ message: String) {
        write(level: "WARN", message)
    }

    func error(_ message: String) {
        write(level: "ERROR", message)
    }

    private func write(level: String, _ message: String) {
        // OSLog にも同じ内容を流し、Console.app からも追えるようにする。
        osLogger.info("\(level, privacy: .public) \(message, privacy: .public)")

        lock.lock()
        defer { lock.unlock() }
        guard let directoryURL else { return }

        let now = Date()
        let fileURL = directoryURL.appendingPathComponent(
            "app.\(Self.dayString(now)).log", isDirectory: false)
        let line = "\(Self.timestampString(now)) [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        do {
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.createDirectory(
                    at: directoryURL, withIntermediateDirectories: true)
                fileManager.createFile(atPath: fileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            osLogger.error(
                "failed to write log \(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
        pruneLocked(now: now)
    }

    /// 保持期間を超えた `app.*.log` を削除する。日付が変わるまで再走査しない。
    private func pruneLocked(now: Date) {
        guard let directoryURL else { return }
        let day = Self.dayString(now)
        guard lastPrunedDay != day else { return }
        lastPrunedDay = day

        let fileManager = FileManager.default
        guard
            let files = try? fileManager.contentsOfDirectory(
                at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 24 * 60 * 60)
        for file in files {
            guard file.lastPathComponent.hasPrefix("app."), file.pathExtension == "log" else {
                continue
            }
            guard
                let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                let modified = values.contentModificationDate,
                modified < cutoff
            else { continue }
            try? fileManager.removeItem(at: file)
        }
    }

    private static func dayString(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d%02d%02d",
            components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func timestampString(_ date: Date) -> String {
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        return String(
            format: "%04d-%02d-%02d %02d:%02d:%02d.%03d",
            components.year ?? 0, components.month ?? 0, components.day ?? 0,
            components.hour ?? 0, components.minute ?? 0, components.second ?? 0,
            (components.nanosecond ?? 0) / 1_000_000)
    }
}
