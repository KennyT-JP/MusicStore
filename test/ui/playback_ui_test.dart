/// リスト内での再生の操作（仕様書 8 章）
///
/// 端末の音は鳴らさず、**どのボタンが出るか**と**押したときに何を頼むか**を
/// 確かめる。音を鳴らす側は差し替えてある。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/audio_player_handle.dart';
import 'package:music_list_app/data/models/list_item.dart';
import 'package:music_list_app/data/models/music_list.dart';
import 'package:music_list_app/domain/local_date.dart';
import 'package:music_list_app/domain/role.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/providers/playback_provider.dart';
import 'package:music_list_app/ui/screens/list_detail_screen.dart';

const _listId = 'list-1';

/// 何を頼まれたかだけを覚える、音の側の差し替え。
class _FakeHandle implements AudioPlayerHandle {
  final calls = <String>[];

  @override
  Future<void> playFrom(String url) async => calls.add('playFrom:$url');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Stream<void> get onCompleted => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

ListItem _fileItem(int seq) => ListItem(
  id: 'item-$seq',
  seq: seq,
  itemDate: LocalDate.tryParse('2026-08-01')!,
  kind: ItemKind.file,
  file: ItemFile(
    storagePath: 'lists/$_listId/items/item-$seq/take.mp3',
    fileName: 'take$seq.mp3',
    sizeBytes: 1024,
    contentType: 'audio/mpeg',
  ),
  createdBy: 'u1',
  registrantDisplayName: '山田',
  status: ContentStatus.active,
);

/// 音ではないファイル。仕様 7.1 でファイルの種類は制限していない。
ListItem _imageItem(int seq) => ListItem(
  id: 'item-$seq',
  seq: seq,
  itemDate: LocalDate.tryParse('2026-08-01')!,
  kind: ItemKind.file,
  file: ItemFile(
    storagePath: 'lists/$_listId/items/item-$seq/photo.jpg',
    fileName: '顔写真3.jpg',
    sizeBytes: 1024,
    contentType: 'application/octet-stream',
  ),
  createdBy: 'u1',
  registrantDisplayName: '山田',
  status: ContentStatus.active,
);

ListItem _urlItem(int seq) => ListItem(
  id: 'item-$seq',
  seq: seq,
  itemDate: LocalDate.tryParse('2026-08-01')!,
  kind: ItemKind.url,
  url: 'https://example.com/$seq',
  createdBy: 'u1',
  registrantDisplayName: '山田',
  status: ContentStatus.active,
);

Widget _app(List<ListItem> items, _FakeHandle handle) => ProviderScope(
  overrides: [
    audioPlayerHandleProvider.overrideWithValue(handle),
    // Storage に繋がずに URL を返す。
    downloadUrlResolverProvider.overrideWithValue(
      (path) async => 'https://example.com/$path',
    ),
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
    listItemsProvider(
      (listId: _listId, withdrawnLabel: '退会したユーザー'),
    ).overrideWith((ref) => Stream.value(items)),
    listAccessProvider(_listId).overrideWith(
      (ref) => const ListAccess(isSiteAdmin: false, role: ListRole.superUser),
    ),
    listStatsProvider(_listId).overrideWith((ref) => Stream.value(null)),
    listMembersProvider(_listId).overrideWith((ref) => Stream.value(const [])),
    myMembershipsProvider.overrideWith(
      (ref) => Stream.value([
        (
          listId: _listId,
          member: const ListMember(uid: 'u1', role: ListRole.superUser),
        ),
      ]),
    ),
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

void main() {
  testWidgets('ファイルの項目に再生ボタンを出す（仕様 4）', (tester) async {
    await tester.pumpWidget(_app([_fileItem(1)], _FakeHandle()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    // 止まっているうちは停止ボタンを出さない。
    expect(find.byIcon(Icons.stop), findsNothing);
    expect(find.byIcon(Icons.pause), findsNothing);
  });

  testWidgets('画像のファイルには出さない（押しても鳴らないため）', (tester) async {
    await tester.pumpWidget(_app([_imageItem(1)], _FakeHandle()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_arrow), findsNothing);
    // 行そのものは出る。開けば中身は見られる。
    expect(find.text('顔写真3.jpg'), findsOneWidget);
  });

  testWidgets('音のファイルと画像が並んでいても、音にだけ出す', (tester) async {
    await tester.pumpWidget(
      _app([_imageItem(1), _fileItem(2)], _FakeHandle()),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('URL の項目には出さない（外部のページは鳴らせない）', (tester) async {
    await tester.pumpWidget(_app([_urlItem(1)], _FakeHandle()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('再生中は一時停止と停止を出す（仕様 6）', (tester) async {
    final handle = _FakeHandle();
    await tester.pumpWidget(_app([_fileItem(1)], handle));
    await tester.pumpAndSettle();

    // 再生を押す。URL の取り出しは差し替えてあるので Firestore は要らない。
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();

    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('一時停止すると、再生と停止に戻る（仕様 7）', (tester) async {
    final handle = _FakeHandle();
    await tester.pumpWidget(_app([_fileItem(1)], handle));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    // **一時停止中も停止を出す。** 出さないと頭に戻す手段がなくなる。
    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(handle.calls, contains('pause'));
  });

  testWidgets('停止すると、その行から停止ボタンが消える（仕様 7）', (tester) async {
    final handle = _FakeHandle();
    await tester.pumpWidget(_app([_fileItem(1)], handle));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsNothing);
    expect(handle.calls, contains('stop'));
  });

  testWidgets('一時停止から再生すると、その位置から続ける（仕様 7）', (tester) async {
    final handle = _FakeHandle();
    await tester.pumpWidget(_app([_fileItem(1)], handle));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();

    handle.calls.clear();
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();

    // **先頭から鳴らし直さない。** resume を頼むこと。
    expect(handle.calls, contains('resume'));
    expect(handle.calls.any((c) => c.startsWith('playFrom')), isFalse);
  });

  testWidgets('2 曲あっても、操作の対象は 1 つだけ', (tester) async {
    final handle = _FakeHandle();
    await tester.pumpWidget(_app([_fileItem(1), _fileItem(2)], handle));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_arrow), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.play_arrow).first);
    await tester.pump();

    // 押したほうだけが一時停止になり、もう一方は再生のまま。
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.stop), findsOneWidget);
  });
}
