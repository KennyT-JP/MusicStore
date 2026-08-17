/// 未読バッジの上限表示（監査 第5回・群B）
///
/// 未読件数は provider 側で 100 件までしか購読しないが、表示側でも
/// 99 を超えたら「99+」で頭打ちにする。数字がいくつであっても、
/// 上限を超えたら「99+」しか出さないことを固定する。
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

  AppShell shell({int unread = 0}) => AppShell(
    currentRoute: AppRoutes.home,
    onNavigate: (_) {},
    unreadNotificationCount: unread,
    child: const Center(child: Text('本文')),
  );

  testWidgets('99 は数字のまま出す（14.1）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(shell(unread: 99)));
    await tester.pumpAndSettle();

    expect(find.text('99'), findsWidgets);
    expect(find.text('99+'), findsNothing);
  });

  testWidgets('100 以上は「99+」で頭打ちにする（監査 第5回・群B）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // provider が 100 件で購読を止めるため、表示に来る最大値は 100。
    await tester.pumpWidget(wrap(shell(unread: 100)));
    await tester.pumpAndSettle();

    expect(find.text('99+'), findsWidgets);
    expect(find.text('100'), findsNothing);
  });
}
