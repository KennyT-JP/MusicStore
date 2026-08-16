/// Sign in with Apple の規則（docs/MOBILE-APP-DESIGN.md 5-6）
///
/// **ここで守るのは 2 つ。どちらも壊れても実行時に気づけない。**
///
/// | 規則 | 破れると |
/// | --- | --- |
/// | ボタンを出すのは iOS だけ | Web と Android に押しても何も起きないボタンが出る |
/// | 判定を 1 箇所に閉じる | 画面が `Platform.isIOS` を書き、**`flutter build web` が落ちる** |
/// | nonce は Apple に SHA-256、Firebase に生 | `invalid-credential`。**実機でしか気づけない** |
///
/// **規則は本物（lib/domain/apple_sign_in.dart）を検証する。**
/// テストファイル内に写しを書くと、本番が変わっても緑のままになる
/// （監査 第4回。test/domain/signup_locale_test.dart と同じ立て付け）。
///
/// nonce を「実際にどちらへ渡しているか」は
/// test/domain/mobile_sign_in_test.dart が本物の実装を動かして確かめる。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/repositories/auth_repository.dart';
import 'package:music_list_app/domain/apple_sign_in.dart';

import '../support/repo_files.dart';

/// `//`・`///` のコメント行を取り除く。
///
/// **このリポジトリは「なぜそうしないか」を長い注記で残す流儀**なので、
/// 素の `contains` だと**説明文に残った名前のせいで、実際に書いてあっても
/// 書いていなくても同じ結果になる**（test/domain/no_dead_code_test.dart と
/// 同じ手当て）。改行コードは先にそろえる——CRLF だと `//.*$` が行末に
/// 届かず、1 行もコメントを落とせない。
String _stripComments(String source) => source
    .replaceAll('\r\n', '\n')
    .split('\n')
    .map((line) => line.replaceFirst(RegExp(r'(?<!:)//.*$'), ''))
    .join('\n');

String _sourceOf(String path) =>
    _stripComments(File(path).readAsStringSync());

