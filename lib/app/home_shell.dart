import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:material_ui/material_ui.dart';

import '../core/constants/app_constants.dart';
import 'providers.dart';
import '../ui/screens/about_screen.dart';
import '../ui/screens/convert_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/theme/glass_constants.dart';
import 'package:tree_image_optimizer/l10n/generated/app_localizations.dart';

/// 左サイドナビ・右コンテンツのレイアウトを持つ画面シェル。
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _selectedIndex = 0;

  static const _screens = [ConvertScreen(), SettingsScreen(), AboutScreen()];

  static const _icons = [Icons.edit, Icons.settings, Icons.info];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsViewModelProvider);
    final wallpaper = settings.wallpaper.isNotEmpty
        ? settings.wallpaper
        : AppConstants.wallpaperAsset;
    final wallpaperOpacity = settings.wallpaperOpacity;
    final backgroundColor =
        _parseColor(settings.wallpaperBackgroundColor) ??
        const Color(0xFFFFFFFF);
    return Scaffold(
      body: LiquidGlassView(
        backgroundWidget: Container(
          color: backgroundColor,
          child: Opacity(
            opacity: wallpaperOpacity,
            child: _buildWallpaper(wallpaper),
          ),
        ),
        realTimeCapture: false,
        child: Stack(
          children: [
            // サイドバー（Liquid Glass）。
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 150,
              child: LiquidGlassLens(
                style: GlassConstants.sidebarLiquidStyle,
                child: Column(
                  children: [
                    for (var i = 0; i < _screens.length; i++)
                      _NavItem(
                        icon: _icons[i],
                        label: [
                          l10n.navConvert,
                          l10n.navSettings,
                          l10n.navAbout,
                        ][i],
                        selected: _selectedIndex == i,
                        onTap: () => setState(() => _selectedIndex = i),
                      ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
            // メインコンテンツ（壁紙の上に配置）。
            Positioned(
              left: 150,
              top: 0,
              right: 0,
              bottom: 0,
              child: _screens[_selectedIndex],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWallpaper(String source) {
    // アスペクト比を保ったままアプリケーション内に収まるように contain を使用
    if (source.startsWith('assets/')) {
      return Image.asset(
        source,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        errorBuilder: (context, error, stackTrace) =>
            const ColoredBox(color: Color(0xFF1A1A2E)),
      );
    }
    final file = File(source);
    // 存在しない場合はフォールバックで同梱壁紙を表示
    if (!file.existsSync()) {
      return Image.asset(
        AppConstants.wallpaperAsset,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        errorBuilder: (context, error, stackTrace) =>
            const ColoredBox(color: Color(0xFF1A1A2E)),
      );
    }
    return Image.file(
      file,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      errorBuilder: (context, error, stackTrace) =>
          const ColoredBox(color: Color(0xFF1A1A2E)),
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
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0x402B5CFF) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
