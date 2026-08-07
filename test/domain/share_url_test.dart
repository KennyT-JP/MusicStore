/// 共有・招待 URL の組み立て（仕様書 3.3 / 5.3）と、日時の表示（6.2）
///
/// **どちらも本番から使われているのに、テストが 1 件も無かった**（監査 第3回）。
///
/// 招待 URL は、壊れると**誰もリストに参加できなくなる**。しかも
/// 壊れたことは、実際に人を招くまで分からない。
///
/// 日時の表示は、かつて同じ関数が 2 つの画面に写しで置かれ、さらに
/// 項目詳細だけがゼロ埋めのない別の書き方をしていた。1 か所にまとめた
/// のに、**その形を固定するものが無かった**（監査 第2回の積み残し）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/ui/format.dart';
import 'package:music_list_app/ui/share_url.dart';

void main() {
  group('共有・招待 URL', () {
    final staging = Uri.parse('https://music-storage-dev.web.app/');

    test('アプリ内のパスから、人に渡せる URL を作る', () {
      expect(
        buildShareUrl('/invite/abc123', base: staging),
        'https://music-storage-dev.web.app/#/invite/abc123',
      );
    });

    test('# を挟む（go_router のハッシュ方式）', () {
      // ここが抜けると、受け取った人はアプリの入口ではなく
      // 存在しないパスへ飛ばされる。
      expect(buildShareUrl('/lists/x', base: staging), contains('/#/'));
    });

    test('開いている環境の URL になる（検証と本番が混ざらない）', () {
      final prod = Uri.parse('https://music-storage-d79b2.web.app/');

      expect(buildShareUrl('/invite/a', base: prod), startsWith(prod.origin));
      expect(
        buildShareUrl('/invite/a', base: staging),
        isNot(contains('d79b2')),
      );
    });

    test('サブディレクトリで配信していても壊れない', () {
      // ルート直下とは限らない。base の path を落とすと参加できなくなる。
      expect(
        buildShareUrl('/invite/a', base: Uri.parse('https://example.test/app/')),
        'https://example.test/app/#/invite/a',
      );
    });
  });

  group('日時の表示', () {
    test('ゼロ埋めして桁をそろえる', () {
      final value = DateTime(2026, 8, 6, 9, 5).toUtc();

      // 2026-8-6 9:5 のような形にしない。一覧で桁が揃わなくなる。
      expect(formatDateTime(value), '2026/08/06 ${_localHourMinute(value)}');
    });

    test('見る人の現地時刻で出す', () {
      final utc = DateTime.utc(2026, 8, 6, 12, 0);

      // 端末の時間帯に合わせて変換される。ここでは「変換していること」
      // だけを確かめる（実行環境の時間帯に依存しないように）。
      final local = utc.toLocal();
      expect(
        formatDateTime(utc),
        '${local.year}/${_two(local.month)}/${_two(local.day)} '
        '${_two(local.hour)}:${_two(local.minute)}',
      );
    });

    test('秒は出さない', () {
      expect(formatDateTime(DateTime(2026, 1, 2, 3, 4, 56)), isNot(contains(':56')));
    });
  });
}

String _two(int v) => v.toString().padLeft(2, '0');

String _localHourMinute(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}
