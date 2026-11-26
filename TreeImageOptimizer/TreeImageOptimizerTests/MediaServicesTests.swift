import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import TreeImageOptimizer

@Suite("MediaServices")
struct MediaServicesTests {
    func makeDirs() throws -> (bundled: URL, user: URL) {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundled = base.appendingPathComponent("bundled", isDirectory: true)
        let user = base.appendingPathComponent("user", isDirectory: true)
        try fm.createDirectory(at: bundled, withIntermediateDirectories: true)
        try fm.createDirectory(at: user, withIntermediateDirectories: true)
        return (bundled, user)
    }

    func touch(_ url: URL) {
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
    }

    @Test("壁紙一覧（同梱優先・ソート・拡張子）")
    func wallpapers() throws {
        let (bundled, user) = try makeDirs()
        touch(bundled.appendingPathComponent("wallpaper2.jpg"))
        touch(bundled.appendingPathComponent("wallpaper1.jxl"))
        touch(bundled.appendingPathComponent("note.txt"))
        touch(user.appendingPathComponent("custom.png"))
        touch(user.appendingPathComponent("custom.webp"))
        touch(user.appendingPathComponent("custom.avif"))
        let service = WallpaperService(bundledBaseURL: bundled, userBaseURL: user)
        let list = service.listWallpapers()
        #expect(
            list.map { $0.name } == [
                "wallpaper1.jxl", "wallpaper2.jpg", "custom.avif", "custom.png", "custom.webp"
            ])
        #expect(list[0].isBundled)
        #expect(!list[4].isBundled)
    }

    @Test("壁紙のフォールバック")
    func wallpaperFallback() throws {
        let (bundled, user) = try makeDirs()
        touch(bundled.appendingPathComponent("wallpaper1.jpg"))
        let service = WallpaperService(bundledBaseURL: bundled, userBaseURL: user)
        let list = service.listWallpapers()
        #expect(service.resolveSelected("wallpaper1.jpg", options: list) == "wallpaper1.jpg")
        #expect(service.resolveSelected("gone.png", options: list) == "wallpaper1.jpg")
        // ユーザー壁紙が削除されていたらフォールバック
        touch(user.appendingPathComponent("mine.png"))
        let list2 = service.listWallpapers()
        #expect(service.resolveSelected("mine.png", options: list2) == "mine.png")
        try FileManager.default.removeItem(at: user.appendingPathComponent("mine.png"))
        let list3 = service.listWallpapers()
        #expect(service.resolveSelected("mine.png", options: list3) == "wallpaper1.jpg")
    }

    @Test("サウンド一覧と選択補正")
    func sounds() throws {
        let (bundled, user) = try makeDirs()
        let success = bundled.appendingPathComponent("success", isDirectory: true)
        try FileManager.default.createDirectory(at: success, withIntermediateDirectories: true)
        touch(success.appendingPathComponent("b.mp3"))
        touch(success.appendingPathComponent("a.mp3"))
        let userSuccess = user.appendingPathComponent("success", isDirectory: true)
        try FileManager.default.createDirectory(at: userSuccess, withIntermediateDirectories: true)
        touch(userSuccess.appendingPathComponent("mine.wav"))
        let service = SoundService(bundledBaseURL: bundled, userBaseURL: user)
        let list = service.listSounds(success: true)
        #expect(list.map { $0.name } == ["a.mp3", "b.mp3", "mine.wav"])
        #expect(service.resolveSelected("b.mp3", options: list) == "b.mp3")
        #expect(service.resolveSelected("gone.mp3", options: list) == "a.mp3")
    }

    @Test("ランダム抽選はユーザー配置サウンドのみ対象")
    func randomPlaybackOption() throws {
        let (bundled, user) = try makeDirs()
        let success = bundled.appendingPathComponent("success", isDirectory: true)
        try FileManager.default.createDirectory(at: success, withIntermediateDirectories: true)
        touch(success.appendingPathComponent("sample.mp3"))
        let userSuccess = user.appendingPathComponent("success", isDirectory: true)
        try FileManager.default.createDirectory(at: userSuccess, withIntermediateDirectories: true)
        touch(userSuccess.appendingPathComponent("user1.mp3"))
        touch(userSuccess.appendingPathComponent("user2.mp3"))
        let service = SoundService(bundledBaseURL: bundled, userBaseURL: user)
        // ランダム無効時は選択中のサウンド
        let fixed = service.resolvePlaybackOption(success: true, name: "sample.mp3", random: false)
        #expect(fixed?.name == "sample.mp3")
        // ランダム有効時は同梱サンプルが選ばれない
        for _ in 0..<20 {
            let chosen = service.resolvePlaybackOption(success: true, name: "sample.mp3", random: true)
            #expect(chosen?.name == "user1.mp3" || chosen?.name == "user2.mp3")
        }
    }

    @Test("ユーザー配置が無い場合ランダムは選択中のサウンドへフォールバック")
    func randomPlaybackOptionFallback() throws {
        let (bundled, user) = try makeDirs()
        let success = bundled.appendingPathComponent("success", isDirectory: true)
        try FileManager.default.createDirectory(at: success, withIntermediateDirectories: true)
        touch(success.appendingPathComponent("sample.mp3"))
        let service = SoundService(bundledBaseURL: bundled, userBaseURL: user)
        let chosen = service.resolvePlaybackOption(success: true, name: "sample.mp3", random: true)
        #expect(chosen?.name == "sample.mp3")
    }

    @Test("アップデート比較")
    func updateComparison() {
        let info = UpdateInfo(version: "0.1.0", build: 2, url: "https://example.com/a.zip", sha256: "x")
        #expect(info.isNewerThan(currentVersion: "0.0.9", currentBuild: 99))
        #expect(info.isNewerThan(currentVersion: "0.1.0", currentBuild: 1))
        #expect(!info.isNewerThan(currentVersion: "0.1.0", currentBuild: 2))
        #expect(!info.isNewerThan(currentVersion: "0.2.0", currentBuild: 1))
        #expect(!info.isNewerThan(currentVersion: "0.1.0", currentBuild: 3))
    }

    @Test("ダウンロード進捗は受信バイト数を0〜1に丸める")
    func updateDownloadProgress() {
        #expect(UpdateInstallProgress.downloadFraction(received: 0, total: 100) == 0)
        #expect(UpdateInstallProgress.downloadFraction(received: 50, total: 100) == 0.5)
        #expect(UpdateInstallProgress.downloadFraction(received: 120, total: 100) == 1)
        // Content-Lengthが不明なら0%固定にせず不確定表示にする。
        #expect(UpdateInstallProgress.downloadFraction(received: 10, total: -1) == nil)
        let progress = UpdateInstallProgress.downloading(received: 25, total: 100)
        #expect(progress.phase == .downloading)
        #expect(progress.fraction == 0.25)
        #expect(UpdateInstallProgress.indeterminate(.verifying).fraction == nil)
    }

    @Test("インストール先は/Applications配下")
    func installDestination() {
        let prepared = URL(fileURLWithPath: "/tmp/TreeImageOptimizer.app", isDirectory: false)
        #expect(
            UpdateService.installDestination(for: prepared).path == "/Applications/TreeImageOptimizer.app")
    }

    @Test("再起動用アプリはApplicationsへ配置せずステージングする")
    func stageUpdateForRestart() throws {
        let fileManager = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: base) }
        let prepared = base.appendingPathComponent("TreeImageOptimizer.app", isDirectory: false)
        try fileManager.createDirectory(
            at: prepared.appendingPathComponent("Contents", isDirectory: true), withIntermediateDirectories: true)
        touch(prepared.appendingPathComponent("Contents/Info.plist"))

        let paths = AppPaths(baseURL: base)
        let staged = try UpdateService().stageForRestart(preparedApp: prepared, paths: paths)
        let expected = paths.updatesDirectoryURL.appendingPathComponent(
            "TreeImageOptimizer.app", isDirectory: false)
        #expect(staged == expected)
        #expect(fileManager.fileExists(atPath: staged.appendingPathComponent("Contents/Info.plist").path))
        #expect(!fileManager.fileExists(atPath: prepared.path))
    }

    @Test("起動時にステージング済みアプリを掃除する")
    func cleanupStagedUpdate() throws {
        let fileManager = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: base) }
        let prepared = base.appendingPathComponent("TreeImageOptimizer.app", isDirectory: false)
        try fileManager.createDirectory(at: prepared, withIntermediateDirectories: true)
        let paths = AppPaths(baseURL: base)
        let service = UpdateService()
        _ = try service.stageForRestart(preparedApp: prepared, paths: paths)

        service.cleanupStagedUpdate(paths: paths)
        #expect(!fileManager.fileExists(atPath: paths.updatesDirectoryURL.path))
    }

    @Test("適用は展開済みアプリを複写する")
    func applyUpdateCopies() throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let prepared = base.appendingPathComponent("TreeImageOptimizer.app", isDirectory: false)
        try fm.createDirectory(
            at: prepared.appendingPathComponent("Contents", isDirectory: true), withIntermediateDirectories: true)
        touch(prepared.appendingPathComponent("Contents/Info.plist"))
        let destination = base.appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("TreeImageOptimizer.app", isDirectory: false)
        let service = UpdateService()
        let installed = try service.applyUpdate(preparedApp: prepared, destination: destination)
        #expect(installed == destination)
        #expect(fm.fileExists(atPath: destination.appendingPathComponent("Contents/Info.plist").path))
    }

    @Test("適用は存在しない展開元で失敗する")
    func applyUpdateFailsWithoutSource() {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let service = UpdateService()
        #expect(throws: AppError.self) {
            try service.applyUpdate(
                preparedApp: base.appendingPathComponent("Missing.app", isDirectory: false),
                destination: base.appendingPathComponent("Dest.app", isDirectory: false))
        }
    }

    @Test("配置失敗時は部分コピーを削除し旧アプリを復元する")
    func applyUpdateRestoresPreviousAppOnCopyFailure() throws {
        let fileManager = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let prepared = base.appendingPathComponent("Prepared.app", isDirectory: false)
        let destination = base.appendingPathComponent("Installed.app", isDirectory: false)
        defer {
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: prepared.path)
            try? fileManager.removeItem(at: base)
        }
        try fileManager.createDirectory(
            at: prepared.appendingPathComponent("Contents", isDirectory: true), withIntermediateDirectories: true)
        touch(prepared.appendingPathComponent("Contents/New"))
        try fileManager.setAttributes([.posixPermissions: 0], ofItemAtPath: prepared.path)
        try fileManager.createDirectory(
            at: destination.appendingPathComponent("Contents", isDirectory: true), withIntermediateDirectories: true)
        touch(destination.appendingPathComponent("Contents/Old"))

        #expect(throws: (any Error).self) {
            try UpdateService().applyUpdate(preparedApp: prepared, destination: destination)
        }
        #expect(fileManager.fileExists(atPath: destination.appendingPathComponent("Contents/Old").path))
        #expect(!fileManager.fileExists(atPath: destination.appendingPathComponent("Contents/New").path))
    }

    @Test("更新確認結果はサイドナビの更新カード状態に解決する")
    @MainActor
    func resolveCard() {
        let info = UpdateInfo(version: "0.1.0", build: 2, url: "https://example.com/a.zip", sha256: "x")
        #expect(UpdateCheckController.resolveCard(for: .available(info)) == .available(info))
        // 更新なし・確認失敗どちらも「更新なし」カードを表示する。
        #expect(UpdateCheckController.resolveCard(for: .latest) == .noUpdate)
        #expect(UpdateCheckController.resolveCard(for: .failed("offline")) == .noUpdate)
    }

    @Test("再起動待ちは更新確認を上書きしない")
    @MainActor
    func restartReadyBlocksUpdateCheck() {
        let controller = UpdateCheckController()
        let destination = URL(fileURLWithPath: "/Applications/TreeImageOptimizer.app")
        let info = UpdateInfo(version: "0.1.0", build: 2, url: "https://example.com/a.zip", sha256: "x")
        controller.card = .readyToRestart(destination, info)
        controller.checkForUpdate(language: "ja")
        #expect(controller.isReadyToRestart)
        #expect(!controller.isChecking)
        #expect(controller.card == .readyToRestart(destination, info))
    }

    @Test("ステージング掃除中は更新確認とダウンロードを開始しない")
    @MainActor
    func stagedUpdateCleanupBlocksUpdateOperations() {
        let controller = UpdateCheckController()
        let info = UpdateInfo(version: "0.1.0", build: 2, url: "https://example.com/a.zip", sha256: "x")
        controller.isCleaningStagedUpdate = true
        controller.checkForUpdate(language: "ja")
        controller.startDownload(info, language: "ja")
        #expect(!controller.canCheckForUpdates)
        #expect(!controller.isChecking)
        #expect(!controller.isInstalling)
        #expect(controller.card == nil)
    }

    @Test("手動確認結果は確認失敗時を除きサイドナビの更新カード状態に解決する")
    @MainActor
    func resolveManualCard() {
        let info = UpdateInfo(version: "0.1.0", build: 2, url: "https://example.com/a.zip", sha256: "x")
        #expect(UpdateCheckController.resolveManualCard(for: .available(info)) == .available(info))
        #expect(UpdateCheckController.resolveManualCard(for: .latest) == .noUpdate)
        // 確認失敗時はnilを返し、カードは変更しない。
        #expect(UpdateCheckController.resolveManualCard(for: .failed("offline")) == nil)
    }
}

