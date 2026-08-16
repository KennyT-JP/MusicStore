/// 目録の JSON 変換（docs/DOWNLOAD-DESIGN.md 3.5）
///
/// ## なぜ `lib/domain/download_index.dart` ではなく、ここに置いたか
///
/// **依頼の条件は「目録の形が 2 か所にならないこと」だった。**
/// 形（項目の一覧）は `lib/domain/download_index.dart` の
/// [DownloadIndex] / [DownloadedItem] / [OfflineComment] **だけ**にある。
/// このファイルは**その型と JSON のあいだの写し方**しか持たず、
/// 独自の項目一覧を作らない（[DownloadedItem] を直接組み立てて返す）。
/// **形は 1 か所、写し方も 1 か所である。**
///
/// そのうえでデータ層に置いた理由は 3 つ。
///
/// 1. **domain 側が自分で禁じている。** `download_index.dart` の冒頭は
///    「**型だけを置く。読み書きはここではしない。**」と書いてある。
///    そこへ `toJson` を足すと、その注記が最初の 1 歩で嘘になる
/// 2. **このリポジトリの流儀に合う。** `fromDoc` / `toMap` は
///    `lib/data/models/` にあり（`list_item.dart` の [ItemFile] など）、
///    `lib/domain/` は判定だけを持つ。**保存の形は外の世界の都合**で、
///    版を上げる・古い版を読むといった話は domain の関心事ではない
/// 3. **domain のテストを重くしない。** `lib/domain/` の回帰テストは
///    通信も端末も要らないことが取り柄で、JSON の壊れ方の網羅は
///    ファイルを触るテスト（8.3）と一緒に置いたほうが読みやすい
///
/// ## 読めなかったときは null を返す（消さないため）
///
/// **既定を「空の目録」にしない。** 空だと 4.7 の掃除が
/// 「目録に載っていないディレクトリ」を全部消し、**壊れた 1 行のために
/// 端末の音源が全部消える。** 読めないことと、何も持っていないことは違う。
library;

import 'dart:convert';

import '../../domain/download_index.dart';
import '../../domain/local_date.dart';

/// `index.json` と `comments.json` の読み書き（3.5）。
class DownloadIndexCodec {
  const DownloadIndexCodec._();

  /// `index.json` の中身を組み立てる。
  ///
  /// **`items` は `index.json` に載っている順のまま出す。** 並べ替えは
  /// 画面の仕事（6.1 は「リストごとにまとめ、リスト内は `seq` 順」）で、
  /// 目録は持っている順を保つ。
  static String encode(DownloadIndex index) =>
      const JsonEncoder.withIndent('  ').convert(toMap(index));

  /// [encode] が書く形。テストから直接確かめられるように分けてある。
  static Map<String, dynamic> toMap(DownloadIndex index) => {
    'version': index.version,
    'lastVerifiedAt': index.lastVerifiedAt?.millisecondsSinceEpoch,
    'allowMobileData': index.allowMobileData,
    'items': index.items.map(_itemToMap).toList(),
  };

  /// `index.json` を読む。**読めなければ null**（このファイルの冒頭）。
  static DownloadIndex? tryDecode(String source) {
    try {
      final raw = jsonDecode(source);
      if (raw is! Map) return null;
      final items = raw['items'];
      if (items is! List) return null;

      final parsed = <DownloadedItem>[];
      for (final entry in items) {
        if (entry is! Map) return null;
        final item = _itemFromMap(entry.cast<String, dynamic>());
        // **1 件でも読めなければ、目録ごと読めなかったことにする。**
        // 黙って飛ばすと、その曲のファイルが孤児になって
        // 次の掃除で消える（10 節の 1）。
        if (item == null) return null;
        parsed.add(item);
      }

      return DownloadIndex(
        version: (raw['version'] as num?)?.toInt() ?? kDownloadIndexVersion,
        lastVerifiedAt: _timeFrom(raw['lastVerifiedAt']),
        allowMobileData: raw['allowMobileData'] == true,
        items: parsed,
      );
    } on FormatException {
      return null;
    }
  }

