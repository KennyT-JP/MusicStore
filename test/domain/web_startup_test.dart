/// 最初の表示までの待ち時間に効く指定（web/index.html）
///
/// **回帰テスト。** サイトを開いてから画面が出るまで 5 秒ほどかかり、
/// その間まったくの白い画面だった（2026-08-07）。
///
/// Flutter Web は「index.html を読む → flutter_bootstrap.js →
/// main.dart.js → 描画に必要なものを取りに行く」と順に辿るため、
/// **何が要るか分かるまでに時間がかかる。** 先に分かっている分は
/// 先に取りに行かせ、待っている間は待っていると分かる表示を出す。
///
/// `web/index.html` は Flutter の雛形をそのまま使うことが多く、
/// SDK の更新やテンプレートの入れ替えで**黙って元に戻りやすい**。
/// ここで固定する。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _indexHtml() => File('web/index.html').readAsStringSync();

void main() {
  group('最初の表示までの待ち時間', () {
    test('読み込み中であることを、アプリを待たずに出す', () {
      final html = _indexHtml();

      // HTML と CSS だけで書いてあること。script の到着を待つと、
      // いちばん見せたい最初の数秒に間に合わない。
      expect(html, contains('id="loading"'));
      final loadingAt = html.indexOf('id="loading"');
      // 説明文にも同じ名前が出るので、読み込む指定そのものを探す。
      final bootstrapAt = html.indexOf('<script src="flutter_bootstrap.js"');
      expect(bootstrapAt, isNot(-1), reason: 'アプリの読み込み指定が見つかりません');
      expect(
        loadingAt,
        lessThan(bootstrapAt),
        reason: '読み込み中の表示は、アプリの読み込みより前に書くこと',
      );
    });

    test('最初の描画が済んだら消す', () {
      final html = _indexHtml();

      // このイベント名は Flutter の engine が発火する。
      // 変えると読み込み中の表示が消えなくなる。
      expect(html, contains('flutter-first-frame'));
      expect(html, contains("getElementById('loading')"));
    });

    test('どの画面でも要るものは、先に取りに行かせる', () {
      final html = _indexHtml();

      // main.dart.js は flutter_bootstrap.js を読み終えて初めて分かる。
      // 先に知らせておくと、その分だけ早く始められる。
      expect(html, contains('rel="preload"'));
      expect(html, contains('main.dart.js'));

      // 描画部（CanvasKit）は Google の配信網から取る。
      // 接続の確立だけでも往復が要るので、先に済ませておく。
      expect(html, contains('rel="preconnect"'));
      expect(html, contains('gstatic.com'));
    });

    test('雛形のままの文言が残っていない', () {
      final html = _indexHtml();

      // 雛形の値はブラウザのタブや共有時にそのまま出る。
      expect(html, isNot(contains('A new Flutter project')));
      expect(html, isNot(contains('<title>music_list_app</title>')));
    });
  });
}
