/// 端末に持つ目録の形（docs/DOWNLOAD-DESIGN.md 3.4 / 3.5）
///
/// **型だけを置く。読み書きはここではしない。** `index.json` の読み書きは
/// データ層の仕事で、書き込みは必ず `index.json.tmp` へ書いてから
/// rename する（3.4）。
///
/// **`shared_preferences` には置かない**（3.4）。目録は消えると困るもので、
/// `local_preferences.dart` は「消えても困らないもの」だけを置くと
/// 定めた場所。目録が消えるとファイルだけが残り、数えることも消すことも
/// できない孤児になる。
library;

import 'comment_tree.dart';
import 'local_date.dart';

/// `index.json` の形（3.5）。**形を変えたら上げる。**
const int kDownloadIndexVersion = 1;

/// 端末に何を持っているかの目録（3.5）。
class DownloadIndex {
  const DownloadIndex({
    this.version = kDownloadIndexVersion,
    this.lastVerifiedAt,
    this.allowMobileData = false,
    this.items = const [],
  });

  /// 形を変えたときの移行用。
  final int version;

  /// **サーバーが返した**最終確認時刻（4.2）。
  ///
  /// 一度も確認が取れていなければ null。
  /// **端末の時計で入れないこと**——時計を進めるだけで確認を偽装できる。
  /// 経過時間の判定は `OfflineAccessPolicy` が行う。
  final DateTime? lastVerifiedAt;

  /// 通信条件（4.6）。**既定は Wi-Fi のみ**（論点 11b）。
  final bool allowMobileData;

  /// 持っている曲。
  final List<DownloadedItem> items;

  /// 端末内の使用量（6.4）。
  ///
  /// **端末上の実測（[DownloadedItem.localBytes]）を合計する。**
  /// サーバー側の [DownloadedItem.sizeBytes] を使うと、落とし損ねたぶんが
  /// 数字に出ず、設定画面の「端末内の使用量」が実際と食い違う。
  int get localBytesTotal =>
      items.fold(0, (sum, item) => sum + item.localBytes);
}

/// 端末に持っている 1 曲（3.5）。
class DownloadedItem {
  const DownloadedItem({
    required this.listId,
    required this.listName,
    required this.itemId,
    required this.seq,
    required this.date,
    required this.storagePath,
    required this.fileName,
    required this.contentType,
    required this.sizeBytes,
    required this.localAudio,
    required this.localBytes,
    required this.downloadedAt,
    this.title,
    this.artist,
    this.localImage,
    this.commentsSyncedAt,
  });

  final String listId;

  /// **オフラインで「どのリストのものか」を出すために持つ**（論点 8）。
  final String listName;

  final String itemId;

  /// 連番。一覧の並び順に使う（6.1）。
  final int seq;

  /// 録音日（論点 8）。
  final LocalDate date;

  /// 差し替えの検出に使う（4.4）。
  ///
  /// 差し替えは必ず別名になるので、**パスの一致だけで検出できる。**
  final String storagePath;

  /// 画面に出す名前。**端末上のファイル名ではない**（3.3）。
  final String fileName;

  final String contentType;

  /// サーバー側の大きさ。
  final int sizeBytes;

  /// 音源の置き場所。**`downloads/` からの相対パス**（3.5）。
  ///
  /// **絶対パスで持たないこと。** iOS はアプリを更新するとコンテナの
  /// 絶対パスが変わることがあり、更新の翌日に全部「ファイルが無い」ことになる。
  final String localAudio;

  /// 画像の置き場所（論点 5）。相対パス。無ければ null。
  final String? localImage;

  /// **端末上の実測。** 使用量の表示に使う（6.4）。
  final int localBytes;

  final DateTime downloadedAt;

  final String? title;
  final String? artist;

  /// コメントを最後に同期した時刻。まだなら null。
  final DateTime? commentsSyncedAt;
}

/// 端末に持っているコメント 1 件（3.5 の `comments.json`）。
///
/// **`parentId` / `path` をそのまま持つので、`comment_tree.dart` の
/// ツリー組み立てをオフラインでもそのまま使える。**
/// 別の組み立て方を作らないこと。
///
/// **[authorName] は解決済みで持つ。** 表示名は `users/{uid}` にあり、
/// オフラインでは引けない。同期のときに解決して埋める。名前が変わっても
/// 端末側は古いまま出るが、**「名前が古い」と「名前が出ない」なら
/// 前者のほうがまし。**
class OfflineComment extends CommentNodeInput {
  const OfflineComment({
    required super.id,
    required super.parentId,
    required super.path,
    required super.createdAt,
    required this.body,
    required this.authorName,
    required this.status,
  });

  final String body;
  final String authorName;

  /// `'active'` / `'deleted'`。削除済みも持つ（ツリーの親になるため）。
  final String status;
}
