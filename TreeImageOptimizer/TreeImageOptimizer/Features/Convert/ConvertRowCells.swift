import AppKit
import SwiftUI

/// 変換前後の画像をFinderで表示するリンクセル。
/// ファイルが存在しない場合はポップオーバーで通知する（Why not: 選択するとFinderが空振りするため）。
/// `ConvertView` 本体の行数制限（file_length / type_body_length）を守るため別ファイルに置く。
struct FileLinkCell: View {
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
struct FooterStat: View {
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
