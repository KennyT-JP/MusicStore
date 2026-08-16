/// 端末に置くときのファイル名の決め方（docs/DOWNLOAD-DESIGN.md 3.3）
///
/// **元のファイル名は使わない。** Storage の保存名には任意の文字が入り、
/// `:` `/` `\` `?` `*` `"` `<` `>` `|` はファイルシステムで使えないか、
/// 使えても扱いが端末ごとに違う。長さの上限にも当たる。
/// **`itemId` をディレクトリ名にし、ファイル名はこちらで決める。**
/// 元の名前は `index.json` に持つ（画面に出すのはそちら）。
///
/// **拡張子は残す。** `just_audio` がコンテナ形式を推測する手がかりになる。
/// 白リストは `playback.dart` の [kPlayableAudioExtensions] と
/// `download_target.dart` の [kDownloadableImageExtensions] にあり、
/// **ここには集合を書かない**（3.3・2.3）。
library;

import '../../domain/playback.dart';

/// `downloads/` の中の置き場所を決める（3.3）。
///
/// **相対パスだけを扱う。** 絶対パスは端末ごとに違い、iOS は
/// アプリの更新でコンテナの絶対パスが変わることがある（3.5）。
class DownloadPaths {
  const DownloadPaths._();

  /// 保存先の直下に作るディレクトリ（3.3）。
  static const String rootDirectoryName = 'downloads';

  /// 目録（3.4）。**同じディレクトリに置く**ので、バックアップ除外も
  /// アンインストールも「アプリのデータを消去」も、まとめて効く。
  static const String indexFileName = 'index.json';

  /// その曲のコメント（3.4）。**目録には混ぜない**——コメント 1 件の
  /// 同期のたびに目録全体を書き直すことになる。
  static const String commentsFileName = 'comments.json';

  /// 書きかけの目録（3.4 の tmp + rename）。
  static const String tempSuffix = '.tmp';

  /// 落としかけの本体（3.3）。**完了時に外す**（4.1 の手順 6）。
  static const String partSuffix = '.part';

  /// `<listId>/<itemId>`。
  static String itemDirectory({
    required String listId,
    required String itemId,
  }) => '$listId/$itemId';

  /// `<listId>/<itemId>/comments.json`。
  static String commentsFile({
    required String listId,
    required String itemId,
  }) => '${itemDirectory(listId: listId, itemId: itemId)}/$commentsFileName';

  /// `<listId>/<itemId>/audio-<stamp>.<ext>`（3.3）。
  ///
  /// **[stamp] を残すのは、差し替えのときに新旧を同じディレクトリへ
  /// 並べられるようにするため**（3.3）。古いのを先に消すと、落とし直しに
  /// 失敗したときに聴けるものが 1 つも無くなる。
  static String audioFile({
    required String listId,
    required String itemId,
    required String storagePath,
    required String fileName,
  }) => _mediaFile(
    prefix: 'audio',
    listId: listId,
    itemId: itemId,
    storagePath: storagePath,
    fileName: fileName,
  );

  /// `<listId>/<itemId>/image-<stamp>.<ext>`（3.3・論点 5）。
  static String imageFile({
    required String listId,
    required String itemId,
    required String storagePath,
    required String fileName,
  }) => _mediaFile(
    prefix: 'image',
    listId: listId,
    itemId: itemId,
    storagePath: storagePath,
    fileName: fileName,
  );

  static String _mediaFile({
    required String prefix,
    required String listId,
    required String itemId,
    required String storagePath,
    required String fileName,
  }) {
    final ext = fileExtension(fileName);
    final base =
        '${itemDirectory(listId: listId, itemId: itemId)}/'
        '$prefix-${stamp(storagePath)}';
    return ext.isEmpty ? base : '$base.$ext';
  }

  /// 落としかけの名前。**完了時に外す**（4.1）。
  static String partOf(String relativePath) => '$relativePath$partSuffix';

  /// `storagePath` から取る、その版を表す印（3.3 の `<millis>`）。
  ///
  /// **仕様の `<millis>` をそのままは使えない。**
  /// 3.3 は「Storage の保存名は `{millis}-{元のファイル名}`」と書いているが、
  /// **それは差し替えのときだけ**である
  /// （`item_repository.dart` の `uploadReplacementFile` が付ける）。
  /// **最初のアップロード（`addFileItem`）は元の名前をそのまま置く**ので、
  /// 数字の接頭辞が無い。そこを `<millis>` 前提で書くと、
  /// 最初に落とした曲のファイル名が決まらない。
  ///
  /// そこで
  ///
  /// - 先頭が `{数字}-` なら**その数字を使う**（差し替え後。仕様どおり）
  /// - 無ければ **`storagePath` 全体から作った短い印**を使う
  ///
  /// **どちらの場合も、差し替えで必ず別の値になる。** 差し替えは必ず
  /// 別の場所へ置かれる（`storage.rules` が同じパスへの上書きを禁じている）
  /// ので、パスが変われば印も変わる——4.4 が拠り所にしているのはそこだけ。
  static String stamp(String storagePath) {
    final name = storagePath.split('/').last;
    final digits = RegExp(r'^(\d+)-').firstMatch(name);
    if (digits != null) return digits.group(1)!;
    return _fingerprint(storagePath);
  }

  /// パスから作る 8 桁の印（32 ビットの FNV-1a）。
  ///
  /// **暗号の用途ではない。** 求めているのは「同じパスなら同じ名前、
  /// 違うパスなら違う名前」だけで、当てられて困るものではない。
  /// 突き合わせる相手は**同じ曲のディレクトリの中にある新旧 2 つだけ**なので、
  /// 32 ビットで足りる。
  ///
  /// **64 ビットで作らないこと。** Dart の int は符号付きなので、
  /// 掛け算が桁あふれすると負になり、`toRadixString` が
  /// `audio--7d5f….wav` という**ハイフンが 2 つ並んだファイル名**を作る
  /// （実際に踏んだ／2026-08-16）。32 ビットの遮蔽（`& 0xFFFFFFFF`）は
  /// 正の数なので、この問題が起きない。
  static String _fingerprint(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
