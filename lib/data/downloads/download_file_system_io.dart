/// 端末のファイルを触る実装（docs/DOWNLOAD-DESIGN.md 3.1 / 3.3 / 3.4）
///
/// **このファイルだけが `dart:io` を持つ**（Web 側は
/// `download_file_system_stub.dart`）。共通コードに `dart:io` を書くと
/// `flutter build web` が落ちる（10 節の 5）。
///
/// ## 保存先（3.1）
///
/// **`getApplicationSupportDirectory()` の下の `downloads/`。**
///
/// | プラットフォーム | 実際の場所 |
/// | --- | --- |
/// | iOS | `Library/Application Support`（`NSApplicationSupportDirectory`） |
/// | Android | 内部ストレージの `files`（`Context.getFilesDir()`） |
///
/// この 2 つが、依頼者の要求 3 つを同時に満たす唯一の組み合わせである。
///
/// | 要求 | なぜ満たされるか |
/// | --- | --- |
/// | 他アプリから見えない | iOS はアプリごとのコンテナ、Android は内部ストレージ。OS がプロセス境界で隔離する |
/// | アンインストールで消える | 両方ともアプリのデータ領域。OS が削除する。**こちらから消す処理は要らない** |
/// | 利用者にも見えない | `path_provider` の文言が明示している（"files you don't want exposed to the user"） |
///
/// **`getApplicationDocumentsDirectory()` と `getTemporaryDirectory()` を
/// 呼ばないこと。** 前者は iOS で `NSDocumentDirectory` なので、
/// `Info.plist` に `UIFileSharingEnabled` を書かれた瞬間に
/// **ファイル App から中身が丸見えになる**。後者は iOS で
/// `NSCachesDirectory` なので、**OS が容量不足のときに勝手に消す**——
/// 論点 7 の「自動で消える場面は 2 つだけ」に反し、消えたことに気づけない。
/// **間違えても動いてしまう**ので、`test/domain/download_storage_test.dart`
/// の静的な見張りで止めている（10 節の 2）。
library;

import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'download_file_system.dart';
import 'download_paths.dart';

/// 実際の端末（iOS / Android、テストの Dart VM）で使う実装。
DownloadFileSystem createDownloadFileSystem(
  FirebaseStorage Function() storage, {
  String? rootOverride,
}) => IoDownloadFileSystem(storage, rootOverride);

/// `dart:io` を使う [DownloadFileSystem]。
class IoDownloadFileSystem implements DownloadFileSystem {
  /// [rootOverride] は**テストのためだけ**にある
  /// （8.3 は `Directory.systemTemp` を使う）。
  /// 本番では null にして、3.1 の保存先を解決させること。
  ///
  /// [storage] は**取り出し方**を受け取る。目録を読むだけの用で
  /// Firebase の初期化を要求しないため。
  IoDownloadFileSystem(this._storage, [this._rootOverride]);

  final FirebaseStorage Function() _storage;
  final String? _rootOverride;
  String? _root;

  @override
  Future<String> ensureRoot() async {
    final cached = _root;
    if (cached != null) return cached;

    final base =
        _rootOverride ??
        // **ここだけが保存先を知っている**（3.1）。
        '${(await getApplicationSupportDirectory()).path}/'
            '${DownloadPaths.rootDirectoryName}';

    await Directory(base).create(recursive: true);
    _root = base;
    return base;
  }

  @override
  Future<String> absolutePathOf(String relativePath) async =>
      '${await ensureRoot()}/$relativePath';

  @override
  Future<bool> exists(String relativePath) async =>
      File(await absolutePathOf(relativePath)).exists();

  @override
  Future<int> lengthOf(String relativePath) async {
    final file = File(await absolutePathOf(relativePath));
    if (!await file.exists()) return 0;
    return file.length();
  }

