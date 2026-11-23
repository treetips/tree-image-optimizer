# アプリケーション設定ファイル

## 設定ファイルパス

`~/.config/tree-image-optimizer/settings.json`

## 設定ファイル構造

`settings` `batchConvert` `easyConvert` の3セクションを持ちます。
一括変換と、かんたん変換の設定は独立して保存します。

```json
{
  "settings": {
    "showOsNotification": false,
    "playSound": false,
    "successSound": "assets/sounds/success/decision49.mp3",
    "errorSound": "assets/sounds/error/beep1.mp3",
    "successSoundRandom": false,
    "errorSoundRandom": false,
    "language": "",
    "appearance": "auto",
    "fontSize": "standard",
    "wallpaper": "背景無し",
    "wallpaperOpacity": 1.0,
    "wallpaperBackgroundColor": "#1E1E1E",
    "wallpaperRandom": false,
    "wallpaperShuffleInterval": 1
  },
  "batchConvert": {
    "targetFilter": "sevenDays",
    "showWaiting": true,
    "showRunning": true,
    "showSuccess": true,
    "showFailure": true,
    "showCancelled": true,
    "mode": "fixed",
    "contentType": "anime",
    "targetSize": "k5",
    "qualityPreset": "high",
    "scale": 2,
    "model": "realesr-animevideov3-x4",
    "engine": "upscayl",
    "realCuganModel": "models-se/up2x-conservative",
    "format": "jpegXl",
    "optimizeType": "anime",
    "quality": 80,
    "parallelCount": 7,
    "inputFolderPath": null,
    "outputFolderPath": null,
    "modeNoteExpanded": true,
    "formatsExpanded": true
  },
  "easyConvert": {
    "engine": "upscayl",
    "model": "realesr-animevideov3-x4",
    "realCuganModel": "models-se/up2x-conservative",
    "scale": 2,
    "format": "jpegXl",
    "optimizeType": "anime",
    "quality": 80,
    "parallelCount": 7,
    "outputFolderPath": null
  }
}
```

- `parallelCount` の初期値はPコア数の半分（端数切り捨て、最低1）です。
  上の例はPコア数14の環境を想定しています。
- `settings.language` が空文字の場合はOSの言語設定に従います。
- 壁紙のランダム表示は `wallpaperRandom`、切り替え間隔（分）は
  `wallpaperShuffleInterval` です。旧名のキーは互換のため読み書きされます。
- `mode` は `fixed` / `auto`。`auto` のときは `contentType` `targetSize`
  `qualityPreset` を使い、`scale` `optimizeType` `quality` は使いません。

## 旧形式からの移行

- 旧形式の `convert` / `batch` キーがある場合は `batchConvert` として読み込みます。
- 旧形式の `easy` キーがある場合は `easyConvert` として読み込みます。
- 不足セクションは初期値で補い、新形式で書き換えます。

## 自動生成

- アプリケーション起動時に `settings.json` は自動生成されます。
- 各設定は初期値が設定されます。

## 自動更新

- 各画面で設定値を変更すると、その選択値が `settings.json` に反映されます。

## アプリ起動時に設定が復元

- アプリケーション起動時に `settings.json` が読み込まれ、設定値が復元されます。
