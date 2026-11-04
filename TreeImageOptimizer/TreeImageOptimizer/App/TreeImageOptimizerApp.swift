import SwiftUI

/// アプリのエントリポイント。
@main
struct TreeImageOptimizerApp: App {
    @State private var updateCheck = UpdateCheckController()
    @State private var settings = SettingsViewModel()
    @State private var navigation = SidebarNavigation()
    @State private var convertJobStore = ConvertJobStore()
    @State private var easyConvertJobStore = EasyConvertJobStore()

    init() {
        // 起動直後のツール展開や変換コマンドの失敗を追えるよう、最初にファイルログを開く。
        let paths = AppPaths()
        AppLogger.shared.configure(directoryURL: paths.logsURL)
        AppLogger.shared.info(
            "app launch: version=\(AppInfo.bundleVersion) base=\(paths.projectDirectoryURL.path)"
        )
        // 完了通知を使えるよう起動時に許可を求める。拒否時は通知なしになる。
        settings.requestNotificationAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                navigation: navigation, settings: settings, updateCheck: updateCheck,
                convertJobStore: convertJobStore, easyConvertJobStore: easyConvertJobStore
            )
            .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 900, height: 900)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L10n.string("menu.checkForUpdates", language: settings.language)) {
                    updateCheck.checkForUpdate(language: settings.language)
                }
                .disabled(updateCheck.isChecking)
                Button(L10n.string("menu.settings", language: settings.language)) {
                    navigation.selection = .settings
                }
                .keyboardShortcut(",")
                Divider()
            }
        }
    }
}
