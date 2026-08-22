/// 曲ごとのダウンロードボタンの出し分け（docs/DOWNLOAD-DESIGN.md 6.5）
///
/// **守るのは 6.5 の表そのもの。**
///
/// | 相手 | 見せ方 |
/// | --- | --- |
/// | プレミアムでない人 | **薄く出す。** 押すと案内＋クーポン入力への導線（論点 19） |
/// | 閲覧者（viewer） | **出さない**（論点 9） |
/// | サイト管理者 | **出す**（メンバーでなくても・全リスト／仕様書 4.2） |
/// | 判定が届く前 | **どちらも出さない** |
/// | Web で開いている人 | **出さない**（7 節の告知に置き換える） |
///
/// **2 つの「出さない」は、守るものが違う。**
///
/// | 行 | 何を防ぐか |
/// | --- | --- |
/// | 閲覧者に出さない | 契約しても使えないものを押させること |
/// | プレミアムでない人には**出す** | **行きすぎた修正。** 「使えない人には出さない」と読んで隠すと、契約する理由が伝わらなくなる |
/// | サイト管理者には**出す** | **行きすぎた修正。** 「メンバーでないと不可」と読んで隠すと、全リストを扱える権限（4.2）と食い違う |
///
/// 判定そのもの（`Permissions.canDownload`）は
/// `test/domain/permissions_test.dart` が固定している。ここで確かめるのは
/// **画面がその判定を通っているか**である（監査 S8「テストがあることと、
/// 守られていることは別」）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/models/list_item.dart';
import 'package:music_list_app/domain/download_index.dart';
import 'package:music_list_app/domain/local_date.dart';
import 'package:music_list_app/domain/role.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/providers/download_provider.dart';
import 'package:music_list_app/ui/downloads/download_support.dart';
import 'package:music_list_app/ui/widgets/download_button.dart';

import 'support/downloads_harness.dart';

const _listId = 'list-1';

ListItem _audio({String id = 'item-1'}) => ListItem(
  id: id,
  seq: 1,
  itemDate: LocalDate.tryParse('2026-08-01')!,
  kind: ItemKind.file,
  file: ItemFile(
    storagePath: 'lists/$_listId/items/$id/1755200000000-take3.wav',
    fileName: 'take3.wav',
    sizeBytes: 41234567,
    contentType: 'audio/wav',
  ),
  title: '練習 1 本目',
  createdBy: 'u1',
  registrantDisplayName: '山田',
  status: ContentStatus.active,
);

/// 音源ではないファイル。**落とす対象ではない**（論点 5）。
ListItem _pdf() => ListItem(
  id: 'item-pdf',
  seq: 2,
  itemDate: LocalDate.tryParse('2026-08-01')!,
  kind: ItemKind.file,
  file: const ItemFile(
    storagePath: 'lists/$_listId/items/item-pdf/1755200000000-score.pdf',
    fileName: 'score.pdf',
    sizeBytes: 1024,
    contentType: 'application/pdf',
  ),
  createdBy: 'u1',
  registrantDisplayName: '山田',
  status: ContentStatus.active,
);

Widget _wrap({
  required ListAccess access,
  required AsyncValue<bool> premium,
  DownloadIndex index = const DownloadIndex(),
  bool downloadsSupported = true,
  ListItem? item,
}) => ProviderScope(
  overrides: [
    listAccessProvider(_listId).overrideWith((ref) => access),
    // `premium` は実効プレミアム（`isPremiumOrAdminProvider`）に効かせる。
    // サイト管理者の軸は listAccessProvider 側で与えるので、ここは false 固定
    // にして「渡した premium がそのまま実効値になる」形にする（仕様書 4.1）。
    isPremiumProvider.overrideWithValue(premium),
    isSiteAdminProvider.overrideWith((ref) => false),
    downloadsProvider.overrideWith(() => FakeDownloadsController(index)),
    audioDownloadSupportedProvider.overrideWithValue(downloadsSupported),
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
    home: Scaffold(
      body: ItemDownloadButton(
        listId: _listId,
        listName: '練習音源',
        item: item ?? _audio(),
      ),
    ),
  ),
);

/// 「使える」ボタン（濃く出ていて、押すと落とし始めるほう）。
final _usable = find.byTooltip('端末に保存');

/// 「薄い」ボタン（押すと案内が出るほう）。
final _gated = find.byTooltip('オフライン保存はプレミアムの機能です');

