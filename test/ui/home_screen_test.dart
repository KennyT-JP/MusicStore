/// ホーム画面のテスト（仕様書 5.2.1 / 14.2）
///
/// **回帰テスト。** 参加リストが 0 件のとき、画面に「リストを作成する」しか
/// 置いておらず、**申請一覧へ行く手段がなかった**。申請を出した直後は必ず
/// この状態になるため、自分の申請がどうなったかを確認できなかった。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/role.dart';
import 'package:music_list_app/data/models/music_list.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/ui/screens/home_screen.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppL10n.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppL10n.supportedLocales,
  locale: const Locale('ja'),
  home: child,
);

MyListEntry _entry() => MyListEntry(
  list: MusicList(
    id: 'list-1',
    name: '練習音源',
    createdBy: 'u1',
    memberCount: 3,
    adminCount: 1,
  ),
  role: ListRole.superUser,
);

void main() {
  testWidgets('参加リストが 0 件でも申請一覧へ行ける', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myListsProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: _app(const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 申請の導線と、その状態を見る導線の両方が要る。
    expect(find.text('リスト作成を申請'), findsOneWidget);
    expect(find.text('自分の申請'), findsOneWidget);
  });

  testWidgets('参加リストがあるときも申請一覧へ行ける', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myListsProvider.overrideWith((ref) => Stream.value([_entry()])),
        ],
        child: _app(const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('練習音源'), findsOneWidget);
    expect(find.text('自分の申請'), findsOneWidget);
  });

  // **届く前に「0件」と言い切らない（2026-08-11 の実機確認）。**
  //
  // 曲数はリスト本体とは別に読みに行くので、開いた直後は届いていない。
  // 以前は `?? 0` で既定に倒しており、**中身があるのに数秒のあいだ
  // 「0件」と出て**いた。「空である」と「まだ取れていない」は別のことで、
  // 0 と書くと前者にしか読めない（AUDIT-CHECKLIST 観点 2）。
  group('曲数が届く前の見え方', () {
    testWidgets('届いていないあいだは件数を出さない', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myListsProvider.overrideWith((ref) => Stream.value([_entry()])),
            // 値を流さない＝まだ届いていない状態。
            listStatsProvider.overrideWith(
              (ref, listId) => const Stream<ListStats?>.empty(),
            ),
          ],
          child: _app(const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('練習音源'), findsOneWidget);
      expect(
        find.textContaining('件'),
        findsNothing,
        reason: '届いていないのに 0 という確定した数を出してはいけない',
      );
    });

    testWidgets('届いたら件数を出す', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myListsProvider.overrideWith((ref) => Stream.value([_entry()])),
            listStatsProvider.overrideWith(
              (ref, listId) => Stream.value(
                const ListStats(
                  nextSeq: 5,
                  usedBytes: 0,
                  quotaBytes: 1,
                  itemCount: 4,
                ),
              ),
            ),
          ],
          child: _app(const HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('4件'), findsOneWidget);
    });
  });
}
