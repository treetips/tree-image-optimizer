import Darwin
import Foundation

/// ハードウェアのコア構成を取得する。
enum HardwareInfo {
    /// 高性能コア（Pコア）の論理CPU数。
    /// Apple Siliconでは `hw.perflevel0.logicalcpu` を返し、Intelや取得失敗時は
    /// 全論理コア数へフォールバックする。
    /// Why not: 全論理コア数を並列数の上限にすると、Eコアまでワーカーを広げてしまい、
    /// 遅いEコアの完了待ちが全体の処理時間を決めることがある。
    static func performanceCoreCount() -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.logicalcpu", &value, &size, nil, 0) == 0, value > 0 {
            return Int(value)
        }
        return max(1, ProcessInfo.processInfo.processorCount)
    }

    /// 並列数の初期値。最大の半分（端数切り捨て）にする。
    /// 動画視聴やブラウジングを妨げない負荷を既定にしたいので、最大まで使わない（ADR 0039）。
    /// 最大値がPコア数から決まるため、取得処理と同じ場所に置く。
    static func defaultParallelCount(maxParallel: Int = HardwareInfo.performanceCoreCount()) -> Int {
        max(1, max(1, maxParallel) / 2)
    }
}
