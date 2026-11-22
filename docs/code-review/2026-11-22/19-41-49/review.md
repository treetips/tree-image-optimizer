# コードレビュー結果

- 対象: `fix/preview-layout-loop`（`main` との差分）
- 実行: `ocr review --from main --to HEAD --audience agent`
- セッション: `f3d25f40-79e4-48c6-b55f-79c1118ba16b`

## 指摘

### 1. 無効時にボタン特性とアクションが残る

- 重要度: bug / low
- 内容: 出力未完了で無効なプレビューセルでも、VoiceOver には押せるボタンとして
  提示され、実行しても何も起きない。
- 対応: 採用。`accessibilityAddTraits` を有効時だけ `.isButton` にし、
  `accessibilityRespondsToUserInteraction(isEnabled)` を追加した。

### 2. `ComparisonWindowController` が `@unchecked Sendable`

- 重要度: maintainability / low
- 内容: メインアクター隔離が型で保証されておらず、`Task` からの `open` 呼び出しが
  コンパイラの検査を受けない。
- 対応: 採用。`@MainActor` を付け、`@unchecked Sendable` を削除した。
