/// アプリ全体のプロバイダ
///
/// Firebase の各サービスとリポジトリ、認証状態をここで組み立てる。
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/firestore_paths.dart';
import '../data/models/app_user.dart';
import '../data/models/list_item.dart';
import '../data/models/music_list.dart';
import '../data/models/requests.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/functions_repository.dart';
import '../data/repositories/item_repository.dart';
import '../data/repositories/list_repository.dart';
import '../env/firebase_emulators.dart';
import '../domain/display_name.dart';
import '../domain/quota.dart';
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

final firebaseFunctionsProvider = Provider<FirebaseFunctions>(
  (ref) => FirebaseFunctions.instanceFor(region: kFunctionsRegion),
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

final functionsRepositoryProvider = Provider<FunctionsRepository>(
  (ref) => FunctionsRepository(ref.watch(firebaseFunctionsProvider)),
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
  const MyListEntry({required this.list, required this.role, this.stats});

  final MusicList list;
  final ListRole role;

  /// リスト管理者以上にのみ表示する容量（仕様書 7.4）。
  final ListStats? stats;
}

final myListsProvider = StreamProvider<List<MyListEntry>>((ref) {
  // **`.value` で受けてはいけない。**
  //
  // AsyncValue の `.value` は、エラーのときも読み込み中のときも null を返す。
  // 以前はここで null を「参加 0 件」に丸めていたため、権限の拒否も
  // 索引の不足も通信の失敗も、すべて画面では
  // 「まだどのリストにも参加していません。」という**断定的な文言**になった。
  // ログイン直後に全員が通る画面で、再読み込みの導線すら出なかった
  // （監査 第2回。実際、以前の「リストを作ってもホームに出ない」不具合は
  // この表示のせいで原因が見えなかった）。
  //
  // エラーはエラーのまま、読み込み中は読み込み中のまま流す。
  final memberships = ref.watch(myMembershipsProvider);

  if (memberships.hasError) {
    return Stream<List<MyListEntry>>.error(
      memberships.error!,
      memberships.stackTrace,
    );
  }
  // まだ 1 度も値が来ていない＝読み込み中。値を流さず待たせる。
  if (!memberships.hasValue) return const Stream<List<MyListEntry>>.empty();

  final value = memberships.requireValue;
  if (value.isEmpty) return Stream.value(const []);

  final repo = ref.watch(listRepositoryProvider);

  return Stream.fromFuture(
    Future.wait(
      value.map((m) async {
        final list = await repo.fetchList(m.listId);
        if (list == null) return null;
        return MyListEntry(list: list, role: m.member.role);
      }),
    ).then(
      (entries) =>
          entries.whereType<MyListEntry>().toList()
            ..sort((a, b) => a.list.name.compareTo(b.list.name)),
    ),
  );
});

final listProvider = StreamProvider.autoDispose.family<MusicList?, String>(
  (ref, listId) => ref.watch(listRepositoryProvider).watchList(listId),
);

final listStatsProvider = StreamProvider.autoDispose.family<ListStats?, String>(
  (ref, listId) => ref.watch(listRepositoryProvider).watchStats(listId),
);

final listMembersProvider =
    StreamProvider.autoDispose.family<List<ListMember>, String>(
  (ref, listId) => ref.watch(listRepositoryProvider).watchMembers(listId),
);

/// 参加せずに見るだけの人（仕様書 3.3）。リスト管理者だけが読める。
final listViewersProvider =
    StreamProvider.autoDispose.family<List<String>, String>(
  (ref, listId) => ref.watch(listRepositoryProvider).watchViewers(listId),
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
//
// **リストや項目ごとに作られるプロバイダは autoDispose にすること。**
// Riverpod の既定は非 autoDispose で、ProviderScope はアプリ全体に 1 つしか
// 無い。そのため一度でも監視したキーの購読が、画面を離れてもセッション中
// ずっと残る。項目詳細を 50 件開けば snapshot の listener が 50 本残り、
// 閲覧時間に比例してメモリと通信が増え続けていた（監査 S7）。
// ---------------------------------------------------------------------------

/// 表示名を解決するための、ユーザー情報のキャッシュ。
/// [userDirectoryProvider] に渡すキーを作る。
///
/// **Set をそのままキーにしてはいけない。** Dart の Set は `==` を
/// 上書きしないため、中身が同じでも別のキーとして扱われる。画面が再描画
/// されるたびに新しいプロバイダとクエリが作られ、キャッシュに当たらない
/// （監査 性能-S3）。並び順を固定した文字列にして同一性を保つ。
String userDirectoryKey(Iterable<String> uids) {
  final unique = uids.where((u) => u.isNotEmpty).toSet().toList()..sort();
  return unique.join(',');
}

final userDirectoryProvider =
    FutureProvider.autoDispose.family<Map<String, AppUser>, String>(
      (ref, key) => ref
          .watch(listRepositoryProvider)
          .fetchUsers(key.isEmpty ? const <String>[] : key.split(',')),
    );

/// [listItemsProvider] / [itemProvider] に渡す引数。
///
/// **退会者の表示名を引数で受け取る。** プロバイダは BuildContext を
/// 持たないため l10n を引けない。以前は日本語の定数を直接使っており、
/// 英語表示のときだけ項目一覧の登録者名が「退会したユーザー」になり、
/// 同じ画面群のコメント欄は "Former member" という混在が起きていた
/// （監査 第2回）。画面側から l10n.withdrawnUser を渡す。
typedef ItemsArgs = ({String listId, String withdrawnLabel});

/// リストの項目（表示名を解決済み）。
///
/// 検索・並び替えはアプリのメモリ上で行うため（仕様書 13.6）、
/// 削除済みも含めてまとめて読み込む。
final listItemsProvider =
    StreamProvider.autoDispose.family<List<ListItem>, ItemsArgs>((
  ref,
  args,
) async* {
  final listId = args.listId;
  final repo = ref.watch(itemRepositoryProvider);
  final listRepo = ref.watch(listRepositoryProvider);

  // **メンバー一覧が届くまで、項目の購読を始めない。**
  //
  // 以前は `await for` の**中で** listMembersProvider を watch していた。
  // members は最初 AsyncLoading で、直後に AsyncData へ変わるため、
  // プロバイダが必ず 1 回作り直され、**items の購読が 2 本張られて
  // 全件を 2 回読んでいた**（項目 1000 件のリストなら 1 回開くたびに +1000）。
  // さらに破棄済みの Ref に対する watch で未捕捉の例外が出ていた
  // （監査 第2回）。
  final members = ref.watch(listMembersProvider(listId));
  if (!members.hasValue) return;
  final memberUids = members.requireValue.map((m) => m.uid).toSet();

  // 表示名は覚えておき、まだ知らない人のぶんだけ引く。
  // 以前はスナップショットが届くたびに全員ぶんを引き直しており、
  // 誰かが 1 件足すたびに、閲覧中の全員が人数ぶんの読み取りを起こしていた。
  final known = <String, UserNameSource?>{};

  await for (final items in repo.watchItems(listId)) {
    final missing = items
        .map((i) => i.createdBy)
        .where((uid) => !known.containsKey(uid))
        .toSet();
    if (missing.isNotEmpty) {
      final fetched = await listRepo.fetchUsers(missing);
      for (final uid in missing) {
        final user = fetched[uid];
        known[uid] = user == null
            ? null
            : UserNameSource(
                displayName: user.displayName,
                isWithdrawn: user.isWithdrawn,
              );
      }
    }

    yield items
        .map(
          (item) => item.withRegistrantName(
            DisplayNameResolver.resolveInList(
              uid: item.createdBy,
              user: known[item.createdBy],
              currentMemberUids: memberUids,
              withdrawnLabel: args.withdrawnLabel,
            ).text,
          ),
        )
        .toList();
  }
});

final itemProvider =
    StreamProvider.autoDispose
        .family<ListItem?, ({String listId, String itemId})>(
      (ref, args) =>
          ref.watch(itemRepositoryProvider).watchItem(args.listId, args.itemId),
    );

final itemCommentsProvider =
    StreamProvider.autoDispose
        .family<List<ItemComment>, ({String listId, String itemId})>(
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
    this.defaultQuotaBytes = kDefaultQuotaBytes,
    this.siteAdminCount = 1,
  });

  final int inviteExpiryHours;
  final int itemPurgeGraceDays;

  /// 新規リストの容量上限の初期値（仕様書 13.3）。
  ///
  /// **読まずに定数で埋めていたため、設定画面で保存するたびに 1GB へ
  /// 戻っていた**（監査 S10）。サーバーはこの値を見てリストを作るので、
  /// 画面側も必ずここから読むこと。
  final int defaultQuotaBytes;

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
          inviteExpiryHours: (data['inviteExpiryHours'] as num?)?.toInt() ?? 24,
          itemPurgeGraceDays:
              (data['itemPurgeGraceDays'] as num?)?.toInt() ?? 30,
          defaultQuotaBytes:
              (data['defaultQuotaBytes'] as num?)?.toInt() ?? kDefaultQuotaBytes,
          siteAdminCount: (data['siteAdminCount'] as num?)?.toInt() ?? 1,
        );
      }),
);

