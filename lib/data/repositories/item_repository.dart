/// 項目とコメント（仕様書 6 章 / 7.5 / 9 章）
library;

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../domain/comment_tree.dart';
import '../../domain/concurrent_edit.dart';
import '../../domain/local_date.dart';
import '../../domain/quota.dart';
import '../../domain/sequence.dart';
import '../firestore_paths.dart';
import '../models/list_item.dart';

/// 同時編集で保存を中止したときに投げる（仕様書 6.3）。
class ConcurrentEditException implements Exception {
  const ConcurrentEditException();
}

/// 容量上限でアップロードをブロックしたときに投げる（仕様書 7.3）。
class QuotaExceededException implements Exception {
  const QuotaExceededException(this.reason);

  final UploadBlockReason reason;
}

/// アップロードの進捗。
typedef UploadProgressCallback = void Function(double fraction);

/// アップロードを利用者が中止したときに投げる（仕様書 7.5 / 14.4）。
///
/// 通信の失敗と区別するために専用の型にしている。中止は失敗ではないので、
/// 画面ではエラーとして見せない。
class UploadCanceledException implements Exception {
  const UploadCanceledException();

  @override
  String toString() => 'UploadCanceledException';
}

/// 項目とコメントの読み書き。
class ItemRepository {
  ItemRepository(this._db, this._storage);

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  // -------------------------------------------------------------------
  // 項目
  // -------------------------------------------------------------------

  /// リストの項目をすべて監視する。
  ///
  /// 検索はアプリのメモリ上で行うため（仕様書 13.6）、削除済みも含めて
  /// まとめて読み込む。並び替えと絞り込みは domain/item_query.dart が担う。
  Stream<List<ListItem>> watchItems(String listId) => _db
      .collection(FirestorePaths.listItems(listId))
      .orderBy('seq')
      .snapshots()
      .map(
        (s) => s.docs
            .map((doc) => ListItem.fromDoc(doc, registrantDisplayName: ''))
            .toList(),
      );

  Stream<ListItem?> watchItem(String listId, String itemId) => _db
      .doc(FirestorePaths.listItem(listId, itemId))
      .snapshots()
      .map(
        (doc) => doc.exists
            ? ListItem.fromDoc(doc, registrantDisplayName: '')
            : null,
      );

  /// [fetchItemsByIds] が 1 回のクエリに詰める ID の数。
  ///
  /// **Firestore の `whereIn` には上限がある。** いまの上限は 30 だが、
  /// **10 にしてある。** 読み取りの課金は「返ったドキュメントの数」で
  /// 決まるので、分割を細かくしても**費用は 1 円も変わらない**
  /// （増えるのは往復の回数だけ）。上限の解釈を間違えたときの代償
  /// ——本番でクエリごと失敗する——のほうがはるかに高い。
  static const int _idsPerQuery = 10;

  /// 同期のために、前に見たときより新しい項目だけを読む
  /// （docs/DOWNLOAD-DESIGN.md 4.4）。
  ///
  /// **`status` で絞らないこと。** 同期は「消えたものを端末からも消す」
  /// ために使う。`status == 'active'` を足すと**ソフト削除された項目が
  /// クエリから消え**、端末には落としたものが永遠に残る（論点 11）。
  ///
  /// **`orderBy` を足さないこと。** いまは `updatedAt` 1 つの範囲だけなので
  /// Firestore の自動索引で足りるが、並び替えや 2 つ目の絞り込みを足すと
  /// **合成索引が要る**。エミュレータは索引を強制しないので、
  /// 足りないことに統合テストでは気づけず、**本番だけが落ちる**
  /// （10 節の危険 7。2026-08-10 にユーザー削除で実際に起きた）。
  /// この形を `test/domain/download_sync_query_test.dart` が見張っている。
  ///
  /// **無い項目はここでは分からない。** 消えたドキュメントは「更新された
  /// ドキュメント」として上がってこない。存在の確認は [fetchItemsByIds]。
  Future<List<ListItem>> fetchItemsUpdatedAfter(
    String listId,
    DateTime since,
  ) async {
    final snapshot = await _db
        .collection(FirestorePaths.listItems(listId))
        .where('updatedAt', isGreaterThan: Timestamp.fromDate(since))
        .get();
    return snapshot.docs
        .map((doc) => ListItem.fromDoc(doc, registrantDisplayName: ''))
        .toList();
  }

