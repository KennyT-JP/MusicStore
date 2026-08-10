/// 配信するファイルのキャッシュ指定（firebase.json）
///
/// **回帰テスト。** 2026-08 に実際に起きた不具合を固定する。
///
/// 1. 画面に再生ボタンを足して配信したのに、**ボタンの場所だけ空いていて
///    絵柄が出ない**。原因はフォントを `max-age=31536000, immutable`
///    （1 年、取り直さない）にしていたこと。Flutter はアイコン用の
///    `MaterialIcons-Regular.otf` を**使っているアイコンだけに削り込んで
///    作り直す**。名前は変わらないのに中身がビルドごとに変わるファイルで、
///    これを溜め込ませると、新しい画面が古いフォントで描かれる。
///    **「名前が変わらない = 中身が変わらない」ではない。**
///
/// 2. Hosting のヘッダは、同じパスに複数のブロックが一致すると
///    **後に書いたものが勝つ**。no-cache のブロックの後ろに
///    `**/*.@(js|json)` の max-age=3600 を書いていたため、
///    flutter_service_worker.js などの no-cache が上書きされて
///    無効になっていた（本番の実ヘッダで確認）。書いてあるだけでは
///    駄目で、**最後に一致した値（実効値）**を見なければならない。
///
/// そのためこのテストは、規則を 1 つずつ見るのではなく、
/// Hosting と同じ「後勝ち」でパスごとの実効値を計算して検証する。
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

/// Hosting の source（glob）を正規表現へ。
///
/// firebase.json で実際に使っている形だけを支える：
/// `**`（全体）・`**/`（0 個以上のディレクトリ）・`*`（/ 以外）・
/// `@(a|b)`（いずれか）。それ以外の記法を足したら、ここも育てること。
RegExp _globToRegExp(String glob) {
  // Hosting は先頭の / の有無に関わらずパス全体へ照合するので、揃える。
  final g = glob.startsWith('/') ? glob.substring(1) : glob;
  final out = StringBuffer('^');
  var i = 0;
  while (i < g.length) {
    final c = g[i];
    if (c == '*') {
      if (i + 1 < g.length && g[i + 1] == '*') {
        // `**/` は「0 個以上のディレクトリ」。`**/a.js` はルート直下にも一致する。
        if (i + 2 < g.length && g[i + 2] == '/') {
          out.write('(?:.*/)?');
          i += 3;
        } else {
          out.write('.*');
          i += 2;
        }
      } else {
        out.write('[^/]*');
        i += 1;
      }
    } else if (c == '@' && i + 1 < g.length && g[i + 1] == '(') {
      out.write('(?:');
      i += 2;
    } else if (c == '|' || c == ')') {
      out.write(c);
      i += 1;
    } else {
      out.write(RegExp.escape(c));
      i += 1;
    }
  }
  out.write(r'$');
  return RegExp(out.toString());
}

/// [path]（先頭の / なし）に実際に付く Cache-Control。
///
/// **同じパスに複数の規則が一致するときは、最後の 1 件が効く**（後勝ち）。
/// Hosting の挙動に合わせ、一致した規則を上書きしながら最後まで見る。
String? _effectiveCacheControl(String path) {
  String? value;
  for (final rule in _hostingHeaders()) {
    if (!_globToRegExp(rule['source'] as String).hasMatch(path)) continue;
    for (final header in (rule['headers'] as List)) {
      final entry = (header as Map).cast<String, dynamic>();
      if ((entry['key'] as String).toLowerCase() == 'cache-control') {
        value = entry['value'] as String; // 後勝ち。break しない
      }
    }
  }
  return value;
}

void main() {
  group('キャッシュ指定（後勝ちで計算した実効値）', () {
    test('index.html・SW・bootstrap・version.json は溜め込まない', () {
      // SW と bootstrap は `**/*.@(js|json)` にも一致する。no-cache の
      // ブロックが前にあると max-age=3600 に上書きされて無効になる
      // （実際に本番で起きた並び）。実効値で確かめる。
      for (final path in [
        'index.html',
        'flutter_service_worker.js',
        'flutter_bootstrap.js',
        'version.json',
      ]) {
        final value = _effectiveCacheControl(path);
        expect(
          value,
          contains('no-cache'),
          reason: '$path の実効値が no-cache でない（$value）。'
              'ブロックの並び順（後勝ち）が崩れていないか確認すること。',
        );
      }
    });

    test('rewrite で index.html が返る深いパスにも no-cache が付く', () {
      // どのブロックにも一致しないパスは Hosting 既定の max-age=3600 になり、
      // 配信後 1 時間、トップから入る利用者に旧版が出る。包括の `**` が
      // それを塞いでいることを確かめる。
      for (final path in ['', 'lists/abc123', 'lists/abc123/items/42']) {
        final value = _effectiveCacheControl(path);
        expect(
          value,
          isNotNull,
          reason: '「$path」に一致するブロックが無い。包括の `**` が消えている。',
        );
        expect(
          value,
          contains('no-cache'),
          reason: '「$path」は rewrite で index.html が返る。'
              '溜め込ませると配信後 1 時間、旧版が出る（$value）。',
        );
      }
    });

    test('MaterialIcons は immutable にも長期キャッシュにもしない', () {
      // 中身がビルドごとに変わる削り込みフォント。max-age を与えると
      // その時間ぶん新旧が混在する窓ができる（immutable にしていたときは
      // 追加したアイコンが場所だけ取って描かれなかった）。
      final value = _effectiveCacheControl(
        'assets/fonts/MaterialIcons-Regular.otf',
      );

      expect(value, isNotNull);
      expect(
        value,
        isNot(contains('immutable')),
        reason: 'MaterialIcons-Regular.otf は中身がビルドごとに変わる。'
            'immutable にすると、増やしたアイコンが出なくなる。',
      );
      expect(
        value,
        contains('no-cache'),
        reason: '毎回確認させる（中身が同じなら 304 で済む）。'
            'max-age を与えると、その時間ぶん新旧の混在窓ができる（$value）。',
      );
      final maxAge = RegExp(r'max-age=(\d+)').firstMatch(value!);
      expect(
        maxAge,
        isNull,
        reason: 'no-cache と max-age を併記しない（読み手が迷う）。',
      );
    });

    test('中身の変わらない資産（NotoSansJP・画像）は 1 時間まで置いてよい', () {
      // ここまで no-cache にすると転送量が無駄に増える。包括の `**` が
      // 資産のブロックまで塗り潰していないことを確かめる。
      for (final path in [
        'assets/assets/fonts/NotoSansJP-400.ttf',
        'brand/png/icon-192.png',
        'main.dart.js',
      ]) {
        final value = _effectiveCacheControl(path)!;
        final maxAge = RegExp(r'max-age=(\d+)').firstMatch(value);
        expect(
          maxAge,
          isNotNull,
          reason: '$path に max-age が無い（$value）。既定の no-cache に'
              '塗り潰されている。資産のブロックは包括 `**` の後ろに置くこと。',
        );
        // 1 日以上溜め込むと、直した版が届くまで時間がかかる。
        expect(int.parse(maxAge!.group(1)!), lessThanOrEqualTo(86400));
        expect(value, isNot(contains('immutable')));
      }
    });
  });
}
