/// アプリ全体のプロバイダ
///
/// Firebase の各サービスとリポジトリ、認証状態をここで組み立てる。
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/firestore_paths.dart';
import '../data/models/app_user.dart';
import '../data/models/list_item.dart';
import '../data/models/music_list.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/item_repository.dart';
import '../data/repositories/list_repository.dart';
import '../domain/display_name.dart';
import '../domain/role.dart';
import '../ui/app_router.dart';

// ---------------------------------------------------------------------------
// Firebase のサービス
// ---------------------------------------------------------------------------

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final firebaseStorageProvider = Provider<FirebaseStorage>(
  (ref) => FirebaseStorage.instance,
);

// ---------------------------------------------------------------------------
// リポジトリ
// ---------------------------------------------------------------------------

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(firebaseAuthProvider),
    ref.watch(firestoreProvider),
  ),
);

final listRepositoryProvider = Provider<ListRepository>(
  (ref) => ListRepository(ref.watch(firestoreProvider)),
);

final itemRepositoryProvider = Provider<ItemRepository>(
  (ref) => ItemRepository(
    ref.watch(firestoreProvider),
    ref.watch(firebaseStorageProvider),
  ),
);

// ---------------------------------------------------------------------------
// 認証状態
// ---------------------------------------------------------------------------

/// Firebase Auth のユーザー。ログイン・ログアウトのたびに流れる。
final firebaseUserProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// サイト管理者かどうか（仕様書 13.5）。
///
/// カスタムクレームで判定するため、トークンを取り直すまで反映されない。
final isSiteAdminProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return false;
  return ref.watch(authRepositoryProvider).isSiteAdmin();
});

/// 未読の通知件数（仕様書 14.1）。
final unreadNotificationCountProvider = StreamProvider<int>((ref) {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return Stream.value(0);
  return ref
      .watch(firestoreProvider)
      .collection(FirestorePaths.userNotifications(user.uid))
      .where('isRead', isEqualTo: false)
      .snapshots()
      .map((s) => s.docs.length);
});

/// ルーティングのリダイレクト判定に渡す認証状態（仕様書 14.3）。
final authStateProvider = Provider<AuthState>((ref) {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return const AuthState.signedOut();
  return AuthState(
    isSignedIn: true,
    // Google 連携でのログインは Google 側で確認済みのため常に true になる。
    isEmailVerified: user.emailVerified,
    isSiteAdmin: ref.watch(isSiteAdminProvider).value ?? false,
    unreadNotificationCount:
        ref.watch(unreadNotificationCountProvider).value ?? 0,
  );
});

/// 自分のユーザードキュメント。
final currentAppUserProvider = StreamProvider<AppUser?>((ref) {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(listRepositoryProvider).watchUser(user.uid);
});

// ---------------------------------------------------------------------------
// リスト
// ---------------------------------------------------------------------------

/// 自分が参加しているリストと、そこでの自分の役割（仕様書 14.2 ホーム）。
final myMembershipsProvider =
    StreamProvider<List<({String listId, ListMember member})>>((ref) {
      final user = ref.watch(firebaseUserProvider).value;
      if (user == null) return Stream.value(const []);
      return ref.watch(listRepositoryProvider).watchMyMemberships(user.uid);
    });

/// ホームに並べるリストの 1 行分。
class MyListEntry {
  const MyListEntry({
    required this.list,
    required this.role,
    this.stats,
  });

  final MusicList list;
  final ListRole role;

  /// リスト管理者以上にのみ表示する容量（仕様書 7.4）。
  final ListStats? stats;
}

final myListsProvider = StreamProvider<List<MyListEntry>>((ref) {
  final memberships = ref.watch(myMembershipsProvider).value;
  if (memberships == null || memberships.isEmpty) {
    return Stream.value(const []);
  }
  final repo = ref.watch(listRepositoryProvider);

  return Stream.fromFuture(
    Future.wait(
      memberships.map((m) async {
        final list = await repo.fetchList(m.listId);
        if (list == null) return null;
        return MyListEntry(list: list, role: m.member.role);
      }),
    ).then(
      (entries) => entries.whereType<MyListEntry>().toList()
        ..sort((a, b) => a.list.name.compareTo(b.list.name)),
    ),
  );
});

