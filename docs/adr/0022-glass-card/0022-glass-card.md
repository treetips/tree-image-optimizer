# 全画面のカードをLiquid Glassに共通化する

- ステータス: Accepted
- 影響範囲: 一括変換・かんたん変換・設定・Aboutの各画面、`Core/GlassCard.swift`
- 関連: ADR 0013（UIデザイン画準拠）

## 背景

一括変換画面の入力エリア等は `GroupBox` で囲まれており、Liquid Glassになっていなかった。
`glassEffect` は実行ボタン（`GlassCTAButton`）と一括変換の下部フローティングフッターにだけ使われ、
濃さ（tint不透明度）や角丸が各所に分散していた。

## 決定

- `Core/GlassCard.swift` に `GlassStyle` と `GlassCard` を新設する。
- `GlassStyle` でカード・フッター・CTAのtint不透明度と角丸を一元管理する。
  透明度や屈折率の調整はこの定義だけを変更すれば全画面に反映される。
- カードの初期値は透明（tintなしの `regular`）とする。青が必要な場所は
  呼び出し側で `tint` を上書きする（例: フッターは `footerTintOpacity: 0.2` で青を維持）。
- `ConvertView`（6箇所）・`EasyConvertView`（4箇所）・`SettingsView`（2箇所）・
  `AboutView`（2箇所）の `GroupBox` を `GlassCard` に置き換える。見出し文言とローカライズは変えない。
- HIGのBoxes（macOSはタイトルを枠の上に表示）に合わせ、タイトルはガラス枠の外・上に置く。
  枠内に含めると透けで可読性が落ちるため。
- `GlassCTAButton` と一括変換フッターの `glassEffect` も `GlassStyle` の定数を参照させる。

## 結果

- 全画面のカード枠がLiquid Glassになり、見た目が統一される。
  初期値は透明で、フッターのみ青を維持する。
- 濃さ・形状の変更点が1ファイルに集約され、調整が容易になる。
- `GlassCardTests` で中央値（カード透明/22、フッター0.2/22、CTA0.5/14）と
  `tint` 上書きの可否を検証する。

## 適合確認

- デプロイメントターゲットmacOS 26.0を維持し、`glassEffect` の利用可能範囲内で実装する。
- 既存テストは削除せず、`GlassCardTests` を追加する。
