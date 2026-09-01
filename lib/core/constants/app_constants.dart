/// アプリケーション全体で使用する定数を定義する。
class AppConstants {
  AppConstants._();

  /// upscal-bin のバージョン。
  static const String upscalBinVersion = 'upscayl-bin-20251207-174704';

  /// JPEG (jpegoptim) のバージョン。
  static const String jpegVersion = 'v1.5.6';

  /// PNG (pngoptim) のバージョン。
  static const String pngVersion = 'v0.5.4';

  /// JPEG XL (libjxl) のバージョン。
  static const String jpegXlVersion = 'v0.12.0';

  /// AV1 (libavif) のバージョン。
  static const String av1Version = 'v1.4.2';

  /// WebP (libwebp) のバージョン。
  static const String webpVersion = '1.6.0';

  /// GitHub のリポジトリオーナー。
  static const String githubOwner = 'treetips';

  /// GitHub のリポジトリ名。
  static const String githubRepo = 'tree-image-optimizer';

  /// GitHub リポジトリの URL。
  static const String githubUrl =
      'https://github.com/treetips/tree-image-optimizer';

  /// 配布用 tools アーカイブ（tools-v{version}.zip）の期待 SHA-256。
  ///
  /// ツールを含まないリリースでも本体更新時にこの ZIP をダウンロードするため、
  /// 改ざん・破損検知のために期待ハッシュをアプリに固定（ピン留め）する。
  /// 値は GitHub Releases の `tools-v{version}.zip` の実ハッシュと一致させること。
  /// リリースワークフロー（release.yml）で build 前に自動差し替えられるため、
  /// 通常は手動で変更する必要はない。
  static const String toolsSha256 =
      '9d00d1268aefcdf2bedd0a63da3cc8c9e0bf81059d3ed072b5512810aab63d6b';

  /// アップデート情報 JSON の URL。
  ///
  /// GitHub Releases に配置された update-info.json を参照する。
  static const String updateInfoUrl =
      'https://github.com/treetips/tree-image-optimizer/releases/latest/download/update-info.json';

  /// 壁紙アセットのパス。
  ///
  /// `assets/images/wallpaper/` 配下の壁紙画像を指定する。変更時は `pubspec.yaml` の
  /// `flutter.assets` も合わせて更新すること。
  static const String wallpaperAsset = 'assets/images/wallpaper/wallpaper1.jpg';

  /// 壁紙の不透明度 (0.0: 透明 〜 1.0: 不透明)。
  ///
  /// `HomeShell` の背景画像に適用される。値を下げると壁紙が薄くなり、
  /// Liquid Glass の視認性が上がる。
  static const double wallpaperOpacity = 0.4;
}
