import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 画像を指定した長辺へリサイズする。
/// 自動モードの「目標が近い画像の拡大」と「超解像後の縮小」に使う。
enum ImageResizer {
    /// 長辺が `longEdge` になるようアスペクト比を保ってリサイズする。
    /// 出力はPNG（後段のエンコーダが形式を問わず読める中間形式）。
    static func resize(input: URL, output: URL, longEdge: Int) throws {
        guard longEdge > 0 else { return }
        guard
            let source = CGImageSourceCreateWithURL(input as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw AppError.fileNotFound("画像のデコードに失敗しました: \(input.path)")
        }
        let dimensions = ConversionPlanner.resizedDimensions(
            width: image.width, height: image.height, longEdge: longEdge)
        guard dimensions.width != image.width || dimensions.height != image.height else {
            try linkOrCopy(input: input, output: output)
            return
        }

        // CMYKなどアルファ付きRGB以外の色空間は、8bit RGBAで描けないためsRGBへ寄せる。
        let colorSpace: CGColorSpace
        if let sourceSpace = image.colorSpace, sourceSpace.model == .rgb {
            colorSpace = sourceSpace
        } else {
            colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        }
        guard
            let context = CGContext(
                data: nil,
                width: dimensions.width,
                height: dimensions.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw AppError.verificationFailed("リサイズ用の描画領域を作成できません: \(input.path)")
        }
        context.interpolationQuality = .high
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: dimensions.width, height: dimensions.height))
        guard let resized = context.makeImage() else {
            throw AppError.verificationFailed("リサイズした画像を作成できません: \(input.path)")
        }
        guard
            let destination = CGImageDestinationCreateWithURL(
                output as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw AppError.fileNotFound("出力先を作成できません: \(output.path)")
        }
        CGImageDestinationAddImage(destination, resized, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AppError.processFailed(
                executable: "CGImageDestination", exitCode: -1, output: output.path)
        }
    }

    /// サイズが変わらない場合は再エンコードせず、hard link（不可ならcopy）で済ませる。
    private static func linkOrCopy(input: URL, output: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: output.path) {
            try fileManager.removeItem(at: output)
        }
        do {
            try fileManager.linkItem(at: input, to: output)
        } catch {
            try fileManager.copyItem(at: input, to: output)
        }
    }
}
