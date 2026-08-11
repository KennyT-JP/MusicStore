/// プレミアムの画面（docs/PREMIUM-DESIGN.md 4.3 / 5 / D5）
///
/// ここで固定するのは 3 つ。
///
/// 1. **プレミアムの人にだけ「リストを作る」が出る。**
///    そして**分かるまではどちらも出さない**（「0件」問題と同じ形。
///    既定を「プレミアムでない」に倒すと、押そうとした先が後から
///    入れ替わる／docs/AUDIT-CHECKLIST.md 観点 2）
/// 2. **クーポンの失敗は、原因ごとに違う文言で出る。**
///    「使えません」に丸めると、打ち直せば直るのか、配布元に聞くしか
///    ないのかが分からない
/// 3. **容量は「リストを作った人の合計」を出す。**
///    上限は人ごとの合計にかかるので、リストぶんだけを見せると
///    「空いているのに追加できない」ことになる
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:music_list_app/data/models/app_user.dart';
import 'package:music_list_app/data/models/music_list.dart';
import 'package:music_list_app/data/models/requests.dart';
import 'package:music_list_app/data/repositories/functions_repository.dart';
import 'package:music_list_app/domain/role.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/ui/screens/home_screen.dart';
import 'package:music_list_app/ui/screens/settings_screen.dart';
import 'package:music_list_app/ui/screens/site_admin_screens.dart';

class _FakeFunctions extends Mock implements FunctionsRepository {}

const _listId = 'list-1';

const _oneGb = 1024 * 1024 * 1024;

AppUser _user({DateTime? premiumUntil, UserStorage? storage}) => AppUser(
  uid: 'u1',
  displayName: '太郎',
  email: 'taro@example.com',
  locale: 'ja',
  isWithdrawn: false,
  notificationSettings: const NotificationSettings(),
  premiumUntil: premiumUntil,
  storage: storage,
);

MyListEntry _entry() => const MyListEntry(
  list: MusicList(
    id: _listId,
    name: '練習音源',
    createdBy: 'u1',
    memberCount: 3,
    adminCount: 1,
  ),
  role: ListRole.listAdmin,
);

ListStats _stats({int? ownerUsedBytes, int? ownerQuotaBytes}) => ListStats(
  nextSeq: 1,
  // このリストぶんの値。**画面にはこちらを出さない。**
  usedBytes: 100 * 1024 * 1024,
  quotaBytes: _oneGb,
  itemCount: 3,
  ownerUsedBytes: ownerUsedBytes,
  ownerQuotaBytes: ownerQuotaBytes,
);

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppL10n.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppL10n.supportedLocales,
  locale: const Locale('ja'),
  home: child,
);

/// ホーム。作成後の遷移先も見たいので、小さなルーターを添える。
Widget _home({
  required Stream<AppUser?> user,
  FunctionsRepository? functions,
  ListStats? stats,
}) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/lists/:listId',
        builder: (_, state) =>
            Scaffold(body: Text('開いたリスト:${state.pathParameters['listId']}')),
      ),
      GoRoute(
        path: '/request-list',
        builder: (_, _) => const Scaffold(body: Text('申請の画面')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      currentAppUserProvider.overrideWith((ref) => user),
      myListsProvider.overrideWith((ref) => Stream.value([_entry()])),
      listStatsProvider(_listId).overrideWith((ref) => Stream.value(stats)),
      listAccessProvider(_listId).overrideWith(
        (ref) => const ListAccess(isSiteAdmin: false, role: ListRole.listAdmin),
      ),
      if (functions != null)
        functionsRepositoryProvider.overrideWithValue(functions),
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
  );
}

Widget _settings({
  required AppUser user,
  FunctionsRepository? functions,
}) => ProviderScope(
  overrides: [
    currentAppUserProvider.overrideWith((ref) => Stream.value(user)),
    if (functions != null)
      functionsRepositoryProvider.overrideWithValue(functions),
  ],
  child: _wrap(const SettingsScreen()),
);

