# 壁紙表示の圧縮フォーマット対応

## ステータス

- 承認済み (Accepted)

## 背景・課題

本アプリで変換した画像 (jxl / avif / webp) を設定画面の背景画像にそのまま
使いたい要望がある。従来は背景画像一覧が jpg / jpeg / png の拡張子のみを
受け付けており、圧縮フォーマットで変換したファイルはそのまま使えなかった。

macOS 標準の ImageIO は jxl / avif / webp のデコードに対応している
(壁紙表示に用いる `NSImage(contentsOf:)` は ImageIO 経由で読むため、
表示側の変更は不要)。拡張子フィルタだけが壁紙一覧を絞っていた。

## 決定

- `WallpaperService` の拡張子フィルタに `jxl`, `avif`, `webp` を追加する。
- アニメーション対応の拡張子 (`avifs`, アニメーション WebP の動画用途) は
  スコープ外とする (静止画のみ)。
- デコードは macOS 標準の ImageIO に任せ、デコーダーやライブラリは
  追加しない。

## 代替案

- 独自に libjxl / libavif をリンクしてデコードする
  - 却下: ImageIO が同等のデコードを提供しており、依存とバンドルの
    複雑さを増やすだけのため。
- 変換後に png へ再変換して壁紙にする
  - 却下: ユーザーが「変換画像をそのまま使う」要件に反する。

## 結果

- ユーザー配置フォルダ (`wallpaper/`) に変換済みの
  `.jxl` / `.avif` / `.webp` を置くだけで背景画像として選択できる。
- 実装箇所: `WallpaperService.listWallpaperFiles`
- テスト: `MediaServicesTests.wallpapers`
