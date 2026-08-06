/// 配信するファイルのキャッシュ指定（firebase.json）
///
/// **回帰テスト。** 2026-08 に実際に起きた不具合を固定する。
///
/// 画面に再生ボタンを足して配信したのに、**ボタンの場所だけ空いていて
/// 絵柄が出ない**という状態になった。強制リロードでも直らなかった。
///
/// 原因は `firebase.json` のキャッシュ指定。フォントを
/// `max-age=31536000, immutable`（1 年、取り直さない）にしていた。
/// ところが Flutter はアイコン用の `MaterialIcons-Regular.otf` を
/// **使っているアイコンだけに削り込んで作り直す**。名前は変わらないのに
/// 中身がビルドごとに変わるファイルで、これを immutable にすると、
/// 新しい画面が古いフォントで描かれる。増やしたアイコンは絵柄を持たない
/// ので、場所だけ取って何も出ない。
///
/// **「名前が変わらない = 中身が変わらない」ではない。**
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> _hostingHeaders() {
  final config =
      jsonDecode(File('firebase.json').readAsStringSync())
          as Map<String, dynamic>;
  final hosting = config['hosting'] as Map<String, dynamic>;
  return (hosting['headers'] as List).cast<Map<String, dynamic>>();
}

String _cacheControlFor(String extension) {
  for (final rule in _hostingHeaders()) {
    final source = rule['source'] as String;
    if (!source.contains(extension)) continue;
    for (final header in (rule['headers'] as List)) {
      final entry = (header as Map).cast<String, dynamic>();
      if ((entry['key'] as String).toLowerCase() == 'cache-control') {
        return entry['value'] as String;
      }
    }
  }
  fail('$extension を対象にした Cache-Control の指定が見つかりません。');
}

void main() {
  group('キャッシュ指定', () {
    test('フォントを immutable にしない（アイコンが出なくなる）', () {
      final value = _cacheControlFor('otf');

      expect(
        value,
        isNot(contains('immutable')),
        reason: 'MaterialIcons-Regular.otf は中身がビルドごとに変わる。'
            'immutable にすると、増やしたアイコンが出なくなる。',
      );
    });

    test('フォントは毎回サーバーに確認させる', () {
      final value = _cacheControlFor('otf');

      expect(value, contains('must-revalidate'));
      // 1 日以上溜め込むと、直した版が届くまで時間がかかる。
      final maxAge = RegExp(r'max-age=(\d+)').firstMatch(value);
      expect(maxAge, isNotNull, reason: 'max-age を明示すること');
      expect(int.parse(maxAge!.group(1)!), lessThanOrEqualTo(86400));
    });

    test('index.html と Service Worker は溜め込まない', () {
      final value = _cacheControlFor('index.html');

      expect(value, contains('no-cache'));
    });
  });
}