void main() {
  group('「Apple でサインイン」を出す条件', () {
    test('iOS のアプリにだけ出す', () {
      expect(
        AppleSignInPolicy.isAvailable(
          isWeb: false,
          platform: TargetPlatform.iOS,
        ),
        isTrue,
      );
    });

    test('Web には出さない（iPhone の Safari も含む）', () {
      // **`defaultTargetPlatform` は Web でも iOS を返す。**
      // `isWeb` を先に外さないと、iPhone のブラウザで開いた人に
      // 押しても何も起きないボタンが出る。
      expect(
        AppleSignInPolicy.isAvailable(
          isWeb: true,
          platform: TargetPlatform.iOS,
        ),
        isFalse,
      );
    });

    test('Android には出さない', () {
      // Android で出すには Apple 側に Services ID と戻り先 URL の登録
      // （ドメイン検証つき）が別途要る。今回はやらない。
      expect(
        AppleSignInPolicy.isAvailable(
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
    });

    test('iOS 以外のネイティブにも出さない', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          AppleSignInPolicy.isAvailable(isWeb: false, platform: platform),
          isFalse,
          reason: '$platform に出しています',
        );
      }
    });
  });

  group('画面が見る窓口（AuthRepository.isAppleSignInAvailable）', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('iOS では true', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(AuthRepository.isAppleSignInAvailable, isTrue);
    });

    test('Android では false', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(AuthRepository.isAppleSignInAvailable, isFalse);
    });

    // Web（`kIsWeb` が true）は Dart VM の上では作れない。
    // そのぶんは [AppleSignInPolicy] 側の「Web には出さない」で押さえ、
    // ここでは**窓口が本当に規則を呼んでいる**ことを見る。
    test('規則の写しを持たず、domain の本物を呼んでいる', () {
      final source = _sourceOf('lib/data/repositories/auth_repository.dart');

      expect(
        source,
        contains('AppleSignInPolicy.isAvailable('),
        reason: '判定を書き写すと、このテストが見ているものと本番が食い違う',
      );
      expect(source, contains('isWeb: kIsWeb'));
      expect(source, contains('platform: defaultTargetPlatform'));
    });

    test('画面は窓口だけを見ていて、自分で判定していない', () {
      for (final path in [
        'lib/ui/screens/auth/sign_in_screen.dart',
        'lib/ui/screens/auth/sign_up_screen.dart',
      ]) {
        final source = _sourceOf(path);

        expect(
          source,
          contains('AuthRepository.isAppleSignInAvailable'),
          reason: '$path が Apple ボタンの出し分けをしていません',
        );
        // **判定が画面へ散ると、直すべき場所が増える。**
        // `Platform.isIOS` はそのうえ Web ビルドを落とす。
        for (final forbidden in [
          'TargetPlatform.iOS',
          'defaultTargetPlatform',
          'kIsWeb',
          'Platform.is',
        ]) {
          expect(
            source,
            isNot(contains(forbidden)),
            reason: '$path が $forbidden で自前の判定を書いています',
          );
        }
      }
    });
  });

  group('nonce の作り方', () {
    test('生の nonce は 32 文字で、使ってよい文字だけでできている', () {
      final nonce = AppleNonce.random();

      expect(nonce.length, 32);
      for (final ch in nonce.split('')) {
        expect(
          AppleNonce.alphabet.contains(ch),
          isTrue,
          reason: '$ch は nonce に使えない文字',
        );
      }
    });

    test('毎回ちがう値になる', () {
      // **同じ値が返るなら nonce として機能しない。**
      // 32 文字・65 種の文字なので、たまたま揃うことは実質ない。
      final values = List.generate(20, (_) => AppleNonce.random()).toSet();
      expect(values.length, 20);
    });

    test('Apple へ渡すものと Firebase へ渡すものは、別の値', () {
      // **これを取り違えると `invalid-credential` になる。**
      final raw = AppleNonce.random();
      expect(AppleNonce.hashed(raw), isNot(raw));
    });

    test('Apple へ渡すのは、生の nonce の SHA-256', () {
      final raw = AppleNonce.random();
      final hashed = AppleNonce.hashed(raw);

      expect(hashed, sha256.convert(utf8.encode(raw)).toString());
      expect(hashed.length, 64); // 16 進数 64 桁
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hashed), isTrue);
    });

    test('同じ生の nonce からは、同じハッシュができる', () {
      // Apple が返す ID トークンに載るのはこのハッシュで、Firebase は
      // 生の値を自分でハッシュして突き合わせる。ここが揺れたら通らない。
      expect(AppleNonce.hashed('abc'), AppleNonce.hashed('abc'));
    });
  });

  group('共通コードにネイティブ専用の参照を書かない', () {
    // **`flutter build web` が通ることで確かめられる規則を、先にここで止める。**
    // ビルドは 1 分以上かかるので、気づくのが遅い。
    //
    // `dart:io` の側は test/domain/download_storage_test.dart が同じ範囲を
    // 見ているが、**この変更でいちばん誘発されやすいのは `Platform.isIOS`**
    // なので、認証の規則としてもここに置く。
    List<({String path, String source})> libSources() => filesUnder('lib')
        .where((e) => !e.path.startsWith('lib/l10n/')) // 生成物
        .map((e) => (path: e.path, source: _stripComments(e.file.readAsStringSync())))
        .toList();

    test('lib/ に Platform.is* が 1 つも無い', () {
      final offenders = libSources()
          .where(
            (e) => RegExp(r'(?<![A-Za-z])Platform\.is[A-Z]').hasMatch(e.source),
          )
          .map((e) => e.path)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            '$offenders が Platform.is* を使っています。\n'
            'これは dart:io のもので、flutter build web が落ちます。\n'
            'プラットフォームの判定は lib/domain/apple_sign_in.dart のように\n'
            'kIsWeb / defaultTargetPlatform で書き、1 箇所に閉じてください。',
      );
    });

    test('認証まわりが dart:io を取り込んでいない', () {
      final offenders = libSources()
          .where((e) => e.source.contains("import 'dart:io'"))
          .map((e) => e.path)
          .where((path) => !path.startsWith('lib/platform/'))
          .where((path) => !path.endsWith('_io.dart'))
          .toList();

      expect(
        offenders,
        isEmpty,
        reason: '$offenders が dart:io を直接取り込んでいます（flutter build web が落ちます）',
      );
    });
  });
}
