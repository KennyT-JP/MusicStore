/// レスポンシブなアプリ外枠（仕様書 14.1）
///
/// 画面幅に応じてナビゲーションを切り替える。
///
/// | 画面幅 | ナビゲーション |
/// | --- | --- |
/// | 広い（PC・タブレット横） | 左側に常時表示のサイドバー |
/// | 狭い（スマートフォン） | 下部にボトムナビゲーション |
library;

import 'package:flutter/material.dart';

import '../../env/app_environment.dart';
import '../../domain/help_links.dart';
import '../../l10n/app_localizations.dart';
import '../routes.dart';
import '../widgets/brand_logo.dart';
import '../widgets/help_button.dart';

/// サイドバーとボトムナビを切り替える境界の幅。
///
/// Material の推奨に合わせ、これ以上をタブレット・デスクトップとして扱う。
const double kWideLayoutBreakpoint = 840;

/// ナビゲーションの 1 項目。
class AppNavDestination {
  const AppNavDestination({
    required this.route,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });

  final String route;
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// 未読件数など。0 なら出さない。
  final int badgeCount;
}

/// ナビゲーションを備えたアプリの外枠。
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.child,
    required this.currentRoute,
    required this.onNavigate,
    this.isSiteAdmin = false,
    this.unreadNotificationCount = 0,
    this.showDownloads = false,
    this.onTapAccount,
  });

  final Widget child;
  final String currentRoute;
  final void Function(String route) onNavigate;

  /// サイト管理者にのみ「サイト管理」を出す（14.1）。
  final bool isSiteAdmin;

  /// ベルアイコンとナビの通知に出す未読件数（14.1）。
  final int unreadNotificationCount;

  /// 「ダウンロード済み」を出すか（docs/DOWNLOAD-DESIGN.md 6.1 / 6.5）。
  ///
  /// **Web では出さない。** 保存先が無く、開いても常に空になる。
  /// 既定を false にしてあるのは、**入口を足すかどうかを呼ぶ側に決めさせる**
  /// ため（判定は `lib/platform/downloads_supported.dart` の 1 か所）。
  final bool showDownloads;

  final VoidCallback? onTapAccount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final destinations = _destinations(l10n);
    final selectedIndex = _selectedIndex(destinations);
    final isWide = MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;

    return Scaffold(
      appBar: AppBar(
        // **横一列のロックアップ（brand/README.md）。**
        // 「サイトトップ用」として用意されたもので、上部バーに収まる
        // 高さ（下限 28px）で組んである。以前はアイコンとアプリ名を
        // 並べていたが、そちらは横組み 2 段が入らないための代用だった。
        // 読み上げには、いま出ている言語のアプリ名を伝える。
        title: BrandLogo.inline(semanticLabel: l10n.appTitle),
        actions: [
          // **いま出ている画面の説明へ飛ぶ**（14.2）。目次の先頭に
          // 落とすだけでは、困っている人が自分で探すことになる。
          HelpButton(topic: helpTopicForRoute(currentRoute)),
          _NotificationBell(
            count: unreadNotificationCount,
            // ナビの「通知」とベルアイコンは同じ画面へ遷移する（14.1）。
            onPressed: () => onNavigate(AppRoutes.notifications),
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: onTapAccount ?? () => onNavigate(AppRoutes.settings),
          ),
          const SizedBox(width: 8),
        ],
        bottom: AppEnvironment.current.showEnvironmentBanner
            ? _EnvironmentBanner(label: l10n.environmentBannerStaging)
            : null,
      ),
      body: isWide
          ? Row(
              children: [
                _SideNavigation(
                  destinations: destinations,
                  selectedIndex: selectedIndex,
                  onSelected: (i) => onNavigate(destinations[i].route),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child),
              ],
            )
          : child,
      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
              selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
              onDestinationSelected: (i) => onNavigate(destinations[i].route),
              destinations: [
                for (final d in destinations)
                  NavigationDestination(
                    icon: _maybeBadge(Icon(d.icon), d.badgeCount),
                    selectedIcon: _maybeBadge(
                      Icon(d.selectedIcon),
                      d.badgeCount,
                    ),
                    label: d.label,
                  ),
              ],
            ),
    );
  }

  List<AppNavDestination> _destinations(AppL10n l10n) => [
    AppNavDestination(
      route: AppRoutes.home,
      icon: Icons.queue_music_outlined,
      selectedIcon: Icons.queue_music,
      label: l10n.navHome,
    ),
    AppNavDestination(
      route: AppRoutes.notifications,
      icon: Icons.notifications_outlined,
      selectedIcon: Icons.notifications,
      label: l10n.navNotifications,
      badgeCount: unreadNotificationCount,
    ),
    // 端末に保存した音源（docs/DOWNLOAD-DESIGN.md 6.1）。
    //
    // **ナビに入口を置く。** 設定の奥に入れると、圏外のときに
    // たどり着けない——設定は Firestore から自分の情報を読むので、
    // オフラインでは読み込み中のまま止まる。
    if (showDownloads)
      AppNavDestination(
        route: AppRoutes.downloads,
        icon: Icons.cloud_download_outlined,
        selectedIcon: Icons.cloud_download,
        label: l10n.navDownloads,
      ),
    AppNavDestination(
      route: AppRoutes.settings,
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: l10n.navSettings,
    ),
    // サイト管理はサイト管理者にのみ表示する（14.1 / 14.5）。
    if (isSiteAdmin)
      AppNavDestination(
        route: AppRoutes.siteAdmin,
        icon: Icons.admin_panel_settings_outlined,
        selectedIcon: Icons.admin_panel_settings,
        label: l10n.navSiteAdmin,
      ),
  ];

  int _selectedIndex(List<AppNavDestination> destinations) {
    // 最長一致で選ぶ。`/admin/users` のような下位のパスでも
    // 「サイト管理」が選択状態になるようにする。
    var best = -1;
    var bestLength = -1;
    for (var i = 0; i < destinations.length; i++) {
      final route = destinations[i].route;
      final matches = route == AppRoutes.home
          ? currentRoute == AppRoutes.home
          : currentRoute == route || currentRoute.startsWith('$route/');
      if (matches && route.length > bestLength) {
        best = i;
        bestLength = route.length;
      }
    }
    return best;
  }

  static Widget _maybeBadge(Widget icon, int count) {
    if (count <= 0) return icon;
    return Badge(label: Text(count > 99 ? '99+' : '$count'), child: icon);
  }
}