  /// ID を並べて項目を読む（4.4 の「ドキュメントが無い」の判定）。
  ///
  /// **返るのは見つかったものだけ。** 呼ぶ側は「返ってこなかった ID」を
  /// **消えた**と読む。ドキュメントごと消える経路は実在する——
  /// アカウント削除（`functions/src/callable/user_admin.ts` の
  /// `deleteSiteUser`）は、その人が登録した曲を `doc.ref.delete()` で
  /// 物理削除する。**`updatedAt` は動かないので、
  /// [fetchItemsUpdatedAfter] には一生上がってこない。**
  ///
  /// ドキュメント ID による絞り込みなので、**索引は要らない**
  /// （キーの索引は Firestore が必ず持っている）。
  Future<List<ListItem>> fetchItemsByIds(
    String listId,
    Iterable<String> itemIds,
  ) async {
    final ids = itemIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const [];

    final collection = _db.collection(FirestorePaths.listItems(listId));
    final found = <ListItem>[];
    for (var from = 0; from < ids.length; from += _idsPerQuery) {
      final to = from + _idsPerQuery;
      final snapshot = await collection
          .where(
            FieldPath.documentId,
            whereIn: ids.sublist(from, to > ids.length ? ids.length : to),
          )
          .get();
      found.addAll(
        snapshot.docs.map(
          (doc) => ListItem.fromDoc(doc, registrantDisplayName: ''),
        ),
      );
    }
    return found;
  }

  /// URL の項目を追加する（仕様書 6.1）。
  ///
  /// 連番はトランザクションで採番し、重複しないようにする（仕様書 6.2）。
  Future<String> addUrlItem({
    required String listId,
    required String uid,
    required String url,
    required LocalDate date,
    String? title,
    String? artist,
  }) => _createItem(
    listId: listId,
    uid: uid,
    date: date,
    title: title,
    artist: artist,
    kind: ItemKind.url,
    extra: {'url': url.trim()},
  );

