import AppKit
import SwiftUI

/// ヘッダー右端に表示するアプリ本体・ツール更新のコンパクトな更新カード。
struct UpdateCardsToolbar: View {
    let updateCheck: UpdateCheckController
    let toolsUpdate: ToolsUpdateController
    let language: String
    let fontScale: CGFloat
    let colorScheme: ColorScheme

    @ViewBuilder
    var body: some View {
        if updateCheck.card != nil || toolsUpdate.card != nil {
            HStack(spacing: 8) {
                if let card = updateCheck.card {
                    appUpdateCard(card)
                }
                if let card = toolsUpdate.card {
                    toolsUpdateCard(card)
                }
            }
        }
    }

    @ViewBuilder
    private func appUpdateCard(_ card: UpdateCard) -> some View {
        switch card {
        case .available(let info):
            availableAppCard(info)
        case .installing(let progress):
            installingAppCard(progress)
        case .readyToRestart:
            restartReadyAppCard()
        case .installFailed:
            failedAppCard()
        case .noUpdate:
            noUpdateAppCard()
        }
    }

    private func availableAppCard(_ info: UpdateInfo) -> some View {
        toolbarPill(
            tint: .blue,
            opacity: GlassStyle.updateCardBlueTintOpacity,
            textColor: statusTextColor
        ) {
            HStack(spacing: 6) {
                statusLabel(t("nav.updateAvailable"), icon: "arrow.down.circle.fill")
                actionButton(
                    title: t("nav.download"),
                    tint: statusTextColor,
                    resetCursorOnClick: true
                ) {
                    updateCheck.startDownload(info, language: language)
                }
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

    private func failedAppCard() -> some View {
        toolbarPill(
            tint: .red,
            opacity: GlassStyle.updateCardTintOpacity,
            textColor: accentTextColor
        ) {
            HStack(spacing: 6) {
                statusLabel(t("nav.installFailed"), icon: "exclamationmark.triangle.fill")
                actionButton(title: t("nav.retry"), tint: accentTextColor) {
                    updateCheck.retryInstall(language: language)
                }
            }
        }
    }

    private func noUpdateAppCard() -> some View {
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

    @ViewBuilder
    private func toolsUpdateCard(_ card: ToolsUpdateCard) -> some View {
        switch card {
        case .available:
            toolbarPill(
                tint: .accentColor,
                opacity: GlassStyle.updateCardTintOpacity,
                textColor: accentTextColor
            ) {
                HStack(spacing: 6) {
                    statusLabel(
                        t("nav.toolsUpdateAvailable"), icon: "shippingbox.and.arrow.backward.fill")
                    actionButton(title: t("a.install"), tint: accentTextColor) {
                        toolsUpdate.showInstallDialog()
                    }
                }
            }
        case .installing(let progress):
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
        case .installFailed:
            toolbarPill(
                tint: .red,
                opacity: GlassStyle.updateCardTintOpacity,
                textColor: accentTextColor
            ) {
                HStack(spacing: 6) {
                    statusLabel(t("nav.installFailed"), icon: "exclamationmark.triangle.fill")
                    actionButton(title: t("nav.retry"), tint: accentTextColor) {
                        toolsUpdate.retryInstall()
                    }
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
        action: @escaping () -> Void
    ) -> some View {
        UpdateCardActionButton(
            title: title,
            systemImage: systemImage,
            tint: tint,
            enabled: enabled,
            fontScale: fontScale,
            resetCursorOnClick: resetCursorOnClick,
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
        guard let fraction = progress.fraction else {
            return progress.label.isEmpty ? t("nav.installing") : progress.label
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
                .background(tint.opacity(0.16), in: Capsule())
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
