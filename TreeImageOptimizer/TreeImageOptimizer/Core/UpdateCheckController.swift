import AppKit
import Foundation

/// アップデート確認の共通コントローラ。
/// About画面のボタン・OSメニューバーの「更新を確認」・サイドナビ通知から共用する。
/// 文言は設定言語に従う。
/// サイドナビ下部の更新カードの状態。ネットワーク確認の有無をUIと切り離すため独立させる。
@MainActor
enum UpdateCard: Equatable {
    /// 更新あり。カード内の Download ボタンからインストールを始める。
    case available(UpdateInfo)
    /// インストール中。カード内に進捗を表示する。
    case installing(UpdateInstallProgress)
    /// 再起動用の準備が完了。緑色のカードから配置と新しいアプリの起動を行う。
    case readyToRestart(URL, UpdateInfo)
    /// インストール失敗。背景を赤くし、カード内の `再実行` から最初からやり直せる。
    case installFailed(UpdateInfo)
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
    var isRestarting = false
    var isCleaningStagedUpdate = false
    var message = ""
    var latestDialog = false
    var errorDialog: String?
    var restartErrorDialog: String?
    /// サイドナビ下部の更新カード。起動時のサイレント確認と手動確認の結果を反映する。
    var card: UpdateCard?

    /// 再起動待ちの間は、更新確認で緑色の完了カードを上書きしない。
    var isReadyToRestart: Bool {
        if case .readyToRestart = card { return true }
        return false
    }

    /// メニュー・About画面の更新確認ボタンで共通する実行可否。
    var canCheckForUpdates: Bool {
        !isChecking && !isInstalling && !isRestarting && !isCleaningStagedUpdate && !isReadyToRestart
    }

    private var hideCardTask: Task<Void, Never>?
    private let updateService = UpdateService()

    private func language() -> String {
        let paths = AppPaths()
        let maxParallel = max(1, HardwareInfo.performanceCoreCount())
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
        // カードが残っている間に掃除すると、Download と削除が競合し得るため初期状態だけを対象にする。
        guard canCheckForUpdates, card == nil else { return }
        isCleaningStagedUpdate = true
        Task {
            // 数百MBの削除で起動直後のUIを止めないよう、確認開始前に別タスクで掃除する。
            // 先行タスクを待つことで、掃除が新しいステージングを消す競合も防ぐ。
            let service = updateService
            await Task.detached(priority: .utility) {
                service.cleanupStagedUpdate()
            }.value
            isCleaningStagedUpdate = false
            guard canCheckForUpdates else { return }
            let current = currentVersion()
            let result = await service.checkForUpdate(
                url: AppInfo.updateInfoURL,
                currentVersion: current.version,
                currentBuild: current.build
            )
            // 確認中にインストールが始まった場合は、古い確認結果で進捗・完了カードを上書きしない。
            guard !isInstalling, !isRestarting, !isReadyToRestart else { return }
            setCard(Self.resolveCard(for: result))
        }
    }

    /// 確認結果をカード状態に解決する。更新の有無に応じて表示文言が変わる。
    /// テストから直接検証できるよう純粋関数として切り出す。
    static func resolveCard(for result: UpdateCheckResult) -> UpdateCard {
        if case .available(let info) = result { return .available(info) }
        return .noUpdate
    }

    /// 手動確認（About画面のボタン・メニューバー）の結果をカード状態に解決する。
    /// 失敗時は更新の有無が分からないためnilとし、カードを現状のままにする。
    /// 「更新なし」カードを出すと、同時に表示される失敗アラートと食い違って
    /// 「更新が無い」と誤解されるため。
    /// テストから直接検証できるよう純粋関数として切り出す。
    static func resolveManualCard(for result: UpdateCheckResult) -> UpdateCard? {
        if case .failed = result { return nil }
        return resolveCard(for: result)
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

    /// 更新ありカードの Download ボタン。確認ダイアログを挟まず、そのままダウンロードを始める。
    func startDownload(_ info: UpdateInfo, language: String? = nil) {
        install(info, language: language)
    }

    /// 更新なしカードのクリック。自動非表示のタイマーも止める。
    func dismissCard() {
        hideCardTask?.cancel()
        hideCardTask = nil
        card = nil
    }

    /// About画面のボタンとメニューバーの手動確認。
    /// 更新なし・失敗時はダイアログとメッセージに出し、更新ありはサイドナビのカードで知らせる。
    func checkForUpdate(language: String? = nil) {
        guard canCheckForUpdates else { return }
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
            // 確認中にインストールへ進んだ場合は、古い結果でダイアログや進捗・完了カードを上書きしない。
            guard !isInstalling, !isRestarting, !isReadyToRestart else {
                isChecking = false
                return
            }
            switch result {
            case .latest:
                message = L10n.string("a.latest", language: lang)
                latestDialog = true
            case .available(let info):
                message = String(format: L10n.string("a.availableMsg", language: lang), info.version)
            case .failed(let reason):
                message = "\(L10n.string("a.checkFailed", language: lang)): \(reason)"
                errorDialog = reason
            }
            // 手動確認の結果をサイドナビ下部の更新カードにも反映する。
            // 失敗時はnilのためカードを触らず、直前の確認結果を表示したままにする。
            if let card = Self.resolveManualCard(for: result) {
                setCard(card)
            }
            isChecking = false
        }
    }

