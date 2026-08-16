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
import 'package:music_list_app/env/app_environment.dart';
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

  group('共有・招待 URL（ネイティブ）', () {
    // このテストは VM 上（kIsWeb == false）で走る。つまり
    // **モバイル実機とまったく同じ経路**を通る。
    // `Uri.base` が `file:` 形式になるのも同じ。

    test('前提：Uri.base は file: 形式で、origin を読むと例外になる', () {
      // ここが崩れると以下のテストが「ネイティブの想定」でなくなる。
      // モバイルで起きることを、この前提の上で確かめている。
      expect(Uri.base.isScheme('file'), isTrue);
      expect(() => Uri.base.origin, throwsStateError);
    });

    test('base を渡さなくても例外にならず、招待 URL を組み立てられる', () {
      // **これがこの修正の主眼。** 直前まで、モバイルではここで
      // StateError が飛び、招待リンクを 1 本も作れなかった。
      expect(() => buildShareUrl('/invite/abc123'), returnsNormally);
      expect(
        buildShareUrl('/invite/abc123'),
        '${AppEnvironment.current.shareOrigin}/#/invite/abc123',
      );
    });

    test('URL の形を変えない（ハッシュ方式のまま）', () {
      // パス方式へ変えると、すでに配ったリンクが動かなくなる。
      final url = Uri.parse(buildShareUrl('/invite/abc123'));

      expect(url.scheme, 'https');
      expect(url.path, '/');
      expect(url.fragment, '/invite/abc123');
    });

    test('固定ドメインは環境ごとに 1 か所で決まる', () {
      // 検証環境のアプリが本番の招待 URL を配ると、受け取った人は
      // 本番のリストに入ろうとして入れない。
      expect(
        AppEnvironment.production.shareOrigin,
        'https://music-storage-d79b2.web.app',
      );
      expect(
        AppEnvironment.staging.shareOrigin,
        'https://music-storage-dev.web.app',
      );
      expect(
        AppEnvironment.production.shareOrigin,
        isNot(AppEnvironment.staging.shareOrigin),
      );
    });

    test('既定の土台は、いま選ばれている環境の固定ドメイン', () {
      // `--dart-define=APP_ENV=` を指定しないので検証環境になる。
      expect(AppEnvironment.current, AppEnvironment.staging);
      expect(defaultShareBase.origin, 'https://music-storage-dev.web.app');
      expect(defaultShareBase.path, '/');
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
