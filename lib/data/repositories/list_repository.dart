/// リストとメンバー（仕様書 5 章 / 13.3）
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../firestore_paths.dart';
import '../models/app_user.dart';
import '../models/requests.dart';
import '../models/music_list.dart';

/// リストとメンバーの読み書き。
class ListRepository {
  ListRepository(this._db);

  final FirebaseFirestore _db;

  /// 自分が参加しているリストの ID と役割（仕様書 13.3）。
  ///
  /// `members` に対する collectionGroup クエリで、自分の uid のものを集める。
  ///
  /// **`FieldPath.documentId` では引けない。** コレクショングループを
  /// ドキュメント ID で引く場合、値は完全なドキュメントパスでなければならず、
  /// 素の uid は「セグメント数が奇数」として拒否される。**この誤りのために、
  /// ホームの参加リスト一覧は一度も動いていなかった。**
  /// メンバーのドキュメントが持つ `uid` 項目で引く（監査 S14 と同じ制約）。
  Stream<List<({String listId, ListMember member})>> watchMyMemberships(
    String uid,
  ) {
    return _db
        .collectionGroup(FirestorePaths.members)
        .where('uid', isEqualTo: uid)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => (
                  // lists/{listId}/members/{uid} → listId を取り出す
                  listId: doc.reference.parent.parent!.id,
                  member: ListMember.fromDoc(doc),
                ),
              )
              .toList(),
        );
  }

  Stream<MusicList?> watchList(String listId) => _db
      .doc(FirestorePaths.list(listId))
      .snapshots()
      .map((doc) => doc.exists ? MusicList.fromDoc(doc) : null);

  Future<MusicList?> fetchList(String listId) async {
    final doc = await _db.doc(FirestorePaths.list(listId)).get();
    return doc.exists ? MusicList.fromDoc(doc) : null;
  }

  /// 容量・連番などの内部情報。メンバーでなければ読めない（仕様書 13.5）。
  Stream<ListStats?> watchStats(String listId) => _db
      .doc(FirestorePaths.listStats(listId))
      .snapshots()
      .map((doc) => doc.exists ? ListStats.fromDoc(doc) : null);

  Stream<List<ListMember>> watchMembers(String listId) => _db
      .collection(FirestorePaths.listMembers(listId))
      .snapshots()
      .map((s) => s.docs.map(ListMember.fromDoc).toList());

  /// 自分のメンバー情報。参加していなければ null。
  Stream<ListMember?> watchMyMembership(String listId, String uid) => _db
      .doc(FirestorePaths.listMember(listId, uid))
      .snapshots()
      .map((doc) => doc.exists ? ListMember.fromDoc(doc) : null);

  /// 自分が出した参加申請を、リストをまたいで集める（仕様書 5.2.1）。
  ///
  /// **申請一覧にはリスト作成申請しか出ていなかった**（監査 S17）。
  /// 参加申請はリストごとの下位コレクションにあるため、
  /// `members` と同じく collectionGroup で横断的に引く。
  Stream<List<JoinRequest>> watchMyJoinRequests(String uid) => _db
      .collectionGroup(FirestorePaths.joinRequests)
      .where('uid', isEqualTo: uid)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .map(
              (doc) => JoinRequest.fromDoc(
                doc,
                // lists/{listId}/joinRequests/{uid} → listId
                listId: doc.reference.parent.parent!.id,
              ),
            )
            .toList(),
      );

  /// 表示名の解決に使うユーザー情報をまとめて引く（仕様書 13.3）。
  ///
  /// 項目・コメントには uid のみを持たせているため、表示時にここで解決する。
  ///
  /// **ID を 1 件ずつ指定して取得する。** 以前は `whereIn` を使っていたが、
  /// これは Firestore のルール上「一覧取得」に当たる。一覧を許すと
  /// 全会員のメールアドレスと表示名を一括で収集できてしまうため、
  /// `users` の一覧はサイト管理者だけに絞った（監査 S2）。
  /// 読み取るドキュメント数は `whereIn` と同じで、課金も変わらない。
  Future<Map<String, AppUser>> fetchUsers(Iterable<String> uids) async {
    final unique = uids.where((u) => u.isNotEmpty).toSet().toList();
    if (unique.isEmpty) return const {};

    final snapshots = await Future.wait(
      unique.map((uid) => _db.doc(FirestorePaths.user(uid)).get()),
    );

    return {
      for (final doc in snapshots)
        if (doc.exists) doc.id: AppUser.fromDoc(doc),
    };
  }

  Stream<AppUser?> watchUser(String uid) => _db
      .doc(FirestorePaths.user(uid))
      .snapshots()
      .map((doc) => doc.exists ? AppUser.fromDoc(doc) : null);

  /// 表示名を変更する（仕様書 3.4）。
  Future<void> updateDisplayName(String uid, String displayName) =>
      _db.doc(FirestorePaths.user(uid)).update({
        'displayName': displayName.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// 表示言語を変更する（仕様書 2 章）。
  Future<void> updateLocale(String uid, String locale) => _db
      .doc(FirestorePaths.user(uid))
      .update({'locale': locale, 'updatedAt': FieldValue.serverTimestamp()});

  /// 通知設定を保存する（仕様書 10.3）。
  Future<void> updateNotificationSettings(
    String uid,
    NotificationSettings settings,
  ) => _db.doc(FirestorePaths.user(uid)).update({
    'notificationSettings': settings.toMap(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  /// メンバーの役割を変更する（仕様書 4.3）。
  Future<void> updateMemberRole(String listId, String uid, String role) =>
      _db.doc(FirestorePaths.listMember(listId, uid)).update({'role': role});

  /// メンバーを外す／自分から抜ける（仕様書 5.4）。
  Future<void> removeMember(String listId, String uid) =>
      _db.doc(FirestorePaths.listMember(listId, uid)).delete();

  /// リストを削除する（仕様書 5.5）。
  ///
  /// 配下の項目・コメント・ファイルの削除は Cloud Functions が行う。
  /// クライアントから全件を消すと、途中で失敗したときに中途半端な状態が残る。
  Future<void> deleteList(String listId) =>
      _db.doc(FirestorePaths.list(listId)).delete();

  /// リスト名が既に使われているか調べる（仕様書 5.1）。
  ///
  /// ドキュメント ID の存在確認だけで行う。`lists` を名前で検索すると
  /// 未参加者が全リスト名を列挙できてしまうため（仕様書 5.3）。
  Future<bool> isListNameTaken(String name) async {
    final doc = await _db
        .doc(FirestorePaths.listName(normalizeListName(name)))
        .get();
    return doc.exists;
  }
}
