import AppKit
import SwiftUI

/// かんたん画像変換画面。ドロップした画像を即座に変換する。
/// 実行状態は共有の `EasyConvertJobStore` を参照するため、サイドナビ切替で
/// Viewが再生成されても進捗・結果が維持される。
struct EasyConvertView: View {
    @State private var viewModel: EasyConvertViewModel
    private let jobStore: EasyConvertJobStore
    @State private var isDropTargeted = false
    @Environment(\.locale) private var locale

    init(jobStore: EasyConvertJobStore) {
        self.jobStore = jobStore
        _viewModel = State(initialValue: EasyConvertViewModel(jobStore: jobStore))
    }

    private var lang: String { locale.language.languageCode?.identifier ?? "" }
    private func t(_ key: String) -> String { L10n.string(key, language: lang) }

    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.outputFolderPath = url.path
        }
    }

    /// ドロップエリアのクリックでファイル選択ダイアログを開く。
    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            viewModel.acceptFileURLs(panel.urls)
        }
    }

    /// 直近の変換結果に応じたエリアの枠色。成功=緑、失敗=赤、未実行=グレー。
    private var dropBorderColor: Color {
        if isDropTargeted { return .accentColor }
        switch jobStore.lastRunSucceeded {
        case true: return .green
        case false: return .red
        case nil: return .secondary.opacity(0.4)
        }
    }

    /// 入力エリアの有効条件。実行中と出力フォルダの検証エラー時は受け付けない。
    /// 終了すれば `isRunning` が戻り自動的に有効になる。
    private var inputEnabled: Bool {
        !jobStore.isRunning && !viewModel.outputFolderHasError
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
                        Text(t("c.label.outputFolder")).appFont(.headline)
                        Button {
                            selectOutputFolder()
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

                GroupBox {
                    FileDropView(
                        isEnabled: inputEnabled,
                        onDropURLs: { viewModel.acceptFileURLs($0) },
                        onHighlightChanged: { isDropTargeted = $0 }
                    ) {
                        VStack(spacing: 8) {
                            if jobStore.isRunning {
                                ProgressView(value: jobStore.progressPercent, total: 100)
                                Text("\(Int(jobStore.progressPercent))%")
                                    .appFont(.headline)
                            } else {
                                Text(t("e.dropHint"))
                                    .appFont(.body)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                                if !viewModel.canRun {
                                    Text(t("e.needOutputFolder"))
                                        .appFont(.body)
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(.orange)
                                }
                            }
                            if !jobStore.resultMessage.isEmpty {
                                Text(jobStore.resultMessage)
                                    .appFont(.body)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .padding(.vertical, 4)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                dropBorderColor,
                                lineWidth: isDropTargeted || jobStore.lastRunSucceeded != nil ? 2 : 1
                            )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if inputEnabled {
                            pickFiles()
                        }
                    }
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .disabled(!inputEnabled)
                } label: {
                    Text(t("c.group.input")).appFont(.headline)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 0)
        }
        .navigationTitle(t("e.navTitle"))
    }
}

/// ドロップ受け付けのAppKitラッパー。ペーストボードからファイルURLを直接読む。
/// `isEnabled` がfalseの間はAppKitレベルでも受け付けない。
/// SwiftUIの `.disabled` だけでは `NSView` のドラッグ受け付けまで止まらないため。
struct FileDropView<Content: View>: NSViewRepresentable {
    var isEnabled: Bool = true
    var onDropURLs: ([URL]) -> Void
    var onHighlightChanged: (Bool) -> Void
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> FileDropNSView {
        let view = FileDropNSView()
        view.isEnabled = isEnabled
        view.onDropURLs = onDropURLs
        view.onHighlightChanged = onHighlightChanged
        let hosting = NSHostingView(rootView: content())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return view
    }

    func updateNSView(_ nsView: FileDropNSView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onDropURLs = onDropURLs
        nsView.onHighlightChanged = onHighlightChanged
        if let hosting = nsView.subviews.first as? NSHostingView<Content> {
            hosting.rootView = content()
        }
    }
}

final class FileDropNSView: NSView {
    var isEnabled: Bool = true
    var onDropURLs: ([URL]) -> Void = { _ in }
    var onHighlightChanged: (Bool) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isEnabled else { return [] }
        guard let types = sender.draggingPasteboard.types, types.contains(.fileURL) else { return [] }
        easyLogger.info("drag entered")
        onHighlightChanged(true)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onHighlightChanged(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard isEnabled else { return false }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        easyLogger.info("drop performed: urls=\(urls.count, privacy: .public)")
        onHighlightChanged(false)
        onDropURLs(urls)
        return true
    }
}
