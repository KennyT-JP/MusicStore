/// ダウンロード済み画面と、残り日数の帯（docs/DOWNLOAD-DESIGN.md 6.1・論点 21）
///
/// **帯の判定そのもの**（`OfflineAccessPolicy.band` / `remainingDays`）は
/// `test/domain/offline_access_test.dart` が境界まで固定している。
/// ここで確かめるのは**画面がその判定を通っていて、段が正しく切り替わるか**
/// である（監査 S8「テストがあることと、守られていることは別」）。
///
/// | 最終確認からの経過 | 残り | 帯 |
/// | --- | --- | --- |
/// | 22 日 | 8 日 | **出さない** |
/// | 23 日 | **7 日** | 予告（ここが境界） |
/// | 24 日 | 6 日 | 予告 |
/// | 30 日以上 | 0 日 | **停止**（予告ではない） |
/// | 一度も確認できていない | 0 日 | 停止 |
///
/// **`DateTime.now()` との差で判定するので、テストは分単位の余白を取る。**
/// 「23 日ちょうど」を渡すと、プロバイダが動くまでの数ミリ秒で
/// 残りが 6 日 23 時間 59 分になり、切り捨てで 6 になる。
/// **境界そのものは純関数側で固定してあり、ここでは段の切り替わりを見る。**
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/download_index.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/download_provider.dart';
import 'package:music_list_app/providers/playback_provider.dart';
import 'package:music_list_app/ui/screens/downloads_screen.dart';

import 'support/downloads_harness.dart';

Widget _wrap(DownloadIndex index) => ProviderScope(
  overrides: [
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
    home: const DownloadsScreen(),
  ),
);

/// 最終確認から [elapsed] だけ経った目録。
DownloadIndex _verified(
  Duration elapsed, {
  List<DownloadedItem> items = const [],
}) => DownloadIndex(
  lastVerifiedAt: DateTime.now().subtract(elapsed),
  items: items,
);

void main() {
  group('残り日数の帯（6.1・論点 21）', () {
    testWidgets('残り 8 日（22 日経過）→ 帯を出さない', (tester) async {
      await tester.pumpWidget(
        _wrap(_verified(const Duration(days: 22) - const Duration(minutes: 1))),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('あと'), findsNothing);
      expect(find.textContaining('オフラインで聴ける期間'), findsNothing);
    });

    testWidgets('残り 7 日 → 予告の帯を出す（ここが境界）', (tester) async {
      await tester.pumpWidget(
        _wrap(_verified(const Duration(days: 23) - const Duration(minutes: 1))),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('あと 7 日でオフライン再生が止まります。一度インターネットに接続してください。'),
        findsOneWidget,
      );
    });

    testWidgets('残り 6 日 → まだ予告（帯が消えない）', (tester) async {
      await tester.pumpWidget(
        _wrap(_verified(const Duration(days: 24) - const Duration(minutes: 1))),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('あと 6 日'), findsOneWidget);
    });

    testWidgets('残り 0 日でも、まだ止まっていなければ予告のまま', (tester) async {
      // **「あと 0 日」を出すことを許す**（8.1）。残り 12 時間を
      // 「あと 1 日」と切り上げると、その表示のまま止まる。
      await tester.pumpWidget(
        _wrap(_verified(const Duration(days: 29, hours: 23, minutes: 58))),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('あと 0 日'), findsOneWidget);
      expect(find.textContaining('オフラインで聴ける期間'), findsNothing);
    });

    testWidgets('30 日を過ぎたら停止の帯に変わり、ファイルが残ると書く（論点 13b）', (tester) async {
      await tester.pumpWidget(
        _wrap(_verified(const Duration(days: 30, minutes: 1))),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('あと'), findsNothing);
      // **「削除しました」とは書かない。** 消していないものを消したと言わない。
      expect(find.textContaining('端末のファイルは残っています'), findsOneWidget);
    });

    testWidgets('一度も確認できていなければ停止の帯（安全側）', (tester) async {
      await tester.pumpWidget(_wrap(const DownloadIndex()));
      await tester.pumpAndSettle();

      expect(find.textContaining('オフラインで聴ける期間'), findsOneWidget);
    });
  });

  group('一覧（6.1・論点 8）', () {
    testWidgets('何も無ければ、保存の仕方を書いて終わる', (tester) async {
      await tester.pumpWidget(_wrap(const DownloadIndex()));
      await tester.pumpAndSettle();

      expect(find.text('端末に保存した曲はまだありません。'), findsOneWidget);
    });

    testWidgets('リストごとにまとめ、曲名・録音日・大きさを出す', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _verified(
            const Duration(days: 1),
            items: [
              downloadedItem(
                itemId: 'b',
                seq: 2,
                listName: 'バンド練習 2026',
                title: '夏の思い出',
                artist: 'サザン',
                date: '2026-08-02',
                localBytes: 41234567,
              ),
              downloadedItem(
                itemId: 'a',
                seq: 1,
                listName: 'バンド練習 2026',
                title: '練習 1 本目',
                date: '2026-08-01',
                localBytes: 10485760,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // どのリストのものか（論点 8）と、そのリストの合計。
      expect(find.text('バンド練習 2026'), findsOneWidget);
      expect(find.text('49.3 MB（2 曲）'), findsOneWidget);

      // 曲名・録音日・端末上の大きさ。
      expect(find.text('練習 1 本目'), findsOneWidget);
      expect(find.text('2026-08-01 · 10.0 MB'), findsOneWidget);
      expect(find.text('2026-08-02 · サザン · 39.3 MB'), findsOneWidget);
    });

    testWidgets('リスト内は seq 順に並ぶ', (tester) async {
      await tester.pumpWidget(
        _wrap(
          _verified(
            const Duration(days: 1),
            items: [
              downloadedItem(itemId: 'b', seq: 2, title: '二番目'),
              downloadedItem(itemId: 'a', seq: 1, title: '一番目'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final first = tester.getTopLeft(find.text('一番目')).dy;
      final second = tester.getTopLeft(find.text('二番目')).dy;
      expect(first, lessThan(second));
    });

    testWidgets('Firestore を 1 つも読まずに開ける（圏外で真っ白にしない）', (tester) async {
      // **この画面は `index.json` だけで描ける**（6.1）。
      // リストや項目のプロバイダを 1 つも差し替えずに描けることが、
      // Firestore を読んでいないことの証拠になる。
      await tester.pumpWidget(
        _wrap(
          _verified(
            const Duration(days: 1),
            items: [downloadedItem(itemId: 'a')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('練習 1 本目'), findsOneWidget);
    });
  });
}
