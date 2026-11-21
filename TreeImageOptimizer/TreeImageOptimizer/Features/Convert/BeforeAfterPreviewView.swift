import AppKit
import SwiftUI

/// 変換前後の画像をスライダーで比較するビュー（ADR 0071）。
/// 前後の画像はアスペクト比を保ったまま同じ表示サイズに揃え、区切り線で「前 → 後」を切り替える。
struct BeforeAfterPreviewView: View {
    let beforePath: String
    let afterPath: String

    @State private var split: CGFloat = 0.5

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .leading) {
                // 後（変換後）を全面に表示する。
                previewImage(afterPath)
                    .frame(width: width, height: height)
                // 前（変換前）を左側の区切りまで表示する。
                previewImage(beforePath)
                    .frame(width: width, height: height)
                    .frame(width: width * split, alignment: .leading)
                    .clipped()
                // 区切り線とハンドル。
                Rectangle()
                    .fill(.white)
                    .frame(width: 2, height: height)
                    .offset(x: width * split - 1)
                Image(systemName: "arrow.left.and.right")
                    .font(.caption.bold())
                    .foregroundStyle(.black)
                    .padding(6)
                    .background(.white, in: Circle())
                    .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                    .offset(x: width * split - 14)
            }
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        split = min(max(value.location.x / width, 0), 1)
                    }
            )
        }
    }

    /// 画像を読み、無ければプレースホルダーを返す。
    @ViewBuilder
    private func previewImage(_ path: String) -> some View {
        if let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            ZStack {
                Color.gray.opacity(0.2)
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 結果表のプレビューセル。クリックで比較シートを開く（ADR 0071）。
struct ConvertPreviewCell: View {
    let beforePath: String
    let afterPath: String
    let title: String
    let beforeLabel: String
    let afterLabel: String

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Text("🔍").appFont(.body)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).appFont(.headline)
                BeforeAfterPreviewView(beforePath: beforePath, afterPath: afterPath)
                    .frame(minHeight: 320)
                HStack {
                    Text(beforeLabel).appFont(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(afterLabel).appFont(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(minWidth: 480, minHeight: 420)
        }
    }
}
