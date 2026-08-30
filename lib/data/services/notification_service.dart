import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_desktop_notifications/flutter_desktop_notifications.dart';

import 'log_service.dart';

/// OSの通知を表示するサービス。
/// [flutter_desktop_notifications](https://pub.dev/packages/flutter_desktop_notifications) を利用する。
class NotificationService {
  NotificationService({LogService? logService}) : _log = logService;

  final LogService? _log;
  final DesktopNotifier _notifier = DesktopNotifier();

  /// 通知アイコンとして使うアセットパス。
  static const String _iconAsset = 'assets/images/icon-tree-01.png';

  /// 一時保存した通知アイコンのファイルパス。
  String? _iconFilePath;

  /// 通知の初期化と権限要求。アプリ起動時に一度呼び出すこと。
  Future<void> init() async {
    try {
      await _notifier.requestPermission();
      await _prepareIcon();
      _log?.logger.info('通知初期化完了');
    } catch (error) {
      _log?.logger.warning('通知の初期化失敗: $error');
    }
  }

  /// 通知アイコンをアセットから一時ファイルへ展開する。
  /// flutter_desktop_notifications は macOS で画像をファイルパスから
  /// UNNotificationAttachment として添付するため、アセットを実ファイル化する。
  Future<void> _prepareIcon() async {
    try {
      final data = await rootBundle.load(_iconAsset);
      final dir = await Directory.systemTemp.createTemp('tree_image_icon');
      final file = File('${dir.path}/icon-tree-01.png');
      await file.writeAsBytes(data.buffer.asUint8List());
      _iconFilePath = file.path;
    } catch (error) {
      _log?.logger.warning('通知アイコンの準備失敗: $error');
    }
  }

  /// OSの通知を表示する。
  Future<void> show({required String title, required String body}) async {
    try {
      await _notifier.show(
        NotificationMessage.fromPluginTemplate(
          'completion',
          title,
          body,
          image: _iconFilePath,
        ),
      );
      _log?.logger.info('通知表示: $title $body');
    } catch (error) {
      _log?.logger.warning('通知表示失敗: $error');
    }
  }
}
