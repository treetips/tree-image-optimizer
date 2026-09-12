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
    private var started = false

    init(toolInstaller: ToolInstaller? = nil) {
        self.toolInstaller = toolInstaller ?? ToolInstaller(paths: AppPaths())
    }

    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    /// 初回はtools展開が必要なため、揃うまで操作をブロックする。
    func start() {
        guard !started else { return }
        started = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            if toolInstaller.isInstalled() {
                phase = .ready
                return
            }
            do {
                try await toolInstaller.ensureInstalled { [weak self] fraction, name in
                    Task { @MainActor [weak self] in
                        self?.phase = .installing(fraction, name)
                    }
                }
                phase = .ready
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// 失敗時に最初からやり直す。
    func retry() {
        phase = .checking
        started = false
        start()
    }
}
