import Foundation

/// ツール更新カードの状態。アプリ本体更新の `UpdateCard` と同型の状態機械を
/// 独立して持つ。差分が無い場合（`noUpdate`）はカード自体を表示しないため、
/// 状態として `noUpdate` は持たず、`card` を nil で表現する。
@MainActor
enum ToolsUpdateCard: Equatable {
    /// ツール更新あり。共通の更新ボタンからインストールを始める。
    case available(ToolsInfo)
    /// 更新中。進捗をヘッダーに表示する。
    case installing(ToolsUpdateProgress)
    /// 更新失敗。背景を赤くし、カード内の `再実行` から最初からやり直せる。
    case installFailed(ToolsInfo)
}

/// ツール更新の進捗。複数ツールを順に処理するため、完了ツール数に基づく
/// 確定表示と、現在のツール名を示す `label` で表す。
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
/// 起動時の差分判定と更新実行を担う。実行順序はヘッダーの共通更新ボタンが調整する。
@Observable
@MainActor
final class ToolsUpdateController {
    /// ヘッダーの更新カード。差分が無ければ nil（カード非表示）。
    var card: ToolsUpdateCard?
    /// 更新処理中かどうか。重複実行を防ぐ。
    var isInstalling = false
    /// 更新情報を確認中かどうか。ヘッダーの確認中表示に使う。
    var isChecking = false
    /// 起動時の更新確認が1回でも完了したか。未確認の間はアプリだけの更新文言を出さない。
    var hasCheckedAvailability = false
    /// 更新確認に失敗したか。失敗時はツールの有無を「なし」と誤認しない。
    var availabilityCheckFailed = false
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
        guard card == nil, !isInstalling, !isChecking else { return }
        isChecking = true
        availabilityCheckFailed = false
        Task {
            defer {
                isChecking = false
                hasCheckedAvailability = true
            }
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
                availabilityCheckFailed = true
                AppLogger.shared.info("tools update check failed: \(error.localizedDescription)")
            }
        }
    }

    /// 差分のあるツールだけを更新する。進捗をカードへ反映し、
    /// 完了でカードを消す。失敗で `.installFailed` へ切り替える。
    /// - Parameter completion: 成否の通知。アプリとツールの順序実行に使う。
    func install(_ info: ToolsInfo, completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        guard !isInstalling else {
            completion(false)
            return
        }
        isInstalling = true
        // Why not 不確定（fraction=nil）から始めるか: applyProgress の
        // ガードは「不確定へ進んだ後の確定値への後退」を無視するため、
        // 先頭を nil にすると以後の確定進捗がすべて破棄され、バーが
        // 不確定のままになる。確定 0 から始める。
        card = .installing(ToolsUpdateProgress(fraction: 0, label: ""))
        let installed = store.loadInstalled()
        Task { [weak self] in
            guard let self else { return }
            let onProgress: @Sendable (Double, String) -> Void = { [weak self] fraction, label in
                Task { @MainActor [weak self] in
                    self?.applyProgress(fraction: fraction, label: label)
                }
            }
            var succeeded = false
            do {
                // `ToolsUpdateService.updateTools` が `.installed.json` への保存まで行う。
                // コントローラ側では状態の切り替えだけを担う。
                _ = try await service.updateTools(
                    info: info, installed: installed, onProgress: onProgress)
                card = nil
                succeeded = true
            } catch {
                // 失敗時は赤いカードに切り替え、カード内の `再実行` で最初からやり直せるようにする。
                card = .installFailed(info)
                errorDialog = error.localizedDescription
            }
            isInstalling = false
            completion(succeeded)
        }
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
