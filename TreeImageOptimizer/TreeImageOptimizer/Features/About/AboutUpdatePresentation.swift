import SwiftUI

/// Aboutの更新カードに必要な状態と操作を1つにまとめる。
@MainActor
struct AboutUpdatePresentation {
    let controller: UpdateCheckController
    let toolsUpdate: ToolsUpdateController?
    let language: String
    let updatesEnabled: Bool

    var isChecking: Bool {
        controller.isChecking || controller.isCleaningStagedUpdate || toolsUpdate?.isChecking == true
    }

    var canCheckForUpdates: Bool {
        if case .appInstalling = resolvedUpdateState { return false }
        if case .toolsInstalling = resolvedUpdateState { return false }
        return controller.canCheckForUpdates && toolsUpdate?.isChecking != true && toolsUpdate?.isInstalling != true
            && !isChecking
    }

    var appStatus: AboutUpdateStatus {
        if controller.isChecking || controller.isCleaningStagedUpdate {
            return checkingStatus
        }
        if let card = appCardForAbout {
            switch card {
            case .available(let info):
                let message = String(format: t("a.update.appAvailable"), info.version)
                return AboutUpdateStatus(message: message, tone: .warning)
            case .installing(let progress):
                return AboutUpdateStatus(
                    message: appInstallMessage(progress),
                    tone: .progress,
                    progress: progress.fraction
                )
            case .readyToRestart:
                return AboutUpdateStatus(message: t("nav.updateReady"), tone: .success)
            case .installFailed:
                return AboutUpdateStatus(message: t("nav.installFailed"), tone: .failure)
            case .noUpdate:
                break
            }
        }
        if controller.availabilityCheckFailed {
            return failedCheckStatus
        }
        if controller.hasCheckedAvailability {
            return AboutUpdateStatus(message: t("a.update.appLatest"), tone: .success)
        }
        return uncheckedStatus
    }

    var toolsStatus: AboutUpdateStatus {
        guard let toolsUpdate else { return uncheckedStatus }
        if toolsUpdate.isChecking {
            return checkingStatus
        }
        if let card = toolsCardForAbout {
            switch card {
            case .available:
                return AboutUpdateStatus(message: t("a.update.librariesAvailable"), tone: .warning)
            case .installing(let progress):
                let message = progress.label.isEmpty ? t("nav.installing") : "\(t("nav.installing")) \(progress.label)"
                return AboutUpdateStatus(
                    message: message,
                    tone: .progress,
                    progress: progress.fraction
                )
            case .installFailed:
                return AboutUpdateStatus(message: t("nav.installFailed"), tone: .failure)
            }
        }
        if toolsUpdate.availabilityCheckFailed {
            return failedCheckStatus
        }
        if toolsUpdate.hasCheckedAvailability {
            return AboutUpdateStatus(message: t("a.update.librariesLatest"), tone: .success)
        }
        return uncheckedStatus
    }

    var installButtonTitle: String {
        if controller.isRestarting { return t("a.restarting") }
        switch resolvedUpdateState {
        case .readyToRestart:
            return t("nav.restart")
        case .appInstallFailed, .toolsInstallFailed:
            return t("nav.retry")
        case .appInstalling, .toolsInstalling:
            return t("a.installing")
        default:
            break
        }
        if controller.isInstalling || toolsUpdate?.isInstalling == true { return t("a.installing") }
        if isChecking { return t("a.checking") }
        return t("a.install")
    }

    var installButtonDisabled: Bool {
        switch updateAction {
        case .restart:
            return controller.isRestarting
        case .install(let plan):
            return !updatesEnabled || isChecking || plan == .none || controller.isInstalling
                || toolsUpdate?.isInstalling == true
        case .none:
            return true
        }
    }

    /// 下部の操作スロット。更新が無い場合は確認、更新があればインストールへ切り替える。
    var primaryButtonTitle: String {
        switch updateAction {
        case .none:
            if case .appInstalling = resolvedUpdateState { return t("a.installing") }
            if case .toolsInstalling = resolvedUpdateState { return t("a.installing") }
            if controller.isInstalling || toolsUpdate?.isInstalling == true { return t("a.installing") }
            if isChecking { return t("a.checking") }
            return t("a.check")
        case .install, .restart:
            return installButtonTitle
        }
    }

    var primaryButtonEnabled: Bool {
        switch updateAction {
        case .none:
            return canCheckForUpdates
        case .install, .restart:
            return !installButtonDisabled
        }
    }

    var primaryButtonTint: Color {
        switch updateAction {
        case .none:
            return .accentColor
        case .install, .restart:
            return .green
        }
    }

