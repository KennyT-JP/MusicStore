/// Web から音源のダウンロードを外す（docs/DOWNLOAD-DESIGN.md 7 節・論点 2）
///
/// **逆向きの見張り。** ここが守るのは「あること」ではなく**「無いこと」**で、
/// 導線が復活したら赤になる。
///
/// | | 外す | 残す |
/// | --- | --- | --- |
/// | **音源ファイル**（`isPlayableAudio` が true） | ダウンロードのボタン | **ストリーミング再生** |
/// | **音源以外のファイル**（楽譜 PDF・zip など） | — | **従来どおり開ける**（論点 2） |
/// | **URL の項目** | — | 従来どおり外部サイトへ |
///
/// ## 引き金は「Android の一般公開」（7.3・論点 17）
///
/// **日付では決めない。期限も切らない。** そのため、外したあとの姿を
/// **外す前に**確かめられる形にしてある（`webAudioDownloadRemovedProvider`）。
/// これが無いと、**引き金を引いた日に初めて動きを見る**ことになる。
///
/// 3 つの状態をすべて固定する。
///
/// | 状態 | 何を守るか |
/// | --- | --- |
/// | アプリ（iOS / Android） | 「端末に保存」が継ぐ。旧ボタンを二重に出さない |
/// | Web・引き金前 | **まだ外さない**（7.3 手順 1）。告知だけを出す |
/// | Web・引き金後 | **音源のダウンロードの導線が 1 つも無い** |
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/models/list_item.dart';
import 'package:music_list_app/data/models/music_list.dart';
import 'package:music_list_app/domain/local_date.dart';
import 'package:music_list_app/domain/role.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/providers/download_provider.dart';
import 'package:music_list_app/providers/playback_provider.dart';
import 'package:music_list_app/ui/downloads/download_support.dart';
import 'package:music_list_app/ui/screens/list_detail_screen.dart';

import 'support/downloads_harness.dart';

const _listId = 'list-1';

/// 楽譜 PDF。**論点 2 で「従来どおり開ける」と決まっている。**
final _pdf = ListItem(
  id: 'item-pdf',
  seq: 2,
  itemDate: LocalDate.tryParse('2026-08-01')!,
  kind: ItemKind.file,
  file: const ItemFile(
    storagePath: 'lists/$_listId/items/item-pdf/1755200000000-score.pdf',
    fileName: 'score.pdf',
    sizeBytes: 2048,
    contentType: 'application/pdf',
  ),
  title: '楽譜',
  createdBy: 'u1',
  registrantDisplayName: '山田',
  status: ContentStatus.active,
);

final _url = ListItem(
  id: 'item-url',
  seq: 3,
  itemDate: LocalDate.tryParse('2026-08-01')!,
  kind: ItemKind.url,
  url: 'https://example.com/3',
  title: '参考動画',
  createdBy: 'u1',
  registrantDisplayName: '山田',
  status: ContentStatus.active,
);

Widget _app({required bool downloadsSupported, required bool removed}) =>
    ProviderScope(
      overrides: [
        audioDownloadSupportedProvider.overrideWithValue(downloadsSupported),
        webAudioDownloadRemovedProvider.overrideWithValue(removed),
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
        )).overrideWith(
          (ref) => Stream.value([
            audioItem(id: 'item-1', seq: 1, title: '一本目'),
            _pdf,
            _url,
          ]),
        ),
        listAccessProvider(_listId).overrideWith(
          (ref) =>
              const ListAccess(isSiteAdmin: false, role: ListRole.readOnly),
        ),
        listStatsProvider(_listId).overrideWith((ref) => Stream.value(null)),
        listMembersProvider(
          _listId,
        ).overrideWith((ref) => Stream.value(const [])),
        isPremiumProvider.overrideWithValue(const AsyncData(true)),
        // 実効プレミアムはサイト管理者も含むが、ここでは premium 側で true を
        // 与えるので管理者の軸は false 固定でよい（仕様書 4.1）。
        isSiteAdminProvider.overrideWith((ref) => false),
        downloadsProvider.overrideWith(() => FakeDownloadsController()),
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

/// 「端末に保存」（新しいほう）。
final _saveToDevice = find.byTooltip('端末に保存');

/// これまでの「ファイルをダウンロード」（URL を開くほう）。
final _legacyDownload = find.byIcon(Icons.download_outlined);

