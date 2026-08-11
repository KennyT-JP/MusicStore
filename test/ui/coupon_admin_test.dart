/// クーポン管理（docs/PREMIUM-DESIGN.md 5 / D1 / D8）
///
/// **クーポンはクライアントから直接読めない**（ルールで全面禁止）。
/// 画面は呼び出し可能関数だけを通す。ここでは、その呼び方と見え方を固定する。
///
/// - 一覧に「使われた数／上限」「期限」「止めてあるか」が出ること
/// - 発行でコードを**自動生成にも、文字列の指定にも**できること（D8）
/// - 上限の変更と停止が、**消さずに**行えること（D1／設計 5）
/// - 狭い画面でコードが縦一列に潰れないこと（2026-08-10 の不具合と同じ形）
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:music_list_app/data/models/coupon.dart';
import 'package:music_list_app/data/models/requests.dart';
import 'package:music_list_app/data/repositories/functions_repository.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/ui/app_router.dart';
import 'package:music_list_app/ui/routes.dart';
import 'package:music_list_app/ui/screens/site_admin_screens.dart';

class _FakeFunctions extends Mock implements FunctionsRepository {}

Coupon _coupon({
  String id = 'c1',
  String code = 'SPRING2026',
  int months = 3,
  int maxUses = 10,
  int usedCount = 2,
  bool disabled = false,
  DateTime? expiresAt,
}) => Coupon(
  id: id,
  code: code,
  months: months,
  maxUses: maxUses,
  usedCount: usedCount,
  disabled: disabled,
  expiresAt: expiresAt,
);

Widget _app({
  required List<Coupon> coupons,
  FunctionsRepository? functions,
  List<CouponRedemption> redemptions = const [],
}) => ProviderScope(
  overrides: [
    couponsProvider.overrideWith((ref) async => coupons),
    for (final coupon in coupons)
      couponRedemptionsProvider(
        coupon.id,
      ).overrideWith((ref) async => redemptions),
    siteUsersProvider.overrideWith(
      (ref) async => const [
        SiteUser(
          uid: 'u1',
          email: 'taro@example.com',
          displayName: '太郎',
          isSiteAdmin: false,
          isWithdrawn: false,
        ),
      ],
    ),
    if (functions != null)
      functionsRepositoryProvider.overrideWithValue(functions),
  ],
  child: MaterialApp(
    localizationsDelegates: const [
      AppL10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppL10n.supportedLocales,
    locale: const Locale('ja'),
    home: const SiteAdminCouponsScreen(),
  ),
);

/// ダイアログの中のボタン。画面側に同じ文字のボタンがあるので、
/// **ダイアログの中に限って**探す。
Finder _inDialog(String label) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(FilledButton, label),
);

