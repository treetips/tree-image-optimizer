import 'dart:convert';
import 'dart:io';

import '../../core/models/convert_settings.dart';
import '../../core/models/optimize_type.dart';
import '../../core/models/output_format.dart';
import '../../core/models/settings_screen_settings.dart';
import '../../core/models/target_filter.dart';
import '../services/log_service.dart';

/// 設定ファイルを読み書きするリポジトリ。
/// 保存先: `$HOME/.config/tree-image-optimizer/settings.json`
///
/// トップレベルは画面ごとのキーで、画面ごとの設定値を格納する。
class SettingsRepository {
  SettingsRepository({LogService? logService, this.configDirectory})
    : _log = logService;

  final LogService? _log;

  /// テスト用にホームディレクトリ相当を注入できる。
  final Directory? configDirectory;

  /// 変換画面の設定キー。
  static const String convertKey = 'convert';

  /// 設定画面の設定キー。
  static const String settingsKey = 'settings';

  /// 書き込みの直列化用。複数回の保存が競合しないようにする。
  Future<void> _pendingWrite = Future.value();

  /// 設定ファイルのパス。
  Future<File> settingsFile() async {
    final home = configDirectory?.path ?? (Platform.environment['HOME'] ?? '');
    final dir = Directory('$home/.config/tree-image-optimizer');
    await dir.create(recursive: true);
    return File('${dir.path}/settings.json');
  }

  /// ファイル全体のJSONを読み込む。無い・壊れている場合は null。
  Future<Map<String, dynamic>?> _readAll() async {
    final file = await settingsFile();
    if (!await file.exists()) return null;
    try {
      final text = await file.readAsString();
      final json = jsonDecode(text);
      if (json is Map<String, dynamic>) return json;
      return null;
    } on Object catch (error) {
      _log?.logger.warning('設定ファイルの読み込み失敗: $error');
      return null;
    }
  }

  /// ファイル全体を書き込む。
  Future<void> _writeAll(Map<String, dynamic> json) {
    final pending = _pendingWrite.then((_) async {
      final file = await settingsFile();
      await file.writeAsString(jsonEncode(json));
    });
    _pendingWrite = pending;
    return pending;
  }

  /// 現在の全JSONを取得し、[update] で変更して書き込む。
  Future<void> _updateAll(
    void Function(Map<String, dynamic> json) update,
  ) async {
    final json = await _readAll() ?? <String, dynamic>{};
    update(json);
    await _writeAll(json);
  }

  /// 変換画面の設定を読み込む。
  /// ファイルが無い場合は [defaults] を保存して返す。
  /// 設定項目に値が無い場合や存在しない値の場合は [defaults] の値で補正し、ファイルを更新して返す。
  Future<ConvertSettings> loadConvert(
    ConvertSettings defaults, {
    required int maxParallel,
  }) async {
    final json = await _readAll();
    if (json == null) {
      _log?.logger.info('設定ファイルが無いため初期値を保存: $convertKey');
      await saveConvert(defaults);
      return defaults;
    }

    final convertJson = json[convertKey];
    if (convertJson is! Map<String, dynamic>) {
      await _updateAll((m) => m[convertKey] = defaults.toJson());
      return defaults;
    }

    final resolved = _resolveConvert(convertJson, defaults, maxParallel);
    if (resolved.needsRewrite) {
      await _updateAll((m) => m[convertKey] = resolved.settings.toJson());
    }
    return resolved.settings;
  }

  /// 変換画面の設定を保存する。
  Future<void> saveConvert(ConvertSettings settings) {
    return _updateAll((json) => json[convertKey] = settings.toJson());
  }

  /// 設定画面の設定を読み込む。
  /// ファイルが無い・項目が無い場合は [defaults] を保存して返す。
  Future<SettingsScreenSettings> loadSettings(
    SettingsScreenSettings defaults,
  ) async {
    final json = await _readAll();
    if (json == null) {
      await saveSettings(defaults);
      return defaults;
    }

    final sJson = json[settingsKey];
    if (sJson is! Map<String, dynamic>) {
      await _updateAll((m) => m[settingsKey] = defaults.toJson());
      return defaults;
    }

    final resolved = _resolveSettings(sJson, defaults);
    if (resolved.needsRewrite) {
      await _updateAll((m) => m[settingsKey] = resolved.settings.toJson());
    }
    return resolved.settings;
  }

  /// 設定画面の設定を保存する。
  Future<void> saveSettings(SettingsScreenSettings settings) {
    return _updateAll((json) => json[settingsKey] = settings.toJson());
  }

