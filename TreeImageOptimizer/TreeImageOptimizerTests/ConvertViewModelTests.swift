import Foundation
import Testing

@testable import TreeImageOptimizer

/// 一括変換画面のViewModelのうち、Real-CUGANモデル選択と設定永続化に関わる挙動を確認する。
/// Why not: 選択が `settings.json` に残らないと、再起動後にプルダウンの選択が失われる。
@Suite("ConvertViewModel RealCUGAN")
struct ConvertViewModelRealCUGANTests {
    /// Real-CUGANのモデルペア一式をテスト用の `tools/realcugan` に配置する。
    private func makeRealCuganTools(base: URL, names: [String]) throws {
        let fm = FileManager.default
        let se = base.appendingPathComponent("tools/realcugan/models-se", isDirectory: true)
        try fm.createDirectory(at: se, withIntermediateDirectories: true)
        for name in names {
            fm.createFile(
                atPath: se.appendingPathComponent("\(name).bin").path, contents: Data("x".utf8))
            fm.createFile(
                atPath: se.appendingPathComponent("\(name).param").path, contents: Data("x".utf8))
        }
        let bin = base.appendingPathComponent(
            "tools/realcugan/bin/macos/realcugan-ncnn-vulkan", isDirectory: false)
        try fm.createDirectory(at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: bin.path, contents: Data("x".utf8))
    }

    /// テスト用の基準ディレクトリを作る。
    private func makeBase() throws -> URL {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @MainActor
    private func makeViewModel(base: URL) throws -> ConvertViewModel {
        let paths = AppPaths(baseURL: base)
        return ConvertViewModel(paths: paths, store: SettingsStore(paths: paths))
    }

    @Test("モデルプルダウンの選択をsettings.jsonへ保存し、再生成後も復元される")
    @MainActor
    func selectionIsPersisted() throws {
        let base = try makeBase()
        try makeRealCuganTools(
            base: base,
            names: ["up2x-conservative", "up2x-denoise3x", "up4x-conservative", "up4x-no-denoise"])
        let paths = AppPaths(baseURL: base)
        let store = SettingsStore(paths: paths)

        let viewModel = try makeViewModel(base: base)
        viewModel.engine = .realCUGAN
        viewModel.selectModel(id: "models-se/up2x-denoise3x")
        #expect(viewModel.selectedModelID == "models-se/up2x-denoise3x")

        // プルダウンで選択した値がそのまま設定ファイルへ書き込まれている。
        #expect(try store.load(maxParallel: 8).batch.realCuganModel == "models-se/up2x-denoise3x")

        // 画面遷移などでViewModelを再生成しても選択が復元される。
        let reloaded = try makeViewModel(base: base)
        #expect(reloaded.selectedModelID == "models-se/up2x-denoise3x")
    }

    @Test("拡大率を変えると対応する拡大率のモデルへ切り替わり、保存もされる")
    @MainActor
    func scaleChangeSwitchesModelAndPersists() throws {
        let base = try makeBase()
        try makeRealCuganTools(
            base: base,
            names: ["up2x-conservative", "up2x-denoise3x", "up4x-conservative", "up4x-no-denoise"])
        let paths = AppPaths(baseURL: base)
        let store = SettingsStore(paths: paths)

        let viewModel = try makeViewModel(base: base)
        viewModel.engine = .realCUGAN
        viewModel.selectModel(id: "models-se/up2x-denoise3x")

        // 拡大率4に合わせて4xモデルへ切り替わる（拡大率2のまま残らない）。
        viewModel.scale = 4
        // フォールバックは保守版（ncnn版の既定値）。一覧は弱い順に no-denoise → conservative。
        #expect(viewModel.selectedModelID == "models-se/up4x-conservative")
        #expect(
            viewModel.modelOptions.map(\.id)
                == ["models-se/up4x-no-denoise", "models-se/up4x-conservative"])
        #expect(try store.load(maxParallel: 8).batch.realCuganModel == "models-se/up4x-conservative")
    }

