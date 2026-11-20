import Foundation

/// ツール更新カードの状態。アプリ本体更新の `UpdateCard` と同型の状態機械を
/// 独立して持つ。差分が無い場合（`noUpdate`）はカード自体を表示しないため、
/// 状態として `noUpdate` は持たず、`card` を nil で表現する。
@MainActor
enum ToolsUpdateCard: Equatable {
    /// ツール更新あり。クリックで確認ダイアログを開く。
    case available(ToolsInfo)
    /// 更新中。確認ダイアログを閉じた後の進捗をサイドナビに表示する。
    case installing(ToolsUpdateProgress)
    /// 更新失敗。背景を赤くし、カード内の `再実行` から最初からやり直せる。
    case installFailed(ToolsInfo)
}

/// ツール更新の進捗。アプリ本体更新の `UpdateInstallProgress` と同様に、
/// ダウンロードは受信バイト数に基づく確定表示、検証・展開は不確定表示で表す。
/// ツール更新は複数ツールを順に処理するため、`label` で現在処理中の段階を示す。
struct ToolsUpdateProgress: Sendable, Equatable {
    /// 0...1。nil の段階は不確定表示にする。
    var fraction: Double?
    /// 現在処理中の段階を示すラベル（例: 検証中・展開中）。
    var label: String

    /// バイト進捗を持たない段階（検証・展開）の不確定表示。
    static func indeterminate(_ label: String) -> ToolsUpdateProgress {
        ToolsUpdateProgress(fraction: nil, label: label)
    }
}

/// ツール更新の状態管理。アプリ本体更新の `UpdateCheckController` を参考に、
/// 起動時の差分判定と「通知 → ユーザー確認 → 更新」のフローを担う。
/// アプリ本体更新とは独立して動作し、同時実行を許可する。
@Observable
@MainActor
final class ToolsUpdateController {
    /// サイドナビ下部のツール更新カード。差分が無ければ nil（カード非表示）。
    var card: ToolsUpdateCard?
    /// 確認ダイアログで表示・使用する更新対象のメタデータ。
    var availableInfo: ToolsInfo?
    /// 更新処理中かどうか。重複実行を防ぐ。
    var isInstalling = false
    /// 更新失敗の詳細理由。エラーダイアログ表示に使う。
    var errorDialog: String?

    private let store: ToolsInfoStore
    private let service: ToolsUpdateService

    init(
        paths: AppPaths = AppPaths(),
        service: ToolsUpdateService? = nil
    ) {
        self.store = ToolsInfoStore(paths: paths)
        self.service = service ?? ToolsUpdateService(paths: paths)
    }

    /// 起動時に `tools-info.json` を取得し、ローカル記録と突き合わせて差分を判定する。
    /// 差分があれば `.available` カードを、無ければカードを出さない（nil）。
    /// ネットワーク到達不能などの失敗時はカードを出さず、既存 tools でフォールバックする。
    func refreshAvailability() {
        guard card == nil, availableInfo == nil, !isInstalling else { return }
        Task {
            do {
                let info = try await service.fetchToolsInfo()
                let installed = store.loadInstalled()
                let updates = store.updatesNeeded(info: info, installed: installed)
                // 差分が無ければカードを出さない。既存の tools をそのまま使う。
                guard !updates.isEmpty else { return }
                card = .available(info)
            } catch {
                // 取得失敗時はカードを出さず、既存 tools でフォールバックする。
                // 差分の有無が分からないため、「更新が無い」と誤解させるカードも出さない。
                AppLogger.shared.info("tools update check failed: \(error.localizedDescription)")
            }
        }
    }

    /// 更新ありカードのクリック。確認ダイアログを開く。
    func showInstallDialog() {
        guard case .available(let info) = card else { return }
        availableInfo = info
    }

    /// 確認ダイアログでキャンセルしたとき。ダイアログを閉じるだけで、カードは残す。
    func dismissInstallDialog() {
        availableInfo = nil
    }

    /// 確認後、差分のあるツールだけを更新する。進捗をカードへ反映し、
    /// 完了でカードを消す。失敗で `.installFailed` へ切り替える。
    func install(_ info: ToolsInfo) {
        guard !isInstalling else { return }
        isInstalling = true
        // 確認ダイアログを閉じ、以降の進捗はサイドナビのカードだけで示す。
        availableInfo = nil
        card = .installing(.indeterminate(""))
        let installed = store.loadInstalled()
        Task {
            let onProgress: @Sendable (Double, String) -> Void = { [weak self] fraction, label in
                Task { @MainActor [weak self] in
                    self?.applyProgress(fraction: fraction, label: label)
                }
            }
            do {
                // `ToolsUpdateService.updateTools` が `.installed.json` への保存まで行う。
                // コントローラ側では状態の切り替えだけを担う。
                _ = try await service.updateTools(
                    info: info, installed: installed, onProgress: onProgress)
                card = nil
            } catch {
                // 失敗時は赤いカードに切り替え、カード内の `再実行` で最初からやり直せるようにする。
                card = .installFailed(info)
                errorDialog = error.localizedDescription
            }
            isInstalling = false
        }
    }

    /// 失敗カードの `再実行`。ダウンロードからやり直す。
    func retryInstall() {
        guard case .installFailed(let info) = card else { return }
        install(info)
    }

    /// 進捗をカードへ反映する。遅れて届いたダウンロード進捗が、
    /// 検証・展開へ進んだ表示を巻き戻さないよう、不確定表示へ進んだ後の
    /// 確定値への後退は無視する。
    private func applyProgress(fraction: Double?, label: String) {
        guard isInstalling, case .installing(let current) = card else { return }
        // 不確定表示（fraction=nil）へ進んだ後の確定値への後退は無視する。
        if current.fraction == nil, fraction != nil { return }
        card = .installing(ToolsUpdateProgress(fraction: fraction, label: label))
    }
}
