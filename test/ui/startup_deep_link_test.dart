/// 起動時に開いた URL が、そのまま効くか（仕様書 3.1.1 / 14.3）
///
/// **配信して初めて分かった不具合の回帰テスト。**
///
/// ログイン状態の復元を待つあいだ読み込み画面を出すようにしたところ、
/// 共有リンクを開いても、そのあと作られるルーターに元の URL が渡らず、
/// ホーム扱いで始まっていた（未ログインだと戻り先の付かないログイン画面に
/// なり、ログインしても共有リンクへ戻れない）。
///
/// 画面はキャンバスに描かれるので、ブラウザの DOM からは中身を読めない。
/// **起動の経路をここで組み立てて、どこへ着くかを機械的に確かめる。**
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

/// 画面が Firebase を掴みに行かないようにするための差し替え。
/// ここで見たいのは「どこへ着いたか」だけで、画面の中身ではない。
class _FakeAuthRepository extends Mock implements AuthRepository {}

void main() {
  /// 起動地点を渡してルーターを組み、いま出ている場所を返す。
  ///
  /// **着いた場所だけを見る。** 画面の中身は各画面のテストが受け持つ。
  /// ここで確かめたいのは「開いた URL が効いているか」だけ。
  Future<String> landingFor(
    WidgetTester tester, {
    required AuthState auth,
    required String launchLocation,
  }) async {
    final router = buildAppRouter(
      readAuthState: () => auth,
      initialLocation: launchLocation,
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

    return router.state.uri.toString();
  }

  const signedOut = AuthState.signedOut();
  const member = AuthState(
    isSignedIn: true,
    isEmailVerified: true,
    isSiteAdmin: false,
  );

  testWidgets('未ログインで共有リンクを開くと、戻り先つきのログインへ', (tester) async {
    final landing = await landingFor(
      tester,
      auth: signedOut,
      launchLocation: '/s/abc123',
    );

    // **戻り先が付いていること。** ここが抜けると、ログインしたあと
    // 共有リンクへ戻れず、ホームに置き去りになる。
    expect(landing, startsWith(AppRoutes.signIn));
    expect(
      Uri.parse(landing).queryParameters[AppRoutes.redirectQueryParam],
      '/s/abc123',
    );
  });

  testWidgets('ログイン済みで共有リンクを開くと、そのまま選択画面へ', (tester) async {
    final landing = await landingFor(
      tester,
      auth: member,
      launchLocation: '/s/abc123',
    );

    expect(landing, '/s/abc123');
  });

  testWidgets('ログイン済みでリストの URL を開くと、そのリストへ', (tester) async {
    final landing = await landingFor(
      tester,
      auth: member,
      launchLocation: '/lists/abc123',
    );

    expect(landing, '/lists/abc123');
  });

  testWidgets('起動地点を渡さなければホーム（既定）', (tester) async {
    final landing = await landingFor(
      tester,
      auth: member,
      launchLocation: AppRoutes.home,
    );

    expect(landing, AppRoutes.home);
  });
}
