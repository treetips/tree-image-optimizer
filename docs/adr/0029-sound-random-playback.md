# 成功時・失敗時のサウンドのランダム再生を追加する

## ステータス

- 承認済み (Accepted)

## 背景・課題

設定画面の `成功時のサウンド` / `失敗時のサウンド` は単一ファイルを選択するのみで、
ユーザーが配置した複数の音声から毎回異なる1つを再生する「ランダム再生」はできなかっ
た。壁紙シャッフル（0027）と同様に、変換終了時にランダムに音声を切り替える機能が求め
られていた。

## 決定

- 設定画面の成功時・失敗時サウンド行それぞれに `ランダム` チェックボックスを追加する。
    - チェックで該当プルダウンと `▶️` ボタンを `disabled` にし、解除で `enable` にする。
    - プルダウンの選択値は消さない。チェックを戻せば元の選択に復帰する。
- 変換終了時（一括変換・かんたん変換とも）に、ランダム有効ならユーザー配置サウンド
  （`~/.config/tree-image-optimizer/sounds/{success,error}`）から抽選して再生する。
    - 同梱（サンプル）サウンドは抽選対象外。壁紙シャッフル（0027）と同一の方針。
    - ユーザー配置が無い・空の場合は選択中のサウンドへフォールバックし、音が鳴らない
      事態を防ぐ。
- 抽選ロジックは `SoundService.resolvePlaybackOption(success:name:random:)` に集約する。
    - 一括変換（`ConvertJobStore`）・かんたん変換（`EasyConvertJobStore`）は同一の呼び
      出しに置き換え、ジョブストア側で抽選を分岐させない。
- 設定は `ScreenSettings` に `successSoundRandom` / `errorSoundRandom` として永続化する。
  初期値は `false`（チェック無し）。旧Flutter設定との互換エイリアスは新キーのため不要。

## 代替案

- 抽選対象に同梱サンプルも含める
    - 却下: 仕様（settings.md）が `サンプル` はシャッフル非対象と定めている。
- 抽選処理を各ジョブストアに実装する
    - 却下: 再生決定処理の重複になる。0027のTimerをViewModelに置いたのに対し、ジョブ
      ストア2箇所の重複はServiceへ集約する方がテスト可能で小さい。
- `▶️` ボタンをランダム有効時も有効のままにする（選択音の試聴を許可）
    - 却下: 初回実装時に採用したが、その後の仕様追記で `▶️` ボタンの無効化が
      定められたため仕様に合わせて無効化する。

## 結果

- 変換終了時にユーザー配置サウンドからランダムに1つ再生できるようになった。
- `SettingsStoreTests` / `MediaServicesTests` / `SettingsViewModelTests` で永続化・抽選・
  UI状態の仕様を固定した。
- 実装箇所:
  - `TreeImageOptimizer/TreeImageOptimizer/Features/Settings/SettingsView.swift`
  - `TreeImageOptimizer/TreeImageOptimizer/Features/Settings/SettingsViewModel.swift`
  - `TreeImageOptimizer/TreeImageOptimizer/Services/SettingsStore.swift`
  - `TreeImageOptimizer/TreeImageOptimizer/Services/SettingsStoreValues.swift`
    - 設定値の型変換・検証ヘルパー（旧Primitives節）。`SettingsStore` のクラス本体が
      行数制限を超えたためextensionとして分離した（機能追加に伴うリファクタ）。
  - `TreeImageOptimizer/TreeImageOptimizer/Services/SoundService.swift`
  - `TreeImageOptimizer/TreeImageOptimizer/Features/Convert/ConvertJobStore.swift`
  - `TreeImageOptimizer/TreeImageOptimizer/Features/EasyConvert/EasyConvertJobStore.swift`
