import CryptoKit
import Foundation
import Testing

@testable import TreeImageOptimizer

@Suite("ToolInstaller")
struct ToolInstallerTests {
    final class LockedReports: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var items: [(Double, String)] = []
        func append(_ item: (Double, String)) {
            lock.lock()
            defer { lock.unlock() }
            items.append(item)
        }
    }

    func makeInstaller() throws -> (ToolInstaller, URL) {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let installer = ToolInstaller(paths: AppPaths(baseURL: base), devToolsCandidates: [])
        return (installer, base)
    }

    @Test("空ディレクトリでは未インストール")
    func notInstalledWhenEmpty() throws {
        let (installer, _) = try makeInstaller()
        #expect(!installer.isInstalled())
    }

    @Test("全バイナリとモデルがあればインストール済み")
    func installedWhenComplete() throws {
        let (installer, base) = try makeInstaller()
        let fm = FileManager.default
        for relative in ToolInstaller.requiredRelativePaths {
            let url = base.appendingPathComponent("tools/\(relative)", isDirectory: false)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: Data("x".utf8))
        }
        let models = base.appendingPathComponent("tools/upscal/models", isDirectory: true)
        try fm.createDirectory(at: models, withIntermediateDirectories: true)
        fm.createFile(atPath: models.appendingPathComponent("m.bin").path, contents: Data("x".utf8))
        #expect(installer.isInstalled())
    }

    @Test("揃っていればensureInstalledは成功する")
    func ensureInstalledWhenComplete() async throws {
        let (installer, base) = try makeInstaller()
        let fm = FileManager.default
        for relative in ToolInstaller.requiredRelativePaths {
            let url = base.appendingPathComponent("tools/\(relative)", isDirectory: false)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: Data("x".utf8))
        }
        let models = base.appendingPathComponent("tools/upscal/models", isDirectory: true)
        try fm.createDirectory(at: models, withIntermediateDirectories: true)
        fm.createFile(atPath: models.appendingPathComponent("m.bin").path, contents: Data("x".utf8))
        let reports = LockedReports()
        try await installer.ensureInstalled { fraction, name in
            reports.append((fraction, name))
        }
        #expect(reports.items.count == 1 && reports.items[0].0 == 1.0)
    }

    @Test("フィクスチャから修復できる")
    func repairsFromFixture() async throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        // 全フォルダ分の最小フィクスチャを用意
        let fixture = base.appendingPathComponent("fixture-tools", isDirectory: true)
        for relative in ToolInstaller.requiredRelativePaths {
            let url = fixture.appendingPathComponent(relative, isDirectory: false)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: Data("x".utf8))
        }
        let models = fixture.appendingPathComponent("upscal/models", isDirectory: true)
        try fm.createDirectory(at: models, withIntermediateDirectories: true)
        fm.createFile(atPath: models.appendingPathComponent("m.bin").path, contents: Data("x".utf8))
        let installer = ToolInstaller(
            paths: AppPaths(baseURL: base),
            devToolsCandidates: [fixture]
        )
        #expect(!installer.isInstalled())
        try await installer.ensureInstalled()
        #expect(installer.isInstalled())
    }

    @Test("1つでも欠ければ未インストール")
    func notInstalledWhenOneMissing() throws {
        let (installer, base) = try makeInstaller()
        let fm = FileManager.default
        for relative in ToolInstaller.requiredRelativePaths.dropLast() {
            let url = base.appendingPathComponent("tools/\(relative)", isDirectory: false)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: Data("x".utf8))
        }
        #expect(!installer.isInstalled())
    }

    @Test("ローカルtoolsから復元できる")
    func restoresFromDevTools() throws {
        let (installer, base) = try makeInstaller()
        let fm = FileManager.default
        // 開発用toolsを用意
        let devTools = base.appendingPathComponent("dev-tools", isDirectory: true)
        let src = devTools.appendingPathComponent("libwebp/bin/macos/cwebp", isDirectory: false)
        try fm.createDirectory(at: src.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: src.path, contents: Data("x".utf8))
        let local = ToolInstaller(
            paths: AppPaths(baseURL: base),
            devToolsCandidates: [devTools]
        )
        #expect(local.copyFromDevTools(folder: "libwebp"))
        #expect(fm.fileExists(atPath: base.appendingPathComponent("tools/libwebp/bin/macos/cwebp").path))
        _ = installer
    }

    @Test("libwebpアーカイブ名の決定")
    func libwebpArchiveNames() {
        #expect(ToolInstaller.libwebpArchiveName(version: "1.6.0", platform: "macos", arch: "arm64")
            == "libwebp-1.6.0-mac-arm64.tar.gz")
        #expect(ToolInstaller.libwebpArchiveName(version: "1.6.0", platform: "macos", arch: "x86_64")
            == "libwebp-1.6.0-mac-x86-64.tar.gz")
        #expect(ToolInstaller.libwebpArchiveName(version: "1.6.0", platform: "linux", arch: "x86_64")
            == "libwebp-1.6.0-linux-x86-64.tar.gz")
        #expect(ToolInstaller.libwebpArchiveName(version: "1.6.0", platform: "linux", arch: "aarch64")
            == "libwebp-1.6.0-linux-aarch64.tar.gz")
        #expect(ToolInstaller.libwebpArchiveName(version: "1.6.0", platform: "windows", arch: "x86_64")
            == "libwebp-1.6.0-windows-x64.zip")
    }

    @Test("SHA-256計算")
    func sha256() {
        let hex = ToolInstaller.sha256Hex(of: Data("abc".utf8))
        #expect(hex == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