void main() {
  setUpAll(() {
    registerFallbackValue(DateTime(2026));
  });

  group('一覧', () {
    testWidgets('コード・月数・使われた数／上限・期限を出す', (tester) async {
      await tester.pumpWidget(
        _app(
          coupons: [_coupon(expiresAt: DateTime(2026, 12, 31, 23, 59))],
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('SPRING2026'), findsOneWidget);
      expect(find.text('3 か月'), findsOneWidget);
      expect(find.text('2 / 10 人'), findsOneWidget);
      expect(find.text('期限 2026/12/31 23:59'), findsOneWidget);
    });

    testWidgets('期限が無ければ、その旨を出す', (tester) async {
      await tester.pumpWidget(_app(coupons: [_coupon()]));
      await tester.pumpAndSettle();

      expect(find.text('期限なし'), findsOneWidget);
    });

    testWidgets('止めてあるクーポンは、そう分かる', (tester) async {
      await tester.pumpWidget(_app(coupons: [_coupon(disabled: true)]));
      await tester.pumpAndSettle();

      expect(find.text('停止中'), findsOneWidget);
      // 止めたものは「停止を解除」で戻せる。**消す操作は置かない。**
      expect(find.text('停止を解除'), findsOneWidget);
      expect(find.text('停止する'), findsNothing);
    });

    testWidgets('人数を使い切ったクーポンは、そう分かる', (tester) async {
      await tester.pumpWidget(
        _app(coupons: [_coupon(usedCount: 10, maxUses: 10)]),
      );
      await tester.pumpAndSettle();

      expect(find.text('上限に達しました'), findsOneWidget);
    });

    testWidgets('1 枚も無ければ、その旨を出す', (tester) async {
      await tester.pumpWidget(_app(coupons: const []));
      await tester.pumpAndSettle();

      expect(find.text('まだクーポンはありません。'), findsOneWidget);
    });
  });

  group('発行（D8）', () {
    testWidgets('月数と人数を決めて発行できる（コードは自動生成）', (tester) async {
      final functions = _FakeFunctions();
      when(
        () => functions.createCoupon(
          months: any(named: 'months'),
          maxUses: any(named: 'maxUses'),
          code: any(named: 'code'),
          expiresAt: any(named: 'expiresAt'),
        ),
      ).thenAnswer((_) async => (couponId: 'c9', code: 'AUTOCODE24'));

      await tester.pumpWidget(_app(coupons: const [], functions: functions));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FloatingActionButton, 'クーポンを発行'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '付与する月数'), '2');
      await tester.enterText(find.widgetWithText(TextField, '使える人数'), '5');
      await tester.tap(_inDialog('クーポンを発行'));
      await tester.pumpAndSettle();

      verify(
        () => functions.createCoupon(
          months: 2,
          maxUses: 5,
          code: null,
          expiresAt: null,
        ),
      ).called(1);
      // **発行したコードをその場で出す。** 見ないと配れない。
      expect(find.textContaining('AUTOCODE24'), findsOneWidget);
    });

    testWidgets('文字列を指定でき、推測されやすいことを画面に出す', (tester) async {
      final functions = _FakeFunctions();
      when(
        () => functions.createCoupon(
          months: any(named: 'months'),
          maxUses: any(named: 'maxUses'),
          code: any(named: 'code'),
          expiresAt: any(named: 'expiresAt'),
        ),
      ).thenAnswer((_) async => (couponId: 'c9', code: 'SPRING'));

      await tester.pumpWidget(_app(coupons: const [], functions: functions));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FloatingActionButton, 'クーポンを発行'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('文字列を指定'));
      await tester.pumpAndSettle();

      expect(find.textContaining('推測もされやすくなります'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '指定するコード'), 'SPRING');
      await tester.tap(_inDialog('クーポンを発行'));
      await tester.pumpAndSettle();

      verify(
        () => functions.createCoupon(
          months: 1,
          maxUses: 1,
          code: 'SPRING',
          expiresAt: null,
        ),
      ).called(1);
    });

    testWidgets('文字列を指定したのに空なら、送らずに促す', (tester) async {
      final functions = _FakeFunctions();
      await tester.pumpWidget(_app(coupons: const [], functions: functions));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FloatingActionButton, 'クーポンを発行'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('文字列を指定'));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog('クーポンを発行'));
      await tester.pumpAndSettle();

      expect(find.text('クーポンコードを入力してください'), findsOneWidget);
      verifyNever(
        () => functions.createCoupon(
          months: any(named: 'months'),
          maxUses: any(named: 'maxUses'),
          code: any(named: 'code'),
          expiresAt: any(named: 'expiresAt'),
        ),
      );
    });

    testWidgets('同じコードが使われていたら、その理由を出す', (tester) async {
      final functions = _FakeFunctions();
      when(
        () => functions.createCoupon(
          months: any(named: 'months'),
          maxUses: any(named: 'maxUses'),
          code: any(named: 'code'),
          expiresAt: any(named: 'expiresAt'),
        ),
      ).thenThrow(
        const FunctionsCallException(
          'already-exists',
          'サーバーの文',
          reason: 'couponCodeTaken',
        ),
      );

      await tester.pumpWidget(_app(coupons: const [], functions: functions));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FloatingActionButton, 'クーポンを発行'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('文字列を指定'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '指定するコード'), 'SPRING');
      await tester.tap(_inDialog('クーポンを発行'));
      await tester.pumpAndSettle();

      expect(find.text('そのコードはすでに使われています。別の文字列を指定してください。'), findsOneWidget);
      expect(find.text('サーバーの文'), findsNothing);
    });
  });

  group('上限の変更と停止（D1）', () {
    testWidgets('人数を変えられる。使った人のぶんは取り消されないと書いてある', (tester) async {
      final functions = _FakeFunctions();
      when(
        () => functions.updateCoupon(couponId: 'c1', maxUses: 1),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(_app(coupons: [_coupon()], functions: functions));
      await tester.pumpAndSettle();

      await tester.tap(find.text('人数を変える'));
      await tester.pumpAndSettle();

      expect(find.textContaining('取り消されません'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '使える人数'), '1');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '保存'),
        ),
      );
      await tester.pumpAndSettle();

      verify(() => functions.updateCoupon(couponId: 'c1', maxUses: 1)).called(1);
    });

    testWidgets('止められる（消さない）', (tester) async {
      final functions = _FakeFunctions();
      when(
        () => functions.updateCoupon(couponId: 'c1', disabled: true),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(_app(coupons: [_coupon()], functions: functions));
      await tester.pumpAndSettle();

      await tester.tap(find.text('停止する'));
      await tester.pumpAndSettle();

      verify(
        () => functions.updateCoupon(couponId: 'c1', disabled: true),
      ).called(1);
    });

    testWidgets('止めるのに失敗したら、理由を出す', (tester) async {
      final functions = _FakeFunctions();
      when(
        () => functions.updateCoupon(couponId: 'c1', disabled: true),
      ).thenThrow(
        const FunctionsCallException(
          'permission-denied',
          'サーバーの文',
          reason: 'siteAdminOnly',
        ),
      );

      await tester.pumpWidget(_app(coupons: [_coupon()], functions: functions));
      await tester.pumpAndSettle();

      await tester.tap(find.text('停止する'));
      await tester.pumpAndSettle();

      // **押しても何も起きない、にしない**（監査 第4回）。
      expect(find.text('この操作はサイト管理者のみ行えます。'), findsOneWidget);
    });
  });

  group('使った人', () {
    testWidgets('使った人と、その日時を出す', (tester) async {
      await tester.pumpWidget(
        _app(
          coupons: [_coupon()],
          redemptions: [
            CouponRedemption(uid: 'u1', redeemedAt: DateTime(2026, 8, 11, 9, 30)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('使った人を見る'));
      await tester.pumpAndSettle();

      // uid ではなく、分かる名前で出す（問い合わせへの回答用）。
      expect(find.text('太郎'), findsOneWidget);
      expect(find.text('2026/08/11 09:30'), findsOneWidget);
    });

    testWidgets('まだ誰も使っていなければ、その旨を出す', (tester) async {
      await tester.pumpWidget(_app(coupons: [_coupon()]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('使った人を見る'));
      await tester.pumpAndSettle();

      expect(find.text('まだどなたも使っていません。'), findsOneWidget);
    });
  });

  group('サイト管理からの行き来', () {
    testWidgets('サイト管理のトップに入口がある（11.1 の並び）', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pendingListRequestsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            allListsProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppL10n.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppL10n.supportedLocales,
            locale: Locale('ja'),
            home: SiteAdminHomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('クーポン'), findsOneWidget);
    });

    // **URL を直接開いても出ること。** サイト管理の画面は URL から
    // 開けるので、経路が 1 本しかないと直打ちで迷子になる（14.3）。
    testWidgets('/admin/coupons を直接開ける', (tester) async {
      final router = buildAppRouter(
        readAuthState: () => const AuthState(
          isSignedIn: true,
          isEmailVerified: true,
          isSiteAdmin: true,
        ),
        initialLocation: AppRoutes.siteAdminCoupons,
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [couponsProvider.overrideWith((ref) async => const [])],
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
      await tester.pumpAndSettle();

      expect(find.byType(SiteAdminCouponsScreen), findsOneWidget);
      expect(find.text('まだクーポンはありません。'), findsOneWidget);
    });
  });

  // **狭い画面で潰れないこと。** 横に並べ続けると残り幅が無くなり、
  // 文字が 1 文字ずつ改行されて縦一列になる（2026-08-10 の不具合）。
  testWidgets('狭い画面（390px）でもコードと数字が横に伸びる', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        coupons: [
          _coupon(
            code: 'ABCDEFGH23456789JKLMNPQR',
            expiresAt: DateTime(2026, 12, 31, 23, 59),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.text('ABCDEFGH23456789JKLMNPQR')).width,
      greaterThan(200),
    );
    expect(tester.getSize(find.text('2 / 10 人')).width, greaterThan(40));
    expect(find.text('期限 2026/12/31 23:59'), findsOneWidget);
  });
}
