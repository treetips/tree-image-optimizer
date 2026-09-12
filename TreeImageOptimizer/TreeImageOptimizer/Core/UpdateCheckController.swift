import Foundation

/// アップデート確認の共通コントローラ。
/// About画面のボタン・OSメニューバーの「更新を確認」・サイドナビ通知から共用する。
/// 文言は設定言語に従う。
@Observable
@MainActor
final class UpdateCheckController {
    var isChecking = false
    var message = ""
    var latestDialog = false
    var availableInfo: UpdateInfo?
    var errorDialog: String?
    /// サイドナビ通知用のサイレント確認結果。ダイアログは出さない。
    var updateAvailableInfo: UpdateInfo?

    private let updateService = UpdateService()

    private func language() -> String {
        let paths = AppPaths()
        let maxParallel = max(1, ProcessInfo.processInfo.processorCount)
        return (try? SettingsStore(paths: paths).load(maxParallel: maxParallel).settings.language) ?? ""
    }

    private func currentVersion() -> (version: String, build: Int) {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1") ?? 1
        return (version, build)
    }

    /// 起動時などにダイアログなしで有無だけ確認し、サイドナビ通知に反映する。
    func refreshAvailability() {
        Task {
            let current = currentVersion()
            let result = await updateService.checkForUpdate(
                url: AppInfo.updateInfoURL,
                currentVersion: current.version,
                currentBuild: current.build
            )
            if case .available(let info) = result {
                updateAvailableInfo = info
            } else {
                updateAvailableInfo = nil
            }
        }
    }

    func checkForUpdate() {
        guard !isChecking else { return }
        isChecking = true
        message = ""
        Task {
            let lang = language()
            let bundle = Bundle.main
            let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
            let build = Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1") ?? 1
            let result = await updateService.checkForUpdate(
                url: AppInfo.updateInfoURL, currentVersion: version, currentBuild: build
            )
            switch result {
            case .latest:
                message = L10n.string("a.latest", language: lang)
                latestDialog = true
            case .available(let info):
                message = String(format: L10n.string("a.availableMsg", language: lang), info.version)
                availableInfo = info
            case .failed(let reason):
                message = "\(L10n.string("a.checkFailed", language: lang)): \(reason)"
                errorDialog = reason
            }
            isChecking = false
        }
    }

    func install(_ info: UpdateInfo) {
        isChecking = true
        Task {
            let lang = language()
            do {
                let appURL = try await updateService.downloadAndPrepare(info: info)
                message = String(format: L10n.string("a.downloadDoneMsg", language: lang), appURL.path)
            } catch {
                message = "\(L10n.string("a.downloadFailed", language: lang)): \(error.localizedDescription)"
                errorDialog = error.localizedDescription
            }
            isChecking = false
        }
    }
}
