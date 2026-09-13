import AppKit
import SwiftUI

/// 一括画像変換画面。
/// 実行状態は共有の `ConvertJobStore` を参照するため、サイドナビ切替で
/// Viewが再生成されても進捗・結果が維持される。
struct ConvertView: View {
    @State private var viewModel: ConvertViewModel
    private let jobStore: ConvertJobStore
    @State private var hoveredFileRowID: UUID?
    @Environment(\.locale) private var locale

    init(jobStore: ConvertJobStore) {
        self.jobStore = jobStore
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
                GroupBox {

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

                GroupBox {

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text(t("c.label.scale")).appFont(.headline)
                            HStack {
                                Slider(value: $viewModel.scale, in: 1 ... 4, step: 1)
                                Text("\(Int(viewModel.scale))").appFont(.body).frame(width: 30)
                                Spacer()
                                HelpPopover(text: t("c.help.scale"))
                            }
                        }
                        GridRow {
                            Text(t("c.label.model")).appFont(.headline)
                            HStack {
                                Picker(t("c.label.model"), selection: $viewModel.selectedModel) {
                                    ForEach(viewModel.models, id: \.self) { model in
                                        Text(model).appFont(.body).tag(model)
                                    }
                                }
                                .labelsHidden()
                                Spacer()
                                HelpPopover(text: t("c.help.model"))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text(t("c.group.upscale")).appFont(.headline)
                }

                GroupBox {

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text(t("c.label.format")).appFont(.headline)
                            HStack {
                                Picker(t("c.label.format"), selection: $viewModel.format) {
                                    Text("JPEG").appFont(.body).tag(OutputFormat.jpeg)
                                    Text("PNG").appFont(.body).tag(OutputFormat.png)
                                    Text("JPEG XL").appFont(.body).tag(OutputFormat.jpegXL)
                                    Text("AV1").appFont(.body).tag(OutputFormat.av1)
                                    Text("WebP").appFont(.body).tag(OutputFormat.webp)
                                }
                                .labelsHidden()
                                Spacer()
                                HelpPopover(text: t("c.help.format"))
                            }
                        }
                        GridRow {
                            Text(t("c.label.optimizeType")).appFont(.headline)
                            HStack {
                                Picker(t("c.label.optimizeType"), selection: $viewModel.optimizeType) {
                                    Text(t("c.optimize.anime")).appFont(.body).tag(OptimizeType.anime)
                                    Text(t("c.optimize.photo")).appFont(.body).tag(OptimizeType.photo)
                                    Text(t("c.optimize.speed")).appFont(.body).tag(OptimizeType.speed)
                                    Text(t("c.optimize.quality")).appFont(.body).tag(OptimizeType.quality)
                                }
                                .labelsHidden()
                                Spacer()
                                HelpPopover(text: t("c.help.optimizeType"))
                            }
                        }
                        GridRow {
                            Text(t("c.label.quality")).appFont(.headline)
                            HStack {
                                Slider(value: $viewModel.quality, in: 1 ... 100, step: 1)
                                Text("\(Int(viewModel.quality))").appFont(.body).frame(width: 40)
                                Spacer()
                                HelpPopover(text: t("c.help.format"))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text(t("c.group.compress")).appFont(.headline)
                }

                GroupBox {

                    HStack {
                        Text(t("c.label.parallel")).appFont(.headline)
                        Slider(value: $viewModel.parallelCount, in: 1 ... viewModel.maxParallel, step: 1)
                        Text("\(Int(viewModel.parallelCount))").appFont(.body).frame(width: 30)
                        HelpPopover(text: t("c.help.parallel"))
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text(t("c.group.process")).appFont(.headline)
                }

                GroupBox {

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
                    disabled: !viewModel.canRun
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

                GroupBox {

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
                        }
                        .toggleStyle(.checkbox)
                        HStack {
                            ProgressView(value: jobStore.progressPercent, total: 100)
                            Text("\(Int(jobStore.progressPercent))%")
                                .frame(width: 64, alignment: .trailing)
                                .appFont(.headline)
                        }
                        Table(viewModel.filteredRows(for: jobStore.rows)) {
                            TableColumn(t("c.col.fileName")) {
                                row in
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting([
                                        URL(fileURLWithPath: row.sourcePath)
                                    ])
                                } label: {
                                    Text(row.fileName)
                                        .appFont(.body)
                                        .foregroundStyle(
                                            hoveredFileRowID == row.id ? Color.accentColor : Color.primary
                                        )
                                        .underline(hoveredFileRowID == row.id)
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .help(t("c.help.fileName"))
                                // セルの作り直し時にも exit が飛ぶため、ここでは状態を消さない。
                                // 消去は表全体の exit でのみ行う。
                                .onHover { hovering in
                                    if hovering {
                                        hoveredFileRowID = row.id
                                        NSCursor.pointingHand.push()
                                    } else {
                                        NSCursor.pop()
                                    }
                                }
                            }
                            TableColumn(t("c.col.upscale")) { row in
                                Text(row.upscale.label(language: lang)).appFont(.body)
                            }
                            .width(min: 40, ideal: 62, max: 90)
                            TableColumn(t("c.col.compress")) { row in
                                Text(row.compress.label(language: lang)).appFont(.body)
                            }
                            .width(min: 40, ideal: 62, max: 90)
                            TableColumn(t("c.col.output")) { row in
                                Text(row.output.label(language: lang)).appFont(.body)
                            }
                            .width(min: 40, ideal: 62, max: 90)
                        }
                        .frame(minHeight: 360)
                        // ポインターが表全体から外れたときだけホバーを消す。
                        .onHover { hovering in
                            if !hovering {
                                hoveredFileRowID = nil
                            }
                        }
                        // ファイル名ヘッダーの右にℹ️を重ねる。
                        // TableColumnにヘッダービュー指定APIがないため、
                        // 見出しと同文言の非表示テキストで位置合わせする。
                        .overlay(alignment: .topLeading) {
                            HStack(spacing: 4) {
                                Text(t("c.col.fileName")).appFont(.body).hidden()
                                HelpPopover(text: t("c.help.fileName"))
                            }
                            .padding(.leading, 12)
                            .padding(.top, 2)
                        }
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
                        FooterStat(icon: "checkmark.circle", iconColor: .green, text: "\(t("c.footer.success")): \(jobStore.successCount)")
                        FooterStat(icon: "xmark.circle", iconColor: .red, text: "\(t("c.footer.failure")): \(jobStore.failureCount)")
                        FooterStat(icon: "clock", text: String(format: t("c.elapsed"), jobStore.elapsedMinutes))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .glassEffect(.regular.tint(Color.accentColor.opacity(0.2)).interactive(), in: RoundedRectangle(cornerRadius: 22))
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
                    .glassEffect(.regular.tint(Color.accentColor.opacity(0.2)).interactive(), in: .circle)
                    .help(t("c.backToTop"))
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .navigationTitle(t("c.navTitle"))
    }
}

/// フッターの統計1項目。Apple Musicのダイナミックタブバーのように
/// アイコンの下にテキストを配置する。
private struct FooterStat: View {
    var icon: String
    var iconColor: Color? = nil
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