// ---------------------------------------------------------------------------
// 通知（仕様書 10 / 14.2）
// ---------------------------------------------------------------------------

/// 自分の通知を新しい順に監視する。
final myNotificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection(FirestorePaths.userNotifications(user.uid))
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((s) => s.docs.map(AppNotification.fromDoc).toList());
});

// ---------------------------------------------------------------------------
// 申請（仕様書 5.1 / 5.2 / 5.2.1）
// ---------------------------------------------------------------------------

/// 自分が出したリスト作成申請（仕様書 5.2.1）。
final myListRequestsProvider = StreamProvider<List<ListRequest>>((ref) {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection(FirestorePaths.listRequests)
      .where('requestedBy', isEqualTo: user.uid)
      .orderBy('requestedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(ListRequest.fromDoc).toList());
});

/// 自分が出した参加申請（リストをまたぐ／仕様書 5.2.1）。
final myJoinRequestsProvider = StreamProvider<List<JoinRequest>>((ref) {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(listRepositoryProvider).watchMyJoinRequests(user.uid);
});

/// 保留中のリスト作成申請（サイト管理者向け／仕様書 5.1）。
final pendingListRequestsProvider = StreamProvider<List<ListRequest>>((ref) {
  final isSiteAdmin = ref.watch(isSiteAdminProvider).value ?? false;
  if (!isSiteAdmin) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection(FirestorePaths.listRequests)
      .where('status', isEqualTo: 'pending')
      .orderBy('requestedAt')
      .snapshots()
      .map((s) => s.docs.map(ListRequest.fromDoc).toList());
});

/// リストの保留中の参加申請（リスト管理者向け／仕様書 5.2）。
final pendingJoinRequestsProvider =
    StreamProvider.autoDispose.family<List<JoinRequest>, String>((ref, listId) {
      return ref
          .watch(firestoreProvider)
          .collection(FirestorePaths.listJoinRequests(listId))
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map(
            (s) => s.docs
                .map((doc) => JoinRequest.fromDoc(doc, listId: listId))
                .toList(),
          );
    });

/// このリストへの自分の参加申請（仕様書 5.3 / 5.2.1）。
final myJoinRequestProvider =
    StreamProvider.autoDispose.family<JoinRequest?, String>((
  ref,
  listId,
) {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return Stream.value(null);
  return ref
      .watch(firestoreProvider)
      .doc(FirestorePaths.listJoinRequest(listId, user.uid))
      .snapshots()
      .map(
        (doc) => doc.exists ? JoinRequest.fromDoc(doc, listId: listId) : null,
      );
});

// ---------------------------------------------------------------------------
// サイト管理（仕様書 11.1）
// ---------------------------------------------------------------------------

/// 全リスト（サイト管理者のみ列挙できる／仕様書 5.3 / 13.5）。
final allListsProvider = StreamProvider<List<MusicList>>((ref) {
  final isSiteAdmin = ref.watch(isSiteAdminProvider).value ?? false;
  if (!isSiteAdmin) return Stream.value(const []);
  return ref
      .watch(firestoreProvider)
      .collection(FirestorePaths.lists)
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map(MusicList.fromDoc).toList());
});

/// ユーザーの一覧（サイト管理者のみ）。
///
/// サイト管理者かどうかは Auth のカスタムクレームにしかないため、
/// Cloud Functions 経由で取得する（仕様書 13.5）。
final siteUsersProvider = FutureProvider<List<SiteUser>>((ref) async {
  final isSiteAdmin = ref.watch(isSiteAdminProvider).value ?? false;
  if (!isSiteAdmin) return const [];
  return ref.watch(functionsRepositoryProvider).listSiteUsers();
});
