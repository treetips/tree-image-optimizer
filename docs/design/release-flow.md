# アプリケーションとツールのリリースフロー

## 目的

検証済みのmacOSアプリと外部ツールをGitHub Releasesへ公開する。利用者が更新を取得できるようにする。アプリ本体とツールは更新頻度が異なるため、別々のReleaseとして配布する。手作業を減らす。

- アプリ本体はセマンティックバージョンとGitHubタグを一致させる。
- ツールはアプリのバージョンを変更せずに公開できる。
- 手動作業はPRマージとGitHub Actionsの実行ボタン押下に限定する。
- ツールの上流更新はRelease Toolsが検出し、更新なしならGitHub Releaseを変更せず正常終了する。
- 失敗した配布物を利用者へ公開しない。

## Release構成

| 種類   | タグ                 | GitHub上の位置                       | 主な成果物                                         |
| ------ | -------------------- | ------------------------------------ | -------------------------------------------------- |
| アプリ | `vMajor.Minor.Patch` | 通常リリース。GitHubの「Latest」     | アプリZIP、`update-info.json`、`SHA256SUMS.txt`    |
| ツール | `tools-latest`       | 事前リリース。「Latest」にはならない | `tools-info.json`、ツール単位ZIP、`SHA256SUMS.txt` |

ツールReleaseを事前リリースに保つことで、アプリの `releases/latest/download/update-info.json` が引き続きアプリ本体を指す。

## 全体フロー

```text
1. 機能開発・PRレビュー・CI
2. mainへマージ
3. Release Tools を実行し、ツールに更新がある場合だけ配布物を更新する。
   ├─ 上流の最新バージョンを解決
   ├─ 既存tools-latestのmanifestと比較
   ├─ 更新がある場合だけツールを取得・ビルド
   ├─ ツール単位ZIP・tools-info.json・SHA256SUMS.txtを生成
   └─ tools-latestの事前リリースを更新
4. アプリを公開する場合 Release を実行
   ├─ tools-latest/tools-info.jsonの取得を検証
   ├─ バージョンとビルド番号を算出
   ├─ Debugテスト・Releaseビルド
   ├─ アプリZIP・update-info.json・SHA256SUMS.txtを生成
   ├─ vX.Y.Zタグを作成
   └─ 通常リリースを作成
```

## ブランチとバージョン

- `main` がリリース候補の安定版ブランチです。直接pushは禁止し、PR経由でマージします。
- アプリの表示バージョンは `TreeImageOptimizer/TreeImageOptimizer/Info.plist` の `CFBundleShortVersionString` と `CFBundleVersion` を使います。
- Releaseワークフローが最新の `vX.Y.Z` タグとbump指定から次のバージョンを算出します。
- ビルド番号は直近のアプリReleaseにある `update-info.json` の `build` に1を加えます。初回だけInfo.plistの値を使います。
- ローカルでアプリのバージョンを手動更新する必要はありません。
- 配布するツールのバージョンはRelease Toolsが上流から解決する。開発用ツールのバージョンは `tools/<name>/.version` を正本とし、ファイルがない3ツールは `TreeImageOptimizer/TreeImageOptimizer/Core/AppInfo.swift` の定数を使います。

## ツールRelease

### 実行

1. GitHubの **Actions** → **Release Tools** → **Run workflow** を開く。
2. 配布先は `tools-latest` に固定される。
3. 上流の更新を確認し、同一バージョンでも配布物を作り直す場合だけ `force` を有効にする。定期実行時は `false` として扱う。

### 処理内容

1. 7ツールの上流最新バージョンを解決する。GitHub Releasesを参照する6ツールに加え、libwebpはGoogle Storageの配布一覧から最新版を選ぶ。
2. 既存の `tools-latest` とバージョン・必須資産・Release状態・asset digestを比較する。
3. 変更がなければbuildとpublishをスキップし、ジョブサマリーに「変更なし」を記録して正常終了する。API障害や不正なmanifestを更新なしとして扱わない。
4. 更新がある場合だけ、Git LFSを取得し、解決済みバージョンで変更されたツールを取得する。libjxlとlibavifはADR 0056・ADR 0037の構成でソースビルドする。現行版の再公開時は、リポジトリ内バイナリがmacOS 26.0以下に対応していれば再利用する。
5. `tools/build-tools-release.sh` が変更されたツールだけZIP化し、変更されないツールは公開中manifestのchecksumを引き継ぐ。ZIPの日時・権限・エントリ順・圧縮方式を固定する。
6. ZIPのルートはツール名ディレクトリとし、クライアントの展開規則を変えない。
7. Git LFSポインタや空のバイナリ・モデル・dylibを実体と誤認しないことを確認する。
8. `tools/publish-tools-release.sh` が事前リリースのDraftを作成・更新し、新しいZIP、チェックサム、マニフェストの順に公開する。
9. 全資産をアップロードしてからDraftを公開し、古い資産は新しいマニフェスト公開後に削除する。
10. 通常公開は同名assetのチェックサムが異なる場合に失敗する。既存manifestとremote assetのchecksumが一致する同版assetは再利用する。`force=true` の場合だけ、明示的な修復として上書きを許可する。

