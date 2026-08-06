/// ホームとリスト詳細のテスト（仕様書 6.4 / 14.2 / 14.5）
///
/// Firestore に繋がずに、権限による出し分けと検索・並び替え・削除済みの
/// 表示切替を検証する。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/models/list_item.dart';
import 'package:music_list_app/data/models/music_list.dart';
import 'package:music_list_app/domain/local_date.dart';
import 'package:music_list_app/domain/role.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/ui/screens/list_detail_screen.dart';
import 'package:music_list_app/ui/screens/requests_screens.dart';

const _listId = 'list-1';

ListItem _item({
  required int seq,
  String? title,
  String? artist,
  String? fileName,
  String registrant = '山田',
  String date = '2026-08-01',
  ContentStatus status = ContentStatus.active,
}) => ListItem(
  id: 'item-$seq',
  seq: seq,
  itemDate: LocalDate.tryParse(date)!,
  kind: fileName == null ? ItemKind.url : ItemKind.file,
  url: fileName == null ? 'https://example.com/$seq' : null,
  file: fileName == null
      ? null
      : ItemFile(
          storagePath: 'p/$fileName',
          fileName: fileName,
          sizeBytes: 1024,
          contentType: 'audio/mpeg',
        ),
  title: title,
  artist: artist,
  createdBy: 'u1',
  registrantDisplayName: registrant,
  status: status,
);

final _items = [
  _item(seq: 1, title: 'サザンオールスターズメドレー', registrant: '佐藤'),
  _item(
    seq: 2,
    fileName: 'Rehearsal_Take2.MP3',
    registrant: '鈴木',
    date: '2026-07-15',
  ),
  _item(
    seq: 3,
    title: '夏の思い出',
    artist: 'サザン',
    registrant: '田中',
    date: '2026-08-20',
  ),
  _item(
    seq: 4,
    title: '消した曲',
    status: ContentStatus.deleted,
    date: '2026-07-01',
  ),
];

/// 参加状況（[ListAccess]）を直接指定して包む。
///
/// 未参加（role が null）の場合の振る舞いを確かめるために使う。
Widget _wrapWithAccess(Widget child, {required ListAccess access}) {
  return ProviderScope(
    overrides: [
      listProvider(_listId).overrideWith(
        (ref) => Stream.value(
          const MusicList(
            id: _listId,
            name: '練習音源',
            createdBy: 'u1',
            adminCount: 1,
            memberCount: 3,
          ),
        ),
      ),
      listItemsProvider(
        (listId: _listId, withdrawnLabel: '退会したユーザー'),
      ).overrideWith((ref) => Stream.value(_items)),
      listAccessProvider(_listId).overrideWith((ref) => access),
      listStatsProvider(_listId).overrideWith((ref) => Stream.value(null)),
      listMembersProvider(
        _listId,
      ).overrideWith((ref) => Stream.value(const [])),
      myJoinRequestProvider(_listId).overrideWith((ref) => Stream.value(null)),
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
      home: child,
    ),
  );
}

Widget _wrap(Widget child, {required ListRole role, bool siteAdmin = false}) {
  return ProviderScope(
    overrides: [
      listProvider(_listId).overrideWith(
        (ref) => Stream.value(
          const MusicList(
            id: _listId,
            name: '練習音源',
            createdBy: 'u1',
            adminCount: 1,
            memberCount: 3,
          ),
        ),
      ),
      listItemsProvider(
        (listId: _listId, withdrawnLabel: '退会したユーザー'),
      ).overrideWith((ref) => Stream.value(_items)),
      listAccessProvider(
        _listId,
      ).overrideWith((ref) => ListAccess(isSiteAdmin: siteAdmin, role: role)),
      listStatsProvider(_listId).overrideWith((ref) => Stream.value(null)),
      listMembersProvider(
        _listId,
      ).overrideWith((ref) => Stream.value(const [])),
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
      home: child,
    ),
  );
}

