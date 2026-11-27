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
}
