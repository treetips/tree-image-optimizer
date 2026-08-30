import 'package:material_ui/material_ui.dart';

import '../../core/models/process_status.dart';
import 'package:tree_image_optimizer/l10n/generated/app_localizations.dart';

/// 処理状態ごとの色。
Color statusColor(ProcessStatus status) => switch (status) {
  ProcessStatus.waiting => const Color(0xFFBDBDBD),
  ProcessStatus.running => const Color(0xFFFFC107),
  ProcessStatus.success => const Color(0xFF4CAF50),
  ProcessStatus.failure => const Color(0xFFE53935),
};

/// 処理状態ごとのプレーンラベル（絵文字なし）。
String statusLabel(ProcessStatus status, AppLocalizations l10n) =>
    switch (status) {
      ProcessStatus.waiting => l10n.statusWaiting,
      ProcessStatus.running => l10n.statusRunning,
      ProcessStatus.success => l10n.statusSuccess,
      ProcessStatus.failure => l10n.statusFailure,
    };

/// 色付きドットとラベルで処理状態を表示するウィジェット。
class StatusIndicator extends StatelessWidget {
  const StatusIndicator({super.key, required this.status});

  /// 表示する処理状態。
  final ProcessStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: statusColor(status),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(statusLabel(status, l10n)),
      ],
    );
  }
}