void main() {
  group('Web・引き金を引いたあと（7.1）', () {
    testWidgets('音源のダウンロードの導線が 1 つも無い', (tester) async {
      await tester.pumpWidget(_app(downloadsSupported: false, removed: true));
      await tester.pumpAndSettle();

      // 新しい「端末に保存」は Web にそもそも出ない（6.5）。
      expect(_saveToDevice, findsNothing);
      // これまでの「ファイルをダウンロード」は、**音源からだけ**消える。
      // 残っている 1 つは PDF の行（下のテストで確かめる）。
      expect(_legacyDownload, findsOneWidget);

      // 音源の行そのものは残る（曲は一覧から消えない）。
      expect(find.text('一本目'), findsOneWidget);
    });

    testWidgets('ストリーミング再生は残る（7.1）', (tester) async {
      await tester.pumpWidget(_app(downloadsSupported: false, removed: true));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('楽譜 PDF は従来どおり落とせる（論点 2）', (tester) async {
      // **これを書かないと、全部落とせなくなったと受け取られる。**
      await tester.pumpWidget(_app(downloadsSupported: false, removed: true));
      await tester.pumpAndSettle();

      final row = find.ancestor(
        of: find.text('楽譜'),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: row, matching: _legacyDownload),
        findsOneWidget,
        reason: '音源以外のファイルは、従来どおりダウンロードできること（論点 2）',
      );
    });

    testWidgets('URL の項目は従来どおり外部サイトへ', (tester) async {
      await tester.pumpWidget(_app(downloadsSupported: false, removed: true));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    });

    testWidgets('ボタンがあった場所を空白にしない（7.3）', (tester) async {
      // **消えた場所に何も無いと、壊れたようにしか見えない。**
      await tester.pumpWidget(_app(downloadsSupported: false, removed: true));
      await tester.pumpAndSettle();

      expect(find.text('オフラインで聴くには、アプリをお使いください。'), findsOneWidget);
    });
  });

  group('Web・引き金を引く前（7.3 手順 1）', () {
    testWidgets('ボタンはまだ外さない（代わりが無いまま消さない）', (tester) async {
      // **順序が要点**（7.3）。告知 → iOS 公開 → Android 一般公開 → 外す。
      // iOS が出ただけで外すと、Android の利用者には代わりが 1 つも無い。
      await tester.pumpWidget(_app(downloadsSupported: false, removed: false));
      await tester.pumpAndSettle();

      // 音源と PDF の 2 つ。
      expect(_legacyDownload, findsNWidgets(2));
    });

    testWidgets('外すより先に告知を出す（7.3）', (tester) async {
      await tester.pumpWidget(_app(downloadsSupported: false, removed: false));
      await tester.pumpAndSettle();

      expect(find.text('ブラウザからの音源のダウンロードについて'), findsOneWidget);
      // **「終了します」を先に、「できること」をすぐ後ろに。**
      expect(find.textContaining('今後終了します'), findsOneWidget);
      expect(find.textContaining('ブラウザでそのまま再生できます'), findsOneWidget);
      expect(
        find.textContaining('楽譜やその他のファイルは、これまでどおりダウンロードできます'),
        findsOneWidget,
      );
    });

    testWidgets('告知は閉じられる（7.3）', (tester) async {
      await tester.pumpWidget(_app(downloadsSupported: false, removed: false));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('閉じる'));
      await tester.pumpAndSettle();

      expect(find.text('ブラウザからの音源のダウンロードについて'), findsNothing);
    });

    testWidgets('Web には「端末に保存」を出さない（6.5）', (tester) async {
      await tester.pumpWidget(_app(downloadsSupported: false, removed: false));
      await tester.pumpAndSettle();

      expect(_saveToDevice, findsNothing);
    });
  });

  group('アプリ（iOS / Android）', () {
    testWidgets('「端末に保存」が旧ボタンの役目を継ぐ', (tester) async {
      await tester.pumpWidget(_app(downloadsSupported: true, removed: false));
      await tester.pumpAndSettle();

      expect(_saveToDevice, findsOneWidget);
      // **同じ画面に似た操作を 2 つ並べない。** 残るのは PDF の 1 つだけ。
      expect(_legacyDownload, findsOneWidget);
    });

    testWidgets('告知は出さない（アプリには外すものが無い）', (tester) async {
      await tester.pumpWidget(_app(downloadsSupported: true, removed: false));
      await tester.pumpAndSettle();

      expect(find.text('ブラウザからの音源のダウンロードについて'), findsNothing);
    });
  });
}
