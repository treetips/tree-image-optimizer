# アプリケーション設定ファイル

## 設定ファイルパス

`~/.config/tree-image-optimizer/settings.json`

## 設定ファイル構造

`settings` `batchConvert` `easyConvert` 等、トップレベルには `画面` セクションを作成します。
一括変換と、かんたん変換の設定は独立して保存します。

```json
{
  "settings": {
    "showOsNotification": false,
    "playSound": false,
    "successSound": "assets/sounds/success/decision49.mp3",
    "errorSound": "assets/sounds/error/beep1.mp3",
    "language": ""
  },
  "batchConvert": {
    "targetFilter": "sevenDays",
    "scale": 2,
    "model": "realesr-animevideov3-x4",
    "format": "jpegXl",
    "optimizeType": "anime",
    "quality": 80,
    "parallelCount": 7,
    "inputFolderPath": null,
    "outputFolderPath": null
  },
  "easyConvert": {
    "scale": 2,
    "model": "realesr-animevideov3-x4",
    "format": "jpegXl",
    "optimizeType": "anime",
    "quality": 80,
    "parallelCount": 7,
    "outputFolderPath": null
  }
}
```

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