/// EXIF 保持のメタデータ引き継ぎ経路を確認する（ADR 0070）。
@Suite("CompressionService メタデータ")
struct CompressionServiceMetadataTests {
    private func makePNG(at url: URL, width: Int, height: Int) throws {
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw NSError(domain: "CompressionServiceMetadataTests", code: 1)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "CompressionServiceMetadataTests", code: 2)
        }
    }

    /// EXIF を付与したPNGを作る。
    private func makePNGWithExif(at url: URL) throws {
        guard
            let context = CGContext(
                data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let image = context.makeImage()
        else {
            throw NSError(domain: "CompressionServiceMetadataTests", code: 3)
        }
        // CGImageMetadataCreateMutable は失敗しない（非Optional）ため、生成はここで行う。
        let metadata = CGImageMetadataCreateMutable()
        CGImageMetadataSetValueMatchingImageProperty(
            metadata, kCGImagePropertyExifDictionary, kCGImagePropertyExifUserComment,
            "tree-image-optimizer" as CFString)
        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw NSError(domain: "CompressionServiceMetadataTests", code: 4)
        }
        CGImageDestinationAddImageAndMetadata(destination, image, metadata, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "CompressionServiceMetadataTests", code: 5)
        }
    }

    /// 画像のメタデータに EXIF のタグが含まれるか。
    private func hasExifTag(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        else { return false }
        var found = false
        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, nil) { path, _ in
            if (path as String).hasPrefix("exif:") { found = true }
            return !found
        }
        return found
    }

    @Test("変換後もEXIFが保持される")
    func keepsExif() throws {
        let fileManager = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }
        let source = base.appendingPathComponent("src.png")
        try makePNGWithExif(at: source)
        #expect(hasExifTag(at: source), "前提として入力にEXIFが入っていること")

        let png = base.appendingPathComponent("out.png")
        try CompressionService.convertToPNG(input: source, output: png, source: source)
        #expect(hasExifTag(at: png), "PNG変換後もEXIFが残ること")

        let jpg = base.appendingPathComponent("out.jpg")
        try CompressionService.convertToJPEG(input: source, output: jpg, quality: 0.9, source: source)
        #expect(hasExifTag(at: jpg), "JPEG変換後もEXIFが残ること")
    }

    @Test("元画像あり・なしどちらでもJPEG/PNG変換が壊れない")
    func convertKeepsOutputReadable() throws {
        let fileManager = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }
        let source = base.appendingPathComponent("src.png")
        try makePNG(at: source, width: 16, height: 16)

        let png = base.appendingPathComponent("out.png")
        try CompressionService.convertToPNG(input: source, output: png, source: source)
        #expect(fileManager.fileExists(atPath: png.path), "元画像ありでもPNGが出力されること")

        let jpg = base.appendingPathComponent("out.jpg")
        try CompressionService.convertToJPEG(input: source, output: jpg, quality: 0.9, source: source)
        #expect(fileManager.fileExists(atPath: jpg.path), "元画像ありでもJPEGが出力されること")
    }
}

/// HEIF/AVIF 入力の判定と対応拡張子を確認する（ADR 0069）。
@Suite("TargetFiles 入力拡張子")
struct TargetFilesInputTests {
    @Test("HEIF/AVIF はPNGデコードが必要と判定される")
    func needsDecodeToPNG() {
        #expect(TargetFiles.needsDecodeToPNG(URL(fileURLWithPath: "a.heic")))
        #expect(TargetFiles.needsDecodeToPNG(URL(fileURLWithPath: "a.heif")))
        #expect(TargetFiles.needsDecodeToPNG(URL(fileURLWithPath: "a.avif")))
        #expect(!TargetFiles.needsDecodeToPNG(URL(fileURLWithPath: "a.png")))
        #expect(!TargetFiles.needsDecodeToPNG(URL(fileURLWithPath: "a.jpg")))
    }

    @Test("HEIF/AVIF が入力拡張子に含まれる")
    func supportedExtensionsIncludeHeifAvif() {
        for ext in ["heic", "heif", "avif"] {
            #expect(TargetFiles.supportedExtensions.contains(ext))
        }
    }
}
