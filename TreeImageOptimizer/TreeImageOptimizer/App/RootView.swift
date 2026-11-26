import AppKit
import Combine
import OSLog
import SwiftUI

private let appearanceLogger = Logger(
    subsystem: "com.treeimageoptimizer.TreeImageOptimizer",
    category: "appearance"
)

/// 背景画像切替のクロスフェード時間（秒）。
private let wallpaperCrossfadeSeconds: Double = 0.5

/// Finder風の左サイドナビ＋右コンテンツ。
/// 背景に設定画面で選んだ壁紙（不透明度・背景色付き）を表示し、選択言語を適用する。
/// 更新結果のダイアログは常時表示のここで出す（メニュー操作時も前面に表示するため）。
struct RootView: View {
    @State private var navigation: SidebarNavigation
    @State private var settings: SettingsViewModel
    @State private var updateCheck: UpdateCheckController
    @State private var toolsUpdate: ToolsUpdateController
    @State private var convertJobStore: ConvertJobStore
    @State private var easyConvertJobStore: EasyConvertJobStore
    @State private var bootstrap = ToolBootstrapModel()
    // クロスフェード中に前面の下へ置いておく直前の壁紙。フェード完了後に解放する。
    @State private var outgoingWallpaper: OutgoingWallpaper?
    // 直前に背景画像の切替が起きた時刻。フェードの中断判定に使う。
    @State private var lastWallpaperChangeDate = Date.distantPast

