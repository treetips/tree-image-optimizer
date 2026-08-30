import 'dart:developer' as dev;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_shell.dart';
import '../../app/providers.dart';
import '../../logic/viewmodels/tool_install_view_model.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_button.dart';
import 'package:tree_image_optimizer/l10n/generated/app_localizations.dart';

/// ログのタグ。
const _tag = 'ToolBootstrap';

/// 初回起動時にツール展開を行い、完了後にメイン画面を表示するブート画面。
class ToolBootstrap extends ConsumerStatefulWidget {
  const ToolBootstrap({super.key});

  @override
  ConsumerState<ToolBootstrap> createState() => _ToolBootstrapState();
}

class _ToolBootstrapState extends ConsumerState<ToolBootstrap> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(toolInstallViewModelProvider);
    final l10n = AppLocalizations.of(context)!;

    dev.log('build: toolInstallStatus=${state.status}', name: _tag);

    if (state.status == ToolInstallStatus.ready) {
      return const HomeShell();
    }

    if (state.status == ToolInstallStatus.failure) {
      return _buildFailure(context, state);
    }

    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.auto_fix_high, size: 64, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(l10n.appTitle, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(l10n.preparingTools, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(l10n.preparingDetail, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            if (state.total == 0)
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(strokeWidth: 3),
              )
            else
              SizedBox(
                width: 320,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 24,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: ColoredBox(color: Color(0xFFE0E0E0)),
                        ),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (state.progressPercent / 100).clamp(
                            0.0,
                            1.0,
                          ),
                          child: const ColoredBox(color: AppColors.primary),
                        ),
                        Center(
                          child: Text(
                            '${state.progressPercent.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              shadows: [
                                Shadow(
                                  color: Colors.black45,
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailure(BuildContext context, ToolInstallState state) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(l10n.toolPrepareFailed, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                state.message ?? l10n.toolPrepareFailedDefault,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 240,
              child: GlassButton(
                label: l10n.retry,
                onPressed: () =>
                    ref.read(toolInstallViewModelProvider.notifier).retry(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
