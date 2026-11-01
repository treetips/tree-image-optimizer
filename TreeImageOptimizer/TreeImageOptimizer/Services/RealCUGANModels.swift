import Foundation

/// Real-CUGANモデル1件分。フォルダ名 と ファイル名（`up2x-conservative`）
/// のペアで一意に決まる。`realcugan-ncnn-vulkan` は `-m` に渡すフォルダ名の
/// 文字列からパディング量を決めるため、フォルダ名は上流配布物のまま維持する。
struct RealCUGANModel: Hashable, Sendable {
    /// `models-se` / `models-pro` / `models-nose`。
    let folder: String
    /// `up2x-conservative` など拡張子を除いたファイル名。
    let name: String

    /// 設定JSONへ保存するID。`models-se/up2x-conservative` 形式。
    var id: String { "\(folder)/\(name)" }

    /// プルダウン表示名。フォルダの役割を添える（例: `SE / up2x-conservative`）。
    var label: String {
        switch folder {
        case "models-se": return "SE / \(name)"
        case "models-pro": return "Pro / \(name)"
        case "models-nose": return "nose / \(name)"
        default: return id
        }
    }

    /// モデルの拡大率。`up{2,3,4}x-...` の接頭辞から取る。
    var scale: Int { Self.parseScale(from: name) ?? 2 }

    /// `-n` に渡すノイズレベル。意味は直感と異なる（-1=conservative、0=no-denoise、
    /// 1〜3=denoise1x〜3x）。実機検証 `docs/design/feature/upscale-engine.md` 参照。
    var noise: Int { Self.parseNoise(from: name) }

    /// ノイズ除去の強さ順位。弱い順に no-denoise(0) → conservative(1) → denoise1x(2) 〜 denoise3x(4)。
    /// Why not: `-n` の値（-1=conservative、0=no-denoise）は強さの大小と一致しない。
    /// 公式Changelog（bilibili/ailab Real-CUGAN）では保守版・非降噪版はノイズ除去を行わず、
    /// 不自然なノイズ（アーティファクト）の最低限の抑制に留まるとされる。除去しない選択肢は
    /// no-denoise のため先頭に置き、conservative はその次（実測 `docs/design/feature/upscale-engine.md` 参照）。
    var denoiseRank: Int {
        if name.contains("no-denoise") { return 0 }
        if name.contains("conservative") { return 1 }
        return noise + 1
    }

    static func parseScale(from name: String) -> Int? {
        guard name.hasPrefix("up") else { return nil }
        let digits = name.dropFirst(2).prefix(while: \.isNumber)
        guard let scale = Int(digits), (2...4).contains(scale) else { return nil }
        return scale
    }

    static func parseNoise(from name: String) -> Int {
        if name.contains("conservative") { return -1 }
        if name.contains("no-denoise") { return 0 }
        if name.contains("denoise1") { return 1 }
        if name.contains("denoise2") { return 2 }
        if name.contains("denoise3") { return 3 }
        return 0
    }

    /// `models-se/up2x-conservative` 形式のIDを分解する。不正ならnil。
    static func parse(_ id: String) -> RealCUGANModel? {
        let parts = id.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, isKnownFolder(parts[0]) else { return nil }
        let name = parts[1]
        guard parseScale(from: name) != nil, name.contains("-") else { return nil }
        return RealCUGANModel(folder: parts[0], name: name)
    }

    /// バイナリが判定に使う既知フォルダ名。
    static func isKnownFolder(_ folder: String) -> Bool {
        folder == "models-se" || folder == "models-pro" || folder == "models-nose"
    }
}

/// Real-CUGANモデルのカタログ。`tools/realcugan/models-*` 配下の
/// `.param` と `.bin` のペア実在ファイルを走査して作る（Why not: 固定配列だと
/// モデルファイルの欠損時に黒画像出力や失敗に至るため。欠損モデルは一覧から除外する）。
enum RealCUGANModels {
    private static let defaultModel = RealCUGANModel(folder: "models-se", name: "up2x-conservative")

    /// 指定されたReal-CUGANのmodels基準ディレクトリ配下からモデル一覧を作る。
    /// `root` は `tools/realcugan`（`models-*` の親）を指す想定。
    static func catalog(in root: URL) -> [RealCUGANModel] {
        let fm = FileManager.default
        guard
            let contents = try? fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey])
        else { return [] }
        var result: [RealCUGANModel] = []
        for dir in contents {
            let values = try? dir.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true, RealCUGANModel.isKnownFolder(dir.lastPathComponent)
            else { continue }
            for model in pairsIn(dir: dir, folder: dir.lastPathComponent) {
                result.append(model)
            }
        }
        return result
    }

    /// 単一フォルダ内の `.param`/`.bin` ペアからモデル一覧を作る。
    /// ペアに欠けがあるものは除外する（欠けたまま実行すると黒画像になるため）。
    static func pairsIn(dir: URL, folder: String) -> [RealCUGANModel] {
        let fm = FileManager.default
        guard
            let contents = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isRegularFileKey])
        else { return [] }
        var names = Set<String>()
        for url in contents {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            guard ext == "param" || ext == "bin" else { continue }
            names.insert(url.deletingPathExtension().lastPathComponent)
        }
        var result: [RealCUGANModel] = []
        for name in names.sorted() {
            let bin = dir.appendingPathComponent("\(name).bin", isDirectory: false)
            let param = dir.appendingPathComponent("\(name).param", isDirectory: false)
            guard fm.fileExists(atPath: bin.path), fm.fileExists(atPath: param.path) else { continue }
            guard RealCUGANModel.parseScale(from: name) != nil else { continue }
            result.append(RealCUGANModel(folder: folder, name: name))
        }
        return result
    }

    /// 拡大率に合うモデルだけを返す。ノイズ除去の強さが弱い順に並べる
    /// （no-denoise → conservative → denoise1x → denoise2x → denoise3x）。
    /// Why not: ファイル名の辞書順や `-n` の値順では、no-denoise と conservative の位置が
    /// 逆になり、プルダウンの上下とノイズ除去の強弱が対応しないため。
    static func models(models: [RealCUGANModel], scale: Int) -> [RealCUGANModel] {
        models
            .filter { $0.scale == scale }
            .sorted { lhs, rhs in
                if lhs.denoiseRank != rhs.denoiseRank { return lhs.denoiseRank < rhs.denoiseRank }
                return lhs.id < rhs.id
            }
    }

    /// 保存済みIDをカタログの実在モデルへ解決する。
    /// 候補は選択中の拡大率に合うモデルだけとし、見つからなければ conservative
    /// （無ければ先頭＝ノイズ除去が最も弱いもの）、それも無ければ既定値を使う。
    /// Why not: conservative はncnn版バイナリの既定値（-n -1）でもあり、初回選択・
    /// フォールバックの既定として扱いやすいため。
    /// カタログが空（ツール未配置）の間は保存IDをそのまま維持する
    /// （Why not: 未配置の起動中に既定値へ書き換えると、ユーザーの選択が失われるため）。
    static func resolve(id: String, catalog: [RealCUGANModel], scale: Int) -> RealCUGANModel {
        let parsed = RealCUGANModel.parse(id)
        let candidates = models(models: catalog, scale: scale)
        if let parsed, candidates.contains(parsed) {
            return parsed
        }
        if catalog.isEmpty, let parsed {
            return parsed
        }
        if let preferred = candidates.first(where: { $0.name.contains("conservative") }) {
            return preferred
        }
        if let first = candidates.first {
            return first
        }
        return defaultModel
    }
}
