import AppKit
import Foundation

/// アップデート確認の共通コントローラ。
/// About画面のボタン・OSメニューバーの「更新を確認」・サイドナビ通知から共用する。
/// 文言は設定言語に従う。
/// サイドナビ下部の更新カードの状態。ネットワーク確認の有無をUIと切り離すため独立させる。
@MainActor
enum UpdateCard: Equatable {
    /// 更新あり。クリックでインストールダイアログを開く。
    case available(UpdateInfo)
    /// 更新なし。クリックでカードを非表示化する。
    case noUpdate
}

@Observable
@MainActor
final class UpdateCheckController {
    /// 更新なしカードの自動非表示までの秒数。仕様は docs/design/feature/update-application.md。
    static let noUpdateCardHideSeconds: Int64 = 10

    var isChecking = false
    var isInstalling = false
    var message = ""
    var latestDialog = false
    var availableInfo: UpdateInfo?
    var errorDialog: String?
    /// サイドナビ下部の更新カード。起動時のサイレント確認結果を反映する。
    var card: UpdateCard?

    private var hideCardTask: Task<Void, Never>?
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

    /// 起動時などにダイアログなしで有無だけ確認し、サイドナビの更新カードに反映する。
    func refreshAvailability() {
        Task {
            let current = currentVersion()
            let result = await updateService.checkForUpdate(
                url: AppInfo.updateInfoURL,
                currentVersion: current.version,
                currentBuild: current.build
            )
            setCard(Self.resolveCard(for: result))
        }
    }

    /// 確認結果をカード状態に解決する。更新の有無に応じて表示文言が変わる。
    // テストから直接検証できるよう純粋関数として切り出す。
    static func resolveCard(for result: UpdateCheckResult) -> UpdateCard {
        if case .available(let info) = result { return .available(info) }
        return .noUpdate
    }

    /// カードを差し替える。更新なしカードは10秒後に自動で非表示化する。
    /// クリック等で先に非表示になった後のタイマー発火を防ぐため、差し替え時に必ず旧タイマーを止める。
    private func setCard(_ newCard: UpdateCard) {
        hideCardTask?.cancel()
        hideCardTask = nil
        card = newCard
        if case .noUpdate = newCard {
            hideCardTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(Self.noUpdateCardHideSeconds))
                } catch {
                    // キャンセルまたは差し替え時はタイマーを終えるだけ。
                    return
                }
                self?.card = nil
            }
        }
    }

    /// 更新ありカードのクリック。サイレント確認結果を元にインストール確認ダイアログを出す。
    func showInstallDialog() {
        guard case .available(let info) = card else { return }
        availableInfo = info
    }

    /// 更新なしカードのクリック。自動非表示のタイマーも止める。
    func dismissCard() {
        hideCardTask?.cancel()
        hideCardTask = nil
        card = nil
    }

    func checkForUpdate(language: String? = nil) {
        guard !isChecking else { return }
        isChecking = true
        message = ""
        Task {
            // 呼び出し元が保持済みの言語を渡す。nil時のみ設定ファイルを読み直す。
            let lang = language ?? self.language()
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

    /// ダウンロード・検証・展開のうえ、`/Applications` に反映する。
    /// 実行中のアプリ自身の更新なら新バージョンを開いて終了する。
    /// それ以外（開発ビルド等）はFinderで開いて終わる。
    func install(_ info: UpdateInfo, language: String? = nil) {
        guard !isInstalling else { return }
        isInstalling = true
        Task {
            // 呼び出し元が保持済みの言語を渡す。nil時のみ設定ファイルを読み直す。
            let lang = language ?? self.language()
            do {
                let prepared = try await updateService.downloadAndPrepare(info: info)
                let destination = UpdateService.installDestination(for: prepared)
                try updateService.applyUpdate(preparedApp: prepared, destination: destination)
                // 実行中のアプリ自身なら新バージョンを開いて終了する。
                // 起動要求に失敗したらFinderで開いて終わる。
                if isRunningFrom(destination), relaunch(appURL: destination) { return }
                message = String(
                    format: L10n.string("a.downloadDoneMsg", language: lang), destination.path)
                revealInFinder(destination)
            } catch {
                message = "\(L10n.string("a.downloadFailed", language: lang)): \(error.localizedDescription)"
                errorDialog = error.localizedDescription
            }
            isInstalling = false
        }
    }

    /// 実行中のバンドルがインストール先と同一か。
    private func isRunningFrom(_ destination: URL) -> Bool {
        Bundle.main.bundleURL.standardizedFileURL.path == destination.standardizedFileURL.path
    }

    /// 新バージョンを別プロセスで開いて旧プロセスを終了する。
    /// 同一bundle IDのため新インスタンス生成を明示しないと、実行中の旧プロセスが
    /// 前面化されて終了時に「すでに閉じられています」ダイアログが出る。
    /// - Returns: 起動要求に成功したらtrue。
    @discardableResult
    private func relaunch(appURL: URL) -> Bool {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        guard NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) != nil else {
            return false
        }
        // 新インスタンスの起動を待ってから終了する。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSApplication.shared.terminate(nil)
        }
        return true
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
