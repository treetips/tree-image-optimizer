import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/tool_installer.dart';

/// 初回展開の状態。
enum ToolInstallStatus { checking, installing, ready, failure }

/// 初回展開の状態。
class ToolInstallState {
  const ToolInstallState({
    this.status = ToolInstallStatus.checking,
    this.completed = 0,
    this.total = 0,
    this.message,
  });

  final ToolInstallStatus status;

  /// 展開済みファイル数。
  final int completed;

  /// 展開対象の総ファイル数。
  final int total;

  /// エラー時のメッセージ。
  final String? message;

  double get progressPercent => total == 0 ? 0 : completed / total * 100;

  ToolInstallState copyWith({
    ToolInstallStatus? status,
    int? completed,
    int? total,
    String? message,
  }) {
    return ToolInstallState(
      status: status ?? this.status,
      completed: completed ?? this.completed,
      total: total ?? this.total,
      message: message ?? this.message,
    );
  }
}

/// 初回展開を管理するビューモデル。
class ToolInstallViewModel extends StateNotifier<ToolInstallState> {
  ToolInstallViewModel({ToolInstaller? installer})
    : _installer = installer ?? ToolInstaller(),
      super(const ToolInstallState()) {
    _install();
  }

  final ToolInstaller _installer;

  bool _running = false;

  Future<void> _install() async {
    if (_running) return;
    _running = true;
    try {
      dev.log('checking isInstalled...', name: 'ToolInstallVM');
      state = state.copyWith(status: ToolInstallStatus.checking);

      // 5バイナリそれぞれと upscal/models の欠損を個別に確認し、
      // 欠損時はフォルダごと削除して再取得する（詳細は ToolInstaller のログ参照）。
      await _installer.repairMissingTools(
        onProgress: (completed, total) {
          if (!mounted) return;
          state = state.copyWith(
            status: ToolInstallStatus.installing,
            completed: completed,
            total: total,
          );
        },
      );

      final installed = await _installer.isInstalled();
      dev.log('after repair isInstalled=$installed', name: 'ToolInstallVM');
      if (installed) {
        if (!mounted) return;
        dev.log('repair done, ready', name: 'ToolInstallVM');
        state = state.copyWith(status: ToolInstallStatus.ready);
        return;
      }

      dev.log(
        'still not installed, starting full install...',
        name: 'ToolInstallVM',
      );
      await _installer.install(
        onProgress: (completed, total) {
          if (!mounted) return;
          state = state.copyWith(
            status: ToolInstallStatus.installing,
            completed: completed,
            total: total,
          );
        },
      );
      if (!mounted) return;
      dev.log('install done, ready', name: 'ToolInstallVM');
      state = state.copyWith(status: ToolInstallStatus.ready);
    } catch (error, st) {
      dev.log(
        'install failed: $error',
        name: 'ToolInstallVM',
        error: error,
        stackTrace: st,
      );
      if (!mounted) return;
      state = state.copyWith(
        status: ToolInstallStatus.failure,
        message: error.toString(),
      );
    } finally {
      _running = false;
    }
  }

  /// 失敗時の再試行。
  void retry() {
    if (_running) return;
    state = const ToolInstallState();
    _install();
  }
}
