/// リスト内での再生の操作（仕様書 8 章）
///
/// 端末の音は鳴らさず、**どのボタンが出るか**と**押したときに何を頼むか**を
/// 確かめる。音を鳴らす側は差し替えてある。
library;

import 'dart:async';

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
  final _errors = StreamController<Object>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();

  /// 鳴らし始められなかったことにする（ブラウザが自動再生を拒んだ等）。
  void failToStart(Object error) => _errors.add(error);

  /// プログレスバーのテスト用に、位置・長さを流す。
  void emitPosition(Duration d) => _position.add(d);
  void emitDuration(Duration d) => _duration.add(d);

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
  Stream<Object> get onError => _errors.stream;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<Duration?> get durationStream => _duration.stream;

  @override
  Future<void> seek(Duration position) async =>
      calls.add('seek:${position.inMilliseconds}');

  @override
  Future<void> dispose() async => _errors.close();
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

Widget _app(
  List<ListItem> items,
  _FakeHandle handle, {
  void Function()? onLookup,
}) => ProviderScope(
  overrides: [
    audioPlayerHandleProvider.overrideWithValue(handle),
    // Storage に繋がずに URL を返す。
    downloadUrlResolverProvider.overrideWithValue((path) async {
      onLookup?.call();
      return 'https://example.com/$path';
    }),
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

  testWidgets('曲が何曲あっても、知らせは 1 回だけ', (tester) async {
    // **行ごとに知らせを出さない。** 出すと曲の数だけ同じ通知が重なる。
    final handle = _FakeHandle();
    await tester.pumpWidget(
      _app([_fileItem(1), _fileItem(2), _fileItem(3)], handle),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow).first);
    await tester.pump();
    handle.failToStart('NotAllowedError: play() failed');
    await tester.pumpAndSettle();

    expect(find.text('再生できませんでした。もう一度お試しください。'), findsOneWidget);
    expect(find.text('詳細'), findsOneWidget);
  });

  testWidgets('URL の取得に失敗したときも、詳細を読める', (tester) async {
    // 押した処理の中で失敗する経路。鳴らし始めの失敗（下）とは別の道を通る。
    final handle = _FakeHandle();
    await tester.pumpWidget(
      _app(
        [_fileItem(1)],
        handle,
        onLookup: () => throw Exception('firebase_storage/object-not-found'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    expect(find.text('詳細'), findsOneWidget);
    await tester.tap(find.text('詳細'));
    await tester.pumpAndSettle();

    final detail = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(detail.data, contains('object-not-found'));
  });

  testWidgets('鳴らし始められなかったら、原因を読める形で知らせる', (tester) async {
    // **握りつぶさない。** 「再生できませんでした」だけでは、
    // 自動再生を拒まれたのか、音が読めなかったのかを切り分けられない。
    final handle = _FakeHandle();
    await tester.pumpWidget(_app([_fileItem(1)], handle));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();

    handle.failToStart('NotAllowedError: play() failed');
    await tester.pump();

    expect(find.text('再生できませんでした。もう一度お試しください。'), findsOneWidget);

    // 「詳細」から技術的な内容を読める。
    await tester.pumpAndSettle(); // 通知が出きるまで待つ
    await tester.tap(find.text('詳細'));
    await tester.pumpAndSettle();

    final detail = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(detail.data, contains('NotAllowedError'));
  });

  testWidgets('鳴らし始めに失敗したら、再生ボタンに戻す', (tester) async {
    // 鳴っていないのに一時停止のボタンが出たままにしない。
    final handle = _FakeHandle();
    await tester.pumpWidget(_app([_fileItem(1)], handle));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(find.byIcon(Icons.pause), findsOneWidget);

    handle.failToStart('NotAllowedError: play() failed');
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.pause), findsNothing);
  });

  testWidgets('2 度目の再生で URL を取り直さない（間に合わなくなるため）', (tester) async {
    var lookups = 0;
    final handle = _FakeHandle();
    await tester.pumpWidget(
      _app([_fileItem(1)], handle, onLookup: () => lookups++),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();

    expect(lookups, 1, reason: '2 度目は覚えた URL を使う');
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

  testWidgets('1 曲目を再生→停止→2 曲目を再生すると、正しい順で頼む（2026-08-23）', (
    tester,
  ) async {
    // 依頼者の報告「1 曲目を再生→停止した後に別の曲を再生すると
    // 1 曲目の途中から再生される」の切り分け。
    //
    // **ここで守るのはコントローラー側の呼び出し順序だけ。** 実際の
    // バグは just_audio 本体（`JustAudioHandle`）側の競合にあり、
    // `AudioPlayerHandle` を差し替えたこのテストでは再現できない
    // （音を鳴らす部分はテストで確かめられないため、ここに閉じ込めて
    // ある——`audio_player_handle.dart` 冒頭の注記）。
    // このテストは「コントローラーが正しい相手・正しい順で頼んでいる」
    // ことを固定し、そちらが原因ではないことを見張り続ける。
    final handle = _FakeHandle();
    await tester.pumpWidget(_app([_fileItem(1), _fileItem(2)], handle));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.play_arrow).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();
    // 停止後は 1・2 曲目とも play_arrow が出るので、2 曲目（後ろの行）を選ぶ。
    await tester.tap(find.byIcon(Icons.play_arrow).at(1));
    await tester.pump();

    expect(handle.calls, [
      'playFrom:https://example.com/lists/$_listId/items/item-1/take.mp3',
      'stop',
      'playFrom:https://example.com/lists/$_listId/items/item-2/take.mp3',
    ]);
  });

  group('プログレスバー（曲一覧・2026-08-24）', () {
    testWidgets('止まっている行には出さない', (tester) async {
      await tester.pumpWidget(_app([_fileItem(1)], _FakeHandle()));
      await tester.pumpAndSettle();

      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('再生しても、長さが分かるまでは出さない', (tester) async {
      final handle = _FakeHandle();
      await tester.pumpWidget(_app([_fileItem(1)], handle));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      handle.emitPosition(const Duration(seconds: 3));
      await tester.pump();

      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('長さが分かると、曲名の下にバーと時刻が出る', (tester) async {
      final handle = _FakeHandle();
      await tester.pumpWidget(_app([_fileItem(1)], handle));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      handle.emitDuration(const Duration(minutes: 3, seconds: 45));
      handle.emitPosition(const Duration(seconds: 30));
      await tester.pump();

      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('0:30'), findsOneWidget);
      expect(find.text('3:45'), findsOneWidget);
    });

    testWidgets('バーを動かして指を離すと、その位置へシークを頼む', (tester) async {
      final handle = _FakeHandle();
      await tester.pumpWidget(_app([_fileItem(1)], handle));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      handle.emitDuration(const Duration(minutes: 4));
      handle.emitPosition(Duration.zero);
      await tester.pump();

      // 中央付近までドラッグ（値そのものより「シークが頼まれること」を確かめる）。
      await tester.drag(find.byType(Slider), const Offset(100, 0));
      await tester.pump();

      expect(handle.calls.any((c) => c.startsWith('seek:')), isTrue);
    });

    testWidgets('停止すると、バーも消える', (tester) async {
      final handle = _FakeHandle();
      await tester.pumpWidget(_app([_fileItem(1)], handle));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      handle.emitDuration(const Duration(minutes: 3));
      handle.emitPosition(const Duration(seconds: 10));
      await tester.pump();
      expect(find.byType(Slider), findsOneWidget);

      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump();

      expect(find.byType(Slider), findsNothing);
    });
  });
}
