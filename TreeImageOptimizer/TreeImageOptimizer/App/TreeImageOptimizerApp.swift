import SwiftUI

/// アプリのエントリポイント。
@main
struct TreeImageOptimizerApp: App {
    @State private var updateCheck = UpdateCheckController()
    @State private var settings = SettingsViewModel()
    @State private var navigation = SidebarNavigation()

    init() {
        // 完了通知を使えるよう起動時に許可を求める。拒否時は通知なしになる。
        settings.requestNotificationAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            RootView(navigation: navigation, settings: settings, updateCheck: updateCheck)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(L10n.string("menu.checkForUpdates", language: settings.language)) {
                    updateCheck.checkForUpdate()
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