    @Test("モデルプルダウンはノイズ除去が弱い順に表示される")
    @MainActor
    func modelOptionsAreOrderedByNoiseStrength() throws {
        let base = try makeBase()
        try makeRealCuganTools(
            base: base,
            names: [
                "up2x-conservative", "up2x-no-denoise", "up2x-denoise1x", "up2x-denoise2x",
                "up2x-denoise3x"
            ])

        let viewModel = try makeViewModel(base: base)
        viewModel.engine = .realCUGAN
        #expect(
            viewModel.modelOptions.map(\.id) == [
                "models-se/up2x-no-denoise", "models-se/up2x-conservative",
                "models-se/up2x-denoise1x", "models-se/up2x-denoise2x", "models-se/up2x-denoise3x"
            ])
    }

    @Test("ツール未配置の間は保存された選択を書き換えない")
    @MainActor
    func selectionSurvivesMissingTools() throws {
        let base = try makeBase()
        let paths = AppPaths(baseURL: base)
        let store = SettingsStore(paths: paths)
        var file = try store.load(maxParallel: 8)
        file.batch.engine = "realCUGAN"
        file.batch.realCuganModel = "models-se/up4x-denoise3x"
        try store.save(file)

        // tools/realcugan が無い状態（起動時ダウンロード前）でも選択は維持される。
        let viewModel = try makeViewModel(base: base)
        #expect(viewModel.selectedModelID == "models-se/up4x-denoise3x")
        #expect(try store.load(maxParallel: 8).batch.realCuganModel == "models-se/up4x-denoise3x")
    }

    @Test("アプリの起動順（設定画面のViewModel→変換ViewModel）でも復元される")
    @MainActor
    func restoresEngineInAppLaunchOrder() throws {
        let base = try makeBase()
        try makeRealCuganTools(base: base, names: ["up2x-conservative", "up2x-denoise1x"])
        let paths = AppPaths(baseURL: base)
        let store = SettingsStore(paths: paths)

        // 一括画面で Real-CUGAN と denoise1x を選択して保存する。
        let selected = try makeViewModel(base: base)
        selected.engine = .realCUGAN
        selected.selectModel(id: "models-se/up2x-denoise1x")

        // アプリ起動順に並べ替える（TreeImageOptimizerApp が SettingsViewModel を先に生成する）。
        // SettingsViewModel のロード時の保存が変換セクションを壊さないことをも確認する。
        let settings = SettingsViewModel(
            store: store,
            soundService: SoundService(userBaseURL: base.appendingPathComponent("sounds")),
            wallpaperService: WallpaperService(userBaseURL: base.appendingPathComponent("wallpaper"))
        )
        _ = settings.language

        let relaunched = try makeViewModel(base: base)
        #expect(relaunched.engine == .realCUGAN)
        #expect(relaunched.selectedModelID == "models-se/up2x-denoise1x")

        let reloaded = try store.load(maxParallel: 8)
        #expect(reloaded.batch.engine == "realCUGAN")
        #expect(reloaded.batch.realCuganModel == "models-se/up2x-denoise1x")
    }

    @Test("ツール展開完了後の再読込で利用可否とモデル一覧が反映される")
    @MainActor
    func reloadToolsReflectsInstalledTools() throws {
        let base = try makeBase()
        let viewModel = try makeViewModel(base: base)
        // 初期化はブートストラップの完了前に走るため、この時点では未配置扱い。
        #expect(!viewModel.realCuganAvailable)
        #expect(viewModel.models == ["realesr-animevideov3-x4"])

        // 展開完了を再現して配置し、再読込する。
        try makeRealCuganTools(base: base, names: ["up2x-conservative", "up4x-conservative"])
        let models = base.appendingPathComponent("tools/upscal/models", isDirectory: true)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: models.appendingPathComponent("m.bin").path, contents: Data("x".utf8))
        viewModel.reloadTools()

        #expect(viewModel.realCuganAvailable)
        #expect(viewModel.realCuganModels.count == 2)
        #expect(viewModel.models == ["m"])
    }
}
