/// 端末に落としたものと、サーバー側の食い違いをどうするか
/// （docs/DOWNLOAD-DESIGN.md 4.4・論点 11）
///
/// 起動時の権限確認と同じタイミングで、`index.json` の 1 件ごとに
/// サーバー側の項目と突き合わせる。**判定だけをここに置く。**
/// ファイルを消すのも落とし直すのもデータ層の仕事。
library;

/// 突き合わせた結果、その 1 件をどうするか（4.4）。
enum SyncAction {
  /// そのまま持っておく。
  keep,

  /// 端末から消す（論点 11：元が削除された）。
  remove,

  /// 落とし直す（論点 11：元が差し替えられた）。
  ///
  /// **古いのを先に消さない。** 新しいのを落とし切ってから消す（4.4）。
  replace,
}

/// 同期の判定（4.4）。
class DownloadSyncPolicy {
  const DownloadSyncPolicy._();

  /// この 1 件をどうするか。
  ///
  /// **`storagePath` の一致だけで差し替えを検出できる。** 差し替えは必ず
  /// 別名（時刻を頭に付けた名前）でアップロードされ
  /// （`item_repository.dart:282` の `uploadReplacementFile`）、
  /// **同じパスへの上書きは `storage.rules:91,100` が禁じている**ので、
  /// パスが同じなら中身も同じ。
  ///
  /// **`previousFiles` は見ない。** サーバー専用の項目で Dart モデルにも無く、
  /// いまの `file` を見れば足りる。**見る必要のないものを読むと、
  /// それも守る対象になる。**
  ///
  /// - [serverStatus] は `'active'` / `'deleted'`、
  ///   **ドキュメントが無いときは null**。
  /// - [serverStoragePath] は項目が URL に変わったときなど、
  ///   ファイルを持たなくなると null。
  static SyncAction decide({
    required String? serverStatus,
    required String? serverStoragePath,
    required String localStoragePath,
  }) {
    if (serverStatus == null) return SyncAction.remove; // 消えた
    if (serverStatus == 'deleted') return SyncAction.remove; // ソフト削除
    if (serverStoragePath == null) return SyncAction.remove; // URL 項目に変わった
    if (serverStoragePath != localStoragePath) return SyncAction.replace;
    return SyncAction.keep;
  }
}
