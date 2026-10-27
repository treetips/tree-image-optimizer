import Foundation
import Testing

@testable import TreeImageOptimizer

@Suite("SettingsViewModel")
@MainActor
struct SettingsViewModelTests {
    func makeEnv() throws -> (store: SettingsStore, dir: URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = SettingsStore(fileURL: dir.appendingPathComponent("settings.json", isDirectory: false))
        return (store, dir)
    }

    @Test("サウンドランダム設定をsettings.jsonから復元する")
    func restoresSoundRandomFlags() throws {
        let (store, dir) = try makeEnv()
        var file = try store.load(maxParallel: 8)
        file.settings.successSoundRandom = true
        file.settings.errorSoundRandom = true
        try store.save(file)
        let viewModel = SettingsViewModel(
            store: store,
            soundService: SoundService(userBaseURL: dir.appendingPathComponent("sounds", isDirectory: true)))
        #expect(viewModel.successSoundRandom == true)
        #expect(viewModel.errorSoundRandom == true)
    }

    @Test("ランダム設定の変更は保存され、選択中のサウンドは変更されない")
    func togglingRandomKeepsSelection() throws {
        let (store, dir) = try makeEnv()
        let viewModel = SettingsViewModel(
            store: store,
            soundService: SoundService(userBaseURL: dir.appendingPathComponent("sounds", isDirectory: true)))
        viewModel.successSound = "user.mp3"
        viewModel.successSoundRandom = true
        #expect(viewModel.successSound == "user.mp3")
        viewModel.successSoundRandom = false
        #expect(viewModel.successSound == "user.mp3")
        let reloaded = try store.load(maxParallel: 8)
        #expect(reloaded.settings.successSoundRandom == false)
        #expect(reloaded.settings.successSound == "user.mp3")
    }
}