  @override
  Future<String?> readAsString(String relativePath) async {
    final file = File(await absolutePathOf(relativePath));
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> writeAsStringAtomically(
    String relativePath,
    String contents,
  ) async {
    final target = File(await absolutePathOf(relativePath));
    await target.parent.create(recursive: true);

    // **別名へ書いてから rename する**（3.4）。先に本体を開いて書くと、
    // 途中で電源が落ちたときに**壊れた目録が残る**。
    final temp = File('${target.path}${DownloadPaths.tempSuffix}');
    // `flush: true` を付ける。付けないと、rename までは済んだのに
    // 中身がまだ書かれていない、という並びになり得る。
    await temp.writeAsString(contents, flush: true);
    await temp.rename(target.path);
  }

  @override
  Future<void> rename(String from, String to) async {
    final source = File(await absolutePathOf(from));
    if (!await source.exists()) return;
    final target = File(await absolutePathOf(to));
    await target.parent.create(recursive: true);
    await source.rename(target.path);
  }

  @override
  Future<void> deleteFile(String relativePath) async {
    final file = File(await absolutePathOf(relativePath));
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> deleteDirectory(String relativePath) async {
    final directory = Directory(await absolutePathOf(relativePath));
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  @override
  Future<void> deleteRoot() async {
    final root = Directory(await ensureRoot());
    if (await root.exists()) await root.delete(recursive: true);
    // **消したまま終わらない。** 次の書き込みが「親が無い」で落ちる。
    await root.create(recursive: true);
  }

  @override
  Future<List<String>> listFiles() async {
    final root = await ensureRoot();
    final directory = Directory(root);
    if (!await directory.exists()) return const [];

    final files = <String>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File) continue;
      files.add(_relative(root, entity.path));
    }
    files.sort();
    return files;
  }

  @override
  Future<List<String>> listItemDirectories() async {
    final root = await ensureRoot();
    final directory = Directory(root);
    if (!await directory.exists()) return const [];

    final directories = <String>[];
    await for (final listEntity in directory.list()) {
      if (listEntity is! Directory) continue;
      await for (final itemEntity in listEntity.list()) {
        if (itemEntity is! Directory) continue;
        directories.add(_relative(root, itemEntity.path));
      }
    }
    directories.sort();
    return directories;
  }

  @override
  Future<void> download({
    required String storagePath,
    required String relativePath,
    DownloadProgress? onProgress,
    void Function(DownloadHandle handle)? onStarted,
  }) async {
    final target = File(await absolutePathOf(relativePath));
    await target.parent.create(recursive: true);

    final task = _storage().ref(storagePath).writeToFile(target);
    // **中断できるように、進行中のものを呼び出し元へ渡す**（6.3・論点 20）。
    onStarted?.call(_TaskHandle(task));

    if (onProgress != null) {
      task.snapshotEvents.listen(
        (snapshot) =>
            onProgress(snapshot.bytesTransferred, snapshot.totalBytes),
        // **失敗は await 側で受ける。** ここで受けないと未捕捉になる。
        onError: (Object _) {},
      );
    }

    await task;
  }

  /// 絶対パスを `downloads/` からの相対パスに直す。
  ///
  /// **区切りを `/` にそろえる。** Windows では円記号で返るため、
  /// そのままだと `index.json` に書いた相対パスと一致しない
  /// （`test/support/repo_files.dart` が同じ手当てをしている）。
  static String _relative(String root, String absolute) {
    final normalized = absolute.replaceAll(r'\', '/');
    final base = root.replaceAll(r'\', '/');
    return normalized.startsWith('$base/')
        ? normalized.substring(base.length + 1)
        : normalized;
  }
}

/// `DownloadTask` を [DownloadHandle] に包む。
///
/// **`pause()` / `resume()` は出さない。** アプリを閉じると
/// `DownloadTask` は消えるので「あとで続き」は成立せず、
/// **できないことを言葉で約束しない**（9 節）。
class _TaskHandle implements DownloadHandle {
  const _TaskHandle(this._task);

  final DownloadTask _task;

  @override
  Future<void> cancel() => _task.cancel();
}