    init(
        navigation: SidebarNavigation = SidebarNavigation(),
        settings: SettingsViewModel = SettingsViewModel(),
        updateCheck: UpdateCheckController = UpdateCheckController(),
        toolsUpdate: ToolsUpdateController = ToolsUpdateController(),
        convertJobStore: ConvertJobStore = ConvertJobStore(),
        easyConvertJobStore: EasyConvertJobStore = EasyConvertJobStore()
    ) {
        _navigation = State(initialValue: navigation)
        _settings = State(initialValue: settings)
        _updateCheck = State(initialValue: updateCheck)
        _toolsUpdate = State(initialValue: toolsUpdate)
        _convertJobStore = State(initialValue: convertJobStore)
        _easyConvertJobStore = State(initialValue: easyConvertJobStore)
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                VStack(alignment: .leading, spacing: 0) {
                    List(SidebarSelection.allCases, selection: $navigation.selection) { item in
                        NavigationLink(value: item) {
                            HStack(spacing: 6) {
                                Label {
                                    Text(item.title(language: settings.language))
                                        .font(AppTheme.font(.body, scale: fontScale))
                                } icon: {
                                    // 実行中はアイコンをローディング表示に切り替える。
                                    // 終了すれば `isRunning` が戻り元のアイコンに戻る。
                                    if isItemRunning(item) {
                                        SidebarLoadingIcon()
                                    } else {
                                        Image(systemName: item.systemImage)
                                    }
                                }
                                // 一括変換の実行中は右端に進捗%を表示する。
                                // 終了すれば非表示になる。かんたん変換は1ファイルのため%は出さない。
                                if item == .convert, convertJobStore.isRunning {
                                    Spacer()
                                    Text(convertProgressLabel)
                                        .font(AppTheme.font(.caption, scale: fontScale))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, 8)
                            // 実行中は行の下端の最背面に細いリニアバーを表示する。
                            // 背景配置のためレイアウトに参加せず行の高さは変わらない。
                            // 一括変換は進捗連動の確定バー、かんたん変換は不確定バー。
                            .background(alignment: .bottom) {
                                VStack(spacing: 0) {
                                    Spacer(minLength: 0)
                                    if item == .convert, convertJobStore.isRunning {
                                        DeterminateLinearBar(progress: convertJobStore.progressPercent)
                                    } else if item == .easyConvert, easyConvertJobStore.isRunning {
                                        IndeterminateLinearBar()
                                    }
                                }
                            }
                        }
                    }
                    .navigationSplitViewColumnWidth(min: 150, ideal: 180)
                    // 更新カード。更新ありは青、進捗中は青、完了時は緑で表示する。
                    // 更新なしは透明（10秒後の自動非表示はUpdateCheckController側）。
                    if let card = updateCheck.card {
                        Divider()
                        switch card {
                        case .available(let info):
                            availableUpdateCard(info: info)
                        case .installing(let progress):
                            installingCard(progress: progress)
                        case .readyToRestart:
                            restartReadyCard()
                        case .installFailed:
                            installFailedCard()
                        case .noUpdate:
                            Button {
                                updateCheck.dismissCard()
                            } label: {
                                updateCardLabel(
                                    text: L10n.string("nav.updateNone", language: settings.language),
                                    icon: "checkmark.circle",
                                    fontScale: fontScale
                                )
                                // 更新なしはLiquid Glassで透明に近い目立たない色にする。
                                .glassEffect(
                                    .regular
                                        .tint(Color.accentColor.opacity(GlassStyle.updateCardNoneTintOpacity))
                                        .interactive(),
                                    in: RoundedRectangle(cornerRadius: GlassStyle.updateCardCornerRadius)
                                )
                                // サイドナビのメニュー項目と同じテキスト色（標準のprimary）。
                                .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                    }
                    // ツール更新カード。アプリ本体更新とは独立した「ツール更新」の状態を示す。
                    // 差分がある場合のみ表示し、クリックで確認ダイアログを出す。
                    if let card = toolsUpdate.card {
                        Divider()
                        switch card {
                        case .available:
                            Button {
                                toolsUpdate.showInstallDialog()
                            } label: {
                                updateCardLabel(
                                    text: L10n.string("nav.toolsUpdateAvailable", language: settings.language),
                                    icon: "shippingbox.and.arrow.backward.fill",
                                    fontScale: fontScale
                                )
                                .glassEffect(
                                    .regular
                                        .tint(Color.accentColor.opacity(GlassStyle.updateCardTintOpacity))
                                        .interactive(),
                                    in: RoundedRectangle(cornerRadius: GlassStyle.updateCardCornerRadius)
                                )
                                .bold()
                                .foregroundStyle(availableTextColor)
                                .onHover { hovering in
                                    if hovering {
                                        NSCursor.pointingHand.push()
                                    } else {
                                        NSCursor.pop()
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        case .installing(let progress):
                            toolsInstallingCard(progress: progress)
                        case .installFailed:
                            toolsInstallFailedCard()
                        }
                    }
                }
            } detail: {
                ZStack {
                    backgroundColor
                    backgroundImage
                    switch navigation.selection {
                    case .convert:
                        // ツール更新中は tools/<name> が一時的に置換されるため、
                        // 変換を抑止する（toolsReady を false にする）。
                        ConvertView(
                            jobStore: convertJobStore,
                            toolsReady: bootstrap.isReady && !toolsUpdate.isInstalling)
                    case .easyConvert:
                        EasyConvertView(
                            jobStore: easyConvertJobStore,
                            toolsReady: bootstrap.isReady && !toolsUpdate.isInstalling)
                    case .settings:
                        SettingsView(viewModel: settings)
                    case .about:
                        AboutView(controller: updateCheck)
                    }
                }
            }
            .environment(\.locale, settings.effectiveLocale)
            .preferredColorScheme(appearanceScheme)
            .environment(\.sizeCategory, AppTheme.sizeCategory(for: settings.fontSize))
            .environment(\.appFontScale, AppTheme.fontScale(for: settings.fontSize))
            .onAppear {
                logAppearance(context: "appear")
                // 起動時にサイレント確認し、サイドナビ通知に反映する。
                updateCheck.refreshAvailability()
                // ツール更新も起動時に差分を確認し、サイドナビ通知に反映する。
                toolsUpdate.refreshAvailability()
                // 初回はtools展開が必要なため、揃うまで操作をブロックする。
                bootstrap.start()
            }
            .disabled(!bootstrap.isReady)
            if !bootstrap.isReady {
                bootstrapOverlay
            }
        }
        .onChange(of: settings.appearance) {
            logAppearance(context: "change")
        }
        .onChange(of: settings.fontSize) {
            logFontSize()
        }
        .onReceive(
            DistributedNotificationCenter.default().publisher(
                for: Notification.Name("AppleInterfaceThemeChangedNotification")
            )
        ) { _ in
            // 自動モード時はmacOS設定の変更に追従して背景色を更新する。
            settings.refreshAutoBackgroundColor()
        }
        .alert(
            Text(L10n.string("a.latest", language: settings.language))
                .font(AppTheme.font(.headline, scale: fontScale)),
            isPresented: $updateCheck.latestDialog
        ) {
            Button {
            } label: {
                Text(L10n.string("a.ok", language: settings.language))
                    .font(AppTheme.font(.body, scale: fontScale))
            }
        } message: {
            Text(L10n.string("a.latestMsg", language: settings.language))
                .font(AppTheme.font(.body, scale: fontScale))
        }
        .alert(
            Text(L10n.string("a.checkFailed", language: settings.language))
                .font(AppTheme.font(.headline, scale: fontScale)),
            isPresented: Binding(
                get: { updateCheck.errorDialog != nil },
                set: { if !$0 { updateCheck.errorDialog = nil } }
            )
        ) {
            Button {
            } label: {
                Text(L10n.string("a.ok", language: settings.language))
                    .font(AppTheme.font(.body, scale: fontScale))
            }
        } message: {
            Text(updateCheck.errorDialog ?? "")
                .font(AppTheme.font(.body, scale: fontScale))
        }
        .alert(
            Text(L10n.string("a.restartFailed", language: settings.language))
                .font(AppTheme.font(.headline, scale: fontScale)),
            isPresented: Binding(
                get: { updateCheck.restartErrorDialog != nil },
                set: { if !$0 { updateCheck.restartErrorDialog = nil } }
            )
        ) {
            Button {
            } label: {
                Text(L10n.string("a.ok", language: settings.language))
                    .font(AppTheme.font(.body, scale: fontScale))
            }
        } message: {
            Text(updateCheck.restartErrorDialog ?? "")
                .font(AppTheme.font(.body, scale: fontScale))
        }
        // ツール更新の確認ダイアログ。クリックで表示し、更新対象ツールを提示する。
        .alert(
            Text(L10n.string("a.toolsConfirmInstall", language: settings.language))
                .font(AppTheme.font(.headline, scale: fontScale)),
            isPresented: Binding(
                get: { toolsUpdate.availableInfo != nil },
                set: { if !$0 { toolsUpdate.dismissInstallDialog() } }
            )
        ) {
            Button(role: .cancel) {
            } label: {
                Text(L10n.string("a.cancel", language: settings.language))
                    .font(AppTheme.font(.body, scale: fontScale))
            }
            if let info = toolsUpdate.availableInfo {
                Button {
                    toolsUpdate.install(info)
                } label: {
                    Text(L10n.string("a.install", language: settings.language))
                        .font(AppTheme.font(.body, scale: fontScale))
                }
            }
        } message: {
            if toolsUpdate.availableInfo != nil {
                Text(toolsUpdateMessage(language: settings.language))
                    .font(AppTheme.font(.body, scale: fontScale))
            }
        }
        // ツール更新の失敗ダイアログ。失敗理由を提示する。
        .alert(
            Text(L10n.string("nav.installFailed", language: settings.language))
                .font(AppTheme.font(.headline, scale: fontScale)),
            isPresented: Binding(
                get: { toolsUpdate.errorDialog != nil },
                set: { if !$0 { toolsUpdate.errorDialog = nil } }
            )
        ) {
            Button {
            } label: {
                Text(L10n.string("a.ok", language: settings.language))
                    .font(AppTheme.font(.body, scale: fontScale))
            }
        } message: {
            Text(toolsUpdate.errorDialog ?? "")
                .font(AppTheme.font(.body, scale: fontScale))
        }
    }

    /// ツール展開中の全画面オーバーレイ。揃うまで操作をブロックする。
    @ViewBuilder
    private var bootstrapOverlay: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                switch bootstrap.phase {
                case .checking:
                    ProgressView()
                    Text(L10n.string("boot.preparing", language: settings.language))
                        .font(AppTheme.font(.body, scale: fontScale))
                case .installing(let fraction, let name):
                    ProgressView(value: fraction, total: 1.0)
                        .frame(maxWidth: 300)
                    Text("\(L10n.string("boot.preparing", language: settings.language)) \(name)")
                        .font(AppTheme.font(.body, scale: fontScale))
                case .failed(let reason):
                    Text(L10n.string("boot.failed", language: settings.language))
                        .font(AppTheme.font(.headline, scale: fontScale))
                    Text(reason)
                        .font(AppTheme.font(.footnote, scale: fontScale))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    // Why not ログをアプリ内で表示するか: 失敗原因は外部コマンドや
                    // ファイル操作にも及び、まず現物のログを開ける方が調査が速い。
                    Text(
                        String(
                            format: L10n.string("boot.logHint", language: settings.language),
                            bootstrap.logDirectoryURL.path
                        )
                    )
                    .font(AppTheme.font(.footnote, scale: fontScale))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    Button {
                        bootstrap.retry()
                    } label: {
                        Text(L10n.string("boot.retry", language: settings.language))
                            .font(AppTheme.font(.body, scale: fontScale))
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        NSWorkspace.shared.open(bootstrap.logDirectoryURL)
                    } label: {
                        Text(L10n.string("boot.openLogs", language: settings.language))
                            .font(AppTheme.font(.body, scale: fontScale))
                    }
                case .ready:
                    EmptyView()
                }
            }
            .padding()
        }
    }

    /// 設定の外観モードを配色に反映する。
    /// モディファイアの付け外しではなく値の変更で切り替える。
    /// 付け外しだとライト→自動のような遷移で配色が張り付くため。
    /// 自動はシステム設定を読み取って明示値に解決する。
    private var appearanceScheme: ColorScheme {
        switch settings.appearance {
        case AppearanceMode.light.rawValue: return .light
        case AppearanceMode.dark.rawValue: return .dark
        default: return systemScheme
        }
    }

    private var systemScheme: ColorScheme {
        SettingsViewModel.systemIsDark() ? .dark : .light
    }

    private var fontScale: CGFloat {
        AppTheme.fontScale(for: settings.fontSize)
    }

    /// ツール更新カードとアプリ更新の失敗カードで使うテキスト色。半透明アクセントtintの上で
    /// ライト・ダークどちらのモードでも強調して見える色にする。
    /// 自動モードは `appearanceScheme` で実効スキームに解決済み。
    private var availableTextColor: Color {
        appearanceScheme == .dark ? .white : Color(nsColor: .textColor)
    }

    /// サイドナビの一括変換メニュー右端に表示する進捗%。
    private var convertProgressLabel: String {
        "\(Int(convertJobStore.progressPercent))%"
    }

    /// 更新カード共通のラベル。文言とアイコンだけを受け取り、両カードで見た目の共通部分を纏める。
    private func updateCardLabel(text: String, icon: String, fontScale: CGFloat) -> some View {
        Label {
            Text(text)
                .font(AppTheme.font(.body, scale: fontScale))
        } icon: {
            Image(systemName: icon)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    /// 更新ありカード。Rex の更新フローに合わせ、確認ダイアログではなく
    /// カード内の Download ボタンからそのままダウンロードを始める。
    private func availableUpdateCard(info: UpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(L10n.string("nav.updateAvailable", language: settings.language))
                    .font(AppTheme.font(.body, scale: fontScale))
            } icon: {
                Image(systemName: "arrow.down.circle.fill")
            }
            .bold()
            updateCardAction(
                title: L10n.string("nav.download", language: settings.language),
                tint: statusCardTextColor,
                resetCursorOnClick: true
            ) {
                updateCheck.startDownload(info, language: settings.language)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .glassEffect(
            .regular.tint(Color.blue.opacity(GlassStyle.updateCardBlueTintOpacity)),
            in: RoundedRectangle(cornerRadius: GlassStyle.updateCardCornerRadius)
        )
        .foregroundStyle(statusCardTextColor)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    /// インストール中の更新カード。Download ボタン押下後の進捗をここへ集約する。
    /// ダウンロード中は受信バイト数の確定バー、検証・展開・コピー中は不確定バーを出す。
    private func installingCard(progress: UpdateInstallProgress) -> some View {
        VStack(spacing: 8) {
            Label {
                Text(installingDetail(for: progress))
                    .font(AppTheme.font(.body, scale: fontScale))
            } icon: {
                Image(systemName: "arrow.down.circle")
            }
            .bold()
            if let fraction = progress.fraction {
                DeterminateLinearBar(progress: fraction * 100, tint: statusCardTextColor)
            } else {
                IndeterminateLinearBar(tint: statusCardTextColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        // 更新ありと同じ青。クリックできないため `.interactive()` は付けない。
        .glassEffect(
            .regular.tint(Color.blue.opacity(GlassStyle.updateCardBlueTintOpacity)),
            in: RoundedRectangle(cornerRadius: GlassStyle.updateCardCornerRadius)
        )
        .foregroundStyle(statusCardTextColor)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    /// 再起動準備完了カード。自動再起動せず、緑色のカードから明示的に再起動する。
    private func restartReadyCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(L10n.string("nav.updateReady", language: settings.language))
                    .font(AppTheme.font(.body, scale: fontScale))
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .bold()
            updateCardAction(
                title: updateCheck.isRestarting
                    ? L10n.string("a.restarting", language: settings.language)
                    : L10n.string("nav.restart", language: settings.language),
                tint: statusCardTextColor,
                enabled: !updateCheck.isRestarting
            ) {
                updateCheck.restart(language: settings.language)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .glassEffect(
            .regular.tint(Color.green.opacity(GlassStyle.updateCardGreenTintOpacity)),
            in: RoundedRectangle(cornerRadius: GlassStyle.updateCardCornerRadius)
        )
        .foregroundStyle(statusCardTextColor)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    /// 更新カード内のアクションボタン。背景色に埋もれないよう、前景色を薄く重ねる。
    private func updateCardAction(
        title: String, tint: Color, enabled: Bool = true, resetCursorOnClick: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        UpdateCardActionButton(
            title: title,
            tint: tint,
            enabled: enabled,
            fontScale: fontScale,
            resetCursorOnClick: resetCursorOnClick,
            action: action
        )
    }

    private var statusCardTextColor: Color {
        // 半透明の青・緑ではライトモードの白文字が読めないため、実効スキームで切り替える。
        appearanceScheme == .dark ? .white : Color.black.opacity(0.8)
    }

    /// インストール中の補足文言。進捗率はダウンロード段階だけ表示する。
    private func installingDetail(for progress: UpdateInstallProgress) -> String {
        let lang = settings.language
        switch progress.phase {
        case .downloading:
            guard let fraction = progress.fraction else {
                return L10n.string("nav.downloading", language: lang)
            }
            return String(
                format: L10n.string("nav.downloadingPercent", language: lang),
                Int((fraction * 100).rounded(.down))
            )
        case .verifying:
            return L10n.string("nav.verifying", language: lang)
        case .extracting:
            return L10n.string("nav.extracting", language: lang)
        case .installing:
            return L10n.string("nav.preparingUpdate", language: lang)
        }
    }

    /// インストール失敗カード。赤背景で失敗を示し、カード内の `再実行` から
    /// ダウンロードからやり直せる。失敗の詳細理由はエラーダイアログとAbout画面に出す。
    private func installFailedCard() -> some View {
        VStack(spacing: 6) {
            Label {
                Text(L10n.string("nav.installFailed", language: settings.language))
                    .font(AppTheme.font(.body, scale: fontScale))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .bold()
            Button {
                updateCheck.retryInstall(language: settings.language)
            } label: {
                Text(L10n.string("nav.retry", language: settings.language))
                    .font(AppTheme.font(.caption, scale: fontScale))
                    .bold()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(availableTextColor.opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        // 失敗は赤。濃さは更新ありカードと揃え、不透明な塗りでグラスを飽和させない。
        .glassEffect(
            .regular.tint(Color.red.opacity(GlassStyle.updateCardTintOpacity)),
            in: RoundedRectangle(cornerRadius: GlassStyle.updateCardCornerRadius)
        )
        .foregroundStyle(availableTextColor)
        .padding(.horizontal)
        .padding(.vertical, 8)
        // 再実行ボタンを読み上げ対象に残すため、進捗カードの combine は使わない。
        .accessibilityElement(children: .contain)
    }

    /// ツール更新のインストール中カード。確認ダイアログを閉じた後の進捗をここへ集約する。
    /// ダウンロード中は受信バイト数の確定バー、検証・展開中は不確定バーを出す。
    private func toolsInstallingCard(progress: ToolsUpdateProgress) -> some View {
        VStack(spacing: 6) {
            Label {
                Text(L10n.string("nav.installing", language: settings.language))
                    .font(AppTheme.font(.body, scale: fontScale))
            } icon: {
                Image(systemName: "shippingbox.and.arrow.backward")
            }
            .bold()
            Text(toolsInstallingDetail(for: progress))
                .font(AppTheme.font(.caption, scale: fontScale))
                .opacity(0.8)
            if let fraction = progress.fraction {
                DeterminateLinearBar(progress: fraction * 100, tint: availableTextColor)
            } else {
                IndeterminateLinearBar(tint: availableTextColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .glassEffect(
            .regular.tint(Color.accentColor.opacity(GlassStyle.updateCardTintOpacity)),
            in: RoundedRectangle(cornerRadius: GlassStyle.updateCardCornerRadius)
        )
        .foregroundStyle(availableTextColor)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    /// ツール更新のインストール中の補足文言。進捗率はダウンロード段階だけ表示する。
    private func toolsInstallingDetail(for progress: ToolsUpdateProgress) -> String {
        guard let fraction = progress.fraction else {
            // 進捗が無い段階（検証・展開）では対象ツール名だけを示す。
            return progress.label.isEmpty
                ? L10n.string("nav.installing", language: settings.language)
                : progress.label
        }
        return String(
            format: L10n.string("nav.downloadingPercent", language: settings.language),
            Int((fraction * 100).rounded(.down))
        )
    }

    /// ツール更新の失敗カード。赤背景で失敗を示し、カード内の `再実行` から
    /// 最初からやり直せる。失敗の詳細理由はエラーダイアログに出す。
    private func toolsInstallFailedCard() -> some View {
        VStack(spacing: 6) {
            Label {
                Text(L10n.string("nav.installFailed", language: settings.language))
                    .font(AppTheme.font(.body, scale: fontScale))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .bold()
            Button {
                toolsUpdate.retryInstall()
            } label: {
                Text(L10n.string("nav.retry", language: settings.language))
                    .font(AppTheme.font(.caption, scale: fontScale))
                    .bold()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(availableTextColor.opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .glassEffect(
            .regular.tint(Color.red.opacity(GlassStyle.updateCardTintOpacity)),
            in: RoundedRectangle(cornerRadius: GlassStyle.updateCardCornerRadius)
        )
        .foregroundStyle(availableTextColor)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    /// ツール更新の確認ダイアログ本文。差分のあるツール名だけを列挙して提示する。
    /// 現状はツール名の一覧のみで、合計サイズは提示しない（サイズ情報はメタデータに無いため）。
    private func toolsUpdateMessage(language: String) -> String {
        let names = toolsUpdate.pendingToolNames.joined(separator: ", ")
        return String(format: L10n.string("a.toolsConfirmInstallMsg", language: language), names)
    }

    /// 実行中のメニューはアイコンをローディング表示に切り替える。
    private func isItemRunning(_ item: SidebarSelection) -> Bool {
        switch item {
        case .convert: return convertJobStore.isRunning
        case .easyConvert: return easyConvertJobStore.isRunning
        case .settings, .about: return false
        }
    }

    /// 診断用に文字の大きさ解決結果を記録する。
    private func logFontSize() {
        let message =
            "fontsize: setting=\(settings.fontSize), "
            + "sizeCategory=\(String(describing: AppTheme.sizeCategory(for: settings.fontSize)))"
        appearanceLogger.info("\(message, privacy: .public)")
    }

    /// 診断用に外観解決結果を記録する。ヘッドレスでも `log` コマンドで確認できる。
    private func logAppearance(context: String) {
        let systemStyle = SettingsViewModel.systemAppearanceName() ?? "(light)"
        let message =
            "appearance[\(context)]: setting=\(settings.appearance), "
            + "scheme=\(String(describing: appearanceScheme)), "
            + "bg=\(settings.effectiveWallpaperBackgroundColorHex), " + "system=\(systemStyle)"
        appearanceLogger.info("\(message, privacy: .public)")
    }

    private var backgroundColor: Color {
        parseHex(settings.effectiveWallpaperBackgroundColorHex) ?? .white
    }

    /// 表示対象の壁紙URL。「背景無し」選択時はnil。
    private var wallpaperURL: URL? {
        settings.wallpaperFileURL()
    }

    /// 直近の切替から、フェードと裏面解放が静まるまでの期間内かどうか。
    /// 期間内の追加切替はフェードを打ち切り即時切替にする。
    private var isWallpaperFadeSuppressed: Bool {
        lastWallpaperChangeDate.addingTimeInterval(wallpaperCrossfadeSeconds * 2) > Date.now
    }

    @ViewBuilder
    private var backgroundImage: some View {
        ZStack {
            // 直前の壁紙。不透明のまま背面に置き、新壁紙をその上へフェードインさせる。
            // 旧画像だけをフェードアウトさせると中間点で新旧が半透明になり、
            // 背景色が透けて一瞬濁って見えるため、不透明の裏面で隙間を埋める。
            if let outgoing = outgoingWallpaper {
                wallpaperLayer(outgoing.image)
                    .opacity(settings.wallpaperOpacity)
                    .transition(.opacity)
                    .task(id: outgoing.url) {
                        // フェード完了後に背面レイヤを解放する。解放もフェードさせることで、
                        // 不透明度が1未満のときに透明度が一度跳ねるのを防ぐ。
                        do {
                            try await Task.sleep(for: .milliseconds(Int(wallpaperCrossfadeSeconds * 1000)))
                        } catch {
                            // 解放待ちの間に次の切り替えが始まった場合は何もしない。
                            return
                        }
                        withAnimation(.easeInOut(duration: wallpaperCrossfadeSeconds)) {
                            outgoingWallpaper = nil
                        }
                    }
            }
            if let url = wallpaperURL, let image = NSImage(contentsOf: url) {
                wallpaperLayer(image)
                    .opacity(settings.wallpaperOpacity)
                    .id(url)
                    .transition(.opacity)
            }
        }
        .animation(
            isWallpaperFadeSuppressed ? nil : .easeInOut(duration: wallpaperCrossfadeSeconds), value: wallpaperURL
        )
        .onChange(of: wallpaperURL) { oldURL, newURL in
            guard let oldURL, let newURL, oldURL != newURL else { return }
            let changeDate = Date.now
            defer { lastWallpaperChangeDate = changeDate }
            // フェード中の追加切替では裏面を張り替えない。
            // 裏面と進行中のフェードアウト残骸の内容が食い違い画像がガタつくため。
            // .animation 側がこの時刻でフェードを無効化し、即時切替になる。
            guard !isWallpaperFadeSuppressed else { return }
            // 「背景無し」への切り替えは新壁紙が無いため背面レイヤを張らず、
            // 旧壁紙のフェードアウトでそのまま背景色へ戻す。
            guard let outgoingImage = NSImage(contentsOf: oldURL) else { return }
            outgoingWallpaper = OutgoingWallpaper(url: oldURL, image: outgoingImage)
        }
    }

    /// 壁紙1枚のレイヤ。縦にピッタリ合わせ、アスペクト比は維持する。
    private func wallpaperLayer(_ image: NSImage) -> some View {
        GeometryReader { geometry in
            let aspect = image.size.width / max(image.size.height, 1)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(
                    width: geometry.size.height * aspect,
                    height: geometry.size.height
                )
                .clipped()
                .position(
                    x: geometry.frame(in: .local).midX,
                    y: geometry.frame(in: .local).midY
                )
        }
    }

    private func parseHex(_ hex: String) -> Color? {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        if h.count == 6 { h = "FF" + h }
        guard h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        let a = Double((v >> 24) & 0xFF) / 255
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        return Color(red: r, green: g, blue: b, opacity: a)
    }
}

/// 更新カード内のアクションボタン。カードの差し替えや無効化でカーソル状態が残らないよう管理する。
private struct UpdateCardActionButton: View {
    let title: String
    let tint: Color
    let enabled: Bool
    let fontScale: CGFloat
    let resetCursorOnClick: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button {
            if resetCursorOnClick {
                // クリックでカードが差し替わると onHover(false) が来ないため、先に戻す。
                NSCursor.arrow.set()
            }
            action()
        } label: {
            Text(title)
                .font(AppTheme.font(.body, scale: fontScale))
                .bold()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
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
            // クリック以外でカードが消えた場合もカーソルを戻す。
            NSCursor.arrow.set()
        }
    }

    private func updateCursor() {
        // push/pop はカード消滅時に不均衡になり得るため、現在のカーソルを直接設定する。
        if isHovering && enabled {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}

/// クロスフェード中に背面へ残しておく直前の壁紙。
private struct OutgoingWallpaper {
    let url: URL
    let image: NSImage
}

/// 実行中メニュー用のローディングアイコン。テーマカラーで回転表示する。
/// `ProgressView` のスピナーはmacOSで着色が効かないため、SF Symbolsで自前表示する。
private struct SidebarLoadingIcon: View {
    @State private var spinning = false

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .foregroundStyle(Color.accentColor)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

/// 進捗連動の細いリニアバー。標準の `ProgressView` より細くするため自前表示する。
/// `tint` はアクセント色の上に重ねる更新カードなど、背景に合わせた色が必要な場合に上書きする。
private struct DeterminateLinearBar: View {
    var progress: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tint.opacity(0.25))
                    .frame(height: 3)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tint)
                    .frame(width: barWidth(total: geometry.size.width), height: 3)
            }
        }
        .frame(height: 3)
    }

    private func barWidth(total: CGFloat) -> CGFloat {
        total * min(max(progress, 0), 100) / 100
    }
}

/// MUIのLinear indeterminate風のバー。標準SwiftUIのみで実装する。
/// 進捗%がない場合（かんたん変換の1ファイル処理など）に使う。
private struct IndeterminateLinearBar: View {
    @State private var move = false
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let barWidth = max(width * 0.35, 24)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tint.opacity(0.25))
                    .frame(height: 3)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(tint)
                    .frame(width: barWidth, height: 3)
                    .offset(x: move ? width - barWidth : 0)
                    .animation(
                        .easeInOut(duration: 1).repeatForever(autoreverses: true),
                        value: move
                    )
                    .onAppear { move = true }
            }
        }
        .frame(height: 3)
    }
}

extension SidebarSelection {
    fileprivate func title(language: String) -> String {
        switch self {
        case .convert: return L10n.string("nav.convert", language: language)
        case .easyConvert: return L10n.string("nav.easyConvert", language: language)
        case .settings: return L10n.string("nav.settings", language: language)
        case .about: return L10n.string("nav.about", language: language)
        }
    }

    fileprivate var systemImage: String {
        switch self {
        case .convert: return "photo.badge.arrow.down"
        case .easyConvert: return "wand.and.stars"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}
