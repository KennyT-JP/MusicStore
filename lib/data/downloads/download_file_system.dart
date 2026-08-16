/// 端末のファイルを触る口（docs/DOWNLOAD-DESIGN.md 3.1 / 3.3 / 3.4）
///
/// **ここには `dart:io` を書かない。** `writeToFile()` は `dart:io` の
/// `File` を取るので、共通コードに書くと **`flutter build web` が落ち、
/// `scripts/deploy.mjs` の配信が止まる**（10 節の 5）。
/// 実装は `download_file_system_io.dart`、Web 側は
/// `download_file_system_stub.dart` にあり、
/// `download_file_system_factory.dart` が条件付きで選ぶ
/// （`lib/platform/app_ready.dart` と同じ形）。
///
/// **扱うパスはすべて `downloads/` からの相対パスで、区切りは `/`。**
/// 絶対パスを持ち回らない——iOS はアプリを更新するとコンテナの絶対パスが
/// 変わることがあり、覚えておくと更新の翌日に全部「ファイルが無い」ことに
/// なる（3.5）。
library;

/// 進み具合を知らせる（4.1 の手順 3）。
///
/// **画面には「%」だけでなく「12.3 MB / 41.2 MB」も出すこと。**
/// 曲は大きく、% だけだと止まって見える。
typedef DownloadProgress = void Function(int transferredBytes, int totalBytes);

/// 進行中のダウンロードを止める手（6.3・論点 20）。
///
/// **上限を置かない代わりが、見積もり・進捗・中断の 3 つ。**
/// どれか 1 つでも欠けると「押したら何が起きるか分からないボタン」になる。
///
/// **「再開」は持たない。** `DownloadTask` はアプリのプロセスと寿命を
/// 共にし、途中から続けることはできない（9 節）。
/// **できないことを言葉で約束しない**ので、`resume` という名前を置かない。
abstract class DownloadHandle {
  Future<void> cancel();
}

/// 保存先が使えないときに投げる。
///
/// **Web ではダウンロード機能そのものを出さない**（論点 2 / 6.5）ので、
/// これが飛ぶのは「Web に導線が残っている」という作りの誤りのとき。
class DownloadStorageUnavailableException implements Exception {
  const DownloadStorageUnavailableException();

  @override
  String toString() => 'DownloadStorageUnavailableException';
}

/// `downloads/` の下を読み書きする（3.3）。
///
/// **保存先の選び方はこの実装だけが知っている**（3.1）。
/// `getApplicationSupportDirectory()` を使い、
/// `getApplicationDocumentsDirectory()` と `getTemporaryDirectory()` は
/// **使わない**——前者は iOS で `UIFileSharingEnabled` を 1 行足された
/// 瞬間にファイル App から丸見えになり、後者は OS が容量不足のときに
/// 勝手に消す（3.1 の「使ってはいけない場所」）。
abstract class DownloadFileSystem {
  /// `downloads/` を用意して、その絶対パスを返す。
  ///
  /// **何度呼んでもよい。** 起動のたびに呼ばれる（3.2 の「冪等に設定する」）。
  Future<String> ensureRoot();

  /// 相対パスから絶対パスを作る。**再生に渡すときだけ使う**（4.3）。
  Future<String> absolutePathOf(String relativePath);

  Future<bool> exists(String relativePath);

  /// ファイルの大きさ。無ければ 0。
  ///
  /// **端末上の実測**で、`index.json` の `localBytes` はこれを持つ（3.5）。
  Future<int> lengthOf(String relativePath);

  /// 中身を読む。無ければ null。
  Future<String?> readAsString(String relativePath);

  /// **別名へ書いてから rename する**（3.4）。
  ///
  /// ```
  /// <path>.tmp へ全体を書く → flush → rename(<path>)
  /// ```
  ///
  /// `rename` は同一ファイルシステム内では POSIX が原子性を保証しており、
  /// iOS / Android はどちらも POSIX。**途中で電源が落ちても、
  /// 古いものか新しいもののどちらかが残り、壊れたものは残らない。**
  Future<void> writeAsStringAtomically(String relativePath, String contents);

  /// 落とし終えた `.part` を外す（4.1 の手順 6）。
  Future<void> rename(String from, String to);

  Future<void> deleteFile(String relativePath);

  /// ディレクトリごと消す（4.4 の `remove`）。無ければ何もしない。
  Future<void> deleteDirectory(String relativePath);

  /// `downloads/` を丸ごと消して作り直す（4.5・論点 12）。
  Future<void> deleteRoot();

  /// `downloads/` の下にあるファイルを、相対パスで全部返す。
  ///
  /// 掃除（4.7）が `.part` と孤児を見つけるために使う。
  Future<List<String>> listFiles();

  /// `<listId>/<itemId>` の形のディレクトリを全部返す（4.7 の孤児探し）。
  Future<List<String>> listItemDirectories();

  /// Storage から**この相対パスへ**落とす（4.1）。
  ///
  /// **`getDownloadURL()` は使わない**（4.1 の A/B 比較）。理由は 2 つ。
  ///
  /// 1. **監査 L-9 を広げない。** `getDownloadURL()` が返す URL は
  ///    **無期限・認証不要**で、いまも未対応の指摘である。ダウンロードを
  ///    そちらで作ると、利用者の端末に**そのリストの全曲ぶんの無期限 URL が
  ///    並んだファイル**ができる。未対応の問題を、別の機能を作るついでに
  ///    拡大しない
  /// 2. **権限確認がもう一枚増える。** `writeToFile()` は SDK が Auth
  ///    トークンを付けるので、脱退・除外された人が始めた時点で
  ///    `storage.rules` の `canRead()` に落ちて失敗する。URL には権限の
  ///    概念が無いので、この守りが 1 枚も無くなる
  ///
  /// **`getData()` も使わない。** 既定の上限が 10 MB で、上限を上げても
  /// ファイル全体が端末のメモリに載る。100 MB の WAV を 10 曲並べれば落ちる。
  ///
  /// **`Reference` を受け取らない。** Firebase の型が口に出ていると、
  /// **端末のファイルを触るだけのテストにも Firebase の初期化が要る。**
  /// 中断は [DownloadHandle] に包んで渡す。
  Future<void> download({
    required String storagePath,
    required String relativePath,
    DownloadProgress? onProgress,
    void Function(DownloadHandle handle)? onStarted,
  });
}