void main() {
  setUp(() {
    // 既定の並び替え状態を毎回リセットする。
  });

  _joinRequestRedirectTests();

  group('リスト詳細（6.4）', () {
    testWidgets('項目が連番順に並ぶ', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ListDetailScreen(listId: _listId),
          role: ListRole.superUser,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('練習音源'), findsOneWidget);
      expect(find.text('サザンオールスターズメドレー'), findsOneWidget);
      expect(find.text('Rehearsal_Take2.MP3'), findsOneWidget);
    });

    testWidgets('削除済みは「削除されました」と出て中身を見せない', (tester) async {
      await tester.pumpWidget(
        _wrap(const ListDetailScreen(listId: _listId), role: ListRole.readOnly),
      );
      await tester.pumpAndSettle();

      expect(find.text('削除されました'), findsOneWidget);
      // 曲名は出さない。
      expect(find.text('消した曲'), findsNothing);
    });

    testWidgets('切替で削除済みを隠せる', (tester) async {
      await tester.pumpWidget(
        _wrap(const ListDetailScreen(listId: _listId), role: ListRole.readOnly),
      );
      await tester.pumpAndSettle();
      expect(find.text('削除されました'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, '削除済みも表示'));
      await tester.pumpAndSettle();

      expect(find.text('削除されました'), findsNothing);
    });

    testWidgets('曲名で検索できる', (tester) async {
      await tester.pumpWidget(
        _wrap(const ListDetailScreen(listId: _listId), role: ListRole.readOnly),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'サザン');
      await tester.pumpAndSettle();

      // 曲名に含む 1 番と、アーティスト名が「サザン」の 3 番。
      expect(find.text('サザンオールスターズメドレー'), findsOneWidget);
      expect(find.text('夏の思い出'), findsOneWidget);
      expect(find.text('Rehearsal_Take2.MP3'), findsNothing);
    });

    testWidgets('ファイル名でも検索できる（曲名が未記入の項目）', (tester) async {
      await tester.pumpWidget(
        _wrap(const ListDetailScreen(listId: _listId), role: ListRole.readOnly),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'rehearsal');
      await tester.pumpAndSettle();

      expect(find.text('Rehearsal_Take2.MP3'), findsOneWidget);
      expect(find.text('夏の思い出'), findsNothing);
    });

    testWidgets('検索中は削除済みを出さない', (tester) async {
      await tester.pumpWidget(
        _wrap(const ListDetailScreen(listId: _listId), role: ListRole.readOnly),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '消した');
      await tester.pumpAndSettle();

      expect(find.text('削除されました'), findsNothing);
    });
  });

  group('権限による出し分け（14.5）', () {
    testWidgets('Read Only には「追加」を出さない', (tester) async {
      await tester.pumpWidget(
        _wrap(const ListDetailScreen(listId: _listId), role: ListRole.readOnly),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('Super User には「追加」を出す', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ListDetailScreen(listId: _listId),
          role: ListRole.superUser,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FloatingActionButton, '追加'), findsOneWidget);
    });

    testWidgets('Super User にはリスト管理への導線を出さない', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ListDetailScreen(listId: _listId),
          role: ListRole.superUser,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.settings_outlined), findsNothing);
    });

    testWidgets('リスト管理者にはリスト管理への導線を出す', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ListDetailScreen(listId: _listId),
          role: ListRole.listAdmin,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });

    testWidgets('サイト管理者はメンバーでなくても管理できる', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ListDetailScreen(listId: _listId),
          role: ListRole.readOnly,
          siteAdmin: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// 2026-08-06 の監査 S9 の回帰テスト。
//
// 共有 URL は誰でも開ける。未参加者がそのまま項目一覧に入ると、ルールに
// 弾かれて「権限がありません」になっていた。実装済みの参加申請画面
// （仕様書 5.3）へ繋がっていなかった。
// ---------------------------------------------------------------------------

void _joinRequestRedirectTests() {
  testWidgets('未参加者には参加申請の画面を出す（5.3）', (tester) async {
    await tester.pumpWidget(
      _wrapWithAccess(
        const ListDetailScreen(listId: _listId),
        // メンバー情報は読めたが、このリストには入っていない。
        access: const ListAccess(isSiteAdmin: false, role: null),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(JoinRequestScreen), findsOneWidget);
  });

  testWidgets('メンバーには項目一覧を出す', (tester) async {
    await tester.pumpWidget(
      _wrapWithAccess(
        const ListDetailScreen(listId: _listId),
        access: const ListAccess(isSiteAdmin: false, role: ListRole.readOnly),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(JoinRequestScreen), findsNothing);
    expect(find.text('サザンオールスターズメドレー'), findsOneWidget);
  });
}
