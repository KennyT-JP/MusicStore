/// ホームからの共有リンク（仕様書 3.3 / 14.2）
///
/// **回帰テスト。** 以前は共有 URL を出すのにメンバー管理画面まで
/// 行く必要があり、人を呼ぶたびに 3 画面ぶん移動していた。
/// ホームのリスト行から直接コピーできるようにした。
///
/// 権限のない人に導線を出さないこと（仕様書 14.5）と、
/// **配る側に相手の種類を選ばせないこと**（3.3）を固定する。
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
  testWidgets('リスト管理者には共有リンクの導線を出す', (tester) async {
    await tester.pumpWidget(_app(role: ListRole.listAdmin));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.link), findsOneWidget);
  });

  testWidgets('Super User には出さない（発行はリスト管理者以上／3.3）', (tester) async {
    await tester.pumpWidget(_app(role: ListRole.superUser));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.link), findsNothing);
  });

  testWidgets('Read Only にも出さない', (tester) async {
    await tester.pumpWidget(_app(role: ListRole.readOnly));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.link), findsNothing);
  });

  testWidgets('サイト管理者には出す（全リストでリスト管理者と同等／4.2）', (tester) async {
    await tester.pumpWidget(_app(role: ListRole.readOnly, siteAdmin: true));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.link), findsOneWidget);
  });

  testWidgets('リンクは 1 つだけ。相手の種類は選ばせない（3.3）', (tester) async {
    // **回帰テスト。** 以前はここで「Super User として招待」
    // 「Read Only として招待」を選ばせていた。配る側は相手が参加するか
    // どうかも知らないので、選ばせること自体をやめた。
    await tester.pumpWidget(_app(role: ListRole.listAdmin));
    await tester.pumpAndSettle();

    final l10n = await AppL10n.delegate.load(const Locale('ja'));

    // 選択肢を持つ形（メニュー）ではなく、押すだけのボタンであること。
    expect(find.byType(PopupMenuButton<ListRole>), findsNothing);
    expect(find.byTooltip(l10n.copyShareLink), findsOneWidget);
    expect(find.byIcon(Icons.link), findsOneWidget);
  });
}
