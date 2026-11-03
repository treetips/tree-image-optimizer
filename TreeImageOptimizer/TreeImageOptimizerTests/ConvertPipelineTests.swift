import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import TreeImageOptimizer

@Suite("ConvertPipeline")
struct ConvertPipelineTests {
    @Test("品質→distance変換")
    func qualityToDistance() {
        #expect(CompressionService.qualityToDistance(100) == 0)
        #expect(CompressionService.qualityToDistance(80) == 2.0)
        #expect(CompressionService.qualityToDistance(1) == 9.9)
        #expect(CompressionService.qualityToDistance(0) == 9.9)
        #expect(CompressionService.qualityToDistance(101) == 0)
    }

    @Test("jpegoptim引数")
    func jpegoptimArgs() {
        #expect(
            CompressionService.jpegoptimArguments(output: "/tmp/o/a.jpg", quality: 75)
                == ["-m75", "-o", "-d", "/tmp/o", "/tmp/o/a.jpg"])
    }

    @Test("pngoptim引数")
    func pngoptimArgs() {
        #expect(
            CompressionService.pngoptimArguments(output: "/tmp/o/a.png", quality: 80)
                == ["/tmp/o/a.png", "-o", "/tmp/o/a.png", "--quality", "80"])
    }

    @Test("cjxl引数（アニメ・実写・速度・画質）")
    func cjxlArgs() {
        #expect(
            CompressionService.cjxlArguments(
                input: "i.png", output: "o.jxl", optimizeType: .anime, quality: 80, threads: 4)
                == ["i.png", "o.jxl", "--distance=2.0", "-e", "7", "--num_threads=4", "--lossless_jpeg=0"])
        #expect(
            CompressionService.cjxlArguments(
                input: "i.png", output: "o.jxl", optimizeType: .quality, quality: 80, threads: 2)
                == ["i.png", "o.jxl", "--distance=2.0", "-e", "9", "--num_threads=2", "--lossless_jpeg=0"])
        #expect(
            CompressionService.cjxlArguments(
                input: "i.png", output: "o.jxl", optimizeType: .speed, quality: 100, threads: 1)
                == ["i.png", "o.jxl", "--distance=0.0", "-e", "7", "--num_threads=1", "--lossless_jpeg=0"])
    }

    @Test("エンコーダのスレッド配分は並列数を予算にワーカー数で割る")
    func encoderThreads() {
        #expect(CompressionService.encoderThreads(parallelCount: 6, workers: 4, processorCount: 12) == 1)
        #expect(CompressionService.encoderThreads(parallelCount: 6, workers: 2, processorCount: 12) == 3)
        #expect(CompressionService.encoderThreads(parallelCount: 2, workers: 1, processorCount: 12) == 2)
        #expect(CompressionService.encoderThreads(parallelCount: 0, workers: 1, processorCount: 12) == 1)
        #expect(CompressionService.encoderThreads(parallelCount: 20, workers: 4, processorCount: 12) == 3)
    }

    @Test("エンコーダの総スレッド数は並列数を超えないで、下げるほど減る")
    func encoderThreadBudgetIsMonotonic() {
        let processorCount = 12
        var previous = 0
        for parallel in 1...processorCount {
            let workers = ConvertOrchestrator.stageWorkerCounts(parallelCount: parallel).compression
            let threads = CompressionService.encoderThreads(
                parallelCount: parallel, workers: workers, processorCount: processorCount)
            let total = workers * threads
            #expect(total <= parallel, "並列\(parallel): \(workers)ワーカー×\(threads)=\(total)が並列数を超えること")
            #expect(total >= previous, "並列を下げると総スレッド数も下がること: 並列\(parallel)で\(total)、前は\(previous)")
            previous = total
        }
    }

    @Test("avifenc引数（4:4:4種別はlibaom、4:2:0種別はSVT-AV1）")
    func avifencArgs() {
        #expect(
            CompressionService.avifencArguments(
                input: "i.png", output: "o.avif", optimizeType: .anime, quality: 90, threads: 2)
                == [
                    "-c", "aom", "--speed", "3", "-q", "90", "-y", "444", "-j", "2", "-a",
                    "end-usage=q", "-a", "cq-level=20", "i.png", "o.avif"
                ])
        #expect(
            CompressionService.avifencArguments(
                input: "i.png", output: "o.avif", optimizeType: .photo, quality: 85, threads: 4)
                == [
                    "-c", "svt", "--speed", "4", "-q", "85", "-y", "420", "-j", "4", "-a",
                    "crf=11", "i.png", "o.avif"
                ])
        #expect(
            CompressionService.avifencArguments(
                input: "i.png", output: "o.avif", optimizeType: .speed, quality: 70, threads: 1)
                == ["-c", "svt", "--speed", "8", "-q", "70", "-y", "420", "-j", "1", "i.png", "o.avif"])
        #expect(
            CompressionService.avifencArguments(
                input: "i.png", output: "o.avif", optimizeType: .quality, quality: 90, threads: 3)
                == [
                    "-c", "aom", "--speed", "4", "-q", "90", "-y", "444", "-j", "3", "-a",
                    "end-usage=q", "-a", "cq-level=16", "i.png", "o.avif"
                ])
    }

    @Test("SVT-AV1を使う種別は4:2:0のみ（4:4:4はエンコードに失敗する）")
    func avifCodecMatchesYuv() {
        for (optimizeType, codec) in CompressionService.avifCodec {
            let yuv = CompressionService.avifYuv[optimizeType, default: 420]
            if codec == "svt" {
                #expect(yuv == 420, "\(optimizeType) はSVT-AV1を使うため420である必要がある")
            }
        }
    }

    @Test("cwebp引数")
    func cwebpArgs() {
        #expect(
            CompressionService.cwebpArguments(
                input: "i.png", output: "o.webp", optimizeType: .anime, quality: 80)
                == ["-preset", "drawing", "-q", "80", "-m", "4", "-mt", "i.png", "-o", "o.webp"])
        #expect(
            CompressionService.cwebpArguments(
                input: "i.png", output: "o.webp", optimizeType: .speed, quality: 80)
                == ["-preset", "default", "-q", "80", "-m", "0", "-mt", "i.png", "-o", "o.webp"])
        #expect(
            CompressionService.cwebpArguments(
                input: "i.png", output: "o.webp", optimizeType: .quality, quality: 80)
                == ["-preset", "photo", "-q", "80", "-m", "6", "-mt", "i.png", "-o", "o.webp"])
    }

    @Test("upscayl-bin引数")
    func upscaleArgs() {
        #expect(
            UpscaleService.arguments(
                input: "i.png", output: "o.png", scale: 2, model: "m", modelsDir: "/models")
                == ["-i", "i.png", "-o", "o.png", "-s", "2", "-m", "/models", "-n", "m"])
    }

    @Test("出力ファイル名（最初のドットで切る）")
    func outputFileName() {
        #expect(ConvertOrchestrator.outputFileName(for: "aaa.jpg", format: .jpegXL) == "aaa.jxl")
        #expect(ConvertOrchestrator.outputFileName(for: "a.b.png", format: .webp) == "a.webp")
    }

    @Test("対象ファイル選定（拡張子・日数・ソート）")
    func targetFiles() throws {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["b.png", "a.jpg", "c.webp", "skip.txt", "sub"] {
            let url = dir.appendingPathComponent(name, isDirectory: false)
            if name == "sub" {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                fm.createFile(atPath: url.path, contents: Data("x".utf8))
            }
        }
        // 古いファイルを用意
        let old = dir.appendingPathComponent("old.jpg", isDirectory: false)
        fm.createFile(atPath: old.path, contents: Data("x".utf8))
        try fm.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -10 * 24 * 3600)], ofItemAtPath: old.path)

        let all = try TargetFiles.list(in: dir, modifiedWithinDays: nil)
        #expect(all.map { $0.lastPathComponent } == ["a.jpg", "b.png", "c.webp", "old.jpg"])
        let recent = try TargetFiles.list(in: dir, modifiedWithinDays: 7)
        #expect(!recent.map { $0.lastPathComponent }.contains("old.jpg"))
        #expect(recent.map { $0.lastPathComponent } == ["a.jpg", "b.png", "c.webp"])
    }

    @Test("存在しないフォルダはエラー")
    func missingFolder() {
        #expect(throws: AppError.self) {
            try TargetFiles.list(in: URL(fileURLWithPath: "/nonexistent-xyz"), modifiedWithinDays: nil)
        }
    }

    @Test("並列実行は1件完了するたびに次のファイルを投入する（常時並列を維持）")
    func refillsSlotImmediately() async {
        actor StartLog {
            private(set) var indices: [Int] = []
            func record(_ index: Int) { indices.append(index) }
            func contains(_ index: Int) -> Bool { indices.contains(index) }
        }
        let log = StartLog()
        let result = await ConvertOrchestrator.runParallel(count: 4, workers: 2) { index in
            await log.record(index)
            // ファイル0は「ファイル2が開始済み」を確認して完了する。
            // 完了1件のたびに次が投入されないバッチ方式だと、ファイル2はファイル0の完了待ちで
            // デッドロックし、タイムアウトで失敗扱いになる。
            if index == 0 {
                for _ in 0..<500 {
                    if await log.contains(2) { return true }
                    try? await Task.sleep(for: .milliseconds(2))
                }
                return false
            }
            return true
        }
        #expect(result == (success: 4, failure: 0), "全件成功であること（バッチ方式だとファイル0がタイムアウトで失敗する）: \(result)")
    }

    @Test("並列実行は並列数を超えず、余りが出るまで並列数を満たし続ける")
    func capsConcurrency() async {
        actor Probe {
            private(set) var maxConcurrent = 0
            private var running = 0
            func enter() {
                running += 1
                maxConcurrent = max(maxConcurrent, running)
            }
            func leave() { running -= 1 }
        }
        let probe = Probe()
        let result = await ConvertOrchestrator.runParallel(count: 8, workers: 3) { _ in
            await probe.enter()
            try? await Task.sleep(for: .milliseconds(50))
            await probe.leave()
            return true
        }
        let peak = await probe.maxConcurrent
        #expect(result == (success: 8, failure: 0), "全件処理されること: \(result)")
        #expect(peak <= 3, "並列数を超えないこと: \(peak)")
        #expect(peak == 3, "余りが出るまで並列数を満たし続けること: \(peak)")
    }

    @Test("ステージ別ワーカー数はGPUを最大3にし、残りを圧縮へ回す")
    func stageWorkers() {
        #expect(ConvertOrchestrator.stageWorkerCounts(parallelCount: 1) == StageWorkers(upscale: 1, compression: 1))
        #expect(ConvertOrchestrator.stageWorkerCounts(parallelCount: 2) == StageWorkers(upscale: 1, compression: 1))
        #expect(ConvertOrchestrator.stageWorkerCounts(parallelCount: 3) == StageWorkers(upscale: 1, compression: 2))
        #expect(ConvertOrchestrator.stageWorkerCounts(parallelCount: 6) == StageWorkers(upscale: 2, compression: 4))
        #expect(ConvertOrchestrator.stageWorkerCounts(parallelCount: 7) == StageWorkers(upscale: 2, compression: 5))
        #expect(ConvertOrchestrator.stageWorkerCounts(parallelCount: 15) == StageWorkers(upscale: 3, compression: 12))
        #expect(ConvertOrchestrator.stageWorkerCounts(parallelCount: 30) == StageWorkers(upscale: 3, compression: 27))
    }

    @Test("Pコア数は1以上で全論理コア以下")
    func performanceCoreCount() {
        let performance = HardwareInfo.performanceCoreCount()
        #expect(performance >= 1)
        #expect(performance <= ProcessInfo.processInfo.processorCount)
    }

    @Test("出力確定（同一ボリュームではrename・既存は上書き・元のファイルは残らない）")
    func installOutput() throws {
        let fileManager = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        let source = base.appendingPathComponent("source.jxl", isDirectory: false)
        try Data("new".utf8).write(to: source)
        let destination = base.appendingPathComponent("destination.jxl", isDirectory: false)
        try Data("old".utf8).write(to: destination)

        try ConvertOrchestrator.installOutput(from: source, to: destination)

        #expect(!fileManager.fileExists(atPath: source.path), "元のファイルは残らない（rename移動であること）")
        #expect(try Data(contentsOf: destination) == Data("new".utf8), "宛先は新しい内容で上書きされる")
    }

    @Test("モデル一覧（.bin走査・フォールバック）")
    func models() throws {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(TargetFiles.listModels(in: dir) == ["realesr-animevideov3-x4"])
        for name in ["b.bin", "a.bin", "a.param"] {
            fm.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data("x".utf8))
        }
        #expect(TargetFiles.listModels(in: dir) == ["a", "b"])
    }
}

