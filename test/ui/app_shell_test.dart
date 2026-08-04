/// アプリ外枠のスモークテスト（仕様書 14.1）
///
/// 画面幅に応じてサイドバーとボトムナビが切り替わることを確認する。
/// 12.6 では画面は手動確認としているが、外枠が例外で真っ白になる類の
/// 事故はここで捕まえておく。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/ui/routes.dart';
import 'package:music_list_app/ui/shell/app_shell.dart';

void main() {
  Widget wrap(Widget child, {Size size = const Size(1440, 900)}) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('ja'),
        home: child,
      ),
    );
  }

  AppShell shell({
    String route = AppRoutes.home,
    bool isSiteAdmin = false,
    int unread = 0,
    void Function(String)? onNavigate,
  }) => AppShell(
    currentRoute: route,
    onNavigate: onNavigate ?? (_) {},
    isSiteAdmin: isSiteAdmin,
    unreadNotificationCount: unread,
    child: const Center(child: Text('本文')),
  );

  testWidgets('広い画面ではサイドバーを出す（14.1）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(shell()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('本文'), findsOneWidget);
  });

  testWidgets('狭い画面ではボトムナビを出す（14.1）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(shell(), size: const Size(390, 844)));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('本文'), findsOneWidget);
  });

  testWidgets('サイト管理はサイト管理者にのみ出す（14.1 / 14.5）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(shell()));
    await tester.pumpAndSettle();
    expect(find.text('サイト管理'), findsNothing);

    await tester.pumpWidget(wrap(shell(isSiteAdmin: true)));
    await tester.pumpAndSettle();
    expect(find.text('サイト管理'), findsWidgets);
  });

  testWidgets('未読件数をバッジで出す（14.1）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(shell(unread: 3)));
    await tester.pumpAndSettle();

    // ベルアイコンとナビの通知、両方にバッジが付く。
    expect(find.text('3'), findsWidgets);
  });

  testWidgets('未読が 0 ならバッジを出さない', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(shell()));
    await tester.pumpAndSettle();

    expect(find.byType(Badge), findsNothing);
  });

  testWidgets('ベルアイコンから通知一覧へ遷移する（14.1）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final navigated = <String>[];
    await tester.pumpWidget(wrap(shell(onNavigate: navigated.add)));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.notifications_outlined).first);
    await tester.pumpAndSettle();

    expect(navigated, contains(AppRoutes.notifications));
  });

  testWidgets('下位のパスでも親の項目が選択される', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(shell(route: AppRoutes.siteAdminUsers, isSiteAdmin: true)),
    );
    await tester.pumpAndSettle();

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    // ホーム・通知・設定・サイト管理 の 4 番目。
    expect(rail.selectedIndex, 3);
  });
}
