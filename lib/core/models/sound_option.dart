/// サウンドの選択肢を表す。
class SoundOption {
  const SoundOption({
    required this.name,
    required this.source,
    required this.isBundled,
  });

  /// 表示名(ファイル名)。
  final String name;

  /// 再生ソース。
  /// 同梱サウンドはアセットパス(`assets/sounds/...`)、ユーザーサウンドは絶対パス。
  final String source;

  /// 同梱サウンドかどうか。
  final bool isBundled;

  /// プルダウンに表示するラベル。
  /// 同梱サウンドのみ `（サンプル）` をprefixに付ける。
  String get label => isBundled ? '（サンプル）$name' : name;
}
