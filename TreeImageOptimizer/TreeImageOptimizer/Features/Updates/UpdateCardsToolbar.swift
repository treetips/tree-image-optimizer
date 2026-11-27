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
            actionButton(
                title: t(availability.labelKey),
                systemImage: availability.systemImage,
                tint: statusTextColor,
                enabled: updatesEnabled,
                resetCursorOnClick: true,
                showsBackground: false
            ) {
                start(UpdateToolbarResolver.plan(for: availability))
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
            HStack(spacing: 6) {
                statusLabel(t("nav.checkingUpdates"), icon: "arrow.triangle.2.circlepath")
                ProgressView()
                    .tint(.primary)
                    .frame(width: 14, height: 14)
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
            HStack(spacing: 6) {
                statusLabel(installingDetail(progress), icon: "arrow.down.circle")
                progressIndicator(progress.fraction, tint: statusTextColor)
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
            HStack(spacing: 6) {
                statusLabel(
                    "\(t("nav.installing")) \(toolsInstallingDetail(progress))",
                    icon: "shippingbox.and.arrow.backward")
                progressIndicator(progress.fraction, tint: accentTextColor)
            }
        }
    }

    private func restartReadyAppCard() -> some View {
        toolbarPill(
            tint: .green,
            opacity: GlassStyle.updateCardGreenTintOpacity,
            textColor: statusTextColor
        ) {
            HStack(spacing: 6) {
                statusLabel(t("nav.updateReady"), icon: "checkmark.circle.fill")
                actionButton(
                    title: updateCheck.isRestarting ? t("a.restarting") : t("nav.restart"),
                    tint: statusTextColor,
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
            HStack(spacing: 6) {
                statusLabel(t("nav.installFailed"), icon: "exclamationmark.triangle.fill")
                actionButton(title: t("nav.retry"), tint: accentTextColor, enabled: updatesEnabled) {
                    start(
                        UpdateToolbarResolver.retryPlan(
                            appCard: updateCheck.card,
                            toolsCard: toolsUpdate.card
                        ))
                }
            }
        }
    }

    private func noUpdateCard() -> some View {
        toolbarPill(
            tint: .accentColor,
            opacity: GlassStyle.updateCardNoneTintOpacity,
            textColor: .primary
        ) {
            actionButton(
                title: t("nav.updateNone"),
                systemImage: "checkmark.circle",
                tint: .primary
            ) {
                updateCheck.dismissCard()
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

    private func toolbarPill<Content: View>(
        tint: Color,
        opacity: Double,
        textColor: Color,
        combineAccessibility: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .foregroundStyle(textColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(
                .regular.tint(tint.opacity(opacity)),
                in: Capsule()
            )
            .accessibilityElement(children: combineAccessibility ? .combine : .contain)
    }

    private func statusLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(1)
        }
        .font(AppTheme.font(.body, scale: fontScale))
        .bold()
    }

    private func actionButton(
        title: String,
        systemImage: String? = nil,
        tint: Color,
        enabled: Bool = true,
        resetCursorOnClick: Bool = false,
        showsBackground: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        UpdateCardActionButton(
            title: title,
            systemImage: systemImage,
            tint: tint,
            enabled: enabled,
            fontScale: fontScale,
            resetCursorOnClick: resetCursorOnClick,
            showsBackground: showsBackground,
            action: action
        )
    }

    @ViewBuilder
    private func progressIndicator(_ fraction: Double?, tint: Color) -> some View {
        if let fraction {
            ProgressView(value: fraction, total: 1)
                .progressViewStyle(.linear)
                .tint(tint)
                .frame(width: 44)
        } else {
            ProgressView()
                .tint(tint)
                .frame(width: 14, height: 14)
        }
    }

    private func installingDetail(_ progress: UpdateInstallProgress) -> String {
        switch progress.phase {
        case .downloading:
            guard let fraction = progress.fraction else {
                return t("nav.downloading")
            }
            return String(
                format: t("nav.downloadingPercent"),
                Int((fraction * 100).rounded(.down))
            )
        case .verifying:
            return t("nav.verifying")
        case .extracting:
            return t("nav.extracting")
        case .installing:
            return t("nav.preparingUpdate")
        }
    }

    private func toolsInstallingDetail(_ progress: ToolsUpdateProgress) -> String {
        if !progress.label.isEmpty {
            guard let fraction = progress.fraction else {
                return progress.label
            }
            let percent = String(
                format: t("nav.downloadingPercent"),
                Int((fraction * 100).rounded(.down))
            )
            return "\(progress.label) \(percent)"
        }
        guard let fraction = progress.fraction else {
            return t("nav.installing")
        }
        return String(
            format: t("nav.downloadingPercent"),
            Int((fraction * 100).rounded(.down))
        )
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

/// ヘッダー内のコンパクトなアクションボタン。カード消滅・無効化時にカーソル状態を戻す。
private struct UpdateCardActionButton: View {
    let title: String
    let systemImage: String?
    let tint: Color
    let enabled: Bool
    let fontScale: CGFloat
    let resetCursorOnClick: Bool
    let showsBackground: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            if resetCursorOnClick {
                NSCursor.arrow.set()
            }
            action()
        } label: {
            titleLabel
                .font(AppTheme.font(.body, scale: fontScale))
                .bold()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(showsBackground ? tint.opacity(0.16) : Color.clear, in: Capsule())
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

    @ViewBuilder
    private var titleLabel: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
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
