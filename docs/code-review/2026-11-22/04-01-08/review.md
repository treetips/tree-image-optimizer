# コードレビュー結果

- 実施日時: 2026-11-22 04:01 (Asia/Tokyo)
- ツール: Open Code Review 1.13.13
- モデル: opencode-go / deepseek-v4.1-flash
- 対象: `feat/collapsible-callouts` と `main` の差分（Swift 7ファイル）
- 指摘数: 4件

## 指摘と対応

### 1. パネル全面を単一の Button にしている（medium / bug）

- 指摘: 展開時の本文もボタンのラベルに含まれるため、VoiceOver では本文が1つの
  ボタンとして読み上げられ、開閉状態も伝わらない。本文のクリックでも折りたたみが
  トグルされる。
- 対応: **一部採用**。
  - 開閉状態を読み上げるよう `accessibilityValue` を追加した。
  - 「見出しだけを Button にする」構造変更は却下した。要件が「パネルをクリックすると
    開閉状態が切り替わる」とパネル全面のクリックを求めており、本文の折りたたみ操作も
    その一部のため。
  - `accessibilityLabel` でタイトルだけに上書きする対応も却下した。本文の対応形式や
    モードの説明が読み上げられなくなるため。

### 2. `.move(edge: .top)` のトランジションがカード外へはみ出す（low / bug）

- 指摘: `CalloutContainer` はクリップしないため、開閉アニメーション中に本文がカードの
  上端より外側へ描画される。
- 対応: **採用**。`.transition(.opacity)` に変更し、カード外へのはみ出しをなくした。

### 3. overlay の角丸の二重定義とクリックの奪い（low / bug）

- 指摘: ホバー枠の角丸が `CalloutContainer` と二重定義で、枠線領域がクリックを奪う。
- 対応: **採用**。角丸を `CalloutStyle.cornerRadius` に集約し、overlay に
  `.allowsHitTesting(false)` を付けた。

### 4. 常時表示のレイアウトが `CollapsibleCallout` と二重管理（low / maintainability）

- 指摘: 常時表示用の分岐がアイコン・見出し・本文のレイアウトを再実装しており、
  `CollapsibleCallout` の見出しと乖離するおそれがある。
- 対応: **採用**。アイコン・見出し・本文のレイアウトを `CalloutLayout` に切り出し、
  `CollapsibleCallout` と `SupportedFormatsCallout` で共有した。
