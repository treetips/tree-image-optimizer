import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/providers.dart';
import '../../core/models/sound_option.dart';
import '../widgets/section.dart';
import 'package:tree_image_optimizer/l10n/generated/app_localizations.dart';

/// 設定画面。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsViewModelProvider);
    final viewModel = ref.read(settingsViewModelProvider.notifier);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenTitle(title: l10n.screenSettings),
            const SizedBox(height: 24),
            SectionCard(
              title: l10n.sectionEndAction,
              child: Column(
                children: [
                  InkWell(
                    onTap: () => viewModel.setShowOsNotification(
                      !state.showOsNotification,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      children: [
                        Checkbox(
                          value: state.showOsNotification,
                          onChanged: (v) {
                            if (v != null) viewModel.setShowOsNotification(v);
                          },
                        ),
                        Text(l10n.showOsNotification),
                        const Spacer(),
                        InfoTooltip(text: l10n.infoShowOsNotification),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => viewModel.setPlaySound(!state.playSound),
                    borderRadius: BorderRadius.circular(4),
                    child: Row(
                      children: [
                        Checkbox(
                          value: state.playSound,
                          onChanged: (v) {
                            if (v != null) viewModel.setPlaySound(v);
                          },
                        ),
                        Text(l10n.playSound),
                        const Spacer(),
                        InfoTooltip(text: l10n.infoPlaySound),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _soundRow(
                    context: context,
                    label: l10n.successSound,
                    info: l10n.infoSuccessSound,
                    value: state.successSound,
                    options: state.successSounds,
                    enabled: state.playSound,
                    onChanged: (v) {
                      if (v != null) viewModel.setSuccessSound(v);
                    },
                    onPlay: () => viewModel.playSuccessSound(),
                  ),
                  const SizedBox(height: 16),
                  _soundRow(
                    context: context,
                    label: l10n.errorSound,
                    info: l10n.infoErrorSound,
                    value: state.errorSound,
                    options: state.errorSounds,
                    enabled: state.playSound,
                    onChanged: (v) {
                      if (v != null) viewModel.setErrorSound(v);
                    },
                    onPlay: () => viewModel.playErrorSound(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SectionCard(
              title: l10n.sectionBasic,
              child: _languageRow(
                context: context,
                value: state.language,
                info: l10n.infoLanguage,
                onChanged: (v) => viewModel.setLanguage(v ?? ''),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _languageRow({
    required BuildContext context,
    required String value,
    required String info,
    required ValueChanged<String?> onChanged,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final options = [
      (code: '', label: l10n.languageAuto),
      (code: 'ja-JP', label: '${l10n.languageJapanese} (ja-JP)'),
      (code: 'en-US', label: '${l10n.languageEnglish} (en-US)'),
    ];
    return Row(
      children: [
        SizedBox(width: 110, child: Text(l10n.language)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(value),
            initialValue: value,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final option in options)
                DropdownMenuItem(value: option.code, child: Text(option.label)),
            ],
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        InfoTooltip(text: info),
      ],
    );
  }

  Widget _soundRow({
    required BuildContext context,
    required String label,
    required String info,
    required String value,
    required List<SoundOption> options,
    required bool enabled,
    required ValueChanged<String?> onChanged,
    required VoidCallback onPlay,
  }) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: value,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final option in options)
                DropdownMenuItem(
                  value: option.source,
                  child: Text(option.label),
                ),
            ],
            onChanged: enabled ? onChanged : null,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.play_arrow),
          tooltip: '▶',
          onPressed: enabled && value.isNotEmpty ? onPlay : null,
        ),
        const SizedBox(width: 8),
        InfoTooltip(text: info),
      ],
    );
  }
}
