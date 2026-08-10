/// サイト管理の入口が、クレームが届いた時点で出るか（仕様書 14.1 / 13.5）
///
/// **依頼者の報告（2026-08-10・スマホ）の回帰テスト。**
///
/// サイト管理者でログインしても、**下のナビにサイト管理が出ない**。
/// 別のアイコンを押すと出てくる。
///
/// サイト管理者かどうかは Auth のカスタムクレーム由来で、**最初の描画に
/// 間に合わない**。届いたあとにナビを描き直せていなければ、こうなる。
/// 押すと出るのは、画面を移ったときに描き直されるためで、**直っている
/// わけではない**。
///
/// 画面はキャンバスに描かれ、ブラウザの DOM からは読めない。
/// 「あとから届く」状況をここで作って、機械的に確かめる。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:music_list_app/data/repositories/auth_repository.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/ui/app_router.dart';
import 'package:music_list_app/ui/routes.dart';

class _FakeAuthRepository extends Mock implements AuthRepository {}

void main() {
  testWidgets('クレームが遅れて届いても、サイト管理の入口が出る', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 最初は「サイト管理者かどうか分からない」。既定は false に倒れる。
    var auth = const AuthState(
      isSignedIn: true,
      isEmailVerified: true,
      isSiteAdmin: false,
    );

    // 認証状態が変わったことをルーターへ伝える口（app.dart と同じ形）。
    final refresh = ValueNotifier<int>(0);
    addTearDown(refresh.dispose);

    final router = buildAppRouter(
      readAuthState: () => auth,
      authListenable: refresh,
      initialLocation: AppRoutes.home,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        ],
        child: MaterialApp.router(
          localizationsDelegates: const [
            AppL10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('ja'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('サイト管理'),
      findsNothing,
      reason: 'まだクレームが届いていないので、出ていないのが正しい',
    );

    // クレームが届いた。app.dart はこの形でルーターへ知らせる。
    auth = const AuthState(
      isSignedIn: true,
      isEmailVerified: true,
      isSiteAdmin: true,
    );
    refresh.value++;
    await tester.pump();

    expect(
      find.text('サイト管理'),
      findsOneWidget,
      reason: '届いた時点で出ること。画面を移るまで出ないのは不具合',
    );
  });

  // **未読の件数も同じ経路で届く。** サイト管理の入口だけを直すと、
  // こちらは古いまま残る——「片側だけ塞ぐと、もう片側で同じことが
  // 起きる」（docs/AUDIT-CHECKLIST.md 観点 4）。
  testWidgets('未読の件数も、届いた時点でナビに出る（14.1）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var auth = const AuthState(
      isSignedIn: true,
      isEmailVerified: true,
      isSiteAdmin: false,
    );
    final refresh = ValueNotifier<int>(0);
    addTearDown(refresh.dispose);

    final router = buildAppRouter(
      readAuthState: () => auth,
      authListenable: refresh,
      initialLocation: AppRoutes.home,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
        ],
        child: MaterialApp.router(
          localizationsDelegates: const [
            AppL10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('ja'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('3'), findsNothing);

    auth = const AuthState(
      isSignedIn: true,
      isEmailVerified: true,
      isSiteAdmin: false,
      unreadNotificationCount: 3,
    );
    refresh.value++;
    await tester.pump();

    // 件数は上部バーの鈴とナビの両方に出る。ここで見たいのは
    // 「届いた時点で描き直されたか」なので、数までは縛らない。
    expect(find.text('3'), findsWidgets);
  });
}
