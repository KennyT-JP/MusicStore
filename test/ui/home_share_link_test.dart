/// ホームからの招待（仕様書 3.3 / 14.2）
///
/// **回帰テスト。** 以前は招待 URL を出すのにメンバー管理画面まで
/// 行く必要があり、人を呼ぶたびに 3 画面ぶん移動していた。
/// ホームのリスト行から直接コピーできるようにした。
///
/// 権限のない人にメニューを出さないこと（仕様書 14.5）と、
/// 招待で付与できる役割が 2 つに限られること（3.3）を固定する。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/models/music_list.dart';
import 'package:music_list_app/domain/role.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/ui/screens/home_screen.dart';

const _listId = 'list-1';

MyListEntry _entry(ListRole role) => MyListEntry(
  list: const MusicList(
    id: _listId,
    name: '練習音源',
    createdBy: 'u1',
    memberCount: 3,
    adminCount: 1,
  ),
  role: role,
);

Widget _app({required ListRole role, bool siteAdmin = false}) => ProviderScope(
  overrides: [
    myListsProvider.overrideWith((ref) => Stream.value([_entry(role)])),
    listAccessProvider(
      _listId,
    ).overrideWith((ref) => ListAccess(isSiteAdmin: siteAdmin, role: role)),
    listStatsProvider(_listId).overrideWith((ref) => Stream.value(null)),
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
    home: const HomeScreen(),
  ),
);

void main() {
  testWidgets('リスト管理者には招待のメニューを出す', (tester) async {
    await tester.pumpWidget(_app(role: ListRole.listAdmin));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('Super User には出さない（招待はリスト管理者以上／3.3）', (tester) async {
    await tester.pumpWidget(_app(role: ListRole.superUser));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('Read Only にも出さない', (tester) async {
    await tester.pumpWidget(_app(role: ListRole.readOnly));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('サイト管理者には出す（全リストでリスト管理者と同等／4.2）', (tester) async {
    await tester.pumpWidget(
      _app(role: ListRole.readOnly, siteAdmin: true),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('付与できる役割は Super User と Read Only だけ（3.3）', (tester) async {
    // **リスト管理者を招待で付与できてはいけない。**
    // サーバー側も弾くが、選べてしまうと押してからエラーになる。
    await tester.pumpWidget(_app(role: ListRole.listAdmin));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();

    final l10n = await AppL10n.delegate.load(const Locale('ja'));
    expect(
      find.text(l10n.copyShareLinkAs(l10n.roleSuperUser)),
      findsOneWidget,
    );
    expect(
      find.text(l10n.copyShareLinkAs(l10n.roleReadOnly)),
      findsOneWidget,
    );
    expect(
      find.text(l10n.copyShareLinkAs(l10n.roleListAdmin)),
      findsNothing,
    );
  });
}
