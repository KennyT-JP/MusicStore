/// Web からダウンロードを外す告知の見張り（docs/DOWNLOAD-DESIGN.md 7.3・論点 17）
///
/// **引き金は「Android の一般公開」。日付では決めません。期限も切りません。**
///
/// > **「〇月〇日に終了します」と告知して、その日に Android が出ていないと、
/// > 告知そのものを取り消すことになります。**
///
/// Google Play の一般公開には**クローズドテスト要件（12 人 × 14 日）**があり、
/// 2026-08-16 時点で 12 人の見通しは立っていません。**日程が読めない以上、
/// 日付を書いた時点で嘘になり得ます。**
///
/// 文面は人が書くもので、あとから「そろそろ日付を入れよう」と足されやすい。
/// **機械で止めます。**
///
/// 併せて 2 つ固定します。
///
/// | 何を | なぜ |
/// | --- | --- |
/// | 「楽譜やその他のファイルは従来どおり」を必ず書く | 書かないと**全部落とせなくなった**と受け取られる（論点 2） |
/// | 引き金を決める場所は 1 つだけ | 2 つあると、片方だけ引いたときに画面ごとに動きが違う |
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/repo_files.dart';

/// 告知に出る文言（`lib/l10n/app_{ja,en}.arb` のキー）。
const _noticeKeys = [
  'webDownloadNoticeTitle',
  'webDownloadNoticeBody1',
  'webDownloadNoticeBody2',
  'webDownloadNoticeBody3',
  'webDownloadReplacement',
];

/// 「日付を書いた」と見なす形。
///
/// **和暦・西暦・スラッシュ・英語の月名まで見る。** 1 つでも漏らすと、
/// そこだけ通り抜ける。
final _datePatterns = <String, RegExp>{
  '西暦の年': RegExp(r'\b(19|20)\d{2}\b'),
  '年月日（日本語）': RegExp(r'\d+\s*月\s*\d+\s*日'),
  '年（日本語）': RegExp(r'\d+\s*年'),
  'ISO の日付': RegExp(r'\d{4}-\d{2}-\d{2}'),
  'スラッシュ区切り': RegExp(r'\d{1,4}/\d{1,2}/\d{1,4}'),
  '英語の月名': RegExp(
    r'\b(January|February|March|April|May|June|July|August|'
    r'September|October|November|December)\b',
  ),
};

Map<String, dynamic> _arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
        as Map<String, dynamic>;

