/// 曲の追加・編集画面（仕様書 14.4）
///
/// **回帰テスト。** ファイルを選ばずに保存を押すと、一瞬エラーが出た
/// あと曲の一覧へ戻ってしまっていた（2026-08-09 の依頼者の指摘）。
///
/// 原因は 2 つ重なっていた。
///
/// 1. **足りないまま押せた。** 必須のものが揃っていなくてもボタンが
///    活性のままだった
/// 2. **失敗しても閉じていた。** 保存処理が「入力が足りない」ときに
///    例外ではなく普通に戻っており、呼び出し側が成功と見分けられずに
///    画面を閉じていた。入力した内容ごと失われる
///
/// ここでは 1 を固定する。**2 は「失敗したら閉じない」ことなので、
/// 画面を出したまま確かめる。**
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/models/music_list.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/ui/screens/item_form_screen.dart';

const _listId = 'list-1';

Widget _app() => ProviderScope(
  overrides: [
    listProvider(_listId).overrideWith(
      (ref) => Stream.value(
        const MusicList(
          id: _listId,
          name: '練習音源',
          createdBy: 'u1',
          adminCount: 1,
          memberCount: 1,
        ),
      ),
    ),
    listStatsProvider(_listId).overrideWith((ref) => Stream.value(null)),
  ],
  child: MaterialApp(
    localizationsDelegates: const [
      AppL10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppL10n.supportedLocales,
    locale: const Locale('ja'),
    home: const ItemFormScreen(listId: _listId),
  ),
);

/// 保存ボタンの押せる・押せない。
bool _saveEnabled(WidgetTester tester) {
  final button = tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, '保存'),
  );
  return button.onPressed != null;
}

void main() {
  testWidgets('ファイルを選ぶまで保存を押せない（14.4）', (tester) async {
    // **押せるのに押すと怒られる、をやめる。**
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(_saveEnabled(tester), isFalse);
  });

  testWidgets('何が足りないかを、押す前に書いてある', (tester) async {
    // ボタンが灰色なだけでは、何をすればよいか分からない。
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('ファイルを選択してください'), findsOneWidget);
  });

  testWidgets('URL のタブでは、URL を入れると押せるようになる', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('URL').first);
    await tester.pumpAndSettle();

    // 空のうちは押せない。要るものも書いてある。
    expect(_saveEnabled(tester), isFalse);
    expect(find.text('URL を入力してください'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      'https://example.com/song',
    );
    await tester.pumpAndSettle();

    // **1 文字目で満たされる。** 入力に追従していないと、
    // 条件を満たしても押せないままになる。
    expect(_saveEnabled(tester), isTrue);
  });

  testWidgets('URL を消すと、また押せなくなる', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('URL').first);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'https://example.com');
    await tester.pumpAndSettle();
    expect(_saveEnabled(tester), isTrue);

    // 空白だけにしても、入っていないものとして扱う。
    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.pumpAndSettle();
    expect(_saveEnabled(tester), isFalse);
  });

  testWidgets('タブを切り替えると、要るものが切り替わる', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('URL').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'https://example.com');
    await tester.pumpAndSettle();
    expect(_saveEnabled(tester), isTrue);

    // ファイルのタブへ戻ると、URL があってもファイルが要る。
    await tester.tap(find.text('ファイル').first);
    await tester.pumpAndSettle();
    expect(_saveEnabled(tester), isFalse);
  });
}
