/// ログインの失敗が、次の一手に繋がる形で出るか（仕様書 3.1）
///
/// **回帰テスト。2026-08-11 に実機で起きた。**
///
/// 検証環境で Google ログインを押したところ「エラーが発生しました。
/// しばらくしてからもう一度お試しください。」とだけ出た。
/// **画面にも開発者ツールにも符号が出ず**、原因を絞るために
/// Firebase の設定（承認済みドメイン・連携の有効／無効）まで
/// 照会する必要があった。
///
/// 待っても直らない種類の失敗（ポップアップのブロックなど）に
/// 「しばらくしてから」と出すのは、**直す機会そのものを奪う**
/// （docs/AUDIT-CHECKLIST.md「例外を握りつぶすことは欠陥そのもの」）。
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/ui/widgets/error_message.dart';

/// 待っても直らない＝利用者か管理者が何かをしない限り解消しない失敗。
///
/// **ここに挙げた符号は、汎用の文言に落としてはいけない。**
const _needsAction = [
  'popup-blocked',
  'operation-not-allowed',
  'unauthorized-domain',
];

Future<String> _describe(
  WidgetTester tester,
  FirebaseAuthException e, {
  Locale locale = const Locale('ja'),
}) async {
  late String result;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      locale: locale,
      home: Builder(
        builder: (context) {
          result = describeAuthError(context, e);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return result;
}

void main() {
  for (final locale in AppL10n.supportedLocales) {
    testWidgets(
      '待っても直らない失敗に、汎用の文言を出さない（${locale.languageCode}）',
      (tester) async {
        final generic = await _describe(
          tester,
          FirebaseAuthException(code: 'no-such-code-at-all'),
          locale: locale,
        );

        for (final code in _needsAction) {
          final message = await _describe(
            tester,
            FirebaseAuthException(code: code),
            locale: locale,
          );
          expect(
            message,
            isNot(generic),
            reason:
                '$code は待っても直らない。「しばらくしてからお試しください」'
                'と出すと、利用者は何をすればよいか分からない。',
          );
          expect(message, isNotEmpty);
        }
      },
    );
  }

  testWidgets('ポップアップの「ブロック」と「閉じた」を区別する', (tester) async {
    // どちらもポップアップだが、必要な対処がまったく違う。
    // ブロックは設定を変える必要があり、閉じたなら押し直せばよい。
    final blocked = await _describe(
      tester,
      FirebaseAuthException(code: 'popup-blocked'),
    );
    final closed = await _describe(
      tester,
      FirebaseAuthException(code: 'popup-closed-by-user'),
    );

    expect(blocked, isNot(closed));
  });

  group('詳細（技術的な内容）', () {
    test('知らない符号には詳細を添える', () {
      final detail = authErrorDetail(
        FirebaseAuthException(code: 'something-new', message: '説明文'),
      );

      expect(detail, isNotNull);
      expect(
        detail,
        contains('something-new'),
        reason: '汎用の文言に落ちたときは、符号を追えるようにする。'
            '実機で符号が分からず、設定の照会まで必要になった。',
      );
    });

    test('原因が分かる符号には詳細を添えない', () {
      // 文言だけで足りる。符号を並べると読み手が身構える。
      for (final code in [
        'wrong-password',
        'popup-blocked',
        'network-request-failed',
        ..._needsAction,
      ]) {
        expect(
          authErrorDetail(FirebaseAuthException(code: code)),
          isNull,
          reason: '$code は文言だけで対処が決まる',
        );
      }
    });
  });

  testWidgets('詳細を渡すと画面から読める', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('ja'),
        home: const Scaffold(
          body: ErrorMessage('エラーが発生しました。', detail: 'internal: 詳しい内容'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 畳んだ状態では出さない（利用者向けの文言を邪魔しない）。
    expect(find.text('internal: 詳しい内容'), findsNothing);
    expect(find.text('詳細'), findsOneWidget);

    await tester.tap(find.text('詳細'));
    await tester.pumpAndSettle();

    expect(find.text('internal: 詳しい内容'), findsOneWidget);
  });
}
