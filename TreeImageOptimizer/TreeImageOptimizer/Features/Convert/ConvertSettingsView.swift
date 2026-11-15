import SwiftUI

/// 一括変換の最適化設定。
/// モードタブを設定カードのガラス面の先頭に置き、直下の「拡大」「圧縮」が
/// そのモードの対象であることを示す（ADR 0049）。
struct ConvertSettingsView: View {
    @Bindable var viewModel: ConvertViewModel
    @Environment(\.locale) private var locale

    private var lang: String { locale.language.languageCode?.identifier ?? "" }
    private func t(_ key: String) -> String { L10n.string(key, language: lang) }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    ConvertModeTabBar(mode: $viewModel.mode, localize: t)
                    HelpPopover(text: t("c.help.mode"))
                }

                Text(t("c.mode.scope"))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)

                upscaleSection
                compressSection
            }
        } label: {
            Text(t("c.group.settings")).appFont(.headline)
        }
    }

    private var upscaleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("c.group.upscale")).appFont(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(t("c.label.engine")).appFont(.headline)
                    HStack {
                        Picker(t("c.label.engine"), selection: $viewModel.engine) {
                            ForEach(UpscaleEngine.allCases) { engine in
                                Text(engine.displayName).appFont(.body).tag(engine)
                            }
                        }
                        .labelsHidden()
                        Spacer()
                        HelpPopover(text: t("c.help.engine"))
                    }
                }
                if viewModel.mode == .fixed || viewModel.engine == .upscayl {
                    GridRow {
                        Text(t("c.label.model")).appFont(.headline)
                        HStack {
                            Picker(
                                t("c.label.model"),
                                selection: Binding(
                                    get: { viewModel.selectedModelID },
                                    set: { viewModel.selectModel(id: $0) }
                                )
                            ) {
                                ForEach(viewModel.modelOptions) { option in
                                    Text(option.label).appFont(.body).tag(option.id)
                                }
                            }
                            .labelsHidden()
                            Spacer()
                            HelpPopover(
                                text: viewModel.engine == .realCUGAN
                                    ? t("c.help.realcuganModel") : t("c.help.model"))
                        }
                    }
                }
                if viewModel.mode == .fixed {
                    GridRow {
                        Text(t("c.label.scale")).appFont(.headline)
                        HStack {
                            Slider(value: $viewModel.scale, in: viewModel.scaleRange, step: 1)
                                .tint(SliderLoadLevel.scaleLevel(for: viewModel.scale).tint)
                            Text("\(Int(viewModel.scale))").appFont(.body).frame(width: 30)
                            Spacer()
                            HelpPopover(text: t("c.help.scale"))
                        }
                    }
                } else {
                    GridRow {
                        Text(t("c.label.targetSize")).appFont(.headline)
                        HStack {
                            Picker(t("c.label.targetSize"), selection: $viewModel.targetSize) {
                                ForEach(TargetSize.allCases) { size in
                                    Text(size.label).appFont(.body).tag(size)
                                }
                            }
                            .labelsHidden()
                            Spacer()
                            HelpPopover(text: t("c.help.targetSize"))
                        }
                    }
                    if viewModel.engine == .realCUGAN {
                        GridRow {
                            Text("").appFont(.headline)
                            Text(t("c.auto.realcuganModel"))
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if viewModel.engine == .realCUGAN && !viewModel.realCuganAvailable {
                    GridRow {
                        Text("").appFont(.headline)
                        Text(t("c.realcugan.unavailable"))
                            .appFont(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var compressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t("c.group.compress")).appFont(.headline)
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
                if viewModel.mode == .fixed {
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
                            Slider(value: $viewModel.quality, in: 1...100, step: 1)
                                .tint(SliderLoadLevel.qualityLevel(for: viewModel.quality).tint)
                            Text("\(Int(viewModel.quality))").appFont(.body).frame(width: 40)
                            Spacer()
                            HelpPopover(text: t("c.help.format"))
                        }
                    }
                } else {
                    GridRow {
                        Text(t("c.label.contentType")).appFont(.headline)
                        HStack {
                            Picker(t("c.label.contentType"), selection: $viewModel.contentType) {
                                ForEach(ContentType.allCases) { contentType in
                                    Text(t(contentType.l10nKey)).appFont(.body).tag(contentType)
                                }
                            }
                            .labelsHidden()
                            Spacer()
                            HelpPopover(text: t("c.help.contentType"))
                        }
                    }
                    GridRow {
                        Text(t("c.label.qualityPreset")).appFont(.headline)
                        HStack {
                            Picker(t("c.label.qualityPreset"), selection: $viewModel.qualityPreset) {
                                ForEach(QualityPreset.allCases) { preset in
                                    Text(t(preset.l10nKey)).appFont(.body).tag(preset)
                                }
                            }
                            .labelsHidden()
                            Spacer()
                            HelpPopover(text: t("c.help.qualityPreset"))
                        }
                    }
                }
            }
        }
    }
}

/// 固定最適化 / 自動最適化を切り替えるタブ。
/// 設定画面の外観モードと同じく、選択中はテーマカラーの枠とラジオで示す。
/// 未選択側も枠を常に描き、ガラスの上でもボタンだと分かるようにする。
private struct ConvertModeTabBar: View {
    @Binding var mode: ConvertMode
    let localize: (String) -> String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ConvertMode.allCases) { item in
                let selected = mode == item
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        mode = item
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        Image(systemName: item.symbolName)
                        Text(localize(item.l10nKey)).appFont(.body)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                selected ? Color.accentColor : Color.secondary.opacity(0.45),
                                lineWidth: selected ? 2 : 1
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}
