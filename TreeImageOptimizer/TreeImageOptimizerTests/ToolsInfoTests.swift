import Foundation
import Testing

@testable import TreeImageOptimizer

@Suite("ToolsInfo")
struct ToolsInfoTests {
    func makeStore() throws -> (ToolsInfoStore, URL) {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let store = ToolsInfoStore(paths: AppPaths(baseURL: base))
        return (store, base)
    }

    @Test("ツール配布物はアプリ本体とは別のtools-latestを参照する")
    func toolsInfoURLUsesDedicatedRelease() {
        #expect(
            ToolsInfoStore.toolsInfoURL.absoluteString
                == "https://github.com/treetips/tree-image-optimizer/releases/download/tools-latest/tools-info.json")
    }

    @Test("tools-info.jsonをデコードできる")
    func decodesToolsInfo() throws {
        let json = Data(
            """
            {
              "schemaVersion": 1,
              "tools": [
                {
                  "name": "upscal",
                  "version": "upscayl-bin-20251207-174704",
                  "url": "https://example.com/upscal.zip",
                  "sha256": "abc",
                  "required": true
                }
              ]
            }
            """.utf8)
        let info = try JSONDecoder().decode(ToolsInfo.self, from: json)
        #expect(info.schemaVersion == 1)
        #expect(info.tools.count == 1)
        #expect(info.tools[0].name == "upscal")
        #expect(info.metadata(for: "upscal")?.version == "upscayl-bin-20251207-174704")
        #expect(info.metadata(for: "missing") == nil)
    }

    @Test("インストール済み記録が無ければ同梱バージョンで初期化する")
    func loadsEmptyWhenMissing() throws {
        let (store, _) = try makeStore()
        // .installed.json が無い既存環境では、全ツールを「更新対象」と誤判定
        // しないよう、同梱ツールのバージョンで初期化する。
        #expect(store.loadInstalled() == InstalledTools(tools: ToolsInfoStore.bundledVersions))
    }

    @Test("インストール済み記録を保存して読み戻せる")
    func roundTripsInstalled() throws {
        let (store, base) = try makeStore()
        let installed = InstalledTools(tools: ["upscal": "v1", "libjxl": "v0.13.0"])
        try store.saveInstalled(installed)
        #expect(store.loadInstalled() == installed)
        #expect(
            FileManager.default.fileExists(
                atPath: base.appendingPathComponent("tools/.installed.json").path))
    }

    @Test("差分のあるツールだけを更新対象にする")
    func updatesNeededDetectsDiff() {
        let store = ToolsInfoStore(paths: AppPaths(baseURL: nil))
        let info = ToolsInfo(
            schemaVersion: 1,
            tools: [
                ToolMetadata(name: "upscal", version: "v2", url: "u", sha256: "s", required: true),
                ToolMetadata(name: "libjxl", version: "v0.13.0", url: "u", sha256: "s", required: true),
                ToolMetadata(name: "realcugan", version: "20220728", url: "u", sha256: "s", required: true)
            ]
        )
        let installed = InstalledTools(
            tools: ["upscal": "v1", "libjxl": "v0.13.0"]  // realcugan は未記録
        )
        let needed = store.updatesNeeded(info: info, installed: installed)
        #expect(needed.map(\.name) == ["upscal", "realcugan"])
    }

    @Test("初回復元では実体が無いツールだけを対象にする")
    func missingToolsChecksBinaries() throws {
        let (_, base) = try makeStore()
        let paths = AppPaths(baseURL: base)
        let existing = paths.toolsURL.appendingPathComponent("upscal/bin/upscayl-bin")
        try FileManager.default.createDirectory(
            at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: existing)
        let model = paths.upscalModelsURL.appendingPathComponent("model.bin")
        try FileManager.default.createDirectory(
            at: model.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("model".utf8).write(to: model)

        let info = ToolsInfo(
            schemaVersion: 1,
            tools: [
                ToolMetadata(name: "upscal", version: "v1", url: "u", sha256: "s", required: true),
                ToolMetadata(name: "libjxl", version: "v1", url: "u", sha256: "s", required: true)
            ]
        )
        #expect(ToolsUpdateService.missingTools(info: info, paths: paths).map(\.name) == ["libjxl"])
    }

    @Test("upscal のモデルが欠けていればフォルダ単位で再取得する")
    func missingToolsIncludesMissingUpscalModels() throws {
        let (_, base) = try makeStore()
        let paths = AppPaths(baseURL: base)
        let binary = paths.toolsURL.appendingPathComponent("upscal/bin/upscayl-bin")
        try FileManager.default.createDirectory(
            at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: binary)
        let info = ToolsInfo(
            schemaVersion: 1,
            tools: [
                ToolMetadata(
                    name: "upscal", version: "v1", url: "u",
                    sha256: String(repeating: "a", count: 64), required: true)
            ]
        )
        #expect(ToolsUpdateService.missingTools(info: info, paths: paths).map(\.name) == ["upscal"])
    }

    @Test("空・不正な SHA-256 のツール配布情報を拒否する")
    func rejectsInvalidChecksum() {
        let valid = ToolMetadata(
            name: "upscal", version: "v1", url: "u",
            sha256: String(repeating: "a", count: 64), required: true)
        #expect(throws: Never.self) {
            try ToolsUpdateService.validateChecksum(for: valid)
        }
        for checksum in ["", "abc", String(repeating: "g", count: 64)] {
            var invalid = valid
            invalid.sha256 = checksum
            #expect(throws: AppError.self) {
                try ToolsUpdateService.validateChecksum(for: invalid)
            }
        }
    }

    @Test("差分が無ければ空配列")
    func updatesNeededEmptyWhenSame() {
        let store = ToolsInfoStore(paths: AppPaths(baseURL: nil))
        let info = ToolsInfo(
            schemaVersion: 1,
            tools: [ToolMetadata(name: "upscal", version: "v1", url: "u", sha256: "s", required: true)]
        )
        let installed = InstalledTools(tools: ["upscal": "v1"])
        #expect(store.updatesNeeded(info: info, installed: installed).isEmpty)
    }
}
