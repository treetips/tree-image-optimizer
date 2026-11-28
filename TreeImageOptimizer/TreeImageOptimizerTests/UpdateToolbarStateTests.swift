import Foundation
import Testing

@testable import TreeImageOptimizer

@Suite("UpdateToolbarState")
@MainActor
struct UpdateToolbarStateTests {
    private func appInfo() -> UpdateInfo {
        UpdateInfo(version: "0.2.0", build: 2, url: "https://example.com/app.zip", sha256: "a")
    }

    private func toolsInfo() -> ToolsInfo {
        ToolsInfo(
            schemaVersion: 1,
            tools: [
                ToolMetadata(
                    name: "upscal", version: "v2", url: "https://example.com/tools.zip", sha256: "b", required: true)
            ]
        )
    }

    @Test("更新の組み合わせを1つの表示状態へ解決する")
    func resolvesAvailability() {
        let app = appInfo()
        let tools = toolsInfo()
        #expect(
            UpdateToolbarResolver.resolve(
                appCard: .available(app), toolsCard: .available(tools),
                isChecking: false, toolsCheckCompleted: true, checkFailures: (app: false, tools: false)
            ) == .available(.appAndTools(app, tools)))
        #expect(
            UpdateToolbarResolver.resolve(
                appCard: .available(app), toolsCard: nil,
                isChecking: false, toolsCheckCompleted: true, checkFailures: (app: false, tools: false)
            ) == .available(.app(app)))
        #expect(
            UpdateToolbarResolver.resolve(
                appCard: .noUpdate, toolsCard: .available(tools),
                isChecking: false, toolsCheckCompleted: true, checkFailures: (app: false, tools: false)
            ) == .available(.tools(tools)))
        #expect(
            UpdateToolbarResolver.resolve(
                appCard: .noUpdate, toolsCard: nil,
                isChecking: false, toolsCheckCompleted: true, checkFailures: (app: false, tools: false)
            ) == .noUpdate)
        #expect(
            UpdateToolbarResolver.resolve(
                appCard: nil, toolsCard: nil,
                isChecking: false, toolsCheckCompleted: true, checkFailures: (app: false, tools: false)
            ) == .hidden)
    }

    @Test("ツールの確認完了まではアプリだけの更新文言を出さない")
    func waitsForToolsCheck() {
        let app = appInfo()
        #expect(
            UpdateToolbarResolver.resolve(
                appCard: .available(app), toolsCard: nil,
                isChecking: false, toolsCheckCompleted: false, checkFailures: (app: false, tools: false)
            ) == .checking)
    }

    @Test("片方の確認失敗でも、確認済みの更新は表示する")
    func keepsKnownAvailabilityWhenOtherCheckFails() {
        let app = appInfo()
        let tools = toolsInfo()
        #expect(
            UpdateToolbarResolver.resolve(
                appCard: .available(app), toolsCard: nil,
                isChecking: false, toolsCheckCompleted: true,
                checkFailures: (app: false, tools: true)
            ) == .available(.app(app)))
        #expect(
            UpdateToolbarResolver.resolve(
                appCard: .noUpdate, toolsCard: .available(tools),
                isChecking: false, toolsCheckCompleted: true,
                checkFailures: (app: true, tools: false)
            ) == .available(.tools(tools)))
        #expect(
            UpdateToolbarResolver.resolve(
                appCard: .noUpdate, toolsCard: nil,
                isChecking: false, toolsCheckCompleted: true,
                checkFailures: (app: false, tools: true)
            ) == .hidden)
    }

    @Test("実行中の更新を失敗カードより優先する")
    func prioritizesInstallingOverFailure() {
        let tools = toolsInfo()
        let progress = ToolsUpdateProgress(fraction: 0.5, label: "upscal")
        #expect(
            UpdateToolbarResolver.resolve(
                appCard: .installFailed(appInfo()), toolsCard: .installing(progress),
                isChecking: false, toolsCheckCompleted: true,
                checkFailures: (app: false, tools: false)
            ) == .toolsInstalling(progress))
    }

    @Test("両方ある場合はツールを先に更新する")
    func plansToolsBeforeApp() {
        let app = appInfo()
        let tools = toolsInfo()
        #expect(UpdateToolbarResolver.plan(for: .appAndTools(app, tools)) == .toolsThenApp(app, tools))
        #expect(UpdateToolbarResolver.plan(for: .app(app)) == .app(app))
        #expect(UpdateToolbarResolver.plan(for: .tools(tools)) == .tools(tools))
    }

    @Test("失敗した更新と残っている更新を同じ順序で再実行する")
    func plansRetry() {
        let app = appInfo()
        let tools = toolsInfo()
        #expect(
            UpdateToolbarResolver.retryPlan(
                appCard: .available(app), toolsCard: .installFailed(tools)
            ) == .toolsThenApp(app, tools))
        #expect(
            UpdateToolbarResolver.retryPlan(
                appCard: .installFailed(app), toolsCard: .available(tools)
            ) == .toolsThenApp(app, tools))
        #expect(
            UpdateToolbarResolver.retryPlan(
                appCard: .installFailed(app), toolsCard: nil
            ) == .app(app))
        #expect(
            UpdateToolbarResolver.retryPlan(
                appCard: .noUpdate, toolsCard: .installFailed(tools)
            ) == .tools(tools))
    }

    @Test("Aboutは未確認状態をニュートラルに表示する")
    func aboutStartsUnchecked() {
        let controller = UpdateCheckController()
        let tools = ToolsUpdateController()
        let presentation = AboutUpdatePresentation(
            controller: controller, toolsUpdate: tools, language: "ja", updatesEnabled: true)

        #expect(presentation.appStatus.tone == .neutral)
        #expect(presentation.toolsStatus.tone == .neutral)
        #expect(presentation.appStatus.message == "未確認")
        #expect(presentation.primaryButtonTitle == "アップデートを確認")
        #expect(presentation.primaryButtonEnabled)
        #expect(presentation.installButtonTitle == "インストール")
        #expect(presentation.installButtonDisabled)

        controller.isChecking = true
        let checking = AboutUpdatePresentation(
            controller: controller, toolsUpdate: tools, language: "ja", updatesEnabled: true)
        #expect(checking.primaryButtonTitle == "確認中...")
        #expect(!checking.primaryButtonEnabled)
    }

    @Test("Aboutはアプリとライブラリの更新を同時に表示する")
    func aboutShowsAvailableUpdates() {
        let app = appInfo()
        let tools = toolsInfo()
        let controller = UpdateCheckController()
        controller.card = .available(app)
        let toolsController = ToolsUpdateController()
        toolsController.card = .available(tools)
        toolsController.hasCheckedAvailability = true
        let presentation = AboutUpdatePresentation(
            controller: controller, toolsUpdate: toolsController, language: "ja", updatesEnabled: true)

        #expect(presentation.appStatus.tone == .warning)
        #expect(presentation.appStatus.message == "アプリを v0.2.0 にアップデートできます。")
        #expect(presentation.toolsStatus.tone == .warning)
        #expect(presentation.primaryButtonTitle == "インストール")
        #expect(presentation.primaryButtonEnabled)
        #expect(presentation.installButtonTitle == "インストール")
        #expect(!presentation.installButtonDisabled)

        let disabled = AboutUpdatePresentation(
            controller: controller, toolsUpdate: toolsController, language: "ja", updatesEnabled: false)
        #expect(!disabled.primaryButtonEnabled)
        #expect(disabled.installButtonDisabled)
    }

    @Test("Aboutは更新なしを緑で表示する")
    func aboutShowsLatest() {
        let controller = UpdateCheckController()
        controller.card = .noUpdate
        controller.hasCheckedAvailability = true
        let tools = ToolsUpdateController()
        tools.hasCheckedAvailability = true
        let presentation = AboutUpdatePresentation(
            controller: controller, toolsUpdate: tools, language: "ja", updatesEnabled: true)

        #expect(presentation.appStatus.tone == .success)
        #expect(presentation.appStatus.message == "アプリは最新です。")
        #expect(presentation.toolsStatus.tone == .success)
        #expect(presentation.toolsStatus.message == "ライブラリは最新です。")
        #expect(presentation.primaryButtonTitle == "アップデートを確認")
        #expect(presentation.primaryButtonEnabled)
        #expect(presentation.installButtonDisabled)
    }

    @Test("Aboutはアプリ更新の進捗を表示する")
    func aboutShowsAppProgress() {
        let controller = UpdateCheckController()
        controller.card = .installing(.downloading(received: 25, total: 100))
        let tools = ToolsUpdateController()
        tools.hasCheckedAvailability = true
        let presentation = AboutUpdatePresentation(
            controller: controller, toolsUpdate: tools, language: "ja", updatesEnabled: true)

        #expect(presentation.appStatus.tone == .progress)
        #expect(presentation.appStatus.message == "ダウンロード中...")
        #expect(presentation.appStatus.progress == 0.25)
        #expect(presentation.primaryButtonTitle == "インストール中...")
        #expect(!presentation.primaryButtonEnabled)
        #expect(presentation.installButtonTitle == "インストール中...")
        #expect(presentation.installButtonDisabled)
    }

    @Test("Aboutは再起動待ちと失敗時の操作を切り替える")
    func aboutSwitchesTerminalActions() {
        let app = appInfo()
        let controller = UpdateCheckController()
        controller.card = .readyToRestart(URL(fileURLWithPath: "/tmp/TreeImageOptimizer.app"), app)
        let tools = ToolsUpdateController()
        tools.hasCheckedAvailability = true
        let ready = AboutUpdatePresentation(
            controller: controller, toolsUpdate: tools, language: "ja", updatesEnabled: true)

        #expect(ready.appStatus.tone == .success)
        #expect(ready.primaryButtonTitle == "アプリ再起動する")
        #expect(ready.primaryButtonEnabled)
        #expect(ready.installButtonTitle == "アプリ再起動する")
        #expect(!ready.installButtonDisabled)

        controller.card = .installFailed(app)
        let failed = AboutUpdatePresentation(
            controller: controller, toolsUpdate: tools, language: "ja", updatesEnabled: true)

        #expect(failed.appStatus.tone == .failure)
        #expect(failed.primaryButtonTitle == "再実行")
        #expect(failed.primaryButtonEnabled)
        #expect(failed.installButtonTitle == "再実行")
        #expect(!failed.installButtonDisabled)
    }
}