final listProvider = StreamProvider.family<MusicList?, String>(
  (ref, listId) => ref.watch(listRepositoryProvider).watchList(listId),
);

final listStatsProvider = StreamProvider.family<ListStats?, String>(
  (ref, listId) => ref.watch(listRepositoryProvider).watchStats(listId),
);

final listMembersProvider = StreamProvider.family<List<ListMember>, String>(
  (ref, listId) => ref.watch(listRepositoryProvider).watchMembers(listId),
);

/// このリストに対する自分の権限（仕様書 4.2）。
final listAccessProvider = Provider.family<ListAccess, String>((ref, listId) {
  final isSiteAdmin = ref.watch(isSiteAdminProvider).value ?? false;
  final memberships = ref.watch(myMembershipsProvider).value;
  final role = memberships
      ?.where((m) => m.listId == listId)
      .map((m) => m.member.role)
      .firstOrNull;
  return ListAccess(isSiteAdmin: isSiteAdmin, role: role);
});

// ---------------------------------------------------------------------------
// 項目とコメント
// ---------------------------------------------------------------------------

/// 表示名を解決するための、ユーザー情報のキャッシュ。
final userDirectoryProvider =
    FutureProvider.family<Map<String, AppUser>, Set<String>>(
      (ref, uids) => ref.watch(listRepositoryProvider).fetchUsers(uids),
    );

/// リストの項目（表示名を解決済み）。
///
/// 検索・並び替えはアプリのメモリ上で行うため（仕様書 13.6）、
/// 削除済みも含めてまとめて読み込む。
final listItemsProvider = StreamProvider.family<List<ListItem>, String>((
  ref,
  listId,
) async* {
  final repo = ref.watch(itemRepositoryProvider);
  final listRepo = ref.watch(listRepositoryProvider);

  await for (final items in repo.watchItems(listId)) {
    final memberUids =
        ref.watch(listMembersProvider(listId)).value?.map((m) => m.uid).toSet();
    final users = await listRepo.fetchUsers(items.map((i) => i.createdBy));
    yield items
        .map(
          (item) => item.withRegistrantName(
            DisplayNameResolver.resolveInList(
              uid: item.createdBy,
              user: users[item.createdBy] == null
                  ? null
                  : UserNameSource(
                      displayName: users[item.createdBy]!.displayName,
                      isWithdrawn: users[item.createdBy]!.isWithdrawn,
                    ),
              currentMemberUids: memberUids,
              withdrawnLabel: '退会したユーザー',
            ).text,
          ),
        )
        .toList();
  }
});

final itemProvider =
    StreamProvider.family<ListItem?, ({String listId, String itemId})>(
      (ref, args) => ref
          .watch(itemRepositoryProvider)
          .watchItem(args.listId, args.itemId),
    );

final itemCommentsProvider =
    StreamProvider.family<List<ItemComment>, ({String listId, String itemId})>(
      (ref, args) => ref
          .watch(itemRepositoryProvider)
          .watchComments(args.listId, args.itemId),
    );

// ---------------------------------------------------------------------------
// サイト設定
// ---------------------------------------------------------------------------

/// サイト設定（仕様書 13.3 `siteConfig/global`）。
class SiteConfig {
  const SiteConfig({
    this.inviteExpiryHours = 24,
    this.itemPurgeGraceDays = 30,
    this.siteAdminCount = 1,
  });

  final int inviteExpiryHours;
  final int itemPurgeGraceDays;
  final int siteAdminCount;
}

final siteConfigProvider = StreamProvider<SiteConfig>(
  (ref) => ref
      .watch(firestoreProvider)
      .doc(FirestorePaths.globalConfig)
      .snapshots()
      .map((doc) {
        final data = doc.data() ?? const {};
        return SiteConfig(
          inviteExpiryHours:
              (data['inviteExpiryHours'] as num?)?.toInt() ?? 24,
          itemPurgeGraceDays:
              (data['itemPurgeGraceDays'] as num?)?.toInt() ?? 30,
          siteAdminCount: (data['siteAdminCount'] as num?)?.toInt() ?? 1,
        );
      }),
);
