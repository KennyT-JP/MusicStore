/// ログイン画面のスモークテスト（仕様書 3.1 / 14.2）
///
/// 画面が例外で真っ白になる類の事故をここで捕まえる。
library;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:music_list_app/data/repositories/auth_repository.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/ui/screens/auth/sign_in_screen.dart';

class _FakeAuthRepository extends Mock implements AuthRepository {}

void main() {
  late _FakeAuthRepository auth;

  setUp(() {
    auth = _FakeAuthRepository();
    when(
      () => auth.signInWithGoogle(languageCode: any(named: 'languageCode')),
    ).thenAnswer((_) async {});
    when(
      () => auth.signInWithApple(languageCode: any(named: 'languageCode')),
    ).thenAnswer((_) async {});
    when(
      () => auth.signInWithEmail(
        any(),
        any(),
        languageCode: any(named: 'languageCode'),
      ),
    ).thenAnswer((_) async {});
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Widget wrap(Widget child) => ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(auth)],
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

  testWidgets('例外を出さずに描画される', (tester) async {
    await tester.pumpWidget(wrap(const SignInScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Google ログインとメール入力欄が出ている。
    expect(find.text('Google で続ける'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
  });

  // **並びは依頼者が指定したもの（2026-08-11）。**
  // メール＋パスワードが先、「または」を挟んで Google が下。
  // 以前は Google が最上段だった。積み直すと元へ戻りやすいので固定する。
  testWidgets('メール入力が先、Google はその下に置く', (tester) async {
    await tester.pumpWidget(wrap(const SignInScreen()));
    await tester.pumpAndSettle();

    final email = tester.getTopLeft(find.byType(TextFormField).first).dy;
    final separator = tester.getTopLeft(find.text('または')).dy;
    final google = tester.getTopLeft(find.text('Google で続ける')).dy;

    expect(email, lessThan(separator));
    expect(separator, lessThan(google));
  });

  // **ヘルプは「置いてある」だけでは足りない。押せること。**
  // 認証画面は Stack で組んでおり、本文が上に重なると、見えていても
  // 反応しない状態になり得る（2026-08-11）。
  testWidgets('ヘルプボタンが出ていて、押せる（スマホ幅）', (tester) async {
    // **狭い画面で確かめる。** 本文が広がって重なるとしたら、こちら。
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(const SignInScreen()));
    await tester.pumpAndSettle();

    final help = find.byTooltip('使い方');
    expect(help, findsOneWidget);

    // 覆われていれば、ここで hit test の警告つきで失敗する。
    await tester.tap(help);
    await tester.pumpAndSettle();
  });

  testWidgets('パスワードは伏せてあり、押すと見える', (tester) async {
    await tester.pumpWidget(wrap(const SignInScreen()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('メールとパスワードを入れてログインできる', (tester) async {
    await tester.pumpWidget(wrap(const SignInScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).first,
      'user@example.com',
    );
    await tester.enterText(find.byType(TextFormField).last, 'password');

    await tester.tap(find.widgetWithText(FilledButton, 'ログイン'));
    await tester.pumpAndSettle();

    // **表示言語も渡すこと。** users を作るときの表示言語になる（2 章）。
    // 'ja' を固定で書いていたため、英語で登録した人も登録し終えた瞬間に
    // 日本語へ切り替わっていた（監査 第3回）。
    verify(
      () => auth.signInWithEmail(
        'user@example.com',
        'password',
        languageCode: 'ja',
      ),
    ).called(1);
  });

  // **Apple のボタンは iOS のアプリにだけ出す**
  // （docs/MOBILE-APP-DESIGN.md 5-6・3-2）。
  // 判定は AuthRepository.isAppleSignInAvailable の 1 箇所にあり、
  // 規則そのものは test/domain/apple_sign_in_test.dart が見ている。
  // ここで確かめるのは、**画面がその判定に従っていること**。
  group('Apple のボタン', () {
    // **`debugDefaultTargetPlatformOverride` は本文の中で戻すこと。**
    // flutter_test は本文が終わった時点で「foundation の debug 変数が
    // 元に戻っているか」を確かめるので、`tearDown` では間に合わない。
    // 上の `tearDown` は、途中で落ちたときの後片付け用に残してある。
    Future<void> pumpAs(WidgetTester tester, TargetPlatform platform) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(wrap(const SignInScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('iOS には出す', (tester) async {
      await pumpAs(tester, TargetPlatform.iOS);

      expect(find.text('Apple で続ける'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Android には出さない', (tester) async {
      // Android で出すには Apple 側に Services ID と戻り先 URL の登録が
      // 別途要る。**押しても何も起きないボタンを置かない。**
      await pumpAs(tester, TargetPlatform.android);

      expect(find.text('Apple で続ける'), findsNothing);
      // Google のほうは、どこでも出る。
      expect(find.text('Google で続ける'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('押すと、表示言語を渡して呼ぶ', (tester) async {
      await pumpAs(tester, TargetPlatform.iOS);

      // 画面のいちばん下にあるので、狭い画面では最初は見えていない。
      await tester.ensureVisible(find.text('Apple で続ける'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apple で続ける'));
      await tester.pumpAndSettle();

      // 登録時の表示言語を、その人の設定として残す（2 章）。
      verify(() => auth.signInWithApple(languageCode: 'ja')).called(1);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  testWidgets('未入力なら送信しない', (tester) async {
    await tester.pumpWidget(wrap(const SignInScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'ログイン'));
    await tester.pumpAndSettle();

    verifyNever(
      () => auth.signInWithEmail(
        any(),
        any(),
        languageCode: any(named: 'languageCode'),
      ),
    );
  });
}
