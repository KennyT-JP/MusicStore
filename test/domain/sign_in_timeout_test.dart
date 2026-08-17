/// Web ログインの待ち時間の上限（監査 第5回・AP-12）
///
/// **時計に依存するので `fakeAsync` で固定する。** 実時間で待つと 90 秒
/// かかるうえ不安定になる。仮想時計を進めて、上限の前後だけを見る。
library;

import 'dart:async';

// fake_async は flutter_test が連れてくる（テスト専用）。pubspec に直接は
// 書かず、ここで取り込む——本番コードからは使わない。
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/sign_in_timeout.dart';

void main() {
  group('withSignInTimeout', () {
    test('既定の上限は 90 秒', () {
      // 秒数は名前付き定数に置いてある（呼び出し側と共有する）。
      expect(kWebSignInTimeout, const Duration(seconds: 90));
    });

    test('時間内に解決すれば、その値をそのまま返す', () {
      fakeAsync((async) {
        Object? value;
        Object? caught;
        // 上限より早く終わる Future。
        unawaited(() async {
          try {
            value = await withSignInTimeout<String>(
              () => Future.delayed(const Duration(seconds: 1), () => 'ok'),
            );
          } catch (e) {
            caught = e;
          }
        }());

        async.elapse(const Duration(seconds: 2));

        expect(caught, isNull, reason: '時間内なのに例外が飛んでいます');
        expect(value, 'ok');
      });
    });

    test('上限を過ぎたら SignInTimeoutException を投げる', () {
      fakeAsync((async) {
        Object? caught;
        // 決して解決しない Future（放置されたポップアップの再現）。
        unawaited(() async {
          try {
            await withSignInTimeout<String>(
              () => Completer<String>().future,
            );
          } catch (e) {
            caught = e;
          }
        }());

        // 上限の直前では、まだ何も起きていない。
        async.elapse(kWebSignInTimeout - const Duration(seconds: 1));
        expect(caught, isNull, reason: '上限より前に打ち切っています');

        // 上限を越えた瞬間に例外へ倒れる。
        async.elapse(const Duration(seconds: 2));
        expect(caught, isA<SignInTimeoutException>());
      });
    });

    test('timeout は呼び出し側から差し替えられる', () {
      fakeAsync((async) {
        Object? caught;
        unawaited(() async {
          try {
            await withSignInTimeout<String>(
              () => Completer<String>().future,
              timeout: const Duration(seconds: 5),
            );
          } catch (e) {
            caught = e;
          }
        }());

        async.elapse(const Duration(seconds: 4));
        expect(caught, isNull);

        async.elapse(const Duration(seconds: 2));
        expect(caught, isA<SignInTimeoutException>());
      });
    });
  });
}
