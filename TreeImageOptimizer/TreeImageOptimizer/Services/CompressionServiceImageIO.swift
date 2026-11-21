import Foundation
import ImageIO
import UniformTypeIdentifiers

/// JPEG/PNG の ImageIO 生成と EXIF 引き継ぎ（ADR 0070）。
/// `CompressionService` 本体の行数・ファイル行数の制限を守るため extension に分離する。
extension CompressionService {
    func compressJpeg(
        input: URL, output: URL, profile: CompressionProfile, paths: AppPaths, source: URL?
    ) async throws {
        let quality = profile.jpegQuality
        // jpegoptim はJPEG入力のみ対応のため、一旦JPEGを生成する。
        try Self.convertToJPEG(input: input, output: output, quality: 1.0, source: source)
        do {
            let bin = paths.jpegoptimBinURL
            try await runBinary(
                bin, args: Self.jpegoptimArguments(output: output.path, quality: quality),
                workingDirectory: bin.deletingLastPathComponent().path)
        } catch {
            AppLogger.shared.warning(
                "jpegoptim failed, falling back to re-encode: \(error.localizedDescription)")
            // フォールバック：指定品質で再エンコードする。
            try Self.convertToJPEG(
                input: output, output: output, quality: Double(quality) / 100.0, source: source)
        }
    }

    func compressPng(
        input: URL, output: URL, profile: CompressionProfile, paths: AppPaths, source: URL?
    ) async throws {
        let quality = profile.pngQuality
        try Self.convertToPNG(input: input, output: output, source: source)
        do {
            let bin = paths.pngoptimBinURL
            try await runBinary(
                bin, args: Self.pngoptimArguments(output: output.path, quality: quality),
                workingDirectory: bin.deletingLastPathComponent().path)
        } catch {
            AppLogger.shared.warning(
                "pngoptim failed, falling back to re-encode: \(error.localizedDescription)")
            try Self.convertToPNG(input: output, output: output, source: source)
        }
    }

    // MARK: - ImageIO helpers (Dart `package:image` の代替)

    static func convertToJPEG(input: URL, output: URL, quality: Double, source: URL? = nil) throws {
        guard let sourceRef = CGImageSourceCreateWithURL(input as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(sourceRef, 0, nil),
            let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else {
            throw AppError.fileNotFound("画像のデコードに失敗しました: \(input.path)")
        }
        CGImageDestinationSetProperties(dest, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        Self.addImage(image, metadata: Self.metadata(of: source), to: dest)
        guard CGImageDestinationFinalize(dest) else {
            throw AppError.processFailed(executable: "CGImageDestination", exitCode: -1, output: output.path)
        }
    }

    static func convertToPNG(input: URL, output: URL, source: URL? = nil) throws {
        guard let sourceRef = CGImageSourceCreateWithURL(input as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(sourceRef, 0, nil),
            let dest = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw AppError.fileNotFound("画像のデコードに失敗しました: \(input.path)")
        }
        Self.addImage(image, metadata: Self.metadata(of: source), to: dest)
        guard CGImageDestinationFinalize(dest) else {
            throw AppError.processFailed(executable: "CGImageDestination", exitCode: -1, output: output.path)
        }
    }

    /// 元画像のメタデータ木（EXIF・XMP・IPTC・GPS）を読み出す（ADR 0070）。
    /// ICC は含まれない。画像属性（寸法・色深度）も渡さない。
    private static func metadata(of url: URL?) -> CGImageMetadata? {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCopyMetadataAtIndex(source, 0, nil)
    }

    /// メタデータがあれば引き継ぎ、無ければ画像だけを書き込む。
    private static func addImage(
        _ image: CGImage, metadata: CGImageMetadata?, to destination: CGImageDestination
    ) {
        if let metadata {
            CGImageDestinationAddImageAndMetadata(destination, image, metadata, nil)
        } else {
            CGImageDestinationAddImage(destination, image, nil)
        }
    }
}
