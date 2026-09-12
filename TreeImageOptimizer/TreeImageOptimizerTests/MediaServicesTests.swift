import Foundation
import Testing

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
        touch(bundled.appendingPathComponent("wallpaper1.jpg"))
        touch(bundled.appendingPathComponent("note.txt"))
        touch(user.appendingPathComponent("custom.png"))
        touch(user.appendingPathComponent("custom.webp"))
        let service = WallpaperService(bundledBaseURL: bundled, userBaseURL: user)
        let list = service.listWallpapers()
        #expect(list.map { $0.name } == ["wallpaper1.jpg", "wallpaper2.jpg", "custom.png"])
        #expect(list[0].isBundled)
        #expect(!list[2].isBundled)
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

    @Test("アップデート比較")
    func updateComparison() {
        let info = UpdateInfo(version: "0.1.0", build: 2, url: "https://example.com/a.zip", sha256: "x")
        #expect(info.isNewerThan(currentVersion: "0.0.9", currentBuild: 99))
        #expect(info.isNewerThan(currentVersion: "0.1.0", currentBuild: 1))
        #expect(!info.isNewerThan(currentVersion: "0.1.0", currentBuild: 2))
        #expect(!info.isNewerThan(currentVersion: "0.2.0", currentBuild: 1))
        #expect(!info.isNewerThan(currentVersion: "0.1.0", currentBuild: 3))
    }
}
