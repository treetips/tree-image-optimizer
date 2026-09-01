import 'package:flutter_color_picker_plus/flutter_color_picker_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/providers.dart';
import '../../core/models/sound_option.dart';
import '../../core/models/wallpaper_option.dart';
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
              child: Column(
                children: [
                  _languageRow(
                    context: context,
                    value: state.language,
                    info: l10n.infoLanguage,
                    onChanged: (v) => viewModel.setLanguage(v ?? ''),
                  ),
                  const SizedBox(height: 16),
                  _wallpaperRow(
                    context: context,
                    label: l10n.wallpaper,
                    info: l10n.infoWallpaper,
                    value: state.wallpaper,
                    options: state.wallpapers,
                    onChanged: (v) {
                      if (v != null) viewModel.setWallpaper(v);
                    },
                  ),
                  const SizedBox(height: 16),
                  _wallpaperOpacityRow(
                    context: context,
                    label: l10n.wallpaperOpacity,
                    value: state.wallpaperOpacity,
                    onChanged: (v) => viewModel.setWallpaperOpacity(v),
                  ),
                  const SizedBox(height: 16),
                  _wallpaperBackgroundColorRow(
                    context: context,
                    label: l10n.wallpaperBackgroundColor,
                    info: l10n.infoWallpaperBackgroundColor,
                    value: state.wallpaperBackgroundColor,
                    onChanged: (v) => viewModel.setWallpaperBackgroundColor(v),
                  ),
                ],
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

  Widget _wallpaperRow({
    required BuildContext context,
    required String label,
    required String info,
    required String value,
    required List<WallpaperOption> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label)),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: options.any((o) => o.source == value) ? value : null,
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
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        InfoTooltip(text: info),
      ],
    );
  }

  Widget _wallpaperOpacityRow({
    required BuildContext context,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label)),
        const SizedBox(width: 8),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            divisions: 10,
            label: value.toStringAsFixed(1),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 40, child: Text(value.toStringAsFixed(1))),
      ],
    );
  }

  Widget _wallpaperBackgroundColorRow({
    required BuildContext context,
    required String label,
    required String info,
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    final color = _parseColor(value) ?? const Color(0xFFFFFFFF);
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label)),
        const SizedBox(width: 8),
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: () async {
            final picked = await _showColorPicker(context, color);
            if (picked != null) {
              onChanged(_colorToHex(picked));
            }
          },
          child: const Text('選択'),
        ),
        const SizedBox(width: 8),
        InfoTooltip(text: info),
      ],
    );
  }

  Color? _parseColor(String hex) {
    var h = hex.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final v = int.tryParse(h, radix: 16);
    if (v == null) return null;
    return Color(v);
  }

  String _colorToHex(Color color) {
    final a = (color.a * 255).round();
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    if (a == 255) {
      return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();
    }
    return '#${a.toRadixString(16).padLeft(2, '0')}${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}'
        .toUpperCase();
  }

  Future<Color?> _showColorPicker(BuildContext context, Color initial) async {
    Color pickerColor = initial;
    return showDialog<Color>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('背景色を選択'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: pickerColor,
              onColorChanged: (c) => pickerColor = c,
              // 高機能な HSV / RGB ピッカーを使用
              paletteType: PaletteType.hsvWithHue,
              enableAlpha: false,
              displayThumbColor: true,
              hexInputBar: true,
              portraitOnly: false,
              pickerAreaHeightPercent: 0.7,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(pickerColor),
              child: const Text('決定'),
            ),
          ],
        );
      },
    );
  }
}
