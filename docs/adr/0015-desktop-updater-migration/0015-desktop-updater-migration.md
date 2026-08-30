# 自動アップデート機構の desktop_updater への移行

## ステータス

- 承認済み (Accepted)

## 背景・課題

- 自動アップデート機構に従来 `auto_updater`（macOS は Sparkle ベース / AppCast XML）を採用していた。
- `auto_updater` は API が低水準で、更新チェックのリスナーをアプリ側で実装する必要があり、
  フィード形式（AppCast XML）も配布面で制約がある。
- 後継ライブラリ `desktop_updater` は、署名付き JSON フィード（`app-archive.json` / `release.json`）と
  組み込みの更新カード／ダイアログを備え、ダウンロード〜再起動インストールまでの状態遷移を
  ライブラリ側で一貫して扱える。

## 決定

- 自動アップデート機構を `desktop_updater`（3.1.x）へ移行する。
- 更新フィードは GitHub Releases の flat な `latest/download` を前提とせず、
  `app-archive.json` / `release.json` / zip を静的に配信できるホストへ公開する。
- 更新 UI は desktop_updater 組み込みのカード／ダイアログ（`DesktopUpdateWidget` /
  `DesktopUpdateDirectCard` / `showManualUpdateCheckResultDialog`）を採用し、
  独自アラート（更新あり / 最新 / 失敗のバナー）は廃止する。
- About 画面のバージョン表示とチェックボタンは維持し、更新カードを併设する。
- 起動時の自動チェックは `main` から `runBackgroundUpdateCheck` を呼び出して行い、
  ダイアログ表示なしで組み込みカードに状態遷移を委ねる。
- macOS メニュー / About 画面の手動チェックは `runManualUpdateCheck` を共通窓口とする。
- desktop_updater は `FutureProvider` 経由で提供し、生成に失敗した環境では null にして
  更新 UI を無効化し、起動や操作を妨げない。

## 移行に伴う配布上の前提（対応済み）

- 配布ホストは **GitHub Pages**（`https://treetips.github.io/tree-image-optimizer/`）を採用した。
  GitHub Releases のアセットはフラットでネスト階層（`releases/<ver>/<plat>/...`）を再現できないため、
  desktop_updater の配布物は GitHub Pages、手動インストール用 zip は GitHub Releases を使い分ける。
- `trustedReleasePublicKeys` は `dart run desktop_updater:release keygen` で生成した Ed25519 公開鍵を
  コードに固定済み（`desktop_updater.keys.json` はコミット対象。秘密鍵 `release-key.dukey` はコミット禁止）。
- `desktop_updater.yaml` の `updates.baseUrl` と `app_constants.dart` の `appArchiveUrl` は
  GitHub Pages の URL に合わせてある。
- Release ワークフロー（`.github/workflows/release.yml`）へ、署名鍵 import → `release publish` →
  GitHub Pages への自動デプロイ（gh-pages ブランチ）→ GitHub Release 作成を統合済み。
- **material_ui 互換対応**: `material_ui` は material ライブラリのフォークで独自の
  `MaterialLocalizations` 型を登録する。一方 desktop_updater は標準 `flutter/material` の
  `showDialog` を使うため、標準型の `MaterialLocalizations.of(context)` が null になり
  ダイアログ表示時にクラッシュする（`Null check operator used on a null value`）。
  対策として、`MaterialApp.localizationsDelegates` へ標準 flutter/material の
  `DefaultMaterialLocalizations.delegate` / `DefaultWidgetsLocalizations.delegate` を
  追加した（`app.dart`）。フォーク型と標準型の両方がツリーに登録され、双方の UI が動作する。

## 代替案

- `auto_updater` を維持する
  - 却下: 低水準 API・AppCast XML の配布制約・将来メンテナンスの観点から後継への移行が望ましい。
- 独自の更新 UI を維持して `desktop_updater` を裏で駆動する
  - 却下: ライブラリが提供する組み込み UI を活用する方が、状態管理と保守が簡潔。

## 結果

- 更新処理・配布形式・更新 UI が desktop_updater に一本化される。
- 起動・macOS メニュー・About 画面の3経路の更新確認を、desktop_updater の状態遷移上で統一的に扱える。
- 配布ホストの選定と Release ワークフローへの公開処理統合は、別途のインフラ対応として今後実施する。