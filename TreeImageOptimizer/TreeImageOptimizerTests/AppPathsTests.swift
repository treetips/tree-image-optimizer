import Foundation
import Testing

@testable import TreeImageOptimizer

@Suite("AppPaths")
struct AppPathsTests {
    @Test("注入した基準ディレクトリ配下を解決する")
    func resolvesUnderInjectedBase() {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppPaths(baseURL: base)

        #expect(paths.projectDirectoryURL == base)
        #expect(paths.toolsURL.path.hasPrefix(base.path))
        #expect(paths.logsURL.path.hasSuffix("logs"))
        #expect(paths.settingsFileURL.lastPathComponent == "settings.json")
        #expect(paths.upscalBinURL.lastPathComponent == "upscayl-bin")
        #expect(paths.cjxlBinURL.lastPathComponent == "cjxl")
        #expect(paths.avifencBinURL.lastPathComponent == "avifenc")
        #expect(paths.cwebpBinURL.lastPathComponent == "cwebp")
        #expect(paths.jpegoptimBinURL.lastPathComponent == "jpegoptim")
        #expect(paths.pngoptimBinURL.lastPathComponent == "pngoptim")
    }

    @Test("macOS専用のためbinパスにOS分岐を含まない")
    func macOSOnlyPaths() {
        let paths = AppPaths(baseURL: URL(fileURLWithPath: "/tmp/base", isDirectory: true))
        #expect(paths.cwebpBinURL.path.contains("libwebp/bin/macos/cwebp"))
        #expect(!paths.cwebpBinURL.path.contains(".exe"))
    }

    @Test("Real-CUGANのパスを解決する")
    func realCuganPaths() {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppPaths(baseURL: base)

        #expect(
            paths.realCuganRootURL.path
                == base.appendingPathComponent("tools/realcugan", isDirectory: true).path)
        #expect(
            paths.realCuganBinURL.path
                == base.appendingPathComponent(
                    "tools/realcugan/bin/macos/realcugan-ncnn-vulkan", isDirectory: false
                ).path)
        #expect(paths.realCuganBinURL.lastPathComponent == "realcugan-ncnn-vulkan")
    }
}
