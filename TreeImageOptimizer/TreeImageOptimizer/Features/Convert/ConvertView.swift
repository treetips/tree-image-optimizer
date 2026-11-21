import AppKit
import SwiftUI

/// 一括画像変換画面。
/// 実行状態は共有の `ConvertJobStore` を参照するため、サイドナビ切替で
/// Viewが再生成されても進捗・結果が維持される。
struct ConvertView: View {
    @State private var viewModel: ConvertViewModel
    private let jobStore: ConvertJobStore
    private let toolsReady: Bool
    @Environment(\.locale) private var locale

    init(jobStore: ConvertJobStore, toolsReady: Bool = true) {
        self.jobStore = jobStore
        self.toolsReady = toolsReady
        _viewModel = State(initialValue: ConvertViewModel(jobStore: jobStore))
    }

    private var lang: String { locale.language.languageCode?.identifier ?? "" }
    private func t(_ key: String) -> String { L10n.string(key, language: lang) }

    private func selectFolder(isInput: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if isInput {
                viewModel.inputFolderPath = url.path
            } else {
                viewModel.outputFolderPath = url.path
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Color.clear
                        .frame(height: 1)
                        .id("convertTop")
                    GlassCard {

                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            GridRow {
                                Text(t("c.label.targetFolder")).appFont(.headline)
                                HStack {
                                    Button {
                                        selectFolder(isInput: true)
                                    } label: {
                                        Text(t("c.folderButton")).appFont(.body)
                                    }
                                    TextField(t("c.label.targetFolder"), text: $viewModel.inputFolderPath)
                                        .appFont(.body)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(
                                                    viewModel.inputFolderHasError ? Color.red : Color.clear,
                                                    lineWidth: 2
                                                )
                                        )
                                    HelpPopover(text: t("c.help.targetFolder"))
                                }
                            }
                            GridRow {
                                Text(t("c.label.targetFiles")).appFont(.headline)
                                HStack {
                                    Picker(t("c.label.targetFiles"), selection: $viewModel.targetFilter) {
                                        Text(t("c.filter.oneDay")).appFont(.body).tag(TargetFilter.oneDay)
                                        Text(t("c.filter.threeDays")).appFont(.body).tag(TargetFilter.threeDays)
                                        Text(t("c.filter.sevenDays")).appFont(.body).tag(TargetFilter.sevenDays)
                                        Text(t("c.filter.thirtyDays")).appFont(.body).tag(TargetFilter.thirtyDays)
                                        Text(t("c.filter.all")).appFont(.body).tag(TargetFilter.all)
                                    }
                                    .labelsHidden()
                                    Spacer()
                                    HelpPopover(text: t("c.help.targetFiles"))
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Text(t("c.group.input")).appFont(.headline)
                    }

                    ConvertSettingsView(viewModel: viewModel)

                    GlassCard {

                        HStack {
                            Text(t("c.label.parallel")).appFont(.headline)
                            Slider(value: $viewModel.parallelCount, in: 1...viewModel.settings.maxParallel, step: 1)
                                .tint(
                                    SliderLoadLevel.parallelLevel(
                                        parallel: viewModel.parallelCount,
                                        maxParallel: viewModel.settings.maxParallel
                                    ).tint
                                )
                            Text("\(Int(viewModel.parallelCount))").appFont(.body).frame(width: 30)
                            HelpPopover(text: t("c.help.parallel"))
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Text(t("c.group.process")).appFont(.headline)
                    }

                    GlassCard {

                        HStack {
                            Text(t("c.label.outputFolder")).appFont(.headline)
                            Button {
                                selectFolder(isInput: false)
                            } label: {
                                Text(t("c.folderButton")).appFont(.body)
                            }
                            TextField(t("c.label.outputFolder"), text: $viewModel.outputFolderPath)
                                .appFont(.body)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            viewModel.outputFolderHasError ? Color.red : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                            HelpPopover(text: t("c.help.outputFolder"))
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Text(t("c.group.output")).appFont(.headline)
                    }

                    GlassCTAButton(
                        title: jobStore.isRunning ? t("c.running") : t("c.run"),
                        disabled: !viewModel.canRun,
                        systemImage: "play.fill"
                    ) {
                        viewModel.runConversion()
                        // 実行結果が見えるよう画面最下部へ自動スクロールする。
                        Task {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            withAnimation {
                                proxy.scrollTo("convertBottom", anchor: .bottom)
                            }
                        }
                    }

                    if jobStore.isRunning {
                        ConvertRunControlsView(jobStore: jobStore, lang: lang)
                    }

                    // 実行が終わると操作ボタンごと消えるため、結果（成功・混在・キャンセル）は
                    // この位置に残す。Why not 通知だけに任せるか: 通知を切っている設定でも
                    // キャンセル後に何が起きたか分からなくなるため。
                    if !jobStore.isRunning, !jobStore.resultMessage.isEmpty {
                        Text(jobStore.resultMessage)
                            .appFont(.body)
                            .foregroundStyle(.secondary)
                    }

                    GlassCard {

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Toggle(isOn: $viewModel.showWaiting) {
                                    Text(t("status.waitingIcon")).appFont(.body)
                                }
                                Toggle(isOn: $viewModel.showRunning) {
                                    Text(t("status.runningIcon")).appFont(.body)
                                }
                                Toggle(isOn: $viewModel.showSuccess) {
                                    Text(t("status.successIcon")).appFont(.body)
                                }
                                Toggle(isOn: $viewModel.showFailure) {
                                    Text(t("status.failureIcon")).appFont(.body)
                                }
                                Toggle(isOn: $viewModel.showCancelled) {
                                    Text(t("status.cancelledIcon")).appFont(.body)
                                }
                            }
                            .toggleStyle(.checkbox)
                            HStack {
                                ProgressView(value: jobStore.progressPercent, total: 100)
                                Text("\(Int(jobStore.progressPercent))%")
                                    .frame(width: 64, alignment: .trailing)
                                    .appFont(.headline)
                            }
                            Table(viewModel.filteredRows(for: jobStore.rows)) {
                                TableColumn(t("c.col.fileName")) { row in
                                    Text(row.fileName).appFont(.body)
                                }
                                TableColumn(t("c.col.before")) { row in
                                    FileLinkCell(path: row.sourcePath, missingMessage: t("c.missingFile"))
                                }
                                .width(min: 30, ideal: 40, max: 50)
                                TableColumn(t("c.col.upscale")) { row in
                                    Text(row.upscale.label(language: lang)).appFont(.body)
                                }
                                .width(min: 40, ideal: 62, max: 90)
                                TableColumn(t("c.col.compress")) { row in
                                    Text(row.compress.label(language: lang)).appFont(.body)
                                }
                                .width(min: 40, ideal: 52, max: 90)
                                TableColumn(t("c.col.output")) { row in
                                    Text(row.output.label(language: lang)).appFont(.body)
                                }
                                .width(min: 40, ideal: 52, max: 90)
                                TableColumn(t("c.col.after")) { row in
                                    FileLinkCell(path: row.outputPath, missingMessage: t("c.missingFile"))
                                }
                                .width(min: 30, ideal: 40, max: 50)
                            }
                            .frame(minHeight: 360)
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Text(t("c.group.result")).appFont(.headline)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("convertBottom")
                }
                .padding(.horizontal)
                .padding(.bottom, 0)
            }
            .safeAreaInset(edge: .bottom) {
                // Apple Musicのダイナミックタブバーのように、
                // フッターとトップへ戻るボタンを独立した2つのガラスでフローティング表示する。
                HStack(alignment: .bottom, spacing: 12) {
                    HStack(spacing: 16) {
                        FooterStat(icon: "photo.stack", text: "\(t("c.footer.target")): \(jobStore.rows.count)")
                        FooterStat(
                            icon: "checkmark.circle", iconColor: .green,
                            text: "\(t("c.footer.success")): \(jobStore.successCount)")
                        FooterStat(
                            icon: "xmark.circle", iconColor: .red,
                            text: "\(t("c.footer.failure")): \(jobStore.failureCount)")
                        FooterStat(icon: "clock", text: String(format: t("c.elapsed"), jobStore.elapsedMinutes))
                        // キャンセル待ちは完了件数が増えないため、残り時間を出さない。
                        let eta =
                            jobStore.isRunning && !jobStore.isCancelling
                            ? jobStore.estimatedRemainingMinutes : nil
                        if let eta {
                            FooterStat(icon: "hourglass", text: String(format: t("c.remaining"), eta))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .glassEffect(
                        .regular.tint(Color.accentColor.opacity(GlassStyle.footerTintOpacity)).interactive(),
                        in: RoundedRectangle(cornerRadius: GlassStyle.footerCornerRadius)
                    )
                    Button {
                        withAnimation {
                            proxy.scrollTo("convertTop", anchor: .top)
                        }
                    } label: {
                        Image(systemName: "arrow.up")
                            .appFont(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        .regular.tint(Color.accentColor.opacity(GlassStyle.footerTintOpacity)).interactive(),
                        in: .circle
                    )
                    .help(t("c.backToTop"))
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle(t("c.navTitle"))
        .onChange(of: toolsReady) { _, ready in
            // Why not: ViewModelの初期化はツール展開の完了前に走るため、
            // 完了後の再読込を欠かすと配置済みでも未配置表示のままになる。
            if ready { viewModel.reloadTools() }
        }
    }
}

/// 実行中だけ表示する一時停止・キャンセルの操作（ADR 0054）。
/// 一時停止は区切りで効くため、押した直後も実行中のバッチは終わるまで進む。
private struct ConvertRunControlsView: View {
    var jobStore: ConvertJobStore
    var lang: String
    /// キャンセル確認ダイアログの表示状態。止める操作は取り消せないため必ず確認する。
    @State private var showsCancelConfirmation = false

    private func t(_ key: String) -> String { L10n.string(key, language: lang) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                GlassCTAButton(
                    title: jobStore.isPaused ? t("c.resume") : t("c.pause"),
                    disabled: jobStore.isCancelling,
                    tint: .yellow,
                    systemImage: jobStore.isPaused ? "play.fill" : "pause.fill"
                ) {
                    if jobStore.isPaused {
                        jobStore.resume()
                    } else {
                        jobStore.pause()
                    }
                }
                GlassCTAButton(
                    title: t("c.cancel"), disabled: jobStore.isCancelling, tint: .red,
                    systemImage: "xmark"
                ) {
                    showsCancelConfirmation = true
                }
            }
            if jobStore.isCancelling || jobStore.isPaused {
                Text(jobStore.isCancelling ? t("c.cancelling") : t("c.paused"))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .alert(t("c.cancel.confirmTitle"), isPresented: $showsCancelConfirmation) {
            Button(t("c.cancel.confirmAction"), role: .destructive) {
                jobStore.cancel()
            }
            Button(t("a.cancel"), role: .cancel) {}
        } message: {
            Text(t("c.cancel.confirmMessage"))
        }
    }
}

/// 変換前後の画像をFinderで表示するリンクセル。
/// ファイルが存在しない場合はポップオーバーで通知する（Why not: 選択するとFinderが空振りするため）。
private struct FileLinkCell: View {
    var path: String
    var missingMessage: String

    @State private var showsMissing = false

    var body: some View {
        Button {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                showsMissing = true
            }
        } label: {
            Text("🔗").appFont(.body)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsMissing) {
            Text(missingMessage)
                .appFont(.body)
                .padding()
        }
    }
}

/// フッターの統計1項目。Apple Musicのダイナミックタブバーのように
/// アイコンの下にテキストを配置する。
private struct FooterStat: View {
    var icon: String
    var iconColor: Color?
    var text: String

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .appFont(.headline)
                .foregroundStyle(iconColor ?? .primary)
            Text(text)
                .appFont(.caption)
        }
        .frame(maxWidth: .infinity)
    }
}
