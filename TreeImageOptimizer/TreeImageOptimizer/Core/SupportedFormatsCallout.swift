import SwiftUI

/// 入力として受け付けている拡張子を、GitHub Alerts 風のコールアウトとバッジで示す。
/// 「モードの特徴」コールアウトと同じ見た目に揃え、入力エリアで対応形式を確認できるようにする。
/// 表示する拡張子は `TargetFiles.supportedExtensions` を正とするため、対応形式を増やすと
/// この表示も自動で追従する。
struct SupportedFormatsCallout: View {
    let localize: (String) -> String
    /// 表示する拡張子。呼び出し側が入力として受け付ける形式を渡す。
    /// Why not 既定値で `TargetFiles` を参照するか: Core から Services への依存を作らないため。
    let extensions: [String]

    private let tint = Color.blue

    var body: some View {
        CalloutContainer(tint: tint) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 8) {
                    Text(localize("c.formats.title"))
                        .appFont(.headline)
                        .foregroundStyle(tint)
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
