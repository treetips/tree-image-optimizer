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
        // macOS専用のためarm64/x86_64のみを分岐する。
        #expect(
            ToolInstaller.libwebpArchiveName(version: "1.6.0", arch: "arm64")
                == "libwebp-1.6.0-mac-arm64.tar.gz")
        #expect(
            ToolInstaller.libwebpArchiveName(version: "1.6.0", arch: "x86_64")
                == "libwebp-1.6.0-mac-x86-64.tar.gz")
    }

    @Test("SHA-256計算")
    func sha256() {
        let hex = ToolInstaller.sha256Hex(of: Data("abc".utf8))
        #expect(hex == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test("期待SHA-256が一致すれば検証を通る")
    func verifyArchiveAcceptsMatchingDigest() throws {
        let (installer, _) = try makeInstaller()
        let payload = Data("archive-bytes".utf8)
        let digest = ToolInstaller.sha256Hex(of: payload)
        try installer.verifyArchive(data: payload, expected: digest, name: "sample.tar.gz")
    }

    @Test("期待SHA-256が不一致ならverificationFailedで落ちる")
    func verifyArchiveRejectsMismatchedDigest() throws {
        let (installer, _) = try makeInstaller()
        // 大文字の期待値も小文字化して比較するため、大小文字違いは一致とみなす。
        let digest = ToolInstaller.sha256Hex(of: Data("archive-bytes".utf8)).uppercased()
        try installer.verifyArchive(data: Data("archive-bytes".utf8), expected: digest, name: "sample.tar.gz")

        let wrong = ToolInstaller.sha256Hex(of: Data("tampered".utf8))
        do {
            try installer.verifyArchive(data: Data("archive-bytes".utf8), expected: wrong, name: "sample.tar.gz")
            Issue.record("改ざんされたアーカイブが検証を通った")
        } catch let error as AppError {
            guard case .verificationFailed(let message) = error else {
                Issue.record("想定外のエラー: \(error)")
                return
            }
            #expect(message.contains("checksum mismatch for sample.tar.gz"))
        }
    }

    @Test("期待SHA-256が未設定なら検証をスキップする")
    func verifyArchiveSkipsWhenNotConfigured() throws {
        let (installer, _) = try makeInstaller()
        // Why not 未設定で落とさないか: ハッシュ未設定では検証自体が不可能であり、
        // 取得を止めるより警告を残して継続する方が復旧しやすいため。
        try installer.verifyArchive(data: Data("x".utf8), expected: nil, name: "unknown.zip")
        try installer.verifyArchive(data: Data("x".utf8), expected: "", name: "unknown.zip")
    }

    @Test("一時的なネットワークエラーだけを再試行対象にする")
    func classifiesTransientNetworkErrors() {
        let timeout = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let connectionLost = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost)
        let reset = NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNRESET))
        #expect(ToolInstaller.isTransientNetworkError(timeout))
        #expect(ToolInstaller.isTransientNetworkError(connectionLost))
        #expect(ToolInstaller.isTransientNetworkError(reset))

        // 恒久的失敗（証書エラー等）は再試行しない。
        let badServer = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse)
        let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        #expect(!ToolInstaller.isTransientNetworkError(badServer))
        #expect(!ToolInstaller.isTransientNetworkError(cancelled))
    }

    @Test("Real-CUGANは必須ツール（未配置では未インストール・配置すれば判定が変わる）")
    func realCuganOptional() throws {
        let (installer, base) = try makeInstaller()
        let fm = FileManager.default
        for relative in ToolInstaller.requiredRelativePaths where !relative.contains("realcugan") {
            let url = base.appendingPathComponent("tools/\(relative)", isDirectory: false)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: Data("x".utf8))
        }
        let models = base.appendingPathComponent("tools/upscal/models", isDirectory: true)
        try fm.createDirectory(at: models, withIntermediateDirectories: true)
        fm.createFile(atPath: models.appendingPathComponent("m.bin").path, contents: Data("x".utf8))
        // Real-CUGANのバイナリが無ければ必須判定はfalse（起動時ブートストラップで補完される）。
        #expect(!installer.isInstalled())
        #expect(!installer.isRealCuganInstalled())
        // Real-CUGANはバイナリ+有効なモデルペアで揃うと判定が変わる。
        let bin = base.appendingPathComponent(
            "tools/realcugan/bin/macos/realcugan-ncnn-vulkan", isDirectory: false)
        try fm.createDirectory(at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: bin.path, contents: Data("x".utf8))
        #expect(!installer.isRealCuganInstalled(), "モデルペアが無ければ使えない")
        let se = base.appendingPathComponent("tools/realcugan/models-se", isDirectory: true)
        try fm.createDirectory(at: se, withIntermediateDirectories: true)
        fm.createFile(atPath: se.appendingPathComponent("up2x-conservative.param").path, contents: Data("x".utf8))
        #expect(!installer.isRealCuganInstalled(), ".paramだけでは使えない")
        fm.createFile(atPath: se.appendingPathComponent("up2x-conservative.bin").path, contents: Data("x".utf8))
        #expect(installer.isRealCuganInstalled())
    }

    @Test("展開済みReal-CUGANフォルダをtoolsへ配置できる")
    func installsRealCuganFromExtracted() throws {
        let (installer, base) = try makeInstaller()
        let fm = FileManager.default
        // Why not: 共有のNSTemporaryDirectoryは並列実行の他テストと干渉し得るため、
        // テスト専用base配下に展開済みフォルダを作る。
        let source = base.appendingPathComponent("extracted", isDirectory: true)
        let bin = source.appendingPathComponent("bin/macos/realcugan-ncnn-vulkan", isDirectory: false)
        try fm.createDirectory(at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: bin.path, contents: Data("x".utf8))
        let se = source.appendingPathComponent("models-se", isDirectory: true)
        try fm.createDirectory(at: se, withIntermediateDirectories: true)
        fm.createFile(atPath: se.appendingPathComponent("up2x-conservative.bin").path, contents: Data("x".utf8))
        fm.createFile(atPath: se.appendingPathComponent("up2x-conservative.param").path, contents: Data("x".utf8))

        try installer.installRealCugan(from: source)

        #expect(fm.fileExists(atPath: bin.path))
        #expect(fm.fileExists(atPath: se.appendingPathComponent("up2x-conservative.param").path))
        #expect(fm.fileExists(atPath: base.appendingPathComponent("tools/realcugan/.version").path))
        let installedBin = base.appendingPathComponent(
            "tools/realcugan/bin/macos/realcugan-ncnn-vulkan", isDirectory: false)
        let attrs = try fm.attributesOfItem(atPath: installedBin.path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.uint16Value == 0o755)
        #expect(installer.isRealCuganInstalled())
        // 再配置では既存フォルダを置き換える。
        try installer.installRealCugan(from: source)
        #expect(fm.fileExists(atPath: bin.path))
    }

    @Test("上流ZIPのフラット配置からもbin/macosへ正規化して配置できる")
    func installsRealCuganFromFlatLayout() throws {
        let (installer, base) = try makeInstaller()
        let fm = FileManager.default
        // Why not: 上流ZIPはバイナリがルート直下にある（bin/macosを持たない）ため、
        // その構造のまま配置するとbin/macos参照が失敗するのを再現する。
        let source = base.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        fm.createFile(
            atPath: source.appendingPathComponent("realcugan-ncnn-vulkan").path,
            contents: Data("x".utf8))
        let se = source.appendingPathComponent("models-se", isDirectory: true)
        try fm.createDirectory(at: se, withIntermediateDirectories: true)
        fm.createFile(atPath: se.appendingPathComponent("up2x-conservative.bin").path, contents: Data("x".utf8))
        fm.createFile(atPath: se.appendingPathComponent("up2x-conservative.param").path, contents: Data("x".utf8))

        try installer.installRealCugan(from: source)

        let installedBin = base.appendingPathComponent(
            "tools/realcugan/bin/macos/realcugan-ncnn-vulkan", isDirectory: false)
        #expect(fm.fileExists(atPath: installedBin.path))
        #expect(!fm.fileExists(atPath: base.appendingPathComponent("tools/realcugan/realcugan-ncnn-vulkan").path))
        let attrs = try fm.attributesOfItem(atPath: installedBin.path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.uint16Value == 0o755)
        #expect(installer.isRealCuganInstalled())
    }

    @Test("復元元が無い場合は探索した候補パスを含めて失敗する")
    func reportsSearchedCandidatesWhenMissing() async throws {
        let (installer, _) = try makeInstaller()
        // 実在しない候補だけを渡し、配布.appで復元元が無い状態を再現する。
        let searched = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let local = ToolInstaller(
            paths: installer.paths,
            devToolsCandidates: [searched]
        )

        do {
            try await local.repairMissingTools()
            Issue.record("復元元が無いのに成功した")
        } catch let error as AppError {
            guard case .toolMissing(let message) = error else {
                Issue.record("想定外のエラー: \(error)")
                return
            }
            #expect(message.contains("tools unavailable locally: upscal"))
            #expect(message.contains(searched.path))
        }
    }
}
