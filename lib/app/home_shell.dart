import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:material_ui/material_ui.dart';

import '../core/constants/app_constants.dart';
import '../ui/screens/about_screen.dart';
import '../ui/screens/convert_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/theme/glass_constants.dart';
import 'package:tree_image_optimizer/l10n/generated/app_localizations.dart';

/// 左サイドナビ・右コンテンツのレイアウトを持つ画面シェル。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  static const _screens = [ConvertScreen(), SettingsScreen(), AboutScreen()];

  static const _icons = [Icons.edit, Icons.settings, Icons.info];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: LiquidGlassView(
        backgroundWidget: Opacity(
          opacity: AppConstants.wallpaperOpacity,
          child: Image.asset(
            AppConstants.wallpaperAsset,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                const ColoredBox(color: Color(0xFF1A1A2E)),
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
