import 'package:material_ui/material_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' as loc;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tree_image_optimizer/l10n/generated/app_localizations.dart';

import 'providers.dart';
import '../core/constants/app_constants.dart';
import '../logic/update/update_actions.dart';
import '../ui/screens/tool_bootstrap.dart';
import '../ui/theme/app_colors.dart';

/// 選択された言語（BCP 47）からアプリに適用するロケールを解決する。
/// 空文字は「環境設定に従う」を意味し、デバイスの言語が日本語なら日本語、
/// それ以外（対応言語外を含む）は英語を選択する。
Locale _resolveLocale(String language) {
  if (language == 'ja-JP') return const Locale('ja');
  if (language == 'en-US') return const Locale('en');
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final device = dispatcher.locale;
  if (device.languageCode == 'ja') return const Locale('ja');
  return const Locale('en');
}

/// アプリケーションのルートウィジェット。
class TreeImageOptimizerApp extends ConsumerStatefulWidget {
  const TreeImageOptimizerApp({super.key});

  @override
  ConsumerState<TreeImageOptimizerApp> createState() =>
      _TreeImageOptimizerAppState();
}

class _TreeImageOptimizerAppState extends ConsumerState<TreeImageOptimizerApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(settingsViewModelProvider).language;
    final locale = _resolveLocale(language);
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Tree Image Optimizer',
      locale: locale,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,
        scrollbarTheme: const ScrollbarThemeData(
          thumbVisibility: WidgetStatePropertyAll(true),
        ),
      ),
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
        loc.GlobalMaterialLocalizations.delegate,
        loc.GlobalWidgetsLocalizations.delegate,
        loc.GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja'), Locale('en')],
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context)!;
          return PlatformMenuBar(
            menus: [
              PlatformMenu(
                label: 'Tree Image Optimizer',
                menus: [
                  PlatformMenuItemGroup(
                    members: [
                      if (PlatformProvidedMenuItem.hasMenu(
                        PlatformProvidedMenuItemType.about,
                      ))
                        const PlatformProvidedMenuItem(type: .about),
                      PlatformMenuItem(
                        label: l10n.updateMenu,
                        onSelected: () {
                          final updaterService = ref.read(
                            updaterServiceProvider,
                          );
                          final navigatorContext = _navigatorKey.currentContext;
                          if (navigatorContext == null) return;
                          runManualUpdateCheck(
                            context: navigatorContext,
                            updaterService: updaterService,
                            updateInfoUrl: AppConstants.updateInfoUrl,
                          );
                        },
                      ),
                    ],
                  ),
                  if (PlatformProvidedMenuItem.hasMenu(
                    PlatformProvidedMenuItemType.servicesSubmenu,
                  ))
                    PlatformMenuItemGroup(
                      members: [
                        const PlatformProvidedMenuItem(type: .servicesSubmenu),
                      ],
                    ),
                  if (PlatformProvidedMenuItem.hasMenu(
                        PlatformProvidedMenuItemType.hide,
                      ) ||
                      PlatformProvidedMenuItem.hasMenu(
                        PlatformProvidedMenuItemType.hideOtherApplications,
                      ) ||
                      PlatformProvidedMenuItem.hasMenu(
                        PlatformProvidedMenuItemType.showAllApplications,
                      ))
                    PlatformMenuItemGroup(
                      members: [
                        if (PlatformProvidedMenuItem.hasMenu(
                          PlatformProvidedMenuItemType.hide,
                        ))
                          const PlatformProvidedMenuItem(type: .hide),
                        if (PlatformProvidedMenuItem.hasMenu(
                          PlatformProvidedMenuItemType.hideOtherApplications,
                        ))
                          const PlatformProvidedMenuItem(
                            type: .hideOtherApplications,
                          ),
                        if (PlatformProvidedMenuItem.hasMenu(
                          PlatformProvidedMenuItemType.showAllApplications,
                        ))
                          const PlatformProvidedMenuItem(
                            type: .showAllApplications,
                          ),
                      ],
                    ),
                  if (PlatformProvidedMenuItem.hasMenu(
                    PlatformProvidedMenuItemType.quit,
                  ))
                    PlatformMenuItemGroup(
                      members: [const PlatformProvidedMenuItem(type: .quit)],
                    ),
                ],
              ),
              if (PlatformProvidedMenuItem.hasMenu(
                    PlatformProvidedMenuItemType.minimizeWindow,
                  ) ||
                  PlatformProvidedMenuItem.hasMenu(
                    PlatformProvidedMenuItemType.zoomWindow,
                  ) ||
                  PlatformProvidedMenuItem.hasMenu(
                    PlatformProvidedMenuItemType.arrangeWindowsInFront,
                  ) ||
                  PlatformProvidedMenuItem.hasMenu(
                    PlatformProvidedMenuItemType.toggleFullScreen,
                  ))
                PlatformMenu(
                  label: 'Windows',
                  menus: [
                    PlatformMenuItemGroup(
                      members: [
                        if (PlatformProvidedMenuItem.hasMenu(
                          PlatformProvidedMenuItemType.minimizeWindow,
                        ))
                          const PlatformProvidedMenuItem(type: .minimizeWindow),
                        if (PlatformProvidedMenuItem.hasMenu(
                          PlatformProvidedMenuItemType.zoomWindow,
                        ))
                          const PlatformProvidedMenuItem(type: .zoomWindow),
                        if (PlatformProvidedMenuItem.hasMenu(
                          PlatformProvidedMenuItemType.arrangeWindowsInFront,
                        ))
                          const PlatformProvidedMenuItem(
                            type: .arrangeWindowsInFront,
                          ),
                        if (PlatformProvidedMenuItem.hasMenu(
                          PlatformProvidedMenuItemType.toggleFullScreen,
                        ))
                          const PlatformProvidedMenuItem(
                            type: .toggleFullScreen,
                          ),
                      ],
                    ),
                  ],
                ),
            ],
            child: const ToolBootstrap(),
          );
        },
      ),
    );
  }
}