### 成果物

- `tools-<name>-<version>.zip`
- `tools-info.json`
- `SHA256SUMS.txt`

`tools-info.json` の各URLは `releases/download/tools-latest/` で統一する。スキーマは `schemaVersion: 1` を維持する。

## 上流の配布元

- upscal: [upscayl/upscayl-ncnn の Releases](https://github.com/upscayl/upscayl-ncnn/releases)
- Real-CUGAN: [nihui/realcugan-ncnn-vulkan の Releases](https://github.com/nihui/realcugan-ncnn-vulkan/releases)
- jpegoptim: [tjko/jpegoptim の Releases](https://github.com/tjko/jpegoptim/releases)
- pngoptim: [okooo5km/pngoptim の Releases](https://github.com/okooo5km/pngoptim/releases)
- libjxl: [libjxl/libjxl の Releases](https://github.com/libjxl/libjxl/releases)
- libavif: [AOMediaCodec/libavif の Releases](https://github.com/AOMediaCodec/libavif/releases)
- libwebp: [Google Storage の libwebp 配布一覧](https://storage.googleapis.com/downloads.webmproject.org/releases/webp/index.html)

macOS用assetがあるツールはそのassetを使う。libjxlとlibavifはソースビルドが必要なため、それぞれADR 0056とADR 0037の構成を維持する。

## アプリRelease

### 実行

1. 事前にRelease Toolsを実行し、`tools-latest/tools-info.json` を取得できるようにする。
2. GitHubの **Actions** → **Release** → **Run workflow** を開く。
3. bumpとして `major` / `minor` / `patch` を選ぶ。

### 処理内容

1. 最新の `vX.Y.Z` タグとbump指定から次バージョンを算出する。
2. 直近のアプリReleaseのビルド番号から次ビルド番号を算出する。
3. `tools-latest/tools-info.json` を取得し、必須7ツール・URL・SHA-256・参照assetの存在を検証する。
4. `.xcode-version` で指定したXcodeを選択する。
5. DebugテストとmacOS Releaseビルドを実行する。
6. アプリをアドホック署名し、署名を検証する。
7. アプリZIP、`update-info.json`、`SHA256SUMS.txt` を生成する。
8. `vX.Y.Z` タグを作成してpushする。
9. Draft ReleaseへアプリZIP、チェックサム、更新情報をアップロードし、ダウンロードして内容とSHA-256を検証する。
10. 検証後のDraftだけを通常Releaseとして公開し、GitHubの「Latest」にする。

同じアプリReleaseにツールZIPや `tools-info.json` は添付しない。

## クライアントの参照先

- アプリ更新情報: `https://github.com/treetips/tree-image-optimizer/releases/latest/download/update-info.json`
- アプリ本体: `https://github.com/treetips/tree-image-optimizer/releases/download/<tag>/Tree-Image-Optimizer-v<version>-macos.zip`
- ツール情報: `https://github.com/treetips/tree-image-optimizer/releases/download/tools-latest/tools-info.json`
- ツール本体: `https://github.com/treetips/tree-image-optimizer/releases/download/tools-latest/tools-<name>-<version>.zip`

アプリは更新情報のバージョンとビルド番号を比較し、ZIPをSHA-256検証して再起動用にステージングする。ツールは `tools-info.json` とローカル記録を比較し、差分のあるツールだけを更新する。

## 初回リリースと移行

- 初回は先にRelease Toolsを実行する。ツール配布が無い状態でアプリを公開しない。
- 既存クライアントはアプリ本体の更新を継続できる。
- 新しいアプリへ更新するまでは、旧クライアントのツール更新確認だけ失敗し、既存ツールを使い続ける。
- クリーンインストールの初回起動は、開発用ローカルコピーを試した後、`tools-latest` から不足ツールを取得する。

## 失敗時と再実行

- テスト・ビルド・パッケージングに失敗した場合、タグやReleaseは作成しない。
- アプリReleaseはDraft作成後に全assetを検証してから公開する。失敗時はDraftとタグが残るため、mainが同じコミットのままなら同じbumpで再実行し、Draftを再開する。公開済みReleaseは上書きしない。
- ツール公開は全資産をatomicに置き換える処理ではない。新規・再開Draftは全資産のアップロード後に公開し、途中失敗後は `force=true` で再実行してマニフェストと全資産の整合性を確認する。forceは同名assetの明示的な上書きを許可し、同版のlibjxl/libavifはリポジトリ内バイナリが非対応なら再ビルドする。通常更新ではツールバージョンを変更する。
- アプリ公開後の不具合は新しいバージョンで修正する。公開済みReleaseのタグや成果物を直接上書きしない。

## 配布上の注意

現在はアドホック署名で配布するため、Gatekeeperの警告と初回起動時の手動許可が必要になる。macOS専用配布であり、Windows/Linux向けバイナリは提供しない。