  _ResolvedConvert _resolveConvert(
    Map<String, dynamic> json,
    ConvertSettings defaults,
    int maxParallel,
  ) {
    var needsRewrite = false;

    final targetFilter = _enumByName(TargetFilter.values, json['targetFilter']);
    if (targetFilter == null) needsRewrite = true;

    final scale = _intValue(json['scale'], 1, 4, defaults.scale, (v) {
      needsRewrite = true;
    });
    final model = _stringValue(json['model'], defaults.model, (v) {
      needsRewrite = true;
    });
    final format = _enumByName(OutputFormat.values, json['format']);
    if (format == null) needsRewrite = true;
    final optimizeType = _enumByName(OptimizeType.values, json['optimizeType']);
    if (optimizeType == null) needsRewrite = true;
    final quality = _intValue(json['quality'], 1, 100, defaults.quality, (v) {
      needsRewrite = true;
    });
    final parallelCount = _intValue(
      json['parallelCount'],
      1,
      maxParallel,
      defaults.parallelCount,
      (v) {
        needsRewrite = true;
      },
    );

    final inputFolderPath = _optionalPath(json['inputFolderPath']);
    final outputFolderPath = _optionalPath(json['outputFolderPath']);

    final settings = ConvertSettings(
      inputFolderPath: inputFolderPath,
      outputFolderPath: outputFolderPath,
      targetFilter: targetFilter ?? defaults.targetFilter,
      scale: scale,
      model: model,
      format: format ?? defaults.format,
      optimizeType: optimizeType ?? defaults.optimizeType,
      quality: quality,
      parallelCount: parallelCount,
    );

    return _ResolvedConvert(settings, needsRewrite);
  }

  _ResolvedSettings _resolveSettings(
    Map<String, dynamic> json,
    SettingsScreenSettings defaults,
  ) {
    var needsRewrite = false;

    final showOsNotification = _boolValue(
      json['showOsNotification'],
      defaults.showOsNotification,
      () => needsRewrite = true,
    );
    final playSound = _boolValue(
      json['playSound'],
      defaults.playSound,
      () => needsRewrite = true,
    );
    final successSound = _stringValue(
      json['successSound'],
      defaults.successSound,
      (v) => needsRewrite = true,
    );
    final errorSound = _stringValue(
      json['errorSound'],
      defaults.errorSound,
      (v) => needsRewrite = true,
    );
    final language = _languageValue(
      json['language'],
      defaults.language,
      () => needsRewrite = true,
    );
    final wallpaper = _stringValue(
      json['wallpaper'],
      defaults.wallpaper,
      (v) => needsRewrite = true,
    );
    final wallpaperOpacity = _doubleValue(
      json['wallpaperOpacity'],
      0.0,
      1.0,
      defaults.wallpaperOpacity,
      () => needsRewrite = true,
    );
    final wallpaperBackgroundColor = _colorValue(
      json['wallpaperBackgroundColor'],
      defaults.wallpaperBackgroundColor,
      () => needsRewrite = true,
    );

    final settings = SettingsScreenSettings(
      showOsNotification: showOsNotification,
      playSound: playSound,
      successSound: successSound,
      errorSound: errorSound,
      language: language,
      wallpaper: wallpaper,
      wallpaperOpacity: wallpaperOpacity,
      wallpaperBackgroundColor: wallpaperBackgroundColor,
    );

    return _ResolvedSettings(settings, needsRewrite);
  }

  /// 言語（BCP 47）を読み取る。空文字（自動）も有効な値として扱う。
  String _languageValue(
    Object? value,
    String fallback,
    void Function() onCorrected,
  ) {
    if (value is String) return value;
    onCorrected();
    return fallback;
  }

  /// オプションのフォルダパス。空文字や非文字列の場合は null。
  String? _optionalPath(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  T? _enumByName<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  bool _boolValue(Object? value, bool fallback, void Function() onCorrected) {
    if (value is bool) return value;
    onCorrected();
    return fallback;
  }

  /// 整数値を範囲内にクランプする。
  /// 値が無い・型が違う場合はフォールバックを使用し、[onCorrected] を呼ぶ。
  int _intValue(
    Object? value,
    int min,
    int max,
    int fallback,
    void Function(int v) onCorrected,
  ) {
    if (value is int) {
      final clamped = value.clamp(min, max);
      if (clamped != value) onCorrected(clamped);
      return clamped;
    }
    onCorrected(fallback);
    return fallback;
  }

  String _stringValue(
    Object? value,
    String fallback,
    void Function(String v) onCorrected,
  ) {
    if (value is String && value.isNotEmpty) return value;
    onCorrected(fallback);
    return fallback;
  }

  double _doubleValue(
    Object? value,
    double min,
    double max,
    double fallback,
    void Function() onCorrected,
  ) {
    double? parsed;
    if (value is double) {
      parsed = value;
    } else if (value is int) {
      parsed = value.toDouble();
    } else if (value is String) {
      parsed = double.tryParse(value);
    }
    if (parsed == null) {
      onCorrected();
      return fallback;
    }
    final clamped = parsed.clamp(min, max).toDouble();
    if (clamped != parsed) onCorrected();
    return clamped;
  }

  String _colorValue(
    Object? value,
    String fallback,
    void Function() onCorrected,
  ) {
    if (value is String && _isValidColor(value)) return value;
    onCorrected();
    return fallback;
  }

  bool _isValidColor(String hex) {
    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length != 6 && h.length != 8) return false;
    return int.tryParse(h, radix: 16) != null;
  }
}

class _ResolvedConvert {
  const _ResolvedConvert(this.settings, this.needsRewrite);

  final ConvertSettings settings;
  final bool needsRewrite;
}

class _ResolvedSettings {
  const _ResolvedSettings(this.settings, this.needsRewrite);

  final SettingsScreenSettings settings;
  final bool needsRewrite;
}
