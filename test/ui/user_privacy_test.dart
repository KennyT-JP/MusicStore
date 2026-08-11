/// 私的な情報を画面に出さない／私的な情報から読む（2026-08-11 の分離）
///
/// **回帰テスト。**
///
/// 1. **メールアドレスを画面に出さない。** メンバー一覧・閲覧者一覧・
///    参加申請の一覧に出していた。同じリストにいるだけで全員の連絡先が
///    分かる状態だった。依頼者が「見せない」と判断（2026-08-11）
/// 2. **自分の設定は `users/{uid}/private/state` から読む。**
///    表示言語・通知設定・プレミアムの期限・容量はそちらにある
/// 3. **届く前に既定値を出さない。** 「日本語」「通知はすべてオン」
///    「プレミアムではありません」を先に描くと、直後に別の値へ
///    入れ替わる（docs/AUDIT-CHECKLIST.md 観点 2）
/// 4. **保存に失敗したら、そう伝える。** 切り替えたのに元へ戻るだけだと、
///    押し損ねたようにしか見えない（監査 第4回）
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:music_list_app/data/models/app_user.dart';
import 'package:music_list_app/data/models/music_list.dart';
import 'package:music_list_app/data/models/requests.dart';
import 'package:music_list_app/data/repositories/list_repository.dart';
import 'package:music_list_app/domain/role.dart';
import 'package:music_list_app/l10n/app_localizations.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/ui/screens/list_admin_screens.dart';
import 'package:music_list_app/ui/screens/settings_screen.dart';

class _FakeListRepository extends Mock implements ListRepository {}

const _listId = 'list-1';
const _oneGb = 1024 * 1024 * 1024;

/// この人のメールアドレス。**どの画面にも出てはいけない。**
/// 画面が持てないことは型で保証されているので、ここでは
/// 「@ を含む文字がどこにも出ていない」ことで確かめる。
const _email = 'taro@example.com';

