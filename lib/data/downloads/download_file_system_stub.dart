/// Web での [DownloadFileSystem]（何もできない）
///
/// **Web からは音源を落とさない**（docs/DOWNLOAD-DESIGN.md 論点 2）。
/// ブラウザにはサンドボックスされた保存先が無く、`writeToFile()` は
/// `dart:io` の `File` を取るので、そもそも動かない（4.1 の B の代償）。
///
/// **ここで例外を投げるのは「呼ばれてはいけない」という意味である。**
/// 画面は Web ではダウンロードのボタンを出さない（6.5）。
/// それでも呼ばれたなら、静かに何もしないより、
/// **どこから呼ばれたかが分かる形で落ちたほうがよい**——
/// 黙って成功したことにすると、「落としたはずのものが無い」になる。
library;

import 'package:firebase_storage/firebase_storage.dart';

import 'download_file_system.dart';

/// Web で使う実装。**どの口も [DownloadStorageUnavailableException] を投げる。**
///
/// [storage] も [rootOverride] も受け取るだけで使わない。
/// **口の形を実装どうしで揃えておく**——揃っていないと、条件付きの
/// 取り込みが「Web ビルドのときだけ」壊れる。
DownloadFileSystem createDownloadFileSystem(
  FirebaseStorage Function() storage, {
  String? rootOverride,
}) => const UnsupportedDownloadFileSystem();

/// 保存先を持たない [DownloadFileSystem]。
class UnsupportedDownloadFileSystem implements DownloadFileSystem {
  const UnsupportedDownloadFileSystem();

  @override
  Future<String> ensureRoot() => _unavailable();

  @override
  Future<String> absolutePathOf(String relativePath) => _unavailable();

  @override
  Future<bool> exists(String relativePath) => _unavailable();

  @override
  Future<int> lengthOf(String relativePath) => _unavailable();

  @override
  Future<String?> readAsString(String relativePath) => _unavailable();

  @override
  Future<void> writeAsStringAtomically(String relativePath, String contents) =>
      _unavailable();

  @override
  Future<void> rename(String from, String to) => _unavailable();

  @override
  Future<void> deleteFile(String relativePath) => _unavailable();

  @override
  Future<void> deleteDirectory(String relativePath) => _unavailable();

  @override
  Future<void> deleteRoot() => _unavailable();

  @override
  Future<List<String>> listFiles() => _unavailable();

  @override
  Future<List<String>> listItemDirectories() => _unavailable();

  @override
  Future<void> download({
    required String storagePath,
    required String relativePath,
    DownloadProgress? onProgress,
    void Function(DownloadHandle handle)? onStarted,
  }) => _unavailable();

  static Future<T> _unavailable<T>() =>
      Future<T>.error(const DownloadStorageUnavailableException());
}