  /// `comments.json` を組み立てる（3.5）。
  static String encodeComments({
    required String itemId,
    required DateTime syncedAt,
    required List<OfflineComment> comments,
  }) => const JsonEncoder.withIndent('  ').convert({
    'itemId': itemId,
    'syncedAt': syncedAt.millisecondsSinceEpoch,
    'comments': comments
        .map(
          (c) => {
            'id': c.id,
            'body': c.body,
            'authorName': c.authorName,
            'parentId': c.parentId,
            'path': c.path,
            'depth': c.depth,
            'status': c.status,
            'createdAt': c.createdAt.millisecondsSinceEpoch,
          },
        )
        .toList(),
  });

  /// `comments.json` を読む。**読めなければ空**。
  ///
  /// ここは目録と違って、読めなくても消す判断につながらない
  /// （コメントが出ないだけで、音源は聴ける）。
  static List<OfflineComment> decodeComments(String source) {
    try {
      final raw = jsonDecode(source);
      if (raw is! Map) return const [];
      final comments = raw['comments'];
      if (comments is! List) return const [];

      final parsed = <OfflineComment>[];
      for (final entry in comments) {
        if (entry is! Map) continue;
        final map = entry.cast<String, dynamic>();
        final id = map['id'];
        if (id is! String || id.isEmpty) continue;
        parsed.add(
          OfflineComment(
            id: id,
            parentId: map['parentId'] as String?,
            path:
                (map['path'] as List?)?.whereType<String>().toList() ??
                const <String>[],
            createdAt:
                _timeFrom(map['createdAt']) ??
                DateTime.fromMillisecondsSinceEpoch(0),
            body: map['body'] as String? ?? '',
            authorName: map['authorName'] as String? ?? '',
            status: map['status'] as String? ?? 'active',
          ),
        );
      }
      return parsed;
    } on FormatException {
      return const [];
    }
  }

  static Map<String, dynamic> _itemToMap(DownloadedItem item) => {
    'listId': item.listId,
    'listName': item.listName,
    'itemId': item.itemId,
    'seq': item.seq,
    'date': item.date.toIso8601Date(),
    'title': item.title,
    'artist': item.artist,
    'storagePath': item.storagePath,
    'fileName': item.fileName,
    'contentType': item.contentType,
    'sizeBytes': item.sizeBytes,
    'localAudio': item.localAudio,
    'localImage': item.localImage,
    'localBytes': item.localBytes,
    'downloadedAt': item.downloadedAt.millisecondsSinceEpoch,
    'commentsSyncedAt': item.commentsSyncedAt?.millisecondsSinceEpoch,
  };

  static DownloadedItem? _itemFromMap(Map<String, dynamic> map) {
    final listId = map['listId'];
    final itemId = map['itemId'];
    final localAudio = map['localAudio'];
    final storagePath = map['storagePath'];
    if (listId is! String || listId.isEmpty) return null;
    if (itemId is! String || itemId.isEmpty) return null;
    if (localAudio is! String || localAudio.isEmpty) return null;
    if (storagePath is! String || storagePath.isEmpty) return null;

    final date = LocalDate.tryParse(map['date'] as String?);
    final downloadedAt = _timeFrom(map['downloadedAt']);
    if (date == null || downloadedAt == null) return null;

    return DownloadedItem(
      listId: listId,
      listName: map['listName'] as String? ?? '',
      itemId: itemId,
      seq: (map['seq'] as num?)?.toInt() ?? 0,
      date: date,
      storagePath: storagePath,
      fileName: map['fileName'] as String? ?? '',
      contentType: map['contentType'] as String? ?? '',
      sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
      localAudio: localAudio,
      localImage: map['localImage'] as String?,
      localBytes: (map['localBytes'] as num?)?.toInt() ?? 0,
      downloadedAt: downloadedAt,
      title: map['title'] as String?,
      artist: map['artist'] as String?,
      commentsSyncedAt: _timeFrom(map['commentsSyncedAt']),
    );
  }

  static DateTime? _timeFrom(Object? value) =>
      value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : null;
}
