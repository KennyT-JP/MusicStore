/// 項目とコメント（仕様書 6 章 / 7.5 / 9 章）
library;

import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../domain/comment_tree.dart';
import '../../domain/concurrent_edit.dart';
import '../../domain/local_date.dart';
import '../../domain/quota.dart';
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
    await task;

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
      final nextSeq = (stats.data()?['nextSeq'] as num?)?.toInt() ?? 1;

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
      tx.update(statsRef, {'nextSeq': nextSeq + 1});
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
