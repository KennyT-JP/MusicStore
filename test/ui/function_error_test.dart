/// Cloud Functions のエラー文言（仕様書 2 章）
///
/// **回帰テスト。** サーバーが返す文をそのまま画面に出していたため、
/// 英語表示でも申請・承認・招待・退会・容量変更のエラーが日本語で出ていた。
/// 呼び出し口 15 本のうち 14 本がこの形だった（監査 第2回）。
///
/// サーバーは `details.code` に符号を載せる（functions/src/errors.ts）。
/// ここではその符号すべてに、日英の文言が用意されていることを確かめる。
/// **符号の一覧はサーバー側と同じ内容にしてある。** 増やしたら両方直すこと。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/repositories/functions_repository.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/ui/widgets/error_message.dart';

/// サーバー側の符号（`functions/src/errors.ts` の `ERROR_CODES`）。
///
/// **書き写さずに、その場で読む。** 以前はここに同じ一覧を並べ、
/// 「増やしたら両方直すこと」と注意書きを添えていた。
/// 注意書きは守られないことがあるし、守られなかったときに気づけない。
/// 符号を足して画面側の対応を忘れると、**英語表示でもサーバーの
/// 日本語がそのまま出る**（監査 第2回で実際に起きた形）。
List<String> _serverErrorCodes() {
  final source = File('functions/src/errors.ts').readAsStringSync();
  final block = RegExp(
    r'ERROR_CODES\s*=\s*\[(.*?)\]',
    dotAll: true,
  ).firstMatch(source);
  expect(block, isNotNull, reason: 'errors.ts の ERROR_CODES が読めません');

  final codes = RegExp(r"'([A-Za-z]\w*)'")
      .allMatches(block!.group(1)!)
      .map((m) => m.group(1)!)
      .toList();
  expect(codes, isNotEmpty, reason: '符号を 1 つも読み取れませんでした');
  return codes;
}

/// サーバーが返す控えの文（日本語）。これが画面に出たら翻訳漏れ。
const _serverFallback = 'サーバーの文';

Future<void> _pump(
  WidgetTester tester,
  Locale locale,
  void Function(BuildContext) body,
) async {
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
          body(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
}

void main() {
  for (final locale in const [Locale('ja'), Locale('en')]) {
    testWidgets('すべての符号に文言がある（${locale.languageCode}）', (tester) async {
      final results = <String, String>{};

      await _pump(tester, locale, (context) {
        for (final code in _serverErrorCodes()) {
          results[code] = describeFunctionsError(
            context,
            FunctionsCallException(
              'internal',
              _serverFallback,
              reason: code,
              params: const {'listName': '練習音源'},
            ),
          );
        }
      });

      for (final code in _serverErrorCodes()) {
        final text = results[code]!;
        expect(text.trim(), isNotEmpty, reason: '$code の文言が空');
        expect(
          text,
          isNot(_serverFallback),
          reason: '$code の翻訳が無く、サーバーの文がそのまま出ている',
        );
      }
    });

    testWidgets('文言が使い回されていない（${locale.languageCode}）', (tester) async {
      final seen = <String, String>{};
      final duplicates = <String>[];

      await _pump(tester, locale, (context) {
        for (final code in _serverErrorCodes()) {
          final text = describeFunctionsError(
            context,
            FunctionsCallException('internal', _serverFallback, reason: code),
          );
          // 同じ文が別の符号に割り当てられていると、原因が区別できない。
          if (seen.containsKey(text)) {
            duplicates.add('$code と ${seen[text]}');
          }
          seen[text] = code;
        }
      });

      expect(duplicates, isEmpty, reason: '同じ文言を共有している符号: $duplicates');
    });
  }

  testWidgets('英語表示で日本語が出ない', (tester) async {
    final results = <String>[];

    await _pump(tester, const Locale('en'), (context) {
      for (final code in _serverErrorCodes()) {
        results.add(
          describeFunctionsError(
            context,
            FunctionsCallException(
              'internal',
              _serverFallback,
              reason: code,
              params: const {'listName': 'Practice'},
            ),
          ),
        );
      }
    });

    final japanese = RegExp(r'[぀-ヿ一-龯]');
    for (final text in results) {
      expect(japanese.hasMatch(text), isFalse, reason: '日本語が混じっている: $text');
    }
  });

  testWidgets('知らない符号ならサーバーの文を出す', (tester) async {
    // 画面がまだ知らない符号を増やしても、何も出ないより良い。
    late String text;
    await _pump(tester, const Locale('ja'), (context) {
      text = describeFunctionsError(
        context,
        const FunctionsCallException(
          'internal',
          _serverFallback,
          reason: 'somethingNew',
        ),
      );
    });
    expect(text, _serverFallback);
  });

  testWidgets('リスト名は文言に差し込まれる', (tester) async {
    late String text;
    await _pump(tester, const Locale('ja'), (context) {
      text = describeFunctionsError(
        context,
        const FunctionsCallException(
          'already-exists',
          _serverFallback,
          reason: 'listNameTaken',
          params: {'listName': '練習音源'},
        ),
      );
    });
    expect(text, contains('練習音源'));
  });
}
