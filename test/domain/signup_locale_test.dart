/// 登録したときの表示言語（仕様書 2 章）
///
/// **回帰テスト。** 新しく登録した人の `users.locale` を `'ja'` 固定で
/// 書いていた（監査 第3回）。
///
/// アプリの表示言語は `lib/app.dart` がこの値を見て決める。そのため
/// **英語で使っていた人も、登録し終えた瞬間に日本語へ切り替わっていた。**
/// しかも確認メールだけは使っている言語で送っていたので、
/// 「メールは英語・画面は日本語」という食い違いになっていた。
///
/// 認証そのものは Firebase に触れるためここでは動かせない。
/// 代わりに **`locale` を決める規則と、画面から言語が渡ること**を固定する。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 保存する表示言語を決める。`auth_repository.dart` と同じ規則。
String _localeFor(String languageCode) =>
    const {'ja', 'en'}.contains(languageCode) ? languageCode : 'en';

void main() {
  group('登録したときの表示言語', () {
    test('いま使っている言語をそのまま残す', () {
      expect(_localeFor('ja'), 'ja');
      expect(_localeFor('en'), 'en');
    });

    test('扱わない言語は英語に倒す（日本語にしない）', () {
      // 端末が中国語・韓国語などのとき。日本語に倒すと、
      // 読めない言語で固定されてしまう。
      expect(_localeFor('zh'), 'en');
      expect(_localeFor('ko'), 'en');
      expect(_localeFor(''), 'en');
    });

    test('保存する値を決め打ちしていない', () {
      final source = File(
        'lib/data/repositories/auth_repository.dart',
      ).readAsStringSync();

      expect(
        source,
        isNot(contains("locale: 'ja'")),
        reason: '表示言語を固定すると、英語で登録した人が日本語になる',
      );
      expect(source, contains('locale: '));
    });

    test('users を作る 3 つの入口すべてが、言語を受け取る', () {
      final source = File(
        'lib/data/repositories/auth_repository.dart',
      ).readAsStringSync();

      // Google 連携・メールでのログイン・メールでの登録。
      // どれも「無ければ作る」を通るので、1 つでも漏れると
      // その入口から登録した人だけ言語が決まらない。
      for (final method in [
        'signInWithGoogle',
        'signInWithEmail',
        'signUpWithEmail',
      ]) {
        final at = source.indexOf(method);
        expect(at, isNot(-1), reason: '$method が見つかりません');
        final signature = source.substring(at, at + 260);
        expect(
          signature,
          contains('languageCode'),
          reason: '$method が表示言語を受け取っていません',
        );
      }
    });

    test('画面は、いま出ている言語を渡している', () {
      for (final path in [
        'lib/ui/screens/auth/sign_in_screen.dart',
        'lib/ui/screens/auth/sign_up_screen.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          source,
          contains('Localizations.localeOf(context).languageCode'),
          reason: '$path が表示言語を渡していません',
        );
      }
    });
  });
}
