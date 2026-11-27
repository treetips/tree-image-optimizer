import Foundation

/// ツール展開の状態。
enum ToolBootstrapPhase {
    case checking
    case ready
    case installing(Double, String)
    case failed(String)
}

/// 初回起動時のツール展開を担うModel。`RootView` のオーバーレイ表示と操作ブロックに使う。
@Observable
@MainActor
final class ToolBootstrapModel {
    var phase: ToolBootstrapPhase = .checking

    private let toolInstaller: ToolInstaller
    private let toolsUpdateService: ToolsUpdateService
    private var started = false

    init(
        toolInstaller: ToolInstaller? = nil,
        toolsUpdateService: ToolsUpdateService? = nil
    ) {
        let installer = toolInstaller ?? ToolInstaller(paths: AppPaths())
        self.toolInstaller = installer
        self.toolsUpdateService = toolsUpdateService ?? ToolsUpdateService(paths: installer.paths)
    }

    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    /// 失敗時に案内するログ出力先。調査手順をユーザーへ示すために使う。
    var logDirectoryURL: URL {
        toolInstaller.paths.logsURL
    }

    /// 初回はtools展開が必要なため、揃うまで操作をブロックする。
    func start() {
        guard !started else { return }
        started = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            if toolInstaller.isInstalled() {
                AppLogger.shared.info("bootstrap: tools already installed")
                phase = .ready
                return
            }
            let onProgress: @Sendable (Double, String) -> Void = { [weak self] fraction, name in
                Task { @MainActor [weak self] in
                    self?.phase = .installing(fraction, name)
                }
            }
            do {
                do {
                    try await toolInstaller.ensureInstalled(progress: onProgress)
                } catch {
                    // Why not ローカル修復の失敗で終了するか: 配布アプリには
                    // 開発用ツールが無いため、tools-latest から不足分を取得する必要がある。
                    AppLogger.shared.info(
                        "bootstrap: local repair failed, falling back to release: \(error.localizedDescription)")
                    let info = try await toolsUpdateService.fetchToolsInfo()
                    _ = try await toolsUpdateService.installMissingTools(
                        info: info, onProgress: onProgress)
                    guard toolInstaller.isInstalled() else {
                        throw AppError.toolMissing("tools release install did not complete")
                    }
                }
                AppLogger.shared.info("bootstrap: ready")
                phase = .ready
            } catch {
                AppLogger.shared.error("bootstrap failed: \(error.localizedDescription)")
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// 失敗時に最初からやり直す。
    func retry() {
        AppLogger.shared.info("bootstrap: retry requested")
        phase = .checking
        started = false
        start()
    }
}
