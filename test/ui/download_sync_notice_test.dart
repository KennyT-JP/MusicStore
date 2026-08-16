/// 同期の結果を、黙って済ませない（docs/DOWNLOAD-DESIGN.md 4.4）
///
/// > **画面に何が起きたかを出します**——黙って消えると、
/// > 利用者は「アプリが勝手に消した」と受け取ります。
///
/// **端末の中身が変わったのに何も言わない**のが、ここで防ぎたいこと。
/// 起動時の同期（4.4）は利用者の操作なしに走るので、
/// **知らせが無いと、次に開いたときに「曲が減っている」だけが残る。**
library;

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/repositories/download_repository.dart';
import 'package:music_list_app/domain/download_index.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/ui/downloads/download_sync_notice.dart';

import 'support/downloads_harness.dart';

/// 画面を組まずに文言を作るための l10n。
Future<AppL10n> _l10n(WidgetTester tester) async {
  late AppL10n l10n;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('ja'),
      home: Builder(
        builder: (context) {
          l10n = AppL10n.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return l10n;
}

DownloadSyncReport _report({
  List<DownloadedItem> removed = const [],
  List<DownloadedItem> replaced = const [],
  List<DownloadedItem> failed = const [],
}) => DownloadSyncReport(
  index: const DownloadIndex(),
  removed: removed,
  replaced: replaced,
  failed: failed,
);

void main() {
  testWidgets('何も起きていなければ、黙っている', (tester) async {
    final l10n = await _l10n(tester);
    expect(describeDownloadSync(l10n, _report()), isNull);
  });

  testWidgets('1 曲消えたら、曲名を出して知らせる（4.4）', (tester) async {
    final l10n = await _l10n(tester);
    final message = describeDownloadSync(
      l10n,
      _report(
        removed: [downloadedItem(itemId: 'a', title: '夏の思い出')],
      ),
    );

    expect(message, isNotNull, reason: '黙って消すと「アプリが勝手に消した」になります（4.4）');
    // **どれが消えたのか分かること。** 件数だけでは分からない。
    expect(message, contains('夏の思い出'));
    expect(message, contains('元が削除された'));
  });

  testWidgets('曲名が無ければファイル名で伝える', (tester) async {
    final l10n = await _l10n(tester);
    final message = describeDownloadSync(
      l10n,
      _report(removed: [downloadedItem(itemId: 'a', title: null)]),
    );

    expect(message, contains('take3.wav'));
  });

  testWidgets('複数なら件数にまとめる（通知に収まらないため）', (tester) async {
    final l10n = await _l10n(tester);
    final message = describeDownloadSync(
      l10n,
      _report(
        removed: [
          downloadedItem(itemId: 'a', title: 'あ'),
          downloadedItem(itemId: 'b', title: 'い'),
        ],
      ),
    );

    expect(message, contains('2 曲'));
  });

  testWidgets('落とし直し（差し替え）も知らせる（論点 11）', (tester) async {
    final l10n = await _l10n(tester);
    final message = describeDownloadSync(
      l10n,
      _report(replaced: [downloadedItem(itemId: 'a')]),
    );

    expect(message, isNotNull);
    expect(message, contains('差し替えられた'));
  });

  testWidgets('削除と差し替えが同時に起きたら、両方伝える', (tester) async {
    final l10n = await _l10n(tester);
    final message = describeDownloadSync(
      l10n,
      _report(
        removed: [downloadedItem(itemId: 'a', title: '消えた曲')],
        replaced: [downloadedItem(itemId: 'b')],
      ),
    );

    expect(message, contains('消えた曲'));
    expect(message, contains('差し替えられた'));
  });

  testWidgets('落とし直しの失敗は知らせない（利用者から見て何も変わらない）', (tester) async {
    // **古いほうが残っていて聴ける**（4.4）。次の起動でもう一度試される。
    final l10n = await _l10n(tester);
    expect(
      describeDownloadSync(
        l10n,
        _report(failed: [downloadedItem(itemId: 'a')]),
      ),
      isNull,
    );
  });
}