  /// ファイルの項目を追加する（仕様書 7.5）。
  ///
  /// **先に Storage へアップロードし、成功してから項目を作成する。**
  /// 途中で失敗すれば項目はできず、連番も消費しない。
  Future<String> addFileItem({
    required String listId,
    required String uid,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required LocalDate date,
    required QuotaStatus quota,
    String? title,
    String? artist,
    UploadProgressCallback? onProgress,
    void Function(UploadTask task)? onTaskStarted,
  }) async {
    // アップロードを始める前に容量を確認する。無駄な通信と課金を避ける。
    final decision = QuotaPolicy.canStartUpload(
      status: quota,
      fileSizeBytes: bytes.length,
    );
    if (!decision.allowed) {
      throw QuotaExceededException(decision.reason!);
    }

    // 項目 ID を先に決める。ファイルの置き場所を確定させるため。
    final itemRef = _db.collection(FirestorePaths.listItems(listId)).doc();
    final storagePath = StoragePaths.itemFile(
      listId: listId,
      itemId: itemRef.id,
      fileName: fileName,
    );

    final task = _storage
        .ref(storagePath)
        .putData(bytes, SettableMetadata(contentType: contentType));
    if (onProgress != null) {
      task.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes > 0) {
          onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
        }
      });
    }

    // **中止できるように、進行中のタスクを呼び出し元へ渡す（仕様書 7.5 / 14.4）。**
    // 以前は task を await するだけで、外から止める手段が無かった（監査 S16）。
    // 大きな音源のアップロードを始めてしまうと、完了まで待つしかなかった。
    onTaskStarted?.call(task);

    try {
      await task;
    } on FirebaseException catch (e) {
      // 中止したときは canceled が返る。失敗ではないので専用の例外にする。
      if (e.code == 'canceled') throw const UploadCanceledException();
      rethrow;
    }

    return _createItem(
      listId: listId,
      uid: uid,
      date: date,
      title: title,
      artist: artist,
      kind: ItemKind.file,
      itemRef: itemRef,
      extra: {
        'file': ItemFile(
          storagePath: storagePath,
          fileName: fileName,
          sizeBytes: bytes.length,
          contentType: contentType,
        ).toMap(),
      },
    );
  }

  /// 差し替える新しいファイルを置く（仕様書 6.3 / 13.7）。
  ///
  /// **置くだけ。** 項目が指す先を移すのは Functions（`replaceItemFile`）で、
  /// そちらが旧ファイルを猶予つきで `previousFiles` に積む。
  /// クライアントからその項目は書けない（firestore.rules）——書けると、
  /// 他人のリストのパスを紛れ込ませてサーバーに消させられる（監査 S1）。
  ///
  /// 戻り値は置いた場所。そのまま `replaceItemFile` に渡す。
  Future<String> uploadReplacementFile({
    required String listId,
    required String itemId,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
    required QuotaStatus quota,
    UploadProgressCallback? onProgress,
    void Function(UploadTask task)? onTaskStarted,
  }) async {
    // 送る前に容量を確かめる（追加のときと同じ）。
    // **旧ファイルは猶予のあいだ数え続ける**（依頼者の決定・2026-08-14）ので、
    // 差し替えは一時的に 2 つぶんを使う。ここを甘くすると、送り終えてから
    // サーバーに断られる。
    final decision = QuotaPolicy.canStartUpload(
      status: quota,
      fileSizeBytes: bytes.length,
    );
    if (!decision.allowed) {
      throw QuotaExceededException(decision.reason!);
    }

    // **必ず別の場所へ置く。** 同じ場所への上書きは storage.rules が
    // 禁じているし、上書きできてしまうと**旧ファイルを残せない**
    // （実体が 1 つしかなくなる）。
    final storedName = '${DateTime.now().millisecondsSinceEpoch}-$fileName';
    final storagePath = StoragePaths.itemFile(
      listId: listId,
      itemId: itemId,
      fileName: storedName,
    );

    final task = _storage
        .ref(storagePath)
        .putData(bytes, SettableMetadata(contentType: contentType));
    if (onProgress != null) {
      task.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes > 0) {
          onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
        }
      });
    }
    onTaskStarted?.call(task);

    try {
      await task;
    } on FirebaseException catch (e) {
      if (e.code == 'canceled') throw const UploadCanceledException();
      rethrow;
    }

    return storagePath;
  }

  Future<String> _createItem({
    required String listId,
    required String uid,
    required LocalDate date,
    required ItemKind kind,
    required Map<String, dynamic> extra,
    String? title,
    String? artist,
    DocumentReference<Map<String, dynamic>>? itemRef,
  }) async {
    final ref =
        itemRef ?? _db.collection(FirestorePaths.listItems(listId)).doc();
    final statsRef = _db.doc(FirestorePaths.listStats(listId));

    await _db.runTransaction((tx) async {
      final stats = await tx.get(statsRef);

      // **採番の規則は domain/sequence.dart に置いてある。**
      // 以前はここで直接 +1 しており、テストで手厚く守られていた
      // SequenceCounter は**本番から一度も呼ばれていなかった**
      // （監査 S11・第2回）。テストがあることと、守られていることは別。
      final counter = SequenceCounter(
        (stats.data()?['nextSeq'] as num?)?.toInt() ?? 1,
      );
      final allocation = counter.allocate();
      final nextSeq = allocation.seq;

      tx.set(ref, {
        'seq': nextSeq,
        'date': date.toIso8601Date(),
        'kind': kind.wireName,
        if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
        if (artist != null && artist.trim().isNotEmpty) 'artist': artist.trim(),
        'createdBy': uid,
        'status': ContentStatus.active.wireName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        ...extra,
      });
      // 連番は振り直さない。削除しても戻さない（仕様書 6.2）。
      tx.update(statsRef, {'nextSeq': allocation.updatedCounter.nextSeq});
    });

    return ref.id;
  }

  /// 項目を編集する（仕様書 6.3）。
  ///
  /// 保存時に「開いてから他の人が更新していないか」を確認し、
  /// 更新されていれば [ConcurrentEditException] を投げる。
  Future<void> updateItem({
    required String listId,
    required String itemId,
    required String uid,
    required DateTime? openedWith,
    required LocalDate date,
    String? title,
    String? artist,
    String? url,
    ItemFile? file,
  }) async {
    final ref = _db.doc(FirestorePaths.listItem(listId, itemId));

    await _db.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      final current = (snapshot.data()?['updatedAt'] as Timestamp?)?.toDate();

      if (ConcurrentEditGuard.check(
            openedWith: openedWith,
            currentOnServer: current,
          ) ==
          SaveDecision.conflict) {
        throw const ConcurrentEditException();
      }

      tx.update(ref, {
        'date': date.toIso8601Date(),
        'title': title?.trim().isNotEmpty == true ? title!.trim() : null,
        'artist': artist?.trim().isNotEmpty == true ? artist!.trim() : null,
        if (url != null) ...{
          'kind': ItemKind.url.wireName,
          'url': url.trim(),
          'file': null,
        },
        if (file != null) ...{
          'kind': ItemKind.file.wireName,
          'file': file.toMap(),
          'url': null,
        },
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// 項目を削除する（仕様書 6.2 / 13.4）。
  ///
  /// 物理削除はせず、status を deleted にする。連番は欠番として残す。
  /// ファイル本体は猶予期間の経過後に Cloud Functions が削除する。
  Future<void> deleteItem({
    required String listId,
    required String itemId,
    required String uid,
    required int graceDays,
  }) => _db.doc(FirestorePaths.listItem(listId, itemId)).update({
    'status': ContentStatus.deleted.wireName,
    'deletedBy': uid,
    'deletedAt': FieldValue.serverTimestamp(),
    'purgeAt': Timestamp.fromDate(
      DateTime.now().add(Duration(days: graceDays)),
    ),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  /// 削除した項目を復元する（仕様書 6.3）。猶予期間中のみ。
  Future<void> restoreItem({
    required String listId,
    required String itemId,
    required String uid,
  }) => _db.doc(FirestorePaths.listItem(listId, itemId)).update({
    'status': ContentStatus.active.wireName,
    'deletedBy': null,
    'deletedAt': null,
    'purgeAt': null,
    'updatedBy': uid,
    'updatedAt': FieldValue.serverTimestamp(),
  });

  /// ファイルのダウンロード URL を取り出す（仕様書 8 章）。
  Future<String> downloadUrl(String storagePath) =>
      _storage.ref(storagePath).getDownloadURL();

  // -------------------------------------------------------------------
  // コメント
  // -------------------------------------------------------------------

  /// 項目のコメントを 1 回のクエリで全件取得する（仕様書 13.3）。
  ///
  /// ツリーへの組み直しは domain/comment_tree.dart が担う。
  Stream<List<ItemComment>> watchComments(String listId, String itemId) => _db
      .collection(FirestorePaths.itemComments(listId, itemId))
      .snapshots()
      .map((s) => s.docs.map(ItemComment.fromDoc).toList());

  /// コメント・返信を投稿する（仕様書 9 章）。
  Future<void> addComment({
    required String listId,
    required String itemId,
    required String uid,
    required String body,
    ItemComment? parent,
  }) {
    final path = CommentTree.pathForReply(parent);
    return _db.collection(FirestorePaths.itemComments(listId, itemId)).add({
      'body': body.trim(),
      'parentId': parent?.id,
      'path': path,
      'depth': path.length,
      'createdBy': uid,
      'status': ContentStatus.active.wireName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// コメントを編集する（仕様書 9 章）。同時編集の検出つき。
  Future<void> updateComment({
    required String listId,
    required String itemId,
    required String commentId,
    required String body,
    required DateTime? openedWith,
  }) async {
    final ref = _db.doc(FirestorePaths.itemComment(listId, itemId, commentId));
    await _db.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      final current = (snapshot.data()?['updatedAt'] as Timestamp?)?.toDate();
      if (ConcurrentEditGuard.check(
            openedWith: openedWith,
            currentOnServer: current,
          ) ==
          SaveDecision.conflict) {
        throw const ConcurrentEditException();
      }
      tx.update(ref, {
        'body': body.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// コメントを削除する（仕様書 9 章）。
  ///
  /// 返信がぶら下がっているのでソフト削除にする。物理削除するとツリーが切れる。
  Future<void> deleteComment({
    required String listId,
    required String itemId,
    required String commentId,
  }) => _db.doc(FirestorePaths.itemComment(listId, itemId, commentId)).update({
    'status': ContentStatus.deleted.wireName,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
