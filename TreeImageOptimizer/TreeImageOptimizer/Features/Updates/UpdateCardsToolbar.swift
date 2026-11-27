import AppKit
import SwiftUI

/// ヘッダー右端に表示するアプリ本体・ツール更新の統合カード。
struct UpdateCardsToolbar: View {
    let updateCheck: UpdateCheckController
    let toolsUpdate: ToolsUpdateController
    let toolsReady: Bool
    let updatesEnabled: Bool
    let language: String
    let fontScale: CGFloat
    let colorScheme: ColorScheme

    private var state: UpdateToolbarState {
        let resolved = UpdateToolbarResolver.resolve(
            appCard: updateCheck.card,
            toolsCard: toolsUpdate.card,
            isChecking: updateCheck.isChecking || updateCheck.isCleaningStagedUpdate || toolsUpdate.isChecking,
            toolsCheckCompleted: toolsUpdate.hasCheckedAvailability,
            checkFailures: (
                app: updateCheck.availabilityCheckFailed,
                tools: toolsUpdate.availabilityCheckFailed
            )
        )
        // ツール準備が失敗した場合は、確認中スピナーを出さずオーバーレイへ任せる。
        if case .checking = resolved, !toolsReady { return .hidden }
        return resolved
    }

    @ViewBuilder
    var body: some View {
        switch state {
        case .hidden:
            EmptyView()
        case .checking:
            checkingCard()
        case .available(let availability):
            availableCard(availability)
        case .appInstalling(let progress):
            installingAppCard(progress)
        case .toolsInstalling(let progress):
            installingToolsCard(progress)
        case .readyToRestart:
            restartReadyAppCard()
        case .appInstallFailed, .toolsInstallFailed:
            failedCard()
        case .noUpdate:
            noUpdateCard()
        }
    }
}

extension UpdateCardsToolbar {
    private func availableCard(_ availability: UpdateAvailability) -> some View {
        toolbarPill(
            tint: .blue,
            opacity: GlassStyle.updateCardBlueTintOpacity,
            textColor: statusTextColor
        ) {
            HStack(spacing: 8) {
                statusIcon(availability.systemImage, color: .blue)
                statusText(t(availability.labelKey))
                actionButton(
                    title: availableActionTitle(availability),
                    tint: .blue,
                    foregroundColor: .blue,
                    enabled: updatesEnabled
                ) {
                    start(UpdateToolbarResolver.plan(for: availability))
                }
                closeButton()
            }
        }
    }

    private func checkingCard() -> some View {
        toolbarPill(
            tint: .accentColor,
            opacity: GlassStyle.updateCardNoneTintOpacity,
            textColor: .primary,
            combineAccessibility: true
        ) {
            HStack(spacing: 8) {
                circularProgress(fraction: nil, tint: .primary)
                statusText(t("nav.checkingUpdates"))
            }
        }
    }

    private func installingAppCard(_ progress: UpdateInstallProgress) -> some View {
        toolbarPill(
            tint: .blue,
            opacity: GlassStyle.updateCardBlueTintOpacity,
            textColor: statusTextColor,
            combineAccessibility: true
        ) {
            HStack(spacing: 8) {
                circularProgress(fraction: progress.fraction, tint: .blue)
                statusText(installingDetail(progress))
                if let fraction = progress.fraction {
                    percentLabel(fraction)
                }
            }
        }
    }

    private func installingToolsCard(_ progress: ToolsUpdateProgress) -> some View {
        toolbarPill(
            tint: .accentColor,
            opacity: GlassStyle.updateCardTintOpacity,
            textColor: accentTextColor,
            combineAccessibility: true
        ) {
            HStack(spacing: 8) {
                circularProgress(fraction: progress.fraction, tint: .accentColor)
                statusText(toolsInstallingText(progress))
                if let fraction = progress.fraction {
                    percentLabel(fraction)
                }
            }
        }
    }

    private func restartReadyAppCard() -> some View {
        toolbarPill(
            tint: .green,
            opacity: GlassStyle.updateCardGreenTintOpacity,
            textColor: statusTextColor
        ) {
            HStack(spacing: 8) {
                statusIcon("checkmark.circle.fill", color: .green)
                statusText(t("nav.updateReady"))
                actionButton(
                    title: updateCheck.isRestarting ? t("a.restarting") : t("nav.restart"),
                    tint: .green,
                    foregroundColor: .green,
                    enabled: !updateCheck.isRestarting
                ) {
                    updateCheck.restart(language: language)
                }
            }
        }
    }

    private func failedCard() -> some View {
        toolbarPill(
            tint: .red,
            opacity: GlassStyle.updateCardTintOpacity,
            textColor: accentTextColor
        ) {
            HStack(spacing: 8) {
                statusIcon("exclamationmark.triangle.fill", color: .red)
                statusText(t("nav.installFailed"))
                actionButton(
                    title: t("nav.retry"),
                    tint: .red,
                    foregroundColor: .red,
                    enabled: updatesEnabled
                ) {
                    start(
                        UpdateToolbarResolver.retryPlan(
                            appCard: updateCheck.card,
                            toolsCard: toolsUpdate.card
                        ))
                }
                closeButton()
            }
        }
    }

    private func noUpdateCard() -> some View {
        toolbarPill(
            tint: .accentColor,
            opacity: GlassStyle.updateCardNoneTintOpacity,
            textColor: .primary
        ) {
            HStack(spacing: 8) {
                statusIcon("checkmark.circle.fill", color: .green)
                statusText(t("nav.updateNone"))
                closeButton()
            }
        }
    }

