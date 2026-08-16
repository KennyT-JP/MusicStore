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
///
/// **規則は本物（lib/domain/signup_locale.dart）を検証する。**
/// 以前はこのファイル内の写し（`_localeFor`）を検証しており、
/// 本番の実装が変わっても緑のままだった（監査 第4回）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/signup_locale.dart';

void main() {
  group('登録したときの表示言語', () {
    test('いま使っている言語をそのまま残す', () {
      expect(SignupLocalePolicy.localeFor('ja'), 'ja');
      expect(SignupLocalePolicy.localeFor('en'), 'en');
    });

    test('扱わない言語は英語に倒す（日本語にしない）', () {
      // 端末が中国語・韓国語などのとき。日本語に倒すと、
      // 読めない言語で固定されてしまう。
      expect(SignupLocalePolicy.localeFor('zh'), 'en');
      expect(SignupLocalePolicy.localeFor('ko'), 'en');
      expect(SignupLocalePolicy.localeFor(''), 'en');
    });

    test('本番（auth_repository）がこの規則を呼んでいる', () {
      final source = File(
        'lib/data/repositories/auth_repository.dart',
      ).readAsStringSync();

      expect(
        source,
        isNot(contains("locale: 'ja'")),
        reason: '表示言語を固定すると、英語で登録した人が日本語になる',
      );
      // 規則の写しを持たず、domain の本物を呼ぶこと。写しを書くと、
      // このテストが検証しているものと本番が食い違う。
      expect(
        source,
        contains('locale: SignupLocalePolicy.localeFor('),
        reason: 'users.locale は SignupLocalePolicy.localeFor で決めること',
      );
    });

    test('users を作る 4 つの入口すべてが、言語を受け取る', () {
      final source = File(
        'lib/data/repositories/auth_repository.dart',
      ).readAsStringSync();

      // Google 連携・Apple 連携・メールでのログイン・メールでの登録。
      // どれも「無ければ作る」を通るので、1 つでも漏れると
      // その入口から登録した人だけ言語が決まらない。
      //
      // **Apple は 2026-08-16 に増えた入口**
      // （docs/MOBILE-APP-DESIGN.md 5-6）。増やすたびにここへ足すこと。
      for (final method in [
        'signInWithGoogle',
        'signInWithApple',
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
