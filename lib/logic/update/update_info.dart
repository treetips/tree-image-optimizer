import 'dart:convert';

/// GitHub Releases に配置するアップデート情報。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.build,
    required this.url,
    required this.sha256,
  });

  /// JSON から復元する。
  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] as String,
      build: json['build'] as int,
      url: json['url'] as String,
      sha256: json['sha256'] as String,
    );
  }

  /// 文字列から復元する。
  factory UpdateInfo.fromString(String source) {
    return UpdateInfo.fromJson(jsonDecode(source) as Map<String, dynamic>);
  }

  /// セマンティックバージョン (例: "0.0.10")。
  final String version;

  /// ビルド番号 (例: 6)。
  final int build;

  /// ダウンロード URL。
  final String url;

  /// ZIP ファイルの SHA-256 ハッシュ。
  final String sha256;

  /// 現在のバージョンと比較してアップデートが必要か。
  bool isNewerThan({
    required String currentVersion,
    required int currentBuild,
  }) {
    final currentParts = currentVersion.split('.').map(int.parse).toList();
    final newParts = version.split('.').map(int.parse).toList();

    // セマンティックバージョンを比較 (major.minor.patch)。
    for (var i = 0; i < 3; i++) {
      final c = i < currentParts.length ? currentParts[i] : 0;
      final n = i < newParts.length ? newParts[i] : 0;
      if (n > c) return true;
      if (n < c) return false;
    }

    // バージョンが同じならビルド番号で比較。
    return build > currentBuild;
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'build': build,
    'url': url,
    'sha256': sha256,
  };

  @override
  String toString() => 'UpdateInfo(v$version+$build)';
}
