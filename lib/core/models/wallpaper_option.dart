/// 壁紙の選択肢を表す。
class WallpaperOption {
  const WallpaperOption({
    required this.name,
    required this.source,
    required this.isBundled,
  });

  /// 表示名(ファイル名)。
  final String name;

  /// ソース。
  /// 同梱壁紙はアセットパス(`assets/images/wallpaper/...`)、ユーザー壁紙は絶対パス。
  final String source;

  /// 同梱壁紙かどうか。
  final bool isBundled;

  /// プルダウンに表示するラベル。
  /// 同梱壁紙のみ `（サンプル）` をprefixに付ける。
  String get label => isBundled ? '（サンプル）$name' : name;
}