    /// ダウンロード・検証・展開を行い、再起動用にアプリをステージングする。
    /// `/Applications` の置換は再起動ボタン押下時まで遅らせる。
    func install(_ info: UpdateInfo, language: String? = nil) {
        guard !isInstalling, !isRestarting, !isCleaningStagedUpdate, !isReadyToRestart else { return }
        isInstalling = true
        hideCardTask?.cancel()
        hideCardTask = nil
        card = .installing(.indeterminate(.downloading))
        // 呼び出し元が保持済みの言語を渡す。nil時のみ設定ファイルを読み直す。
        let lang = language ?? self.language()
        Task {
            let onProgress: @Sendable (UpdateInstallProgress) -> Void = { progress in
                Task { @MainActor in
                    self.applyProgress(progress)
                }
            }
            do {
                let prepared = try await updateService.downloadAndPrepare(info: info, onProgress: onProgress)
                card = .installing(.indeterminate(.installing))
                // 数百MBの移動でメインスレッドを止めないよう、別タスクで実行する。
                // 実行中の /Applications のバンドルは、再起動まで先に置換しない。
                let staged = try await Task.detached(priority: .userInitiated) {
                    try UpdateService().stageForRestart(preparedApp: prepared)
                }.value
                // 自動再起動すると完了状態を確認できないため、ここで一旦停止する。
                // 以後はカードの「アプリ再起動する」から配置と起動を切り替える。
                card = .readyToRestart(staged, info)
                message = L10n.string("a.restartReadyMsg", language: lang)
            } catch {
                // 失敗時は赤いカードに切り替え、カード内の `再実行` で最初からやり直せるようにする。
                card = .installFailed(info)
                message = "\(L10n.string("a.downloadFailed", language: lang)): \(error.localizedDescription)"
                errorDialog = error.localizedDescription
            }
            isInstalling = false
        }
    }

    /// 緑色の完了カードの「アプリ再起動する」。ステージングしたアプリを配置して起動し、旧プロセスを終了する。
    func restart(language: String? = nil) {
        guard !isRestarting, case .readyToRestart(let stagedAppURL, let info) = card else { return }
        isRestarting = true
        let lang = language ?? self.language()
        Task {
            var installedAppURL: URL?
            do {
                let destination = UpdateService.installDestination(for: stagedAppURL)
                // 起動だけ失敗して再試行する場合は、配置済みアプリを再度 Trash しない。
                if stagedAppURL.standardizedFileURL.path != destination.standardizedFileURL.path {
                    // 実行中のバンドルを置換するのは、ユーザーが再起動を選んだ後だけに限定する。
                    _ = try await Task.detached(priority: .userInitiated) {
                        try UpdateService().applyUpdate(preparedApp: stagedAppURL, destination: destination)
                    }.value
                }
                installedAppURL = destination
                // フェイルセーフで再試行された場合に配置を繰り返さないよう、カードも配置先へ更新する。
                card = .readyToRestart(destination, info)
                try await relaunch(appURL: destination)
            } catch {
                AppLogger.shared.error(
                    "restart failed: \(error.localizedDescription) (\(stagedAppURL.path))")
                isRestarting = false
                if let installedAppURL {
                    // 配置は済んでいるため、再ダウンロードさせず起動だけを再試行できる。
                    card = .readyToRestart(installedAppURL, info)
                } else {
                    card = .installFailed(info)
                }
                let title = L10n.string("a.restartFailed", language: lang)
                message = "\(title): \(error.localizedDescription)"
                restartErrorDialog = error.localizedDescription
                return
            }
            // 終了が実行されなかった場合に、再起動中のまま操作を固めないためのフェイルセーフ。
            try? await Task.sleep(for: .seconds(10))
            isRestarting = false
        }
    }

    /// 失敗カードの `再実行`。ダウンロードからやり直す。
    func retryInstall(language: String? = nil) {
        guard case .installFailed(let info) = card else { return }
        install(info, language: language)
    }

    /// 進捗をカードへ反映する。遅れて届いたダウンロード進捗が、
    /// 検証・展開へ進んだ表示を巻き戻さないよう段階の後退は無視する。
    private func applyProgress(_ progress: UpdateInstallProgress) {
        guard isInstalling, case .installing(let current) = card, current.phase <= progress.phase else { return }
        card = .installing(progress)
    }

    /// 新バージョンを別プロセスで開いて旧プロセスを終了する。
    /// 同一bundle IDのため新インスタンス生成を明示しないと、実行中の旧プロセスが
    /// 前面化されて終了時に「すでに閉じられています」ダイアログが出る。
    private func relaunch(appURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        // 新インスタンスの起動を待ってから終了する。
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSApplication.shared.terminate(nil)
        }
    }
}