    /// 更新計画を実行する。両方ある場合はツールの成功を待ってアプリを開始する。
    private func start(_ plan: UpdateInstallPlan) {
        guard updatesEnabled else { return }
        switch plan {
        case .none:
            return
        case .app(let info):
            updateCheck.startDownload(info, language: language)
        case .tools(let info):
            toolsUpdate.install(info)
        case .toolsThenApp(let expectedAppInfo, let toolsInfo):
            toolsUpdate.install(toolsInfo) { success in
                guard success else { return }
                // Why not 開始時点の情報をそのまま使うか: ツール更新中に手動確認が
                // 完了している場合、新しい更新を優先し、最新へ戻った場合は開始しない。
                switch updateCheck.card {
                case .available(let currentInfo):
                    updateCheck.startDownload(currentInfo, language: language)
                case .installFailed:
                    updateCheck.startDownload(expectedAppInfo, language: language)
                default:
                    return
                }
            }
        }
    }

    private func dismissNotification() {
        switch state {
        case .available:
            updateCheck.dismissCard()
            toolsUpdate.dismissCard()
        case .noUpdate:
            updateCheck.dismissCard()
        case .appInstallFailed:
            updateCheck.dismissCard()
        case .toolsInstallFailed:
            toolsUpdate.dismissCard()
            switch updateCheck.card {
            case .noUpdate, .available:
                updateCheck.dismissCard()
            default:
                break
            }
        default:
            // 実行中・再起動待ちは閉じず、進捗と再起動操作を失わないようにする。
            return
        }
    }

    private func toolbarPill<Content: View>(
        tint: Color,
        opacity: Double,
        textColor: Color,
        combineAccessibility: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .fixedSize(horizontal: true, vertical: true)
            .foregroundStyle(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 36)
            .glassEffect(
                .regular.tint(tint.opacity(opacity)),
                in: Capsule()
            )
            // Why not 圧縮に任せるか: 本文と操作部を失わず、Rex風の固有サイズを保つため。
            .fixedSize(horizontal: true, vertical: true)
            .accessibilityElement(children: combineAccessibility ? .combine : .contain)
    }

    private func statusIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(AppTheme.font(.caption, scale: fontScale).bold())
            .foregroundStyle(color)
            .frame(width: 22, height: 22)
            .background(color.opacity(0.18), in: Circle())
    }
    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.font(.body, scale: fontScale).bold())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
    private func actionButton(
        title: String,
        tint: Color,
        foregroundColor: Color? = nil,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        UpdateCardActionButton(
            title: title,
            tint: tint,
            foregroundColor: foregroundColor,
            enabled: enabled,
            fontScale: fontScale,
            action: action
        )
    }

    private func closeButton() -> some View {
        Button {
            dismissNotification()
        } label: {
            Image(systemName: "xmark")
                .font(AppTheme.font(.caption, scale: fontScale).bold())
                .foregroundStyle(Color.primary.opacity(0.65))
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(t("a.close")))
    }

    private func circularProgress(fraction: Double?, tint: Color) -> some View {
        Group {
            if let fraction {
                ProgressView(value: fraction, total: 1)
                    .progressViewStyle(.circular)
            } else {
                ProgressView()
            }
        }
        .tint(tint)
        .frame(width: 22, height: 22)
    }
    private func percentLabel(_ fraction: Double) -> some View {
        Text(fraction, format: .percent.precision(.fractionLength(0)))
            .font(AppTheme.font(.body, scale: fontScale))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
    private func availableActionTitle(_ availability: UpdateAvailability) -> String {
        if case .tools = availability {
            return t("a.install")
        }
        return t("nav.download")
    }
    private func installingDetail(_ progress: UpdateInstallProgress) -> String {
        switch progress.phase {
        case .downloading:
            return t("nav.downloading")
        case .verifying:
            return t("nav.verifying")
        case .extracting:
            return t("nav.extracting")
        case .installing:
            return t("nav.preparingUpdate")
        }
    }

    private func toolsInstallingText(_ progress: ToolsUpdateProgress) -> String {
        guard !progress.label.isEmpty else { return t("nav.installing") }
        return "\(t("nav.installing")) \(progress.label)"
    }

    private func t(_ key: String) -> String {
        L10n.string(key, language: language)
    }

    private var statusTextColor: Color {
        // 半透明の青・緑ではライトモードの白文字が読めないため、実効スキームで切り替える。
        colorScheme == .dark ? .white : Color.black.opacity(0.8)
    }

    private var accentTextColor: Color {
        colorScheme == .dark ? .white : Color(nsColor: .textColor)
    }
}

private struct UpdateCardActionButton: View {
    let title: String
    let tint: Color
    let foregroundColor: Color?
    let enabled: Bool
    let fontScale: CGFloat
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            action()
        } label: {
            Text(title)
                .font(AppTheme.font(.body, scale: fontScale).bold())
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(foregroundColor ?? tint)
                .background(tint.opacity(0.28), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .onHover { hovering in
            isHovering = hovering
            updateCursor()
        }
        .onChange(of: enabled) { _, _ in
            updateCursor()
        }
        .onDisappear {
            NSCursor.arrow.set()
        }
    }

    private func updateCursor() {
        if isHovering && enabled {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}