/// マニュアルの告知の段落（タグを外した文章）。
String _manualNotice(String lang) {
  final html = File('docs/manual/$lang.html').readAsStringSync();
  final marker = lang == 'ja'
      ? 'ブラウザからの音源のダウンロードについて'
      : 'About downloading audio from your browser';
  final start = html.indexOf(marker);
  expect(
    start,
    greaterThan(-1),
    reason: 'docs/manual/$lang.html に告知がありません（7.3）',
  );
  final end = html.indexOf('</div>', start);
  return html
      .substring(start, end)
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

void main() {
  group('告知に日付を書かない（論点 17）', () {
    for (final lang in ['ja', 'en']) {
      test('$lang: 画面の文言に日付が無い', () {
        final arb = _arb(lang);
        for (final key in _noticeKeys) {
          final text = arb[key] as String?;
          expect(text, isNotNull, reason: '$key が $lang に無い');
          _expectNoDate(text!, '$lang の $key');
        }
      });

      test('$lang: 使い方ページの告知にも日付が無い', () {
        _expectNoDate(_manualNotice(lang), 'docs/manual/$lang.html の告知');
      });
    }

    test('見張りが効いていること（日付を書けば拾える）', () {
      // **この見張り自身を試す**（監査 第4回：6 つの見張り全部に抜け道があった）。
      const samples = [
        '2026 年 12 月 1 日に終了します',
        'ends on 2026-12-01',
        'ends in December',
        '2026/12/01 に終了します',
      ];
      for (final sample in samples) {
        expect(
          _datePatterns.values.any((p) => p.hasMatch(sample)),
          isTrue,
          reason: '「$sample」を拾えていません',
        );
      }
    });
  });

  group('文面の要件（7.3）', () {
    test('ja: 「楽譜やその他のファイルは従来どおり」を書いている（論点 2）', () {
      final body = _arb('ja')['webDownloadNoticeBody2'] as String;
      expect(body, contains('楽譜'));
      expect(body, contains('これまでどおりダウンロードできます'));
    });

    test('en: 同じことを書いている', () {
      final body = _arb('en')['webDownloadNoticeBody2'] as String;
      expect(body.toLowerCase(), contains('sheet music'));
      expect(body.toLowerCase(), contains('downloaded as before'));
    });

    test('「終了します」が先、「できること」がすぐ後ろ', () {
      // 順序が逆だと、何が変わるのか読み取れない（7.3）。
      final ja = _arb('ja');
      expect(ja['webDownloadNoticeBody1'] as String, contains('終了します'));
      expect(ja['webDownloadNoticeBody2'] as String, contains('再生できます'));
    });

    test('ストリーミング再生が残ることを書いている（7.1）', () {
      expect(
        _arb('ja')['webDownloadNoticeBody2'] as String,
        contains('ブラウザでそのまま再生できます'),
      );
    });
  });

  group('引き金は 1 か所（7.3・10 節の危険 6）', () {
    test('kWebAudioDownloadRemoved を決めているのは 1 ファイルだけ', () {
      final owners = filesUnder('lib')
          .where((e) => !e.path.startsWith('lib/l10n/'))
          .where(
            (e) => e.file.readAsStringSync().contains(
              'const bool kWebAudioDownloadRemoved',
            ),
          )
          .map((e) => e.path)
          .toList();

      expect(
        owners,
        ['lib/ui/downloads/download_support.dart'],
        reason:
            '引き金が 2 か所にあると、片方だけ引いたときに画面ごとに動きが'
            '違います（7.3 の順序が守れなくなります）。',
      );
    });

    test('引き金はまだ引かれていない（7.3 の手順 1〜3 が済んでいない）', () {
      // **iOS が出ただけで外さないこと**（10 節の危険 6）。
      // Google Play の一般公開が済んだら、ここを true にして
      // このテストを「引いた」側へ書き換える。
      final source = File(
        'lib/ui/downloads/download_support.dart',
      ).readAsStringSync();
      expect(
        source,
        contains('const bool kWebAudioDownloadRemoved = false;'),
        reason:
            'Android の一般公開が済むまでは false のままにしてください（7.3）。\n'
            '順序は「告知 → iOS 公開 → Android 一般公開 → 外す」です。\n'
            'iOS だけ出た時点で外すと、Android の利用者には代わりが'
            '1 つも無いまま機能が消えます。',
      );
    });

    test('kIsWeb を画面に散らしていない（7.2）', () {
      // **「Web かどうか」の分岐は lib/platform/ の形に揃える。**
      //
      // **例外を増やすときは、根拠を添えること**
      // （`test/domain/async_provider_read_test.dart` の `_alwaysResolved`
      // と同じ決まり）。「たぶん要る」で足すと、この見張りは何も守らなくなる。
      const allowed = {
        // 共有 URL の土台（3.3 / 5-8-1）。**ダウンロードとは無関係で、
        // 7.2 より前からある。** Web では実際に開いている URL（`Uri.base`）
        // を使い、モバイルでは設定の配信元を使う——「Web でないときの
        // 代わりの実装」ではなく「Web でだけ意味を持つ値」なので、
        // 条件付き取り込みで分ける対象ではない。
        'lib/ui/share_url.dart',
      };

      final offenders = filesUnder('lib/ui')
          .where((e) => !allowed.contains(e.path))
          .where((e) => e.file.readAsStringSync().contains('kIsWeb'))
          .map((e) => e.path)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            '$offenders が kIsWeb を直に見ています。\n'
            'lib/platform/downloads_supported.dart の条件付き取り込みと、\n'
            'lib/ui/downloads/download_support.dart のプロバイダを通してください。',
      );
    });
  });
}

void _expectNoDate(String text, String where) {
  for (final entry in _datePatterns.entries) {
    expect(
      entry.value.hasMatch(text),
      isFalse,
      reason:
          '$where に日付（${entry.key}）が入っています: 「$text」\n'
          '引き金は Android の一般公開で、その日程は未定です（論点 17）。\n'
          '告知した日に Android が出ていないと、告知そのものを'
          '取り消すことになります。',
    );
  }
}