void main() {
  group('6.5 の出し分け', () {
    testWidgets('メンバーでプレミアム → 使えるボタンを出す', (tester) async {
      await tester.pumpWidget(
        _wrap(
          access: const ListAccess(isSiteAdmin: false, role: ListRole.readOnly),
          premium: const AsyncData(true),
        ),
      );
      await tester.pumpAndSettle();

      expect(_usable, findsOneWidget);
      expect(_gated, findsNothing);
    });

    testWidgets('プレミアムでない人 → 薄く出し、押すと案内を出す（論点 19）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          access: const ListAccess(isSiteAdmin: false, role: ListRole.readOnly),
          premium: const AsyncData(false),
        ),
      );
      await tester.pumpAndSettle();

      // **隠さない。** 存在を知らせないと、契約する理由も伝わらない。
      expect(_gated, findsOneWidget);
      expect(_usable, findsNothing);

      await tester.tap(_gated);
      await tester.pumpAndSettle();

      expect(find.text('オフライン保存はプレミアムの機能です'), findsWidgets);
      // **クーポン入力への導線を必ず置く**（論点 19）。
      expect(find.widgetWithText(FilledButton, 'クーポンを入力'), findsOneWidget);
    });

    testWidgets('閲覧者（viewer）→ 出さない（論点 9）', (tester) async {
      // 共有リンクが回った先の人が端末に音源を残す経路を塞ぐ。
      // **プレミアムを契約しても使えない**ので、押せるものを見せない。
      await tester.pumpWidget(
        _wrap(
          access: const ListAccess(
            isSiteAdmin: false,
            role: null,
            isViewer: true,
          ),
          premium: const AsyncData(true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('サイト管理者はメンバーでなくても出す（全リスト／仕様書 4.2）', (tester) async {
      // サイト管理者は「全リストの項目を扱える」ので、参加していないリストでも
      // ダウンロードボタンを出す（旧・論点 18 を上書き）。サーバーの
      // verifyDownloadAccess も全リストを `member` で返すため、落とした後も残る。
      await tester.pumpWidget(
        _wrap(
          access: const ListAccess(isSiteAdmin: true, role: null),
          premium: const AsyncData(true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('サイト管理者でもメンバーなら出す（行きすぎた修正の見張り）', (tester) async {
      // **外すのは例外であって、サイト管理者その人ではない**（8.1）。
      // `!access.isSiteAdmin && …` と書くと、ここだけが落ちる。
      await tester.pumpWidget(
        _wrap(
          access: const ListAccess(isSiteAdmin: true, role: ListRole.readOnly),
          premium: const AsyncData(true),
        ),
      );
      await tester.pumpAndSettle();

      expect(_usable, findsOneWidget);
    });

    testWidgets('判定が届く前は、どちらも出さない', (tester) async {
      // 読み込み中に「使えない」を確定表示すると、プレミアムの人に
      // 一瞬それが見える（app_providers.dart の注記）。
      await tester.pumpWidget(
        _wrap(
          access: const ListAccess(isSiteAdmin: false, role: ListRole.readOnly),
          premium: const AsyncLoading(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('Web では出さない（6.5）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          access: const ListAccess(isSiteAdmin: false, role: ListRole.readOnly),
          premium: const AsyncData(true),
          downloadsSupported: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(IconButton), findsNothing);
    });
  });

  group('6.2 のボタンの状態', () {
    testWidgets('保存済みならチェックの付いたアイコンに変わる', (tester) async {
      await tester.pumpWidget(
        _wrap(
          access: const ListAccess(isSiteAdmin: false, role: ListRole.readOnly),
          premium: const AsyncData(true),
          index: DownloadIndex(items: [downloadedItem(itemId: 'item-1')]),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.offline_pin), findsOneWidget);
      expect(find.byTooltip('端末に保存済み'), findsOneWidget);
      expect(_usable, findsNothing);
    });

    testWidgets('押すと「端末から削除しますか」を出し、曲が消えないことを書く（2.1）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          access: const ListAccess(isSiteAdmin: false, role: ListRole.readOnly),
          premium: const AsyncData(true),
          index: DownloadIndex(items: [downloadedItem(itemId: 'item-1')]),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.offline_pin));
      await tester.pumpAndSettle();

      // **「ダウンロードしたファイルを削除しました」ではなく、
      // 残っているものを具体的に書く**（2.1）。
      expect(find.textContaining('曲もリストも消えません'), findsOneWidget);
    });

    testWidgets('音源以外のファイル（PDF）には出さない（論点 5）', (tester) async {
      await tester.pumpWidget(
        _wrap(
          access: const ListAccess(isSiteAdmin: false, role: ListRole.readOnly),
          premium: const AsyncData(true),
          item: _pdf(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('「URL を開く」と同じアイコンを使わない（6.2）', (tester) async {
      // `Icons.download_outlined` は item_external_action.dart が
      // 「URL を開く」の意味で使っている。**同じ絵で違う動きをさせない。**
      await tester.pumpWidget(
        _wrap(
          access: const ListAccess(isSiteAdmin: false, role: ListRole.readOnly),
          premium: const AsyncData(true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.download_outlined), findsNothing);
    });
  });
}