/// 設定画面は縦に長い。**下まで描かれた状態で確かめる**ため、
/// 背の高い画面にする（ListView は画面外を組み立てない）。
void _tallScreen(WidgetTester tester, {double width = 800}) {
  tester.view.physicalSize = Size(width, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('ホームの「リストを作る」（設計 4.3）', () {
    testWidgets('プレミアムの人にだけ出る', (tester) async {
      await tester.pumpWidget(
        _home(
          user: Stream.value(
            _user(premiumUntil: DateTime.now().add(const Duration(days: 30))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('リストを作る'), findsOneWidget);
      expect(find.text('リスト作成を申請'), findsNothing);
    });

    testWidgets('プレミアムでない人には出ない（申請の導線はいままでどおり）', (tester) async {
      await tester.pumpWidget(_home(user: Stream.value(_user())));
      await tester.pumpAndSettle();

      expect(find.text('リストを作る'), findsNothing);
      expect(find.text('リスト作成を申請'), findsOneWidget);
    });

    // **期限が切れたら作れなくなるだけ**（設計 D3）。
    testWidgets('期限が切れた人には出ない', (tester) async {
      await tester.pumpWidget(
        _home(
          user: Stream.value(
            _user(
              premiumUntil: DateTime.now().subtract(const Duration(days: 1)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('リストを作る'), findsNothing);
      expect(find.text('リスト作成を申請'), findsOneWidget);
    });

    // **届く前に確定した見た目を出さない。** 既定を「プレミアムでない」に
    // 倒すと、押そうとしたボタンが後から別のものへ入れ替わる。
    testWidgets('プレミアムかどうかが分かるまで、どちらも出さない', (tester) async {
      await tester.pumpWidget(_home(user: const Stream<AppUser?>.empty()));
      await tester.pump();

      expect(find.text('リストを作る'), findsNothing);
      expect(find.text('リスト作成を申請'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('名前を入れると作られ、そのリストへ移る', (tester) async {
      final functions = _FakeFunctions();
      when(
        () => functions.createListDirectly(any()),
      ).thenAnswer((_) async => 'list-9');

      await tester.pumpWidget(
        _home(
          user: Stream.value(
            _user(premiumUntil: DateTime.now().add(const Duration(days: 30))),
          ),
          functions: functions,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('リストを作る'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '新しいリスト');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'リストを作る'),
        ),
      );
      await tester.pumpAndSettle();

      verify(() => functions.createListDirectly('新しいリスト')).called(1);
      expect(find.text('開いたリスト:list-9'), findsOneWidget);
    });

    testWidgets('作れなかった理由をその場で出す（名前の重複）', (tester) async {
      final functions = _FakeFunctions();
      when(() => functions.createListDirectly(any())).thenThrow(
        const FunctionsCallException(
          'already-exists',
          'サーバーの文',
          reason: 'listNameTaken',
          params: {'listName': '練習音源'},
        ),
      );

      await tester.pumpWidget(
        _home(
          user: Stream.value(
            _user(premiumUntil: DateTime.now().add(const Duration(days: 30))),
          ),
          functions: functions,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('リストを作る'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '練習音源');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'リストを作る'),
        ),
      );
      await tester.pumpAndSettle();

      // **汎用の文言に落とさない。** 名前を変えれば通ることが分かる。
      expect(find.textContaining('「練習音源」は既に使われている'), findsOneWidget);
      expect(find.text('エラーが発生しました。しばらくしてからもう一度お試しください。'), findsNothing);
    });

    testWidgets('名前が空なら、送らずに促す', (tester) async {
      final functions = _FakeFunctions();
      await tester.pumpWidget(
        _home(
          user: Stream.value(
            _user(premiumUntil: DateTime.now().add(const Duration(days: 30))),
          ),
          functions: functions,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('リストを作る'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'リストを作る'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('リスト名を入力してください'), findsOneWidget);
      verifyNever(() => functions.createListDirectly(any()));
    });
  });

  group('容量は「リストを作った人の合計」（設計 D5 の補足）', () {
    testWidgets('ホームの容量バーは作成者の合計を出す', (tester) async {
      await tester.pumpWidget(
        _home(
          user: Stream.value(_user()),
          stats: _stats(
            // 作成者の合計 1.5GB / 2GB。このリストぶん（100MB / 1GB）とは別。
            ownerUsedBytes: _oneGb + _oneGb ~/ 2,
            ownerQuotaBytes: 2 * _oneGb,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1.5 GB / 2.0 GB'), findsOneWidget);
      // **「このリストの容量」と読めてはいけない。**
      expect(find.text('作成者の合計'), findsOneWidget);
      // リストぶんの数字を出していないこと。
      expect(find.textContaining('100 MB'), findsNothing);
    });

    testWidgets('合計がまだ届いていなければ、数字を出さない', (tester) async {
      await tester.pumpWidget(
        _home(user: Stream.value(_user()), stats: _stats()),
      );
      await tester.pumpAndSettle();

      // 代わりにリストぶんの値を出す、ということをしない。
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('100 MB'), findsNothing);
      expect(find.text('作成者の合計'), findsNothing);
    });
  });

  group('設定画面のクーポン（設計 5）', () {
    testWidgets('プレミアムなら、いつまでかを出す', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(
        _settings(
          user: _user(premiumUntil: DateTime(2027, 3, 31, 12, 0)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2027/03/31 12:00 までプレミアムをご利用いただけます。'), findsOneWidget);
    });

    testWidgets('プレミアムでなければ、消えないことも書いてある（D3）', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(_settings(user: _user()));
      await tester.pumpAndSettle();

      expect(find.text('現在はプレミアムではありません。'), findsOneWidget);
      expect(find.textContaining('そのまま残ります'), findsOneWidget);
    });

    testWidgets('適用に成功したら、いつまでプレミアムかを出す', (tester) async {
      _tallScreen(tester);
      final functions = _FakeFunctions();
      when(
        () => functions.redeemCoupon(any()),
      ).thenAnswer((_) async => DateTime(2027, 3, 31, 12, 0));

      await tester.pumpWidget(
        _settings(user: _user(), functions: functions),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'クーポンコード'),
        ' ABCD-1234 ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'クーポンを適用'));
      await tester.pumpAndSettle();

      // 前後の空白は落として送る（写し取りで必ず混じる）。
      verify(() => functions.redeemCoupon('ABCD-1234')).called(1);
      expect(
        find.text('クーポンを適用しました。2027/03/31 12:00 までプレミアムをご利用いただけます。'),
        findsOneWidget,
      );
    });

    testWidgets('コードが空なら、送らずに促す', (tester) async {
      _tallScreen(tester);
      final functions = _FakeFunctions();
      await tester.pumpWidget(
        _settings(user: _user(), functions: functions),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'クーポンを適用'));
      await tester.pumpAndSettle();

      expect(find.text('クーポンコードを入力してください'), findsOneWidget);
      verifyNever(() => functions.redeemCoupon(any()));
    });

    // **符号ごとに違う文言を出す。** 打ち直せば直るのか、配布元に聞く
    // しかないのかが、利用者にとって別物だから。
    for (final (reason, expected) in const [
      ('couponNotFound', 'そのクーポンコードは見つかりません。入力した文字をご確認ください。'),
      ('couponDisabled', 'このクーポンは停止されています。配布元にお問い合わせください。'),
      ('couponExpired', 'このクーポンは有効期限が切れています。'),
      ('couponUsedUp', 'このクーポンは、使える人数の上限に達しています。'),
      ('couponAlreadyUsed', 'このクーポンはすでにお使いです。同じクーポンは一度だけ使えます。'),
    ]) {
      testWidgets('$reason の理由を出す', (tester) async {
        _tallScreen(tester);
        final functions = _FakeFunctions();
        when(() => functions.redeemCoupon(any())).thenThrow(
          FunctionsCallException('failed-precondition', 'サーバーの文', reason: reason),
        );

        await tester.pumpWidget(
          _settings(user: _user(), functions: functions),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.widgetWithText(TextField, 'クーポンコード'),
          'CODE',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'クーポンを適用'));
        await tester.pumpAndSettle();

        expect(find.text(expected), findsOneWidget);
        // 汎用の文言にも、サーバーの文にも落ちていないこと。
        expect(find.text('エラーが発生しました。しばらくしてからもう一度お試しください。'), findsNothing);
        expect(find.text('サーバーの文'), findsNothing);
      });
    }
  });

  group('設定画面の容量（自分の合計）', () {
    testWidgets('自分の合計の使用量と上限を出す', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(
        _settings(
          user: _user(
            storage: const UserStorage(
              usedBytes: _oneGb,
              quotaBytes: 2 * _oneGb,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1.0 GB / 2.0 GB'), findsOneWidget);
      expect(find.text('残り 1.0 GB'), findsOneWidget);
      // リストごとではなく合計であることを書いてある。
      expect(find.textContaining('すべてのリストの合計'), findsOneWidget);
    });

    testWidgets('まだ集計されていないときに 0 と書かない', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(_settings(user: _user()));
      await tester.pumpAndSettle();

      expect(find.textContaining('まだ集計されていません'), findsOneWidget);
      expect(find.textContaining('0 B /'), findsNothing);
    });
  });

  // サイト管理から延ばす経路（設計 D4）と、人ごとの容量上限（D5 の補足）。
  group('サイト管理からのプレミアム操作', () {
    Widget users({required FunctionsRepository functions}) => ProviderScope(
      overrides: [
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
        functionsRepositoryProvider.overrideWithValue(functions),
      ],
      child: _wrap(const SiteAdminUsersScreen()),
    );

    testWidgets('プレミアムを延長でき、いつまでかを出す', (tester) async {
      final functions = _FakeFunctions();
      when(
        () => functions.extendPremium(uid: 'u1', months: 3),
      ).thenAnswer((_) async => DateTime(2027, 3, 31, 12, 0));

      await tester.pumpWidget(users(functions: functions));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('プレミアムを延長'));
      await tester.pumpAndSettle();

      // 足し算であって上書きではないことを、押す前に書いてある。
      expect(find.textContaining('後ろに足されます'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, '延長する月数'), '3');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '保存'),
        ),
      );
      await tester.pumpAndSettle();

      verify(() => functions.extendPremium(uid: 'u1', months: 3)).called(1);
      expect(find.textContaining('2027/03/31 12:00 まで延長しました'), findsOneWidget);
    });

    testWidgets('容量上限は「人ごとの合計」に効くと書いてある', (tester) async {
      final functions = _FakeFunctions();
      when(
        () => functions.setUserQuota(uid: 'u1', quotaBytes: 2 * _oneGb),
      ).thenAnswer((_) async {});

      await tester.pumpWidget(users(functions: functions));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('利用者の容量上限を変更'));
      await tester.pumpAndSettle();

      expect(find.textContaining('すべてのリストの合計に効きます'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, '新規リストの容量上限'),
        '2048',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '保存'),
        ),
      );
      await tester.pumpAndSettle();

      verify(
        () => functions.setUserQuota(uid: 'u1', quotaBytes: 2 * _oneGb),
      ).called(1);
      expect(find.text('容量上限を変更しました。'), findsOneWidget);
    });
  });

  // **狭い画面で潰れないこと（2026-08-10 の不具合と同じ形）。**
  //
  // 横に並べ続けると、残り幅が無くなって文字が 1 文字ずつ改行され、
  // 縦一列になる。描かれた幅を測って固定する。
  group('狭い画面（390px）', () {
    testWidgets('クーポンの入力欄が縦一列に潰れない', (tester) async {
      _tallScreen(tester, width: 390);
      await tester.pumpWidget(_settings(user: _user()));
      await tester.pumpAndSettle();

      final field = find.widgetWithText(TextField, 'クーポンコード');
      expect(tester.getSize(field).width, greaterThan(300));
      expect(
        tester.getSize(find.widgetWithText(FilledButton, 'クーポンを適用')).width,
        greaterThan(100),
      );
    });

    testWidgets('ホームの「リストを作る」が縦一列に潰れない', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _home(
          user: Stream.value(
            _user(premiumUntil: DateTime.now().add(const Duration(days: 30))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.text('リストを作る')).width, greaterThan(60));
      expect(tester.getSize(find.text('自分の申請')).width, greaterThan(50));
    });

    testWidgets('狭い画面でも容量の数字が縦一列に潰れない', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _home(
          user: Stream.value(_user()),
          stats: _stats(
            ownerUsedBytes: _oneGb + _oneGb ~/ 2,
            ownerQuotaBytes: 2 * _oneGb,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.getSize(find.text('1.5 GB / 2.0 GB')).width, greaterThan(80));
      expect(tester.getSize(find.text('作成者の合計')).width, greaterThan(50));
    });
  });
}
