/// 共有リンクを開いた画面（仕様書 3.3）
///
/// **押す前に、何が起きるかが書いてあること。**
/// 「参加する」と「参加せずに見る」は結果がまるで違う。
/// 選ばせるなら、選ぶ材料を先に出す。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/repositories/functions_repository.dart';
import 'package:music_list_app/domain/share_link.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/ui/screens/share_link_screen.dart';

/// 何を頼まれたかだけを覚える、呼び出し口の差し替え。
class _RecordingFunctions implements FunctionsRepository {
  _RecordingFunctions({this.rejection});

  final ShareLinkRejection? rejection;
  final calls = <({String linkId, bool join})>[];

  @override
  Future<ShareLinkResult> acceptShareLink(
    String linkId, {
    required bool join,
  }) async {
    calls.add((linkId: linkId, join: join));
    if (rejection != null) throw ShareLinkRejectedException(rejection!);
    return ShareLinkResult(listId: 'list-1', joined: join);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Widget _app(_RecordingFunctions functions, {Locale locale = const Locale('ja')}) =>
    ProviderScope(
      overrides: [
        functionsRepositoryProvider.overrideWithValue(functions),
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
        home: const ShareLinkScreen(linkId: 'abc'),
      ),
    );

void main() {
  testWidgets('2 つの選び方を、どちらも出す', (tester) async {
    await tester.pumpWidget(_app(_RecordingFunctions()));
    await tester.pumpAndSettle();

    expect(find.text('参加する'), findsOneWidget);
    expect(find.text('参加せずに見る'), findsOneWidget);
  });

  testWidgets('押す前に、それぞれ何が起きるかを書いてある', (tester) async {
    await tester.pumpWidget(_app(_RecordingFunctions()));
    await tester.pumpAndSettle();

    // 参加する側：通知が届くこと、名前が出ることが読み取れる。
    expect(find.textContaining('メンバーになります'), findsOneWidget);
    expect(find.textContaining('通知'), findsWidgets);

    // 見るだけの側：メンバーにならないこと、書けないことが読み取れる。
    expect(find.textContaining('メンバーにはなりません'), findsOneWidget);
    expect(find.textContaining('書き込みもできません'), findsOneWidget);
  });

  testWidgets('「参加する」は join として送る', (tester) async {
    final functions = _RecordingFunctions();
    await tester.pumpWidget(_app(functions));
    await tester.pumpAndSettle();

    await tester.tap(find.text('参加する'));
    await tester.pumpAndSettle();

    expect(functions.calls, [(linkId: 'abc', join: true)]);
  });

  testWidgets('「参加せずに見る」は view として送る', (tester) async {
    final functions = _RecordingFunctions();
    await tester.pumpWidget(_app(functions));
    await tester.pumpAndSettle();

    await tester.tap(find.text('参加せずに見る'));
    await tester.pumpAndSettle();

    // **join を false で送ること。** ここを取り違えると、
    // 見るだけのつもりの人が勝手にメンバーにされる。
    expect(functions.calls, [(linkId: 'abc', join: false)]);
  });

  testWidgets('あとから参加できることを書いてある', (tester) async {
    // 「見るだけ」を選ぶ心理的な障壁を下げる。取り返しがつくと分かれば選べる。
    await tester.pumpWidget(_app(_RecordingFunctions()));
    await tester.pumpAndSettle();

    expect(find.textContaining('あとから'), findsWidgets);
  });

  testWidgets('取り消されたリンクは、そう伝える', (tester) async {
    // **「見つかりません」と混ぜない。** 受け取った人が次に取る行動が違う。
    // 取り消しなら「新しいリンクを依頼する」、見つからないなら「URL を確かめる」。
    await tester.pumpWidget(
      _app(_RecordingFunctions(rejection: ShareLinkRejection.revoked)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('参加する'));
    await tester.pumpAndSettle();

    expect(find.textContaining('取り消されています'), findsOneWidget);
  });

  testWidgets('見つからないリンクは、URL の確認を促す', (tester) async {
    await tester.pumpWidget(
      _app(_RecordingFunctions(rejection: ShareLinkRejection.notFound)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('参加する'));
    await tester.pumpAndSettle();

    expect(find.textContaining('URL'), findsOneWidget);
  });

  testWidgets('英語でも 2 つの選び方が出る', (tester) async {
    await tester.pumpWidget(
      _app(_RecordingFunctions(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Join'), findsOneWidget);
    expect(find.text('View without joining'), findsOneWidget);
    // 日本語が混ざらないこと。
    expect(find.textContaining(RegExp(r'[ぁ-んァ-ヶ一-龠]')), findsNothing);
  });
}
