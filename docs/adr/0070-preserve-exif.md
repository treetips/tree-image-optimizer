# 変換出力に元画像の EXIF を保持する

## ステータス

- 承認済み (Accepted)

## 背景・課題

変換パイプラインは、アップスケールが PNG 中間画像を生成する段階で元画像の
EXIF（撮影情報・回転）を失っていた。そのため、写真を JPEG/PNG へ変換すると
撮影日時やカメラ情報、回転情報が消えていた。

ImageIO 経由で JPEG/PNG を生成する箇所（`CompressionService.convertToJPEG` /
`convertToPNG`）は `CGImageDestinationAddImage` で画像だけを書き出しており、
メタデータを渡していなかった。

## 決定

ImageIO 経由で生成する JPEG/PNG 出力に対し、元画像のメタデータ木（EXIF・XMP・IPTC・GPS）を
`CGImageMetadata` として引き継ぐ。

### 実装

- 圧縮ワーカーへ元画像のパス（`UpscaledItem.source`）を持たせ、`CompressionService.run`
  へ渡す。
- `CompressionService` は元画像から `CGImageSourceCopyMetadataAtIndex` でメタデータ木を読み、
  `CGImageDestinationAddImageAndMetadata` で出力へ書き込む。
- 出力のピクセルは既に変換済みのため、`CGImageSourceCopyPropertiesAtIndex` の全プロパティ
  （寸法・色深度など）ではなくメタデータ木だけを渡す。寸法プロパティを渡すと
  出力寸法と一致せず書き込みに失敗するため。

### 対象フォーマット

- **JPEG / PNG**: 本 ADR の対象。ImageIO がメタデータ木をそのまま保持できる。
- **JPEG XL / AV1 / WebP**: 本 ADR では対象外。エンコーダが PNG 中間からメタデータを
  引き継ぐか、個別のメタデータ引数が必要で、形式ごとの対応が必要になるため、別途扱う。

### 対象外: ICC（カラープロファイル）

ICC は `CGImageMetadata` のメタデータ木に含まれない（画像の色空間プロパティ側にある）。
また、アップスケーラが色変換を行うか・行わないかが不明で、色空間だけを再タグ付けすると
かえって色味がずれるリスクがある。ICC の保持は別途、アップスケーラの色変換挙動を
実測で確認してから対応する。

## 代替案

- **`CGImageSourceCopyPropertiesAtIndex` の全プロパティを渡す**: 寸法・色深度などの
  画像属性まで含まれるため、リサイズ済み出力との不整合で書き込みに失敗する。却下。
- **色空間の再タグ付け（`CGImage.copy(colorSpace:)`）で ICC を保持する**: アップスケーラが
  色変換済みか未変換かで正否が分かれ、逆に色味を崩す恐れがある。実測後に再検討する。

## 結果

- 写真を JPEG/PNG へ変換しても EXIF（撮影情報・回転）が維持される。
- ICC は引き続き保持されない（今後の課題）。
- 実装箇所: `CompressionService.swift`、`BatchScheduling.swift`、`ConvertOrchestratorWorkers.swift`。
