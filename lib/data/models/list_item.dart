/// リスト項目とコメント（仕様書 13.3）
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/comment_tree.dart';
import '../../domain/item_query.dart';
import '../../domain/local_date.dart';

/// 項目の種別（仕様書 6.1）。1 項目＝ファイル 1 つ、または URL 1 つ。
enum ItemKind {
  file('file'),
  url('url');

  const ItemKind(this.wireName);

  final String wireName;

  static ItemKind? tryParse(String? value) {
    for (final k in ItemKind.values) {
      if (k.wireName == value) return k;
    }
    return null;
  }
}

/// ソフト削除の状態（仕様書 6.2）。
enum ContentStatus {
  active('active'),
  deleted('deleted');

  const ContentStatus(this.wireName);

  final String wireName;

  static ContentStatus tryParse(String? value) =>
      value == deleted.wireName ? deleted : active;
}

/// 項目に添付されたファイル。
class ItemFile {
  const ItemFile({
    required this.storagePath,
    required this.fileName,
    required this.sizeBytes,
    required this.contentType,
  });

  final String storagePath;
  final String fileName;
  final int sizeBytes;
  final String contentType;

  factory ItemFile.fromMap(Map<String, dynamic> map) => ItemFile(
    storagePath: map['storagePath'] as String? ?? '',
    fileName: map['fileName'] as String? ?? '',
    sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
    contentType: map['contentType'] as String? ?? '',
  );

  Map<String, dynamic> toMap() => {
    'storagePath': storagePath,
    'fileName': fileName,
    'sizeBytes': sizeBytes,
    'contentType': contentType,
  };
}

/// リスト項目。
///
/// [ItemQueryInput] を継承しているので、検索・並び替え（domain/item_query.dart）に
/// そのまま渡せる。
class ListItem extends ItemQueryInput {
  ListItem({
    required this.id,
    required super.seq,
    required LocalDate itemDate,
    required this.kind,
    required this.createdBy,
    required super.registrantDisplayName,
    required this.status,
    this.file,
    this.url,
    super.title,
    super.artist,
    this.createdAt,
    this.updatedAt,
    this.updatedBy,
    this.deletedAt,
    this.purgeAt,
  }) : itemDate = itemDate,
       super(
         date: itemDate.toIso8601Date(),
         isDeleted: status == ContentStatus.deleted,
         fileName: file?.fileName,
       );

  final String id;

  /// 録音日想定。タイムゾーンを持たない年月日（仕様書 6.2）。
  final LocalDate itemDate;

  final ItemKind kind;
  final ItemFile? file;
  final String? url;
  final String createdBy;
  final ContentStatus status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? updatedBy;
  final DateTime? deletedAt;

  /// ファイル本体を完全削除する予定日時（仕様書 13.4）。
  final DateTime? purgeAt;

  /// 猶予期間中で、復元できる状態か（仕様書 6.3）。
  bool withinGracePeriod(DateTime now) {
    final purge = purgeAt;
    if (purge == null) return false;
    return now.isBefore(purge);
  }

  /// 一覧に出す表題。曲名がなければアーティスト名、それもなければファイル名や URL。
  String displayLabel() {
    final t = title?.trim();
    if (t != null && t.isNotEmpty) return t;
    final a = artist?.trim();
    if (a != null && a.isNotEmpty) return a;
    if (kind == ItemKind.file) return file?.fileName ?? '';
    return url ?? '';
  }

  factory ListItem.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String registrantDisplayName,
  }) {
    final data = doc.data() ?? const {};
    final rawFile = data['file'] as Map<String, dynamic>?;
    return ListItem(
      id: doc.id,
      seq: (data['seq'] as num?)?.toInt() ?? 0,
      itemDate:
          LocalDate.tryParse(data['date'] as String?) ?? LocalDate.today(),
      kind: ItemKind.tryParse(data['kind'] as String?) ?? ItemKind.url,
      file: rawFile == null ? null : ItemFile.fromMap(rawFile),
      url: data['url'] as String?,
      title: data['title'] as String?,
      artist: data['artist'] as String?,
      createdBy: data['createdBy'] as String? ?? '',
      registrantDisplayName: registrantDisplayName,
      status: ContentStatus.tryParse(data['status'] as String?),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      updatedBy: data['updatedBy'] as String?,
      deletedAt: (data['deletedAt'] as Timestamp?)?.toDate(),
      purgeAt: (data['purgeAt'] as Timestamp?)?.toDate(),
    );
  }

  /// 表示名だけを差し替える。
  ///
  /// 項目には uid のみを持ち、名前は表示時に解決する（仕様書 13.3）。
  ListItem withRegistrantName(String name) => ListItem(
    id: id,
    seq: seq,
    itemDate: itemDate,
    kind: kind,
    file: file,
    url: url,
    title: title,
    artist: artist,
    createdBy: createdBy,
    registrantDisplayName: name,
    status: status,
    createdAt: createdAt,
    updatedAt: updatedAt,
    updatedBy: updatedBy,
    deletedAt: deletedAt,
    purgeAt: purgeAt,
  );
}

/// コメント（仕様書 9 / 13.3）。
///
/// [CommentNodeInput] を継承しているので、ツリー組み立て
/// （domain/comment_tree.dart）にそのまま渡せる。
class ItemComment extends CommentNodeInput {
  const ItemComment({
    required super.id,
    required super.parentId,
    required super.path,
    required super.createdAt,
    required this.body,
    required this.createdBy,
    required this.status,
    this.updatedAt,
  });

  final String body;
  final String createdBy;
  final ContentStatus status;
  final DateTime? updatedAt;

  bool get isDeleted => status == ContentStatus.deleted;

  factory ItemComment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return ItemComment(
      id: doc.id,
      parentId: data['parentId'] as String?,
      path:
          (data['path'] as List<dynamic>?)?.cast<String>() ?? const <String>[],
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      body: data['body'] as String? ?? '',
      createdBy: data['createdBy'] as String? ?? '',
      status: ContentStatus.tryParse(data['status'] as String?),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
