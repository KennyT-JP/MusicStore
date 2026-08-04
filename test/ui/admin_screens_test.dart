/// 管理系画面のテスト（仕様書 5.1 / 5.2 / 5.2.1 / 4.5 / 11.1 / 14.5）
///
/// Firestore に繋がずに、権限による出し分けと申請の見え方を検証する。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/models/music_list.dart';
import 'package:music_list_app/data/models/requests.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/ui/screens/requests_screens.dart';
import 'package:music_list_app/ui/screens/site_admin_screens.dart';

ListRequest _request({
  required String id,
  required String name,
  RequestStatus status = RequestStatus.pending,
  String? createdListId,
}) => ListRequest(
  id: id,
  listName: name,
  estimatedTrackCount: 10,
  expectedUserCount: 3,
  purpose: '練習用',
  requestedBy: 'u1',
  status: status,
  createdListId: createdListId,
);

/// 画面を日本語ロケールの MaterialApp で包む。
///
/// ProviderScope は呼び出し側で被せる。`Override` 型が flutter_riverpod から
/// 公開されていないため、overrides を引数で受け取る形にはできない。
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

void main() {
  group('自分の申請一覧（5.2.1）', () {
    testWidgets('申請中・承認・却下を出し分ける', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myListRequestsProvider.overrideWith(
              (ref) => Stream.value([
                _request(id: 'r1', name: '申請中のリスト'),
                _request(
                  id: 'r2',
                  name: '承認されたリスト',
                  status: RequestStatus.approved,
                  createdListId: 'list-1',
                ),
                _request(
                  id: 'r3',
                  name: '却下されたリスト',
                  status: RequestStatus.rejected,
                ),
              ]),
            ),
          ],
          child: _app(const MyRequestsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('申請中'), findsOneWidget);
      expect(find.text('承認'), findsOneWidget);
      expect(find.text('却下'), findsOneWidget);
    });

    testWidgets('却下された申請には再申請ボタンを出す', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myListRequestsProvider.overrideWith(
              (ref) => Stream.value([
                _request(
                  id: 'r1',
                  name: '却下されたリスト',
                  status: RequestStatus.rejected,
                ),
              ]),
            ),
          ],
          child: _app(const MyRequestsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('もう一度申請する'), findsOneWidget);
    });

    testWidgets('承認された申請にはリストを開くボタンを出す', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myListRequestsProvider.overrideWith(
              (ref) => Stream.value([
                _request(
                  id: 'r1',
                  name: '承認されたリスト',
                  status: RequestStatus.approved,
                  createdListId: 'list-1',
                ),
              ]),
            ),
          ],
          child: _app(const MyRequestsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('リストを開く'), findsOneWidget);
      expect(find.text('もう一度申請する'), findsNothing);
    });

    testWidgets('申請がなければ作成申請へ誘導する', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            myListRequestsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
          ],
          child: _app(const MyRequestsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('まだ申請はありません。'), findsOneWidget);
      expect(find.text('リスト作成を申請'), findsOneWidget);
    });
  });

  group('リスト作成の申請（5.1）', () {
    testWidgets('必要な項目がそろっている', (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: _app(const RequestListScreen())),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // 5.1 で定めた 4 項目。
      expect(find.text('リスト名'), findsOneWidget);
      expect(find.text('概算の登録曲数'), findsOneWidget);
      expect(find.text('使用者数'), findsOneWidget);
      expect(find.text('作成目的'), findsOneWidget);
    });

    testWidgets('未入力なら検証で止まる', (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: _app(const RequestListScreen())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'リスト作成を申請'));
      await tester.pumpAndSettle();

      expect(find.text('リスト名を入力してください'), findsOneWidget);
      expect(find.text('作成目的を入力してください'), findsOneWidget);
    });
  });

  group('サイト管理（11.1 / 5.6）', () {
    testWidgets('未処理の申請件数をバッジで出す', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pendingListRequestsProvider.overrideWith(
              (ref) => Stream.value([
                _request(id: 'r1', name: 'A'),
                _request(id: 'r2', name: 'B'),
              ]),
            ),
            allListsProvider.overrideWith((ref) => Stream.value(const [])),
          ],
          child: _app(const SiteAdminHomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('管理者不在のリスト件数を警告として出す（5.6）', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pendingListRequestsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
            allListsProvider.overrideWith(
              (ref) => Stream.value(const [
                MusicList(
                  id: 'l1',
                  name: '管理者のいないリスト',
                  createdBy: 'u1',
                  adminCount: 0,
                  memberCount: 2,
                ),
                MusicList(
                  id: 'l2',
                  name: '通常のリスト',
                  createdBy: 'u1',
                  adminCount: 1,
                  memberCount: 3,
                ),
              ]),
            ),
          ],
          child: _app(const SiteAdminHomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // 管理者不在は 1 件。
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('申請がなければその旨を出す', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pendingListRequestsProvider.overrideWith(
              (ref) => Stream.value(const []),
            ),
          ],
          child: _app(const SiteAdminListRequestsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('保留中の申請はありません。'), findsOneWidget);
    });

    testWidgets('申請の内容と承認・却下ボタンを出す', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pendingListRequestsProvider.overrideWith(
              (ref) => Stream.value([_request(id: 'r1', name: 'バンド練習')]),
            ),
          ],
          child: _app(const SiteAdminListRequestsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('バンド練習'), findsOneWidget);
      expect(find.text('約 10 曲'), findsOneWidget);
      expect(find.text('3 人'), findsOneWidget);
      expect(find.text('練習用'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '承認'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '却下'), findsOneWidget);
    });
  });

  group('ユーザー管理（4.5）', () {
    List<SiteUser> users({required int adminCount}) => [
      SiteUser(
        uid: 'a1',
        email: 'admin@example.com',
        displayName: '管理者',
        isSiteAdmin: true,
        isWithdrawn: false,
      ),
      if (adminCount >= 2)
        SiteUser(
          uid: 'a2',
          email: 'admin2@example.com',
          displayName: '管理者2',
          isSiteAdmin: true,
          isWithdrawn: false,
        ),
      SiteUser(
        uid: 'u1',
        email: 'user@example.com',
        displayName: '一般ユーザー',
        isSiteAdmin: false,
        isWithdrawn: false,
      ),
    ];

    testWidgets('最後の 1 人は「管理者から外す」を押せない', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            siteUsersProvider.overrideWith((ref) async => users(adminCount: 1)),
          ],
          child: _app(const SiteAdminUsersScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '管理者から外す'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('2 人以上いれば外せる', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            siteUsersProvider.overrideWith((ref) async => users(adminCount: 2)),
          ],
          child: _app(const SiteAdminUsersScreen()),
        ),
      );
      await tester.pumpAndSettle();

      final buttons = tester
          .widgetList<TextButton>(find.widgetWithText(TextButton, '管理者から外す'))
          .toList();
      expect(buttons.length, 2);
      expect(buttons.every((b) => b.onPressed != null), isTrue);
    });

    testWidgets('一般ユーザーには昇格ボタンを出す', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            siteUsersProvider.overrideWith((ref) async => users(adminCount: 1)),
          ],
          child: _app(const SiteAdminUsersScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('サイト管理者にする'), findsOneWidget);
    });

    testWidgets('退会したユーザーは名前を出さず操作もさせない（3.5）', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            siteUsersProvider.overrideWith(
              (ref) async => [
                const SiteUser(
                  uid: 'w1',
                  email: 'gone@example.com',
                  displayName: '退会した人',
                  isSiteAdmin: false,
                  isWithdrawn: true,
                ),
              ],
            ),
          ],
          child: _app(const SiteAdminUsersScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('退会したユーザー'), findsOneWidget);
      expect(find.text('退会した人'), findsNothing);
      expect(find.text('サイト管理者にする'), findsNothing);
    });
  });
}
