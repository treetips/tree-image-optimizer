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

    @Test("ダウンロード配置先と実行パスが一致する")
    func downloadDestinationsMatchExecutionPaths() {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let paths = AppPaths(baseURL: base)

        // libwebp は tools/libwebp/bin/macos/cwebp へ配置し、同じパスを実行する。
        #expect(
            paths.cwebpBinURL.path
                == paths.toolsURL.appendingPathComponent("libwebp/bin/macos/cwebp").path)
        // Real-CUGAN は tools/realcugan へ展開し、bin/macos 配下を実行する。
        #expect(
            paths.realCuganRootURL.path
                == paths.toolsURL.appendingPathComponent("realcugan", isDirectory: true).path)
        #expect(
            paths.realCuganBinURL.path
                == paths.realCuganRootURL.appendingPathComponent(
                    "bin/macos/realcugan-ncnn-vulkan", isDirectory: false
                ).path)
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
