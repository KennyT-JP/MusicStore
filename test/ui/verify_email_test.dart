/// メール確認待ち画面（仕様書 3.1 / 2 章）
///
/// **回帰テスト。**
///
/// 1. 確認メールが英語で届いていた。Firebase Auth は言語を指定しないと
///    既定（英語）で送る。画面が日本語なのに英語のメールが来る状態だった。
/// 2. メールのリンクは**別のタブ**で開かれるため、確認が済んでもこの画面は
///    気づかなかった。利用者が「確認が済んだので次へ」を押すまで待ち続けていた。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/repositories/auth_repository.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/ui/screens/auth/verify_email_screen.dart';

/// 何を頼まれたかだけを覚える、確認用の差し替え。
class _RecordingAuth implements AuthRepository {
  _RecordingAuth({this.verified = false});

  /// 確認が済んだことにするか。
  bool verified;

  /// `reloadEmailVerification` が呼ばれた回数。
  int reloadCount = 0;

  /// 再送のときに渡された言語。
  String? resendLanguage;

  @override
  Future<bool> reloadEmailVerification() async {
    reloadCount++;
    return verified;
  }

  @override
  Future<void> resendVerificationEmail({required String languageCode}) async {
    resendLanguage = languageCode;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _app(Widget child, {required Locale locale, required Object auth}) =>
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth as AuthRepository),
        firebaseUserProvider.overrideWith((ref) => const Stream.empty()),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppL10n.supportedLocales,
        locale: locale,
        home: child,
      ),
    );

void main() {
  testWidgets('確認が済むまで、押さなくても自動で確かめ続ける', (tester) async {
    final auth = _RecordingAuth();

    await tester.pumpWidget(
      _app(const VerifyEmailScreen(), locale: const Locale('ja'), auth: auth),
    );
    await tester.pump();

    expect(auth.reloadCount, 0, reason: '開いた直後はまだ問い合わせない');

    // 3 秒ごとに確かめる。
    await tester.pump(const Duration(seconds: 3));
    expect(auth.reloadCount, 1);

    await tester.pump(const Duration(seconds: 3));
    expect(auth.reloadCount, 2);

    // 画面を閉じたら止まること（開きっぱなしで問い合わせ続けない）。
    await tester.pumpWidget(
      _app(const SizedBox.shrink(), locale: const Locale('ja'), auth: auth),
    );
    final countAfterDispose = auth.reloadCount;
    await tester.pump(const Duration(seconds: 6));
    expect(auth.reloadCount, countAfterDispose);
  });

  testWidgets('確認が済んだら、それ以上は問い合わせない', (tester) async {
    final auth = _RecordingAuth(verified: true);

    await tester.pumpWidget(
      _app(const VerifyEmailScreen(), locale: const Locale('ja'), auth: auth),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(auth.reloadCount, 1);

    // 済んだあとは止める。
    await tester.pump(const Duration(seconds: 9));
    expect(auth.reloadCount, 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('自動で進むことを画面に書いてある', (tester) async {
    await tester.pumpWidget(
      _app(
        const VerifyEmailScreen(),
        locale: const Locale('ja'),
        auth: _RecordingAuth(),
      ),
    );
    await tester.pump();

    final l10n = await AppL10n.delegate.load(const Locale('ja'));
    expect(find.text(l10n.verifyEmailAutoDetect), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final locale in const [Locale('ja'), Locale('en')]) {
    testWidgets('再送はいま出ている言語で送る（${locale.languageCode}）', (tester) async {
      final auth = _RecordingAuth();

      await tester.pumpWidget(
        _app(const VerifyEmailScreen(), locale: locale, auth: auth),
      );
      await tester.pump();

      final l10n = await AppL10n.delegate.load(locale);
      await tester.tap(find.text(l10n.verifyEmailResend));
      await tester.pump();

      expect(auth.resendLanguage, locale.languageCode);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