    var detailMessage: String? {
        let appFailure: Bool
        if case .installFailed = controller.card {
            appFailure = true
        } else {
            appFailure = false
        }
        let shouldShowAppMessage =
            controller.isReadyToRestart || controller.availabilityCheckFailed || appFailure
        if shouldShowAppMessage && !controller.message.isEmpty {
            return controller.message
        }
        if let toolsUpdate {
            if toolsUpdate.availabilityCheckFailed, let reason = toolsUpdate.checkFailureReason {
                return "\(t("a.checkFailed")): \(reason)"
            }
            if case .installFailed = toolsUpdate.card, let reason = toolsUpdate.errorDialog {
                return "\(t("nav.installFailed")): \(reason)"
            }
        }
        return nil
    }

    func checkForUpdates() {
        controller.checkForUpdate(language: language)
        toolsUpdate?.checkForUpdates()
    }

    func performPrimaryAction() {
        switch updateAction {
        case .none:
            checkForUpdates()
        case .install, .restart:
            performUpdateAction()
        }
    }

    func performUpdateAction() {
        switch updateAction {
        case .install(let plan):
            guard updatesEnabled else { return }
            if let toolsUpdate {
                plan.perform(updateCheck: controller, toolsUpdate: toolsUpdate, language: language)
            } else if case .app(let info) = plan {
                controller.startDownload(info, language: language)
            }
        case .restart:
            controller.restart(language: language)
        case .none:
            return
        }
    }

    private var uncheckedStatus: AboutUpdateStatus {
        AboutUpdateStatus(message: t("a.update.notChecked"), tone: .neutral)
    }

    private var checkingStatus: AboutUpdateStatus {
        AboutUpdateStatus(message: t("a.checking"), tone: .progress)
    }

    private var failedCheckStatus: AboutUpdateStatus {
        AboutUpdateStatus(message: t("a.checkFailed"), tone: .failure)
    }

    private func appInstallMessage(_ progress: UpdateInstallProgress) -> String {
        switch progress.phase {
        case .downloading: return t("nav.downloading")
        case .verifying: return t("nav.verifying")
        case .extracting: return t("nav.extracting")
        case .installing: return t("nav.preparingUpdate")
        }
    }

    /// ヘッダーカードが自動非表示・手動削除された後も、最後に確認した更新をAboutへ残す。
    private var appCardForAbout: UpdateCard? {
        if let card = controller.card {
            switch card {
            case .available, .installing, .readyToRestart, .installFailed:
                return card
            case .noUpdate:
                break
            }
        }
        return controller.knownAvailableUpdate.map { .available($0) } ?? controller.card
    }

    private var toolsCardForAbout: ToolsUpdateCard? {
        guard let toolsUpdate else { return nil }
        if let card = toolsUpdate.card { return card }
        return toolsUpdate.knownAvailableUpdate.map { .available($0) }
    }

    private var resolvedUpdateState: UpdateToolbarState {
        UpdateToolbarResolver.resolve(
            appCard: appCardForAbout,
            toolsCard: toolsCardForAbout,
            isChecking: isChecking,
            toolsCheckCompleted: toolsUpdate?.hasCheckedAvailability ?? true,
            checkFailures: (
                app: controller.availabilityCheckFailed,
                tools: toolsUpdate?.availabilityCheckFailed ?? false
            )
        )
    }

    private var updateAction: AboutUpdateAction {
        switch resolvedUpdateState {
        case .available(let availability):
            return .install(UpdateToolbarResolver.plan(for: availability))
        case .appInstallFailed, .toolsInstallFailed:
            let plan = UpdateToolbarResolver.retryPlan(
                appCard: appCardForAbout,
                toolsCard: toolsCardForAbout
            )
            return plan == .none ? .none : .install(plan)
        case .readyToRestart:
            return .restart
        default:
            return .none
        }
    }

    private func t(_ key: String) -> String {
        L10n.string(key, language: language)
    }
}

@MainActor
private enum AboutUpdateAction: Equatable {
    case install(UpdateInstallPlan)
    case restart
    case none
}

struct AboutUpdateStatus {
    enum Tone: Equatable {
        case neutral
        case progress
        case warning
        case success
        case failure
    }

    let message: String
    let tone: Tone
    var progress: Double?
}

struct AboutUpdateStatusBadge: View {
    let status: AboutUpdateStatus

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 7) {
            statusIcon
            Text(status.message)
                .appFont(.subheadline)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let progress = status.progress {
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .appFont(.caption)
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(tint.opacity(0.4), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if status.tone == .progress {
            if let progress = status.progress {
                ProgressView(value: progress, total: 1)
                    .progressViewStyle(.circular)
                    .tint(tint)
            } else {
                ProgressView()
                    .tint(tint)
            }
        } else {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }

    private var systemImage: String {
        switch status.tone {
        case .neutral: return "clock"
        case .progress: return "arrow.triangle.2.circlepath"
        case .warning: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch status.tone {
        case .neutral: return .secondary
        case .progress: return .accentColor
        case .warning: return colorScheme == .dark ? .yellow : .orange
        case .success: return .green
        case .failure: return .red
        }
    }

    private var backgroundOpacity: Double {
        status.tone == .neutral ? 0.06 : (colorScheme == .dark ? 0.12 : 0.1)
    }
}