/// Real-CUGANエンジンに関わるテスト。既存のConvertPipelineスイートと分けて
/// 1型あたりの行数制限を守る。
@Suite("ConvertPipeline RealCUGAN")
struct ConvertPipelineRealCUGANTests {
    @Test("Real-CUGAN引数")
    func realCuganArgs() {
        #expect(
            UpscaleService.realCuganArguments(
                input: "/in/a.webp", output: "/out/a.png", scale: 2, noise: -1,
                modelsDir: "/m/models-se")
                == [
                    "-i", "/in/a.webp", "-o", "/out/a.png", "-s", "2", "-n", "-1", "-m",
                    "/m/models-se"
                ])
    }

    @Test("Real-CUGANモデルIDの分解")
    func realCuganParse() throws {
        // scaleとnoiseの導出。
        let model = try #require(RealCUGANModel.parse("models-se/up2x-conservative"))
        #expect(model == RealCUGANModel(folder: "models-se", name: "up2x-conservative"))
        #expect(model.scale == 2)
        #expect(model.noise == -1)
        #expect(model.label == "SE / up2x-conservative")
        #expect(RealCUGANModel.parse("models-pro/up3x-no-denoise")?.noise == 0)
        #expect(RealCUGANModel.parse("models-se/up4x-denoise3x")?.noise == 3)
        #expect(RealCUGANModel.parse("models-se/up4x-denoise1x")?.noise == 1)
        // 1xは1xモデルが存在しないため不正とする。
        #expect(RealCUGANModel.parse("models-se/up1x-conservative") == nil)
        // 既知外フォルダ・不正形式はnil。
        #expect(RealCUGANModel.parse("models/up2x-conservative") == nil)
        #expect(RealCUGANModel.parse("up2x-conservative") == nil)
        #expect(RealCUGANModel.parse("models-se/conservative-2x") == nil)
    }

    @Test("Real-CUGANモデル一覧はノイズ除去が弱い順に並ぶ")
    func realCuganModelOrder() {
        // ファイル名の辞書順や -n の値順とは違う並びになるため、意図的に混ぜた順で渡す。
        let models = [
            "up2x-denoise3x", "up2x-conservative", "up2x-no-denoise", "up2x-denoise1x",
            "up2x-denoise2x"
        ].map { RealCUGANModel(folder: "models-se", name: $0) }
        let ordered = RealCUGANModels.models(models: models, scale: 2)
        // 除去しない no-denoise が先頭。conservative は「除去しないが最低限の抑制あり」で次。
        #expect(
            ordered.map(\.name) == [
                "up2x-no-denoise", "up2x-conservative", "up2x-denoise1x", "up2x-denoise2x",
                "up2x-denoise3x"
            ])
        // ノイズ除去が同じ場合はID順で確定的に並べる（ProがSEより先）。
        let mixed = [
            RealCUGANModel(folder: "models-se", name: "up2x-conservative"),
            RealCUGANModel(folder: "models-pro", name: "up2x-conservative")
        ]
        #expect(
            RealCUGANModels.models(models: mixed, scale: 2).map(\.folder)
                == ["models-pro", "models-se"])
    }

    @Test("Real-CUGANカタログ（ペア走査・拡大率絞り込み・弱い順）")
    func realCuganCatalog() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let se = root.appendingPathComponent("models-se", isDirectory: true)
        try fm.createDirectory(at: se, withIntermediateDirectories: true)
        for name in ["up2x-conservative", "up2x-denoise3x", "up3x-conservative"] {
            fm.createFile(
                atPath: se.appendingPathComponent("\(name).bin").path, contents: Data("x".utf8))
            fm.createFile(
                atPath: se.appendingPathComponent("\(name).param").path, contents: Data("x".utf8))
        }
        // 片方だけの欠けは一覧から除外する。
        fm.createFile(
            atPath: se.appendingPathComponent("up2x-no-denoise.bin").path, contents: Data("x".utf8))
        // 既知外フォルダ・無関係ファイルは無視する。
        let other = root.appendingPathComponent("models", isDirectory: true)
        try fm.createDirectory(at: other, withIntermediateDirectories: true)
        fm.createFile(
            atPath: other.appendingPathComponent("up2x-conservative.bin").path,
            contents: Data("x".utf8))
        fm.createFile(
            atPath: root.appendingPathComponent("README.txt").path, contents: Data("x".utf8))

        let catalog = RealCUGANModels.catalog(in: root)
        #expect(catalog.count == 3)
        // 同梱しないup2x-no-denoise（.binのみ）が除かれていること。
        #expect(!catalog.contains { $0.name == "up2x-no-denoise" })

        // 拡大率による絞り込みと弱い順の並び（先頭はconservative）。
        let twos = RealCUGANModels.models(models: catalog, scale: 2)
        #expect(twos.count == 2)
        #expect(twos.first?.name == "up2x-conservative")
        #expect(RealCUGANModels.models(models: catalog, scale: 4).isEmpty)
    }

    @Test("Real-CUGANモデル解決（カタログ内・フォールバック・既定値）")
    func realCuganResolve() throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let se = root.appendingPathComponent("models-se", isDirectory: true)
        try fm.createDirectory(at: se, withIntermediateDirectories: true)
        for name in ["up2x-conservative", "up3x-conservative", "up4x-no-denoise"] {
            fm.createFile(
                atPath: se.appendingPathComponent("\(name).bin").path, contents: Data("x".utf8))
            fm.createFile(
                atPath: se.appendingPathComponent("\(name).param").path, contents: Data("x".utf8))
        }
        let catalog = RealCUGANModels.catalog(in: root)

        // カタログ内のIDはそのまま使う。
        #expect(
            RealCUGANModels.resolve(id: "models-se/up4x-no-denoise", catalog: catalog, scale: 4)
                == RealCUGANModel(folder: "models-se", name: "up4x-no-denoise"))
        // 不在IDは拡大率に合う先頭（ノイズ除去が最も弱いもの）へフォールバックする。
        #expect(
            RealCUGANModels.resolve(id: "models-se/up2x-denoise3x", catalog: catalog, scale: 2)
                == RealCUGANModel(folder: "models-se", name: "up2x-conservative"))
        // 拡大率が合わない保存IDも拡大率に合う先頭へフォールバックする。
        #expect(
            RealCUGANModels.resolve(id: "models-se/up2x-conservative", catalog: catalog, scale: 4)
                == RealCUGANModel(folder: "models-se", name: "up4x-no-denoise"))
        // 拡大率に合うモデルが無いIDもフォールバックする。
        #expect(
            RealCUGANModels.resolve(id: "no/such-model", catalog: catalog, scale: 4)
                == RealCUGANModel(folder: "models-se", name: "up4x-no-denoise"))
        // 空カタログ（ツール未配置）では保存IDを維持し、選択を失わない。
        #expect(
            RealCUGANModels.resolve(id: "models-se/up2x-conservative", catalog: [], scale: 2)
                == RealCUGANModel(folder: "models-se", name: "up2x-conservative"))
        #expect(
            RealCUGANModels.resolve(id: "models-se/up4x-denoise3x", catalog: [], scale: 2)
                == RealCUGANModel(folder: "models-se", name: "up4x-denoise3x"))
        // 空カタログで不正なIDなら既定値に戻す。
        #expect(
            RealCUGANModels.resolve(id: "no/such-model", catalog: [], scale: 2)
                == RealCUGANModel(folder: "models-se", name: "up2x-conservative"))
    }

    @Test("Real-CUGAN実行前検証（.param/.binペア）")
    func realCuganPreflight() throws {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = RealCUGANModel(folder: "models-se", name: "up2x-conservative")
        let service = UpscaleService()
        // 何も無い場合はエラー。
        #expect(throws: AppError.self) { try service.preflight(model: model, modelsDir: dir) }
        fm.createFile(
            atPath: dir.appendingPathComponent("up2x-conservative.param").path,
            contents: Data("x".utf8))
        // .paramだけではエラー。
        #expect(throws: AppError.self) { try service.preflight(model: model, modelsDir: dir) }
        fm.createFile(
            atPath: dir.appendingPathComponent("up2x-conservative.bin").path,
            contents: Data("x".utf8))
        // ペアが揃えば通る。
        try service.preflight(model: model, modelsDir: dir)
    }

    @Test("Real-CUGAN実行後検証（存在・空でない・寸法がscale倍）")
    func realCuganPostVerify() throws {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        // 10x8のテスト用PNGを作る（CGImageSourceで読める形式でなければならない）。
        let input = base.appendingPathComponent("input.png", isDirectory: false)
        try Self.writePNG(width: 10, height: 8, to: input)
        let output = base.appendingPathComponent("output.png", isDirectory: false)
        try Self.writePNG(width: 20, height: 16, to: output)
        let service = UpscaleService()
        try service.postVerify(output: output, input: input, scale: 2)
        // 拡大率が合わない出力はエラー。
        try Self.writePNG(width: 30, height: 24, to: output)
        #expect(throws: AppError.self) {
            try service.postVerify(output: output, input: input, scale: 2)
        }
        // 欠損や空ファイルもエラー。
        try fm.removeItem(at: output)
        #expect(throws: AppError.self) {
            try service.postVerify(output: output, input: input, scale: 2)
        }
    }

    /// テスト用の単色PNGを書き出す。
    static func writePNG(width: Int, height: Int, to url: URL) throws {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = context else {
            throw CocoaError(.fileWriteUnknown)
        }
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = ctx.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
