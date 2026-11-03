import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import TreeImageOptimizer

/// 処理枠（並列数）の挙動を実際の変換パイプラインで確認する。
///
/// 実バイナリの代わりにダミーツールを配置し、`アップスケール` の開始と
/// `出力` の完了だけを観測する。単体テストでは組み立てだけを検証できず、
/// 「出力が終わるまで次のファイルを開始しない」が実装から失われたことを
/// 捉えられなかったため、パイプライン全体で確認する（ADR 0038）。
@Suite("ConvertWindow")
struct ConvertWindowTests {
    /// 実バイナリと同様に `-i` / `-o` / `-s` を受け取り、入力画像を拡大して出力する。
    private static let upscaylScript = """
        #!/bin/sh
        in=""
        out=""
        scale=1
        while [ $# -gt 0 ]; do
          case "$1" in
            -i) in="$2"; shift 2 ;;
            -o) out="$2"; shift 2 ;;
            -s) scale="$2"; shift 2 ;;
            *) shift ;;
          esac
        done
        mkdir -p "$out" || exit 1
        for f in "$in"/*; do
          [ -f "$f" ] || continue
          base=${f##*/}
          w=$(/usr/bin/sips -g pixelWidth "$f" | /usr/bin/awk '/pixelWidth/{print $2}')
          h=$(/usr/bin/sips -g pixelHeight "$f" | /usr/bin/awk '/pixelHeight/{print $2}')
          /usr/bin/sips -z $((h * scale)) $((w * scale)) "$f" --out "$out/$base" >/dev/null || exit 1
        done
        exit 0
        """

    /// 実バイナリと同様に `入力 出力 ...` の並びを受け取り、入力を出力へコピーする。
    private static let cjxlScript = """
        #!/bin/sh
        cp "$1" "$2" || exit 1
        exit 0
        """

