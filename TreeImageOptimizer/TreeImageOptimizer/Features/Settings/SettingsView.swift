import AppKit
import OSLog
import SwiftUI

private let bgHexLogger = Logger(
    subsystem: "com.treeimageoptimizer.TreeImageOptimizer",
    category: "bghex"
)

/// 設定画面。
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel = SettingsViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    @Environment(\.locale) private var locale
    private var lang: String { locale.language.languageCode?.identifier ?? "" }
    private func t(_ key: String) -> String { L10n.string(key, language: lang) }

    @State private var bgHexDraft = ""
    @State private var bgHexInvalid = false
    @State private var bgHexFieldID = UUID()

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { parseHex(viewModel.effectiveWallpaperBackgroundColorHex) ?? .white },
            set: {
                viewModel.wallpaperBackgroundColorHex = hexString($0)
                bgHexDraft = viewModel.wallpaperBackgroundColorHex
                bgHexInvalid = false
            }
        )
    }

    /// Enter確定時にドラフトを検証・反映する。
    /// 正常値なら反映して通常枠に戻し、不正値なら赤枠＋変更前の値に復元する。
    /// 無効な入力は保存されないため、ViewModel側が変更前の値を保持している。
    private func commitBgHex() {
        let input = bgHexDraft
        let valid = viewModel.commitBackgroundHex(input)
        if valid {
            bgHexInvalid = false
        } else {
            bgHexInvalid = true
            bgHexDraft = viewModel.wallpaperBackgroundColorHex
            // 編集中のフィールドはプログラム側の変更を反映しないため、
            // IDを付け替えて再生成し、復元値を確実に表示する。
            bgHexFieldID = UUID()
        }
        bgHexLogger.info("bghex commit: input=\(input, privacy: .public) valid=\(valid) stored=\(viewModel.wallpaperBackgroundColorHex, privacy: .public)")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Toggle(isOn: $viewModel.showOsNotification) {
                                Text(t("s.showNotification")).appFont(.body)
                            }
                            .help(t("s.help.showNotification"))
                            .gridCellColumns(2)
                        }
                        GridRow {
                            Toggle(isOn: $viewModel.playSound) {
                                Text(t("s.playSound")).appFont(.body)
                            }
                            .help(t("s.help.playSound"))
                            .gridCellColumns(2)
                        }
                        GridRow {
                            Text(t("s.successSound")).appFont(.body)
                            HStack {
                                Picker(t("s.successSound"), selection: $viewModel.successSound) {
                                    ForEach(viewModel.successSounds) { option in
                                        Text(option.label(language: lang)).appFont(.body).tag(option.name)
                                    }
                                }
                                .labelsHidden()
                                Button {
                                    viewModel.playSuccessSound()
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .help(t("s.help.playThis"))
                                Spacer()
                                HelpPopover(text: t("s.help.successSound"))
                            }
                        }
                        GridRow {
                            Text(t("s.errorSound")).appFont(.body)
                            HStack {
                                Picker(t("s.errorSound"), selection: $viewModel.errorSound) {
                                    ForEach(viewModel.errorSounds) { option in
                                        Text(option.label(language: lang)).appFont(.body).tag(option.name)
                                    }
                                }
                                .labelsHidden()
                                Button {
                                    viewModel.playErrorSound()
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .help(t("s.help.playThis"))
                                Spacer()
                                HelpPopover(text: t("s.help.errorSound"))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text(t("s.group.action")).appFont(.headline)
                }
                .frame(maxWidth: .infinity)

                GroupBox {

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text(t("s.appearance")).appFont(.headline)
                            HStack {
                            ForEach(AppearanceMode.allCases) { mode in
                                let selected = viewModel.appearance == mode.rawValue
                                Button {
                                    viewModel.setAppearance(mode.rawValue)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                                        Image(systemName: appearanceIcon(mode))
                                        Text(appearanceText(mode)).appFont(.body)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                selected ? Color.accentColor : Color.secondary.opacity(0.4),
                                                lineWidth: selected ? 2 : 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                            }
                        }
                        GridRow {
                            Text(t("s.language")).appFont(.headline)
                            HStack {
                            Picker(t("s.language"), selection: $viewModel.language) {
                                Text(t("s.lang.auto")).appFont(.body).tag("")
                                Text(t("s.lang.ja")).appFont(.body).tag("ja-JP")
                                Text(t("s.lang.en")).appFont(.body).tag("en-US")
                            }
                            .labelsHidden()
                            Spacer()
                            HelpPopover(text: t("s.help.language"))
                            }
                        }
                        GridRow {
                            Text(t("s.fontSize")).appFont(.headline)
                            HStack {
                            ForEach(FontSizeOption.allCases) { option in
                                let selected = viewModel.fontSize == option.rawValue
                                Button {
                                    viewModel.fontSize = option.rawValue
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                                        Image(systemName: fontSizeIcon(option))
                                        Text(fontSizeText(option)).appFont(.body)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                selected ? Color.accentColor : Color.secondary.opacity(0.4),
                                                lineWidth: selected ? 2 : 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                            }
                        }
                        GridRow {
                            Text(t("s.wallpaper")).appFont(.headline)
                            HStack {
                            Picker(t("s.wallpaper"), selection: $viewModel.wallpaper) {
                                ForEach(viewModel.wallpapers) { option in
                                    Text(wallpaperLabel(for: option)).appFont(.body).tag(option.name)
                                }
                            }
                            .labelsHidden()
                            Spacer()
                            HelpPopover(text: t("s.help.wallpaper"))
                            }
                        }
                        GridRow {
                            Text(t("s.opacity")).appFont(.headline)
                            HStack {
                            Slider(value: $viewModel.wallpaperOpacity, in: 0 ... 1)
                                .frame(maxWidth: .infinity)
                            Text(String(format: "%.1f", viewModel.wallpaperOpacity)).appFont(.body)
                                .frame(width: 32)
                            Spacer()
                            HelpPopover(text: t("s.help.opacity"))
                            }
                        }
                        GridRow {
                            Text(t("s.bgcolor")).appFont(.headline)
                            HStack {
                            // 自動モードではシステム値を使うため編集不可にする。
                            // タイトルはGridのラベル欄に表示するため、空にして重複を防ぐ。
                            ColorPicker("", selection: backgroundColorBinding)
                            .labelsHidden()
                                .disabled(viewModel.appearance == AppearanceMode.auto.rawValue)
                                .accessibilityLabel(t("s.bgcolor"))
                            TextField("#FFFFFF", text: $bgHexDraft, onCommit: commitBgHex)
                                .appFont(.body)
                                .id(bgHexFieldID)
                                .frame(maxWidth: 110)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(
                                            bgHexInvalid ? Color.red : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                            Button {
                                viewModel.resetWallpaperBackgroundColor()
                                bgHexDraft = viewModel.wallpaperBackgroundColorHex
                                bgHexInvalid = false
                            } label: {
                                Text(t("s.reset")).appFont(.body)
                            }
                            .help(t("s.resetHelp"))
                            .disabled(viewModel.appearance == AppearanceMode.auto.rawValue)
                            Spacer()
                            HelpPopover(text: t("s.help.bgcolor"))
                            }
                        }
                        .onAppear {
                            bgHexDraft = viewModel.wallpaperBackgroundColorHex
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text(t("s.group.basic")).appFont(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .navigationTitle(t("s.navTitle"))
    }

    private func wallpaperLabel(for option: WallpaperOption) -> String {
        if option.name == WallpaperSelection.noneName {
            return t("s.none")
        }
        return option.label(language: lang)
    }

    private func appearanceText(_ mode: AppearanceMode) -> String {
        switch mode {
        case .auto: return t("s.appearance.auto")
        case .light: return t("s.appearance.light")
        case .dark: return t("s.appearance.dark")
        }
    }

    private func appearanceIcon(_ mode: AppearanceMode) -> String {
        switch mode {
        case .auto: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.fill"
        }
    }

    private func fontSizeText(_ option: FontSizeOption) -> String {
        switch option {
        case .small: return t("s.fontSize.small")
        case .standard: return t("s.fontSize.standard")
        case .large: return t("s.fontSize.large")
        }
    }

    private func fontSizeIcon(_ option: FontSizeOption) -> String {
        switch option {
        case .small: return "textformat.size.smaller"
        case .standard: return "textformat.size"
        case .large: return "textformat.size.larger"
        }
    }

    private func parseHex(_ hex: String) -> Color? {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        if h.count == 6 { h = "FF" + h }
        guard h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        return Color(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255
        )
    }

    private func hexString(_ color: Color) -> String {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
