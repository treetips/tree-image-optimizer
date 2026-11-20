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

    @Test("インストール済み記録が無ければ空を返す")
    func loadsEmptyWhenMissing() throws {
        let (store, _) = try makeStore()
        #expect(store.loadInstalled() == InstalledTools())
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
