import SwiftUI

/// 入力として受け付けている拡張子を、GitHub Alerts 風のコールアウトとバッジで示す。
/// モードの説明コールアウトと同じ見た目に揃え、入力エリアで対応形式を確認できるようにする。
/// 表示する拡張子は `TargetFiles.supportedExtensions` を正とするため、対応形式を増やすと
/// この表示も自動で追従する。
struct SupportedFormatsCallout: View {
    let localize: (String) -> String
    /// 表示する拡張子。呼び出し側が入力として受け付ける形式を渡す。
    /// Why not 既定値で `TargetFiles` を参照するか: Core から Services への依存を作らないため。
    let extensions: [String]
    /// 開閉パネルとして使うときの展開状態。`nil` のときは常に本文を表示する。
    /// Why not 常に開閉するか: かんたん変換は操作を絞りたいため、
    /// 対応形式の本文は常に表示しておく。
    var expanded: Binding<Bool>?

    private let tint = Color.blue
    private let symbol = "photo.on.rectangle.angled"

    var body: some View {
        if let expanded {
            CollapsibleCallout(
                tint: tint, icon: symbol, title: localize("c.formats.title"),
                isExpanded: expanded,
                expandedStateLabel: localize("c.callout.expanded"),
                collapsedStateLabel: localize("c.callout.collapsed")
            ) {
                details
            }
        } else {
            CalloutContainer(tint: tint) {
                CalloutLayout(icon: symbol, tint: tint) {
                    Text(localize("c.formats.title"))
                        .appFont(.headline)
                        .foregroundStyle(tint)
                } content: {
                    details
                }
            }
        }
    }

    /// 説明文と拡張子バッジ。開閉パネルと常時表示のどちらでも同じ内容を出す。
    @ViewBuilder private var details: some View {
        Text(localize("c.formats.message"))
            .appFont(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        // 幅に応じて折り返す。カードが狭くなってもバッジが潰れないようにする。
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 66), spacing: 6, alignment: .leading)],
            alignment: .leading, spacing: 6
        ) {
            ForEach(extensions, id: \.self) { ext in
                FormatBadge(label: ext.uppercased(), color: Self.color(for: ext))
            }
        }
    }

    /// 形式ごとの色。系統（JPEG / PNG / WebP / HEIF・HEIC / AVIF）で色を変え、
    /// 一覧の中で形式の違いを見分けやすくする。
    static func color(for ext: String) -> Color {
        switch ext.lowercased() {
        case "jpg", "jpeg": return .orange
        case "png": return .indigo
        case "webp": return .teal
        case "heic", "heif": return .blue
        case "avif": return .green
        default: return .secondary
        }
    }
}

/// 拡張子1つ分のバッジ。等幅フォントで拡張子が揃って見えるようにする。
private struct FormatBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.14), in: Capsule())
            .overlay {
                Capsule().stroke(color.opacity(0.35), lineWidth: 1)
            }
    }
}
