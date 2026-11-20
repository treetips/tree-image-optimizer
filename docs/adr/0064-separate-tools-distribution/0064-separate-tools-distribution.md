# アプリ本体から tools を分離しツール単位で GitHub Releases 配布する

## ステータス

- 承認済み (Accepted)

## 背景・課題

ADR 0048 で「配布ビルドにツール一式を同梱する」方針を採った結果、次の問題が顕在化した。

1. **配布物の肥大化**。`Copy Tools` ビルドフェーズが Release ビルド時に
   `tools/`（約 435MB）を `.app/Contents/Resources/tools` へ同梱するため、
   配布 `.app` は約 466MB に達している。アプリ本体のロジックはごく小さいにも
   かかわらず、毎回 tools 一式を帯同する。
2. **tools に更新が無いのに本体更新で tools ごと更新される**。本体 ZIP に
   tools が丸ごと含まれるため、アプリ本体だけを更新したい場合でも
   必ず約 435MB の tools が付随する。逆に tools だけを更新したい場合でも
   本体ごと再配布しなければならない。
3. **tools の更新機構が存在しない**。`ToolInstaller.isInstalled()` は
   バイナリの有無だけを検査し、バージョン比較や再取得は行わない。
   ADR 0017 が構想した `tools/.installed_version` によるバージョン不整合検知は
   Flutter 版のみで、SwiftUI 版には移植されていない。
4. **ダウンロード処理が一部ツールに限られる**。`ToolInstaller` は `libwebp` と
   `realcugan` のみネットワーク取得でき、`upscal` / `jpegoptim` / `pngoptim` /
   `libjxl` / `libavif` はローカルコピーにしか対応しない。

一方、ADR 0048 の時点で「却下」された別配布案の障壁は、現在は解消している。

- ADR 0048 当時は「SHA-256 検証・展開・失敗時の再試行など配布基盤の追加実装が
  必要」だったが、`UpdateService` と `UpdateCheckController` により
  download → SHA-256 検証 → unzip 展開 → `.app` 検出 → 置換 → 再起動まで
  実装済みである（ADR 0050・0051 も参照）。
- さらに ADR 0057 で、`ToolInstaller` のネットワーク取得（`realcugan` /
  `libwebp`）にも SHA-256 検証と指数バックオフ再試行が導入済みである。
  本 ADR のツール単位ダウンロードは、この検証・再試行の仕組みを全ツールへ
  一般化する形で実装できる。
- `update-image-tools` スキルにより、各ツールの配布元（GitHub Releases /
  Google Storage）と取得方法・配置階層が文書化・自動化されている。

## 決定

- アプリ本体と tools を分離し、**tools はツール単位の ZIP を GitHub Releases で
  別配布する**。アプリ本体の配布 ZIP から `tools/` の同梱を外す。
- 各ツールのメタデータ（名前・バージョン・ダウンロード URL・SHA-256）を
  `tools-info.json` に集約し、GitHub Releases に添付する。
- アプリは**起動時に `tools-info.json` を取得**し、ローカルの tools 状態と
  突き合わせて**差分のあるツールだけ**をダウンロード・差し替えする。
- アプリ本体の更新（`UpdateService`）と tools の更新（新設の `ToolsUpdateService`）は
  独立させ、本体更新で tools を帯同しない。

### 配布アセット構成

1 リリースあたり、アプリ本体 ZIP に加えて次を配布する。

- `Tree-Image-Optimizer-vX.Y.Z-macos.zip`（アプリ本体のみ。tools を含まない）
- `tools-info.json`（全ツールのバージョン・URL・SHA-256 の一覧）
- `tools-<name>-<version>.zip`（ツール単位。更新のあったツールのみ）

`tools-info.json` の形式（案）:

```json
{
  "schemaVersion": 1,
  "tools": [
    {
      "name": "upscal",
      "version": "upscayl-bin-20251207-174704",
      "url": "https://github.com/treetips/tree-image-optimizer/releases/download/v0.3.0/tools-upscal-upscayl-bin-20251207-174704.zip",
      "sha256": "<hex>",
      "required": true
    }
  ]
}
```

### ツール単位のバージョン管理

- バージョンの正は各ツールの `.version`（無いツールは `AppInfo` の定数）とする。
  現在 `.version` を持つのは `upscal` / `realcugan` / `libjxl` / `libavif` の 4 つで、
  `jpegoptim` / `pngoptim` / `libwebp` は持たない（`update-image-tools` スキルの表に従う）。
- ローカルのインストール済みバージョンを記録するため、`tools/.installed.json`
  （または `.installed_version` 相当）を新設し、起動時の更新判定に使う。

### 起動時の更新フロー

1. `ToolBootstrapModel`（または新設の `ToolsUpdateService`）が
   `tools-info.json` を取得する。
2. ローカルのインストール済みバージョンと突き合わせ、差分のあるツールを列挙する。
3. 差分があれば該当ツールの ZIP だけを download → SHA-256 検証 → unzip 展開 →
   配置 → `.installed.json` 更新を行う。
4. 差分が無ければ何もしない（現行の tools をそのまま使用）。
5. ネットワーク到達不能・検証失敗時は、既存 tools でフォールバックし、
   初回起動で tools が無い場合のみ復元元として同梱物を使う（後方互換）。

## ツール更新の UI

tools だけ更新がある場合の画面表示・操作フローを定める。既存のアプリ本体更新
（`UpdateCheckController` とサイドナビ下部の更新カード）と並存させる。

### 更新カードの分割

- サイドナビ下部の更新カードを「アプリ本体」と「ツール」の **2 枚に分割**し、
  縦に並べる。それぞれ独立した状態と操作を持つ。
  - アプリ本体カード: 既存の `UpdateCard`（`.available` / `.installing` /
    `.installFailed` / `.noUpdate`）をそのまま流用する。
  - ツールカード: 新設の `ToolsUpdateCard` として同型の状態機械を別に持つ。
