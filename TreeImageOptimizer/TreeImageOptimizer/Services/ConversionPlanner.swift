import CoreGraphics
import Foundation
import ImageIO

/// 1ファイル分の変換計画。実行前に寸法とファイルサイズから組み立てる。
struct FilePlan: Sendable, Equatable {
    /// 超解像の倍率。`nil` は超解像をかけない。
    var scale: Int?
    /// 出力の目標長辺。`nil` はリサイズしない。
    /// 超解像後に目標を超えた場合の縮小と、目標が近い場合のリサイズだけに使う。
    var resizeLongEdge: Int?
    /// 圧縮品質。
    var quality: Int
}

/// 画像の寸法とファイルサイズ。圧縮の強弱はBPP（bytes per pixel）で決める。
struct ImageMetadata: Sendable, Equatable {
    var width: Int
    var height: Int
    var bytes: Int

    var longEdge: Int { max(width, height) }

    /// 寸法に対してファイルが大きいほど高い値になる。
    var bytesPerPixel: Double {
        guard width > 0, height > 0 else { return 0 }
        return Double(bytes) / Double(width * height)
    }

    /// `CGImageSource` で寸法を読み、ファイルサイズを添える。読めない場合はnil。
    static func read(_ url: URL) -> ImageMetadata? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = props[kCGImagePropertyPixelWidth] as? Int,
            let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ImageMetadata(width: width, height: height, bytes: bytes)
    }
}

/// 画像ごとの変換計画を組み立てる純粋関数。
///
/// 固定モードは全ファイルに同じ倍率・品質を返す。自動モードは目標解像度までの
/// 不足分を整数倍で補い、目標を超えた出力は目標長辺へ縮小する（ADR 0049）。
/// 目標との差が僅かな場合は超解像を使わず、高品質リサイズだけで目標に合わせる。
enum ConversionPlanner {
    /// 超解像をかける最小倍率。これ未満は2倍のコストに見合う画質差が出ないため、
    /// 高品質リサイズで目標ちょうどに合わせる。
    static let modelUpscaleRatio = 1.2
    static let minScale = 2
    static let maxScale = 4

    /// 全ファイルの計画を返す。自動モードでは寸法とサイズの読み取りに失敗したファイルを
    /// 拡大なし・プリセット品質として扱う（後段のデコードで失敗が報告される）。
    static func plans(for files: [URL], config: ConvertConfig) -> [FilePlan] {
        switch config.mode {
        case .fixed:
            return files.map { _ in
                FilePlan(scale: config.scale, resizeLongEdge: nil, quality: config.quality)
            }
        case .auto:
            return files.map { url in
                guard let metadata = ImageMetadata.read(url) else {
                    return FilePlan(
                        scale: nil, resizeLongEdge: nil, quality: config.qualityPreset.quality)
                }
                return plan(metadata: metadata, config: config)
            }
        }
    }

    static func plan(metadata: ImageMetadata, config: ConvertConfig) -> FilePlan {
        let target = config.targetSize.longEdge
        let sourceLong = metadata.longEdge
        let quality = adjustedQuality(
            base: config.qualityPreset.quality, bytesPerPixel: metadata.bytesPerPixel)

        // 元画像が既に目標以上なら拡大しない（縮小もしない）。
        guard sourceLong > 0, sourceLong < target else {
            return FilePlan(scale: nil, resizeLongEdge: nil, quality: quality)
        }

        let ratio = Double(target) / Double(sourceLong)
        if ratio < modelUpscaleRatio {
            // 僅差は高品質リサイズで目標ちょうどに合わせる。
            return FilePlan(scale: nil, resizeLongEdge: target, quality: quality)
        }

        let scale = min(maxScale, max(minScale, Int(ratio.rounded(.up))))
        let outputLong = sourceLong * scale
        let resize = outputLong > target ? target : nil
        return FilePlan(scale: scale, resizeLongEdge: resize, quality: quality)
    }

    /// 入力BPPに応じた品質補正。ファイルが大きい（BPPが高い）ほど強く圧縮し、
    /// 既に小さい画像は弱く圧縮する。補正幅はプリセットの範囲内に収める。
    static func adjustedQuality(base: Int, bytesPerPixel: Double) -> Int {
        let delta: Int
        switch bytesPerPixel {
        case 0.5...: delta = -15
        case 0.25..<0.5: delta = -10
        case 0.12..<0.25: delta = 0
        default: delta = 5
        }
        return min(100, max(1, base + delta))
    }

    /// 長辺を `longEdge` に合わせた寸法。アスペクト比を維持する。
    static func resizedDimensions(width: Int, height: Int, longEdge: Int) -> (width: Int, height: Int) {
        let sourceLong = max(width, height)
        guard sourceLong > 0, sourceLong != longEdge else { return (width, height) }
        let ratio = Double(longEdge) / Double(sourceLong)
        return (
            max(1, Int((Double(width) * ratio).rounded())),
            max(1, Int((Double(height) * ratio).rounded()))
        )
    }
}
