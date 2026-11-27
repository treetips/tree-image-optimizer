import Foundation

/// ヘッダー右端の更新表示を、アプリとツールの状態から1つに解決した結果。
@MainActor
enum UpdateToolbarState: Equatable {
    case hidden
    case checking
    case available(UpdateAvailability)
    case appInstalling(UpdateInstallProgress)
    case toolsInstalling(ToolsUpdateProgress)
    case readyToRestart
    case appInstallFailed(UpdateInfo)
    case toolsInstallFailed(ToolsInfo)
    case noUpdate
}

/// 更新ボタンから実行できる更新の組み合わせ。
@MainActor
enum UpdateAvailability: Equatable {
    case app(UpdateInfo)
    case tools(ToolsInfo)
    case appAndTools(UpdateInfo, ToolsInfo)

    var labelKey: String {
        switch self {
        case .app: return "nav.appUpdateAvailable"
        case .tools: return "nav.toolsUpdateAvailable"
        case .appAndTools: return "nav.appAndToolsUpdateAvailable"
        }
    }

    var systemImage: String {
        switch self {
        case .app, .appAndTools: return "arrow.down.circle.fill"
        case .tools: return "shippingbox.and.arrow.backward.fill"
        }
    }
}

/// アプリとツールの更新状態を共通の表示・実行計画へ変換する。
@MainActor
enum UpdateToolbarResolver {
    static func resolve(
        appCard: UpdateCard?,
        toolsCard: ToolsUpdateCard?,
        isChecking: Bool,
        toolsCheckCompleted: Bool,
        checkFailures: (app: Bool, tools: Bool)
    ) -> UpdateToolbarState {
        if let terminal = terminalState(appCard: appCard, toolsCard: toolsCard) {
            return terminal
        }
        if isChecking || !toolsCheckCompleted { return .checking }
        let availability = availabilityState(appCard: appCard, toolsCard: toolsCard)
        if case .available = availability { return availability }
        // 片方の確認失敗で、もう片方で確認済みの更新まで消さない。
        // 「更新なし」は両方の確認が成功した場合だけ表示する。
        if checkFailures.app || checkFailures.tools { return .hidden }
        return availability
    }

    private static func terminalState(
        appCard: UpdateCard?,
        toolsCard: ToolsUpdateCard?
    ) -> UpdateToolbarState? {
        // 実行中は失敗カードより優先し、再実行ボタンを連打できないようにする。
        if case .installing(let progress) = appCard { return .appInstalling(progress) }
        if case .installing(let progress) = toolsCard { return .toolsInstalling(progress) }
        if case .readyToRestart = appCard { return .readyToRestart }
        if case .installFailed(let info) = appCard { return .appInstallFailed(info) }
        if case .installFailed(let info) = toolsCard { return .toolsInstallFailed(info) }
        return nil
    }

    private static func availabilityState(
        appCard: UpdateCard?,
        toolsCard: ToolsUpdateCard?
    ) -> UpdateToolbarState {
        switch (appCard, toolsCard) {
        case (.available(let appInfo), .available(let toolsInfo)):
            return .available(.appAndTools(appInfo, toolsInfo))
        case (.available(let appInfo), _):
            return .available(.app(appInfo))
        case (_, .available(let toolsInfo)):
            return .available(.tools(toolsInfo))
        case (.noUpdate, _):
            return .noUpdate
        default:
            return .hidden
        }
    }

    static func plan(for availability: UpdateAvailability) -> UpdateInstallPlan {
        switch availability {
        case .app(let info): return .app(info)
        case .tools(let info): return .tools(info)
        case .appAndTools(let appInfo, let toolsInfo): return .toolsThenApp(appInfo, toolsInfo)
        }
    }

    /// 失敗済みの更新を再実行するための計画。利用可能な更新も未完了として扱う。
    static func retryPlan(appCard: UpdateCard?, toolsCard: ToolsUpdateCard?) -> UpdateInstallPlan {
        let app: UpdateInfo?
        switch appCard {
        case .installFailed(let info), .available(let info): app = info
        default: app = nil
        }
        let tools: ToolsInfo?
        switch toolsCard {
        case .installFailed(let info), .available(let info): tools = info
        default: tools = nil
        }
        if let app, let tools { return .toolsThenApp(app, tools) }
        if let app { return .app(app) }
        if let tools { return .tools(tools) }
        return .none
    }
}

/// 更新ボタンが実行する計画。両方ある場合はツールを先に完了させる。
@MainActor
enum UpdateInstallPlan: Equatable {
    case none
    case app(UpdateInfo)
    case tools(ToolsInfo)
    case toolsThenApp(UpdateInfo, ToolsInfo)
}