    @Test("出力が終わるまで次のファイルを開始せず、並列数を超えない")
    func slotReleasedOnOutput() async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: base) }
        let paths = AppPaths(baseURL: base)
        try writeExecutable(paths.upscalBinURL, contents: Self.upscaylScript)
        try writeExecutable(paths.cjxlBinURL, contents: Self.cjxlScript)

        let inputDirectory = base.appendingPathComponent("input", isDirectory: true)
        let outputDirectory = base.appendingPathComponent("output", isDirectory: true)
        try fileManager.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        let files = (0..<6).map { inputDirectory.appendingPathComponent("f\($0).png") }
        for (index, url) in files.enumerated() {
            try makePNG(at: url, width: 32, height: 32 + index)
        }

        let parallelCount = 3
        let window = Window(capacity: parallelCount)
        let config = ConvertConfig(
            scale: 2, model: "realesrgan-x4plus", format: .jpegXL, optimizeType: .photo,
            quality: 80, parallelCount: parallelCount)

        let (success, failure) = await ConvertOrchestrator().run(
            files: files, config: config, outputDirectory: outputDirectory, paths: paths
        ) { outcome in
            if outcome.started {
                if outcome.stage == .upscale {
                    await window.begin(outcome.index)
                }
            } else if outcome.fileDone {
                await window.end(outcome.index)
            }
        }

        #expect(success == 6, "全件成功すること: 成功\(success) 失敗\(failure)")
        #expect(failure == 0, "失敗が無いこと: \(failure)")

        let exceeded = await window.exceeded
        #expect(!exceeded, "並列数を超えて開始しないこと")
        let maxInFlight = await window.maxInFlight
        #expect(maxInFlight == parallelCount, "処理枠が埋まること: \(maxInFlight)")
        let starts = await window.starts
        #expect(starts == 6, "全件を開始すること: \(starts)")
        let startsAfterCompletion = await window.startsAfterCompletion
        #expect(
            startsAfterCompletion > 0,
            "出力が完了した後に次のファイルを開始すること: \(startsAfterCompletion)")

        let outputs = try fileManager.contentsOfDirectory(atPath: outputDirectory.path)
        #expect(outputs.count == 6, "出力が6件揃うこと: \(outputs)")
    }

    @Test("処理枠は出力完了でしか空かず、空き数ぶんだけ次のファイルを渡す")
    func admissionWindow() async {
        actor Marker {
            private(set) var finished = false
            func mark() { finished = true }
            var isFinished: Bool { finished }
        }
        let batcher = FileBatcher(count: 5, batchSize: 4, capacity: 3)

        // 並列数3を超えて渡さない。
        let first = await batcher.next()
        #expect(first == 0..<3, "処理枠ぶんまでしか渡さないこと: \(String(describing: first))")

        let marker = Marker()
        let pending = Task { () -> Range<Int>? in
            let range = await batcher.next()
            await marker.mark()
            return range
        }
        try? await Task.sleep(for: .milliseconds(50))
        let startedBeforeRelease = await marker.isFinished
        #expect(!startedBeforeRelease, "出力が終わるまで次のファイルを渡さないこと")

        // 出力完了で枠が1つ空き、空きぶんだけ次のバッチが始まる。
        await batcher.release()
        let second = await pending.value
        #expect(second == 3..<4, "空き1件につき1ファイルを渡すこと: \(String(describing: second))")

        await batcher.release()
        let third = await batcher.next()
        #expect(third == 4..<5, "残りを処理すること: \(String(describing: third))")
        let end = await batcher.next()
        #expect(end == nil, "ファイルが尽きたらnilを返すこと")
    }

    @Test("処理枠の解放は出力完了の通知だけに紐付く")
    func releaseOnFileDone() async {
        actor Recorder {
            private(set) var delivered: [FileOutcome] = []
            private(set) var releases = 0
            func deliver(_ outcome: FileOutcome) { delivered.append(outcome) }
            func release() { releases += 1 }
        }
        let recorder = Recorder()
        let handler = ConvertOrchestrator.trackingOutcome(
            deliver: { await recorder.deliver($0) },
            release: { await recorder.release() })

        // アップスケールの完了では枠を返さない。
        await handler(
            FileOutcome(index: 0, stage: .upscale, succeeded: true, fileDone: false))
        let afterUpscale = await recorder.releases
        #expect(afterUpscale == 0, "アップスケール完了では枠を返さないこと")

        // 出力の完了で1回だけ返す。
        await handler(
            FileOutcome(index: 0, stage: .output, succeeded: true, fileDone: true))
        // 失敗しても出力と同じく1回返す。
        await handler(
            FileOutcome(index: 1, stage: .upscale, succeeded: false, fileDone: true))
        let releases = await recorder.releases
        #expect(releases == 2, "完了通知1件につき1枠を返すこと: \(releases)")
        let delivered = await recorder.delivered
        #expect(delivered.count == 3, "通知は取り消さないこと")
    }

    /// 開始済みで未完了のファイルを追跡する。
    private actor Window {
        private let capacity: Int
        private var active: Set<Int> = []
        private(set) var starts = 0
        private(set) var completions = 0
        private(set) var startsAfterCompletion = 0
        private(set) var maxInFlight = 0
        private(set) var exceeded = false

        init(capacity: Int) {
            self.capacity = capacity
        }

        func begin(_ index: Int) {
            guard active.insert(index).inserted else { return }
            if active.count > capacity { exceeded = true }
            starts += 1
            if completions > 0 { startsAfterCompletion += 1 }
            maxInFlight = max(maxInFlight, active.count)
        }

        func end(_ index: Int) {
            guard active.remove(index) != nil else { return }
            completions += 1
        }
    }

    private func writeExecutable(_ url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makePNG(at url: URL, width: Int, height: Int) throws {
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
            let image = makeImage(context: context, width: width, height: height),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw NSError(domain: "ConvertWindowTests", code: 1)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "ConvertWindowTests", code: 2)
        }
    }

    private func makeImage(context: CGContext, width: Int, height: Int) -> CGImage? {
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
