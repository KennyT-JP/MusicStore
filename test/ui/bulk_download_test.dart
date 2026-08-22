/// リスト一括ダウンロードの見積もり（docs/DOWNLOAD-DESIGN.md 6.3・論点 20）
///
/// > **上限を置かない代わりが、見積もり・進捗・中断の 3 つ。**
/// > どれか 1 つでも欠けると、「押したら何が起きるか分からないボタン」になる。
/// > **上限が無いことと、無警告で始めることは違う。**
///
/// ここで守るのは**見積もり**——押す前に、**曲数と合計サイズを必ず両方出す**
/// こと（論点 20）。大きさを知らせずに 500 MB を落とし始めるのは、
/// 端末の容量にも通信量にも失礼である。
///
/// **すでに落としてあるぶんを数に入れない**ことも合わせて固定する。
/// 入れると、「残り 4 曲」と言いながら 12 曲ぶんの大きさを出すことになる。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/models/list_item.dart';
import 'package:music_list_app/data/models/music_list.dart';
import 'package:music_list_app/domain/download_index.dart';
import 'package:music_list_app/domain/role.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/providers/download_provider.dart';
import 'package:music_list_app/providers/playback_provider.dart';
import 'package:music_list_app/ui/screens/list_detail_screen.dart';

import 'support/downloads_harness.dart';

const _listId = 'list-1';
const _tenMB = 10485760;

final _items = [
  audioItem(id: 'item-1', seq: 1, sizeBytes: 41234567, title: '一本目'),
  audioItem(id: 'item-2', seq: 2, sizeBytes: _tenMB, title: '二本目'),
  audioItem(id: 'item-3', seq: 3, sizeBytes: _tenMB, title: '三本目'),
];

Widget _app({
  required ListAccess access,
  AsyncValue<bool> premium = const AsyncData(true),
  DownloadIndex index = const DownloadIndex(),
  List<ListItem>? items,
}) => ProviderScope(
  overrides: [
    listProvider(_listId).overrideWith(
      (ref) => Stream.value(
        const MusicList(
          id: _listId,
          name: '練習音源',
          createdBy: 'u1',
          adminCount: 1,
          memberCount: 3,
        ),
      ),
    ),
    listItemsProvider((
      listId: _listId,
      withdrawnLabel: '退会したユーザー',
    )).overrideWith((ref) => Stream.value(items ?? _items)),
    listAccessProvider(_listId).overrideWith((ref) => access),
    listStatsProvider(_listId).overrideWith((ref) => Stream.value(null)),
    listMembersProvider(_listId).overrideWith((ref) => Stream.value(const [])),
    // 実効プレミアム（`isPremiumOrAdminProvider`）を premium で決めるため、
    // サイト管理者の軸は false 固定にする（仕様書 4.1）。
    isPremiumProvider.overrideWithValue(premium),
    isSiteAdminProvider.overrideWith((ref) => false),
    downloadsProvider.overrideWith(() => FakeDownloadsController(index)),
    audioPlayerHandleProvider.overrideWithValue(FakeAudioHandle()),
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
    home: const ListDetailScreen(listId: _listId),
  ),
);

Future<void> _openListMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('押す前に「残り N 曲・約 X」の見積もりを出す（論点 20）', (tester) async {
    await tester.pumpWidget(
      _app(
        access: const ListAccess(isSiteAdmin: false, role: ListRole.readOnly),
        // 1 曲だけすでに端末にある。
        index: DownloadIndex(items: [downloadedItem(itemId: 'item-1')]),
      ),
    );
    await tester.pumpAndSettle();

    await _openListMenu(tester);
    await tester.tap(find.text('このリストを端末に保存'));
    await tester.pumpAndSettle();

    // **曲数と合計サイズを必ず両方出す。**
    // **すでに落としてあるぶんは、数にもサイズにも入れない。**
    expect(
      find.text('3 曲中 1 曲は保存済みです。残り 2 曲・約 20.0 MB をダウンロードします。'),
      findsOneWidget,
    );
    // **「再開」とは書かない**（4.1）。閉じると最初から取り直しになる。
    expect(find.textContaining('アプリを開いたままにしてください'), findsOneWidget);
    expect(find.textContaining('再開'), findsNothing);
  });

  testWidgets('落とすものが無ければ、確認を出さずにそう伝える', (tester) async {
    await tester.pumpWidget(
      _app(
        access: const ListAccess(isSiteAdmin: false, role: ListRole.readOnly),
        index: DownloadIndex(
          items: [
            downloadedItem(itemId: 'item-1'),
            downloadedItem(itemId: 'item-2', seq: 2),
            downloadedItem(itemId: 'item-3', seq: 3),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openListMenu(tester);
    await tester.tap(find.text('このリストを端末に保存'));
    await tester.pumpAndSettle();

    expect(find.text('このリストの曲は、すべて端末に保存済みです。'), findsOneWidget);
    expect(find.text('ダウンロードを始める'), findsNothing);
  });

  testWidgets('プレミアムでない人には、見積もりの前に案内を出す（論点 19）', (tester) async {
    await tester.pumpWidget(
      _app(
        access: const ListAccess(isSiteAdmin: false, role: ListRole.readOnly),
        premium: const AsyncData(false),
      ),
    );
    await tester.pumpAndSettle();

    await _openListMenu(tester);
    await tester.tap(find.text('このリストを端末に保存'));
    await tester.pumpAndSettle();

    expect(find.text('オフライン保存はプレミアムの機能です'), findsWidgets);
    expect(find.widgetWithText(FilledButton, 'クーポンを入力'), findsOneWidget);
    // 見積もりまでは進まない。
    expect(find.textContaining('をダウンロードします'), findsNothing);
  });

  testWidgets('閲覧者には入口そのものを出さない（論点 9）', (tester) async {
    await tester.pumpWidget(
      _app(
        access: const ListAccess(
          isSiteAdmin: false,
          role: null,
          isViewer: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _openListMenu(tester);
    expect(find.text('このリストを端末に保存'), findsNothing);
  });

  testWidgets('メンバーでないサイト管理者にも出す（全リスト／仕様書 4.2）', (tester) async {
    // サイト管理者は「全リストの項目を扱える」ので、参加していないリストでも
    // 一括ダウンロードを出す（旧・論点 18 を上書き）。
    await tester.pumpWidget(
      _app(access: const ListAccess(isSiteAdmin: true, role: null)),
    );
    await tester.pumpAndSettle();

    await _openListMenu(tester);
    expect(find.text('このリストを端末に保存'), findsOneWidget);
  });
}