class _SideNavigation extends StatelessWidget {
  const _SideNavigation({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<AppNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      extended: MediaQuery.sizeOf(context).width >= 1200,
      selectedIndex: selectedIndex < 0 ? null : selectedIndex,
      onDestinationSelected: onSelected,
      labelType: MediaQuery.sizeOf(context).width >= 1200
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      destinations: [
        for (final d in destinations)
          NavigationRailDestination(
            icon: AppShell._maybeBadge(Icon(d.icon), d.badgeCount),
            selectedIcon: AppShell._maybeBadge(
              Icon(d.selectedIcon),
              d.badgeCount,
            ),
            label: Text(d.label),
          ),
      ],
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: count > 0
          ? Badge(
              label: Text(count > 99 ? '99+' : '$count'),
              child: const Icon(Icons.notifications_outlined),
            )
          : const Icon(Icons.notifications_outlined),
    );
  }
}

/// 検証環境で作業していることを見失わないためのバナー（12.2）。
class _EnvironmentBanner extends StatelessWidget
    implements PreferredSizeWidget {
  const _EnvironmentBanner({required this.label});

  final String label;

  @override
  Size get preferredSize => const Size.fromHeight(24);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      height: 24,
      alignment: Alignment.center,
      color: scheme.tertiaryContainer,
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.onTertiaryContainer),
      ),
    );
  }
}
