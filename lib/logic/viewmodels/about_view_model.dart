import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// About 画面の状態。
class AboutState {
  const AboutState({this.appVersion = aboutVersionLoading});

  final String appVersion;

  AboutState copyWith({String? appVersion}) {
    return AboutState(appVersion: appVersion ?? this.appVersion);
  }
}

/// バージョン読み込み中のセンチネル。
const String aboutVersionLoading = '__about_version_loading__';

/// バージョン取得失敗のセンチネル。
const String aboutVersionUnknown = '__about_version_unknown__';

/// About 画面のビューモデル。
///
/// バージョン表示を担当する。
class AboutViewModel extends StateNotifier<AboutState> {
  AboutViewModel() : super(const AboutState());

  Future<void>? _loadVersionFuture;

  /// 起動時に一度だけバージョンを読み込む。既読なら既存の Future を返す。
  Future<void> ensureVersionLoaded() {
    return _loadVersionFuture ??= _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      state = state.copyWith(appVersion: packageInfo.version);
    } catch (_) {
      if (!mounted) return;
      state = state.copyWith(appVersion: aboutVersionUnknown);
    }
  }
}
