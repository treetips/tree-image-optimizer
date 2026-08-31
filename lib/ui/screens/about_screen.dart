import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/providers.dart';
import '../../core/constants/app_constants.dart';
import '../../logic/viewmodels/about_view_model.dart';
import '../../logic/update/updater_service.dart';
import '../theme/app_colors.dart';
import '../widgets/glass_button.dart';
import '../widgets/section.dart';
import 'package:tree_image_optimizer/l10n/generated/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

const _tag = 'AboutScreen';

/// About 画面。
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  bool _isChecking = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(aboutViewModelProvider);
    final viewModel = ref.read(aboutViewModelProvider.notifier);
    final l10n = AppLocalizations.of(context)!;

    viewModel.ensureVersionLoaded();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenTitle(title: l10n.screenAbout),
            SectionCard(
              title: l10n.sectionApp,
              child: Column(
                children: [
                  _ApplicationTable(
                    appVersion: switch (state.appVersion) {
                      aboutVersionLoading => l10n.loading,
                      aboutVersionUnknown => l10n.unknown,
                      _ => state.appVersion,
                    },
                  ),
                  const SizedBox(height: 16),
                  GlassButton(
                    label: _isChecking ? l10n.checking : l10n.checkForUpdate,
                    icon: Icons.refresh,
                    isLoading: _isChecking,
                    onPressed: _isChecking ? null : _checkForUpdate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SectionCard(title: l10n.sectionVersion, child: _VersionTable()),
          ],
        ),
      ),
    );
  }

  Future<void> _checkForUpdate() async {
    dev.log('Button clicked', name: _tag);
    final l10n = AppLocalizations.of(context)!;

    setState(() => _isChecking = true);

    try {
      final updaterService = ref.read(updaterServiceProvider);
      final result = await updaterService.checkForUpdate(
        AppConstants.updateInfoUrl,
      );

      if (!mounted) return;

      switch (result) {
        case UpdateAlreadyLatest():
          await _showDialog(title: l10n.latest, message: l10n.latestMsg);
        case UpdateAvailable(:final info):
          await _downloadAndInstall(info);
        case UpdateError(:final message):
          await _showDialog(title: l10n.updateCheckFailed, message: message);
        case UpdateReady():
          break;
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _downloadAndInstall(dynamic info) async {
    dev.log('Update available: v${info.version}', name: _tag);
    final l10n = AppLocalizations.of(context)!;

    // インストール確認。
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmInstall),
        content: Text(l10n.confirmInstallMsg(info.version)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.install),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    dev.log('Downloading and installing...', name: _tag);

    // ダウンロード + 展開。
    final updaterService = ref.read(updaterServiceProvider);
    final result = await updaterService.downloadAndPrepare(info);

    if (!mounted) return;

    switch (result) {
      case UpdateReady(:final info, :final appPath, :final helperPath):
        dev.log('Download ready, applying...', name: _tag);
        await updaterService.applyUpdate(
          UpdateReady(info: info, appPath: appPath, helperPath: helperPath),
        );
      case UpdateError(:final message):
        dev.log('Download failed: $message', name: _tag);
        await _showDialog(title: l10n.downloadFailed, message: message);
      default:
        break;
    }
  }

  Future<void> _showDialog({
    required String title,
    required String message,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }
}

/// アプリケーション情報のテーブル。
class _ApplicationTable extends StatelessWidget {
  const _ApplicationTable({required this.appVersion});

  final String appVersion;

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Center(
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _value(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Center(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Table(
      border: TableBorder.all(color: Colors.black),
      columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(2)},
      children: [
        TableRow(
          children: [
            _label(l10n.appNameLabel),
            _value(
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/images/icon-tree-01.png', height: 50),
                  const SizedBox(width: 8),
                  Text(l10n.appTitle, style: theme.textTheme.titleMedium),
                ],
              ),
            ),
          ],
        ),
        TableRow(
          children: [
            _label(l10n.versionLabel),
            _value(Text(appVersion, style: theme.textTheme.titleMedium)),
          ],
        ),
        TableRow(
          children: [
            _label(l10n.githubLabel),
            _value(
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () async {
                    await launchUrl(Uri.parse(AppConstants.githubUrl));
                  },
                  child: Text(
                    AppConstants.githubUrl,
                    style: const TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        TableRow(
          children: [_label(l10n.copyrightLabel), _value(Text(l10n.copyright))],
        ),
      ],
    );
  }
}

/// バージョン情報のテーブル。
class _VersionTable extends StatelessWidget {
  const _VersionTable();

  Widget _header(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _cell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(child: Text(text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Table(
      border: TableBorder.all(color: Colors.black),
      columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(2)},
      children: [
        TableRow(
          decoration: const BoxDecoration(color: AppColors.primary),
          children: [_header(l10n.binary), _header(l10n.version)],
        ),
        TableRow(
          children: [_cell('upscal-bin'), _cell(AppConstants.upscalBinVersion)],
        ),
        TableRow(children: [_cell('upscal models'), _cell('')]),
        TableRow(
          children: [
            _cell('JPEG (jpegoptim)'),
            _cell(AppConstants.jpegVersion),
          ],
        ),
        TableRow(
          children: [_cell('PNG (pngoptim)'), _cell(AppConstants.pngVersion)],
        ),
        TableRow(
          children: [
            _cell('JPEG XL (libjxl)'),
            _cell(AppConstants.jpegXlVersion),
          ],
        ),
        TableRow(
          children: [_cell('AV1 (libavif)'), _cell(AppConstants.av1Version)],
        ),
        TableRow(
          children: [_cell('WebP (libwebp)'), _cell(AppConstants.webpVersion)],
        ),
      ],
    );
  }
}