Widget _wrap(Widget child) => MaterialApp(
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

AppUser _appUser(String uid, String name) =>
    AppUser(uid: uid, displayName: name, isWithdrawn: false);

UserPrivate _private({
  String locale = 'ja',
  NotificationSettings? notificationSettings,
  DateTime? premiumUntil,
  UserStorage? storage,
}) => UserPrivate(
  email: _email,
  locale: locale,
  notificationSettings: notificationSettings ?? const NotificationSettings(),
  premiumUntil: premiumUntil,
  storage: storage,
);

/// リスト管理の画面に必要なぶんだけを差し替える。
///
/// **型を書かずに推論に任せる。** `Override` 型は flutter_riverpod から
/// 公開されていない（admin_screens_test.dart と同じ制約）。
final _listOverrides = [
  // ログインしている人（自分）は使わないので、届かないままにする。
  firebaseUserProvider.overrideWith((ref) => const Stream.empty()),
  listProvider(_listId).overrideWith(
    (ref) => Stream.value(
      const MusicList(
        id: _listId,
        name: '練習音源',
        createdBy: 'u1',
        adminCount: 1,
        memberCount: 2,
      ),
    ),
  ),
  listAccessProvider(_listId).overrideWith(
    (ref) => const ListAccess(isSiteAdmin: false, role: ListRole.listAdmin),
  ),
];

/// 設定画面は縦に長い。**下まで描かれた状態で確かめる**ため、
/// 背の高い画面にする（ListView は画面外を組み立てない）。
void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget _settings({
  required AsyncValue<UserPrivate?> private,
  ListRepository? repository,
}) => ProviderScope(
  overrides: [
    currentAppUserProvider.overrideWith(
      (ref) => Stream.value(_appUser('u1', '太郎')),
    ),
    currentUserPrivateProvider.overrideWith(
      (ref) => switch (private) {
        AsyncData(:final value) => Stream.value(value),
        _ => const Stream<UserPrivate?>.empty(),
      },
    ),
    if (repository != null)
      listRepositoryProvider.overrideWithValue(repository),
  ],
  child: _wrap(const SettingsScreen()),
);

void main() {
  setUpAll(() {
    registerFallbackValue(const NotificationSettings());
  });

  group('メールアドレスを画面に出さない（2026-08-11）', () {
    testWidgets('メンバー一覧にも閲覧者一覧にも出さない', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._listOverrides,
            listMembersProvider(_listId).overrideWith(
              (ref) => Stream.value(const [
                ListMember(uid: 'u1', role: ListRole.listAdmin),
                ListMember(uid: 'u2', role: ListRole.readOnly),
              ]),
            ),
            listViewersProvider(
              _listId,
            ).overrideWith((ref) => Stream.value(const ['u3'])),
            userDirectoryProvider(userDirectoryKey(const ['u1', 'u2']))
                .overrideWith(
                  (ref) async => {
                    'u1': _appUser('u1', '太郎'),
                    'u2': _appUser('u2', '花子'),
                  },
                ),
            userDirectoryProvider(
              userDirectoryKey(const ['u3']),
            ).overrideWith((ref) async => {'u3': _appUser('u3', '次郎')}),
          ],
          child: _wrap(const ListMembersScreen(listId: _listId)),
        ),
      );
      await tester.pumpAndSettle();

      // 誰なのかは表示名で分かる。
      expect(find.text('太郎'), findsOneWidget);
      expect(find.text('花子'), findsOneWidget);
      expect(find.text('次郎'), findsOneWidget);

      // **連絡先はどこにも出ていない。**
      expect(find.text(_email), findsNothing);
      expect(find.textContaining('@'), findsNothing);
    });

    testWidgets('参加申請の一覧にも出さない', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ..._listOverrides,
            pendingJoinRequestsProvider(_listId).overrideWith(
              (ref) => Stream.value(const [
                JoinRequest(
                  uid: 'u2',
                  listId: _listId,
                  status: RequestStatus.pending,
                ),
              ]),
            ),
            userDirectoryProvider(
              userDirectoryKey(const ['u2']),
            ).overrideWith((ref) async => {'u2': _appUser('u2', '花子')}),
          ],
          child: _wrap(const ListJoinRequestsScreen(listId: _listId)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('花子'), findsOneWidget);
      expect(find.text(_email), findsNothing);
      expect(find.textContaining('@'), findsNothing);
    });
  });

  group('自分の設定は private から読む', () {
    testWidgets('表示言語', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(
        _settings(private: AsyncData(_private(locale: 'en'))),
      );
      await tester.pumpAndSettle();

      final button = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      );
      expect(button.selected, {'en'});
    });

    testWidgets('通知設定', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(
        _settings(
          private: AsyncData(
            _private(
              notificationSettings: const NotificationSettings(master: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tiles = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      expect(tiles.first.value, isFalse);
      // マスターがオフなら種別ごとの切り替えは効かない。
      for (final tile in tiles.skip(1)) {
        expect(tile.onChanged, isNull);
      }
    });

    testWidgets('プレミアムの期限', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(
        _settings(
          private: AsyncData(_private(premiumUntil: DateTime(2027, 3, 31, 12))),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2027/03/31 12:00 までプレミアムをご利用いただけます。'), findsOneWidget);
    });

    testWidgets('容量の使用量と上限', (tester) async {
      _tallScreen(tester);
      await tester.pumpWidget(
        _settings(
          private: AsyncData(
            _private(
              storage: const UserStorage(
                usedBytes: _oneGb,
                quotaBytes: 2 * _oneGb,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1.0 GB / 2.0 GB'), findsOneWidget);
    });
  });

  // **届く前に確定した値を出さない**（「0件」問題と同じ形）。
  // 表示名は公開されるほうから先に届くが、それに釣られて
  // 私的な設定まで既定値で描いてはいけない。
  testWidgets('private が届くまで、設定の既定値を出さない', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(
      _settings(private: const AsyncLoading<UserPrivate?>()),
    );
    await tester.pump();

    final l10n = await AppL10n.delegate.load(const Locale('ja'));

    // 公開されるほうは届いているので、表示名の欄は出ている。
    expect(find.text(l10n.displayName), findsOneWidget);

    // 私的なほうは、まだ何も出さない。
    expect(find.byType(SegmentedButton<String>), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text(l10n.premiumInactive), findsNothing);
    expect(find.text(l10n.myStorageUnknown), findsNothing);
    expect(find.textContaining('0 B'), findsNothing);

    // 代わりに、読み込み中だと分かるようにしておく。
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  // **黙って捨てない（監査 第4回）。** `users/{uid}/private/state` は
  // 移行前の人にはまだ無いことがあり、書き込みは `set(merge: true)` で
  // 作りにいく。それでもルールや通信で断られることはあるので、
  // 失敗したことは必ず画面に出す。
  group('保存に失敗したら、そう伝える', () {
    testWidgets('表示言語', (tester) async {
      _tallScreen(tester);
      final repository = _FakeListRepository();
      when(
        () => repository.updateLocale(any(), any()),
      ).thenThrow(Exception('書けなかった'));

      await tester.pumpWidget(
        _settings(
          private: AsyncData(_private()),
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();

      verify(() => repository.updateLocale('u1', 'en')).called(1);
      final l10n = await AppL10n.delegate.load(const Locale('ja'));
      expect(find.text(l10n.operationFailed), findsOneWidget);
    });

    testWidgets('通知設定', (tester) async {
      _tallScreen(tester);
      final repository = _FakeListRepository();
      when(
        () => repository.updateNotificationSettings(any(), any()),
      ).thenThrow(Exception('書けなかった'));

      await tester.pumpWidget(
        _settings(
          private: AsyncData(_private()),
          repository: repository,
        ),
      );
      await tester.pumpAndSettle();

      // 先頭はマスタースイッチ。
      await tester.tap(find.byType(SwitchListTile).first);
      await tester.pumpAndSettle();

      verify(() => repository.updateNotificationSettings('u1', any())).called(1);
      final l10n = await AppL10n.delegate.load(const Locale('ja'));
      expect(find.text(l10n.operationFailed), findsOneWidget);
    });
  });
}