- 本体更新とツール更新は**独立に動作し、同時実行を許可する**。
  片方だけ更新がある場合はその 1 枚だけを表示し、もう一方は表示しない
  （`noUpdate` カードも表示しない）。

### ツール更新の検出・通知

- 起動時に `tools-info.json` を取得し、ローカルのインストール済みバージョンと
  差分のあるツールを列挙する。
- 差分があればサイドナビに「ツール更新が有ります」カードを表示する。
  - ユーザーがクリックするまでダウンロード・適用は行わない（本体更新と同じ
    「通知 → ユーザー確認 → 更新」の UX）。
- 差分が無ければカードは表示しない。

### ツール更新の実行フロー

1. ツール更新カードをクリックすると確認ダイアログを表示する
   （更新対象ツールの一覧と合計サイズを提示）。
2. ユーザーが「更新」を選ぶとダイアログが閉じ、カードが「インストール中」に変わる。
3. 差分のあるツールだけを順に download → SHA-256 検証 → 展開 → 配置 → 記録更新する。
   進捗は受信バイト数（Content-Length 基準）の確定バーと、検証・展開の不確定バーで
   表示する（既存の `UpdateInstallProgress` と同様の方式）。
4. 完了したらカードを消す。失敗したら赤い「インストールに失敗」カードへ切り替え、
   「再実行」でやり直せる（既存 ADR 0051 と同様）。
5. ツール更新はアプリ本体の置換・再起動を伴わない。更新完了後もアプリは起動したまま。

### 本体更新との同時表示

- 本体更新とツール更新が同時に発生した場合は、2 枚のカードを縦に並べて表示する。
  どちらから先に操作してもよく、実行も独立（同時実行可）とする。
  - 片方がインストール中でも、もう片方の確認・インストール開始を妨げない。
- **本体更新の完了（再起動）によってツール更新が中断された場合は、次回起動時に
  再開する。** 再開は起動時の `tools-info.json` 差分判定で自然に検出されるため、
  専用の再開フラグを設けず、未完のツールを再度「更新対象」として扱う。
  - ツールの配置は「全削除してから置く」方針（`update-image-tools` スキル）のため、
    中断されたツールは中途半端な配置となり得る。起動時の存在チェックと
    バージョン不一致検知で検出し、再取得する。
  - 本体更新とツール更新を同時に実行すると再起動で進捗が失われるため、
    実装上は「本体更新の完了（再起動）が近い場合はツール更新の開始を
    待機させる」選択肢も残すが、既定は独立実行＋次回再開とする。

### ツール更新と起動時オーバーレイの関係

- 初回起動（tools 未展開）は従来どおり `ToolBootstrapModel` の全画面オーバーレイで
  展開し、操作をブロックする。
- 一方、既に tools が揃っていて**差分更新がある場合**はオーバーレイでブロックせず、
  サイドナビのツール更新カードによる非同期通知のみとする（起動を妨げない）。

## 後方互換・移行

- **初回起動時の復元元**を失わないため、既存ユーザー向けにはアプリ本体 ZIP から
  tools を完全に外すのではなく、`tools/` の同梱を段階的に廃止する。
  少なくとも移行直後のリリースでは、アプリ内 `Resources/tools` を
  フォールバックの復元元として残す選択肢を検討する。
- Application Support 配下にダウンロード済み tools がある既存ユーザーは、
  起動時の更新判定で `.installed.json` が無いため初回に全ツールを再取得する
  ことになる。初回のみ全取得が発生する点を許容し、以後は差分更新に切り替わる。
- ADR 0048 の `Copy Tools` ビルドフェーズは廃止し、ADR 0048 は Superseded とする。

## 代替案

- tools 全体を単一 ZIP（`tools-VERSION.zip`）で配布する
  - 却下: 1 ツールの更新でも全ツール（約 435MB）をダウンロードすることになり、
    「tools に更新が無いのに tools ごと更新される」問題の再発形となる。
- アプリ本体に tools を同梱し続ける（現状維持）
  - 却下: 本 ADR の背景・課題のとおり、肥大化と不要な帯同が解決しない。
- 各ツールの上流（GitHub Releases / Google Storage）から直接取得する
  - 却下: 上流の配布形式・URL・リリース方針がツールごとに異なり、安定した
    取得・検証・フォールバックが保証できない。自前の GitHub Releases に
    正規化したアセットを置く方が堅牢。

## 結果

- アプリ本体 ZIP は tools を含まない約 30MB 程度まで縮小する見込み。
- tools の更新は差分のあるツールだけになり、「tools に更新が無いのに本体更新で
  tools ごと更新される」問題が解消する。
- tools 単独の更新（上流のバグ修正・脆弱性対応など）を、アプリ本体のリリースと
  独立して提供できる。
- 実装箇所（予定）: `.github/workflows/release.yml`（tools アセット生成・
  `tools-info.json` 生成）、`project.pbxproj`（`Copy Tools` 廃止）、
  `ToolInstaller.swift` / 新設 `ToolsUpdateService.swift`・`ToolsUpdateController.swift`、
  `ToolBootstrapModel.swift`、`AppPaths.swift`、`AppInfo.swift`、
  `RootView.swift`（ツール更新カードの追加）

## 未確定事項

- `tools-info.json` の正確なスキーマとバージョン付与（`schemaVersion` の扱い）。
- 移行期間中にアプリ内 `Resources/tools` を残すか完全廃止するかの確定。
- 初回起動時の全ツール一括取得を許容するか、段階取得（必須ツール優先）にするか。
