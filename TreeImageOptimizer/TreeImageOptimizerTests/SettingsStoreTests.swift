import Foundation
import Testing

@testable import TreeImageOptimizer

@Suite("SettingsStore")
struct SettingsStoreTests {
    func makeStore() throws -> (SettingsStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("settings.json", isDirectory: false)
        return (SettingsStore(fileURL: file), file)
    }

    @Test("無い場合は初期値を保存して返す")
    func createsDefaultsWhenMissing() throws {
        let (store, file) = try makeStore()
        let loaded = try store.load(maxParallel: 8)
        #expect(loaded.settings == ScreenSettings.defaults())
        #expect(loaded.batch.format == OutputFormat.jpegXL.rawValue)
        #expect(loaded.batch.quality == 80)
        #expect(loaded.easy.format == OutputFormat.jpegXL.rawValue)
        #expect(loaded.easy.outputFolderPath == nil)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("保存した値を読み込める")
    func roundTrip() throws {
        let (store, _) = try makeStore()
        var file = try store.load(maxParallel: 8)
        file.settings.playSound = true
        file.settings.wallpaperOpacity = 0.4
        file.batch.quality = 95
        file.easy.quality = 70
        try store.save(file)
        let reloaded = try store.load(maxParallel: 8)
        #expect(reloaded.settings.playSound == true)
        #expect(reloaded.settings.wallpaperOpacity == 0.4)
        #expect(reloaded.batch.quality == 95)
        #expect(reloaded.easy.quality == 70)
    }

    @Test("不正値は補正されファイルが更新される")
    func correctsInvalidValues() throws {
        let (store, file) = try makeStore()
        let broken = """
        {"settings":{"showOsNotification":"yes","wallpaperOpacity":9.9,"wallpaperBackgroundColor":"zzz"},
         "batch":{"scale":99,"format":"nope","quality":0,"parallelCount":999},
         "easy":{"scale":99,"quality":0}}
        """
        try broken.write(to: file, atomically: true, encoding: .utf8)
        let loaded = try store.load(maxParallel: 8)
        #expect(loaded.settings.showOsNotification == false)
        #expect(loaded.settings.wallpaperOpacity == 1.0)
        #expect(loaded.settings.wallpaperBackgroundColor == "#1E1E1E")
        #expect(loaded.batch.scale == 4)
        #expect(loaded.batch.format == OutputFormat.jpegXL.rawValue)
        #expect(loaded.batch.quality == 1)
        #expect(loaded.batch.parallelCount == 8)
        #expect(loaded.easy.scale == 4)
        #expect(loaded.easy.quality == 1)
        // 補正後はファイルも更新されている
        let data = try Data(contentsOf: file)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let batch = json?["batchConvert"] as? [String: Any]
        #expect(batch?["scale"] as? Int == 4)
    }

    @Test("旧convertキーはbatchへ移行される")
    func migratesLegacyConvertKey() throws {
        let (store, file) = try makeStore()
        let legacy = """
        {"settings":{"playSound":true},
         "convert":{"scale":3,"quality":75,"outputFolderPath":"/tmp/out"}}
        """
        try legacy.write(to: file, atomically: true, encoding: .utf8)
        let loaded = try store.load(maxParallel: 8)
        #expect(loaded.batch.scale == 3)
        #expect(loaded.batch.quality == 75)
        #expect(loaded.batch.outputFolderPath == "/tmp/out")
        #expect(loaded.easy.scale == 2)
        // 新形式で書き換えられている
        let data = try Data(contentsOf: file)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["batchConvert"] != nil)
        #expect(json?["easyConvert"] != nil)
        #expect(json?["convert"] == nil)
    }

    @Test("中間形式のbatch/easyキーはbatchConvert/easyConvertへ移行される")
    func migratesIntermediateKeys() throws {
        let (store, file) = try makeStore()
        let legacy = """
        {"settings":{},
         "batch":{"scale":3,"outputFolderPath":"/tmp/batch-out"},
         "easy":{"scale":4,"outputFolderPath":"/tmp/easy-out"}}
        """
        try legacy.write(to: file, atomically: true, encoding: .utf8)
        let loaded = try store.load(maxParallel: 8)
        #expect(loaded.batch.scale == 3)
        #expect(loaded.batch.outputFolderPath == "/tmp/batch-out")
        #expect(loaded.easy.scale == 4)
        #expect(loaded.easy.outputFolderPath == "/tmp/easy-out")
        let data = try Data(contentsOf: file)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["batchConvert"] != nil)
        #expect(json?["easyConvert"] != nil)
        #expect(json?["batch"] == nil)
        #expect(json?["easy"] == nil)
    }

    @Test("外観モードの初期値と補正")
    func appearance() throws {
        let (store, file) = try makeStore()
        #expect(try store.load(maxParallel: 8).settings.appearance == "auto")
        var saved = try store.load(maxParallel: 8)
        saved.settings.appearance = "dark"
        try store.save(saved)
        #expect(try store.load(maxParallel: 8).settings.appearance == "dark")
        try #"{"settings":{"appearance":"sepia"}}"#.write(to: file, atomically: true, encoding: .utf8)
        #expect(try store.load(maxParallel: 8).settings.appearance == "auto")
    }

    @Test("外観モード別の背景色初期値")
    func wallpaperBackgroundColorDefaults() {
        #expect(SettingsViewModel.defaultWallpaperBackgroundColorHex(for: "light") == "#FFFFFF")
        #expect(SettingsViewModel.defaultWallpaperBackgroundColorHex(for: "dark") == "#1E1E1E")
    }

    @Test("文字の大きさの初期値と補正")
    func fontSize() throws {
        let (store, file) = try makeStore()
        #expect(try store.load(maxParallel: 8).settings.fontSize == "standard")
        var saved = try store.load(maxParallel: 8)
        saved.settings.fontSize = "large"
        try store.save(saved)
        #expect(try store.load(maxParallel: 8).settings.fontSize == "large")
        try #"{"settings":{"fontSize":"huge"}}"#.write(to: file, atomically: true, encoding: .utf8)
        #expect(try store.load(maxParallel: 8).settings.fontSize == "standard")
    }

    @Test("壊れたJSONは初期値に戻る")
    func recoversFromCorruptJSON() throws {
        let (store, _) = try makeStore()
        // 先に有効な値を保存してから壊す
        var file = try store.load(maxParallel: 8)
        file.batch.quality = 50
        try store.save(file)
        try "not json".write(to: store.fileURL, atomically: true, encoding: .utf8)
        let loaded = try store.load(maxParallel: 8)
        #expect(loaded.batch.quality == 80)
    }

    @Test("保存は決定的なバイト列になる")
    func stableBytes() throws {
        let (store, file) = try makeStore()
        var saved = try store.load(maxParallel: 8)
        saved.batch.scale = 3
        saved.easy.quality = 70
        try store.save(saved)
        let first = try Data(contentsOf: file)
        try store.save(try store.load(maxParallel: 8))
        let second = try Data(contentsOf: file)
        #expect(first == second)
    }

    @Test("色バリデーション")
    func colorValidation() {
        #expect(SettingsStore.isValidColor("#FFFFFF"))
        #expect(SettingsStore.isValidColor("FF00ff00"))
        #expect(!SettingsStore.isValidColor("zzz"))
        #expect(!SettingsStore.isValidColor("#FFF"))
        #expect(!SettingsStore.isValidColor(""))
    }
}
