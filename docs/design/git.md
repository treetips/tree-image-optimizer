# Git運用ルール

## コミットメッセージ

コミットメッセージは [Conventional Commits](https://www.conventionalcommits.org/ja/) を採用する。

### 基本形式

```text
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### type

| type | 用途 |
| :--- | :--- |
| `feat` | 新機能の追加 |
| `fix` | バグ修正 |
| `refactor` | 振る舞いを変えないコードの整理・改善 |
| `perf` | パフォーマンス改善 |
| `docs` | ドキュメントのみの変更 |
| `style` | コードの動作に影響しない整形（空白・セミコロン等） |
| `test` | テストの追加・修正 |
| `chore` | その他（依存更新・設定変更・雑務） |
| `build` | ビルドシステム・外部依存の変更 |
| `ci` | CI設定・スクリプトの変更 |

### 例

```text
feat: 変換結果のサマリーを画面下部に固定表示
fix: 配布版でツール実行に失敗する問題を修正
refactor: PathServiceのOS別パス解決をpath_providerへ統一
docs: リリースフローにConventional Commitsの規約を追記
ci: ReleaseワークフローにAppcast生成ステップを追加
chore(deps): syncfusion_flutter_slidersを更新
```

### 規約

- **description は日本語**で記述する。
- description は命令形・簡潔に（例: `追加` ではなく `追加` / `修正` ではなく `修正`）。
- scope は必要な場合のみ付与する（例: `feat(slider): ...`）。
- 主要ブランチへの直接pushは禁止。必ず `feature/*` または `fix/*` ブランチから PR を作成する。

## ブランチ命名規則

| ブランチ | 用途 |
| :--- | :--- |
| `feature/*` | 機能追加 |
| `fix/*` | バグ修正・リリース前の修正 |
| `release/*` | リリース準備（必要時のみ） |

例:

```text
feature/result-summary-fixed
fix/tools-app-support
release/v0.1.0
```

## PR運用

- PRタイトルも Conventional Commits 形式を推奨する（例: `feat: 変換結果のサマリーを固定表示`）。
- PRのラベルはリリースノートの自動分類（`.github/release.yml`）に利用されるため、適切なラベルを付与する。

## リリースタグ

- タグは `vMajor.Minor.Patch` 形式（例: `v0.1.0`）。
- タグは GitHub Actions の Release ワークフロー（`workflow_dispatch`）で自動作成される。

## 既存コミットの扱い

Conventional Commits 導入以前のコミット（`first commit` など）は遡って書き換えない。既存PR・既存リリースを壊さないため、**新規コミットから本ルールを適用**する。