import Foundation

/// 対象ファイル選定。Flutter版 `ConvertRepository.getTargetFiles` に対応する。
enum TargetFiles {
    static let supportedExtensions = ["jpg", "jpeg", "png", "webp"]

    /// 更新日数が `days` 以内のファイルに絞る。`days == nil` で全件。
    static func list(in folder: URL, modifiedWithinDays days: Double?) throws -> [URL] {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            throw AppError.fileNotFound(folder.path)
        }
        let contents = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])
        let now = Date()
        var result: [URL] = []
        for url in contents {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { continue }
            guard supportedExtensions.contains(url.pathExtension.lowercased()) else { continue }
            if let days, let modified = values.contentModificationDate {
                if now.timeIntervalSince(modified) > days * 24 * 60 * 60 { continue }
            }
            result.append(url)
        }
        return result.sorted { $0.path < $1.path }
    }

    /// `TargetFilter` に対応する日数。`.all` は `nil`。
    static func days(for filter: TargetFilter) -> Double? {
        switch filter {
        case .oneDay: return 1
        case .threeDays: return 3
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .all: return nil
        }
    }

    /// `.bin` からモデル名一覧を返す。空ならフォールバックを返す。
    static func listModels(in modelsDir: URL) -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return ["realesr-animevideov3-x4"]
        }
        var models = Set<String>()
        for url in contents {
            guard url.pathExtension.lowercased() == "bin" else { continue }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            models.insert(url.deletingPathExtension().lastPathComponent)
        }
        let list = models.sorted()
        return list.isEmpty ? ["realesr-animevideov3-x4"] : list
    }
}
