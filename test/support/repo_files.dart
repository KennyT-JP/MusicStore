/// リポジトリのファイルを走査するときの共通処理
///
/// **Windows のパス区切りを吸収する。**
///
/// `Directory.listSync` が返すパスは、Windows では `lib\domain\x.dart` の
/// ように円記号区切りになる。これを `'lib/domain/'` と比べても一致しない。
///
/// **困るのは、失敗ではなく「黙って別の意味になる」こと。**
/// 2026-08-07 に実際に起きた 2 件：
///
/// | テスト | Windows での実際の動き |
/// | --- | --- |
/// | 使われていない文言 | 生成物を除外できず、**常に通る**（何も守らない） |
/// | 死蔵コード | `lib/domain/` を除外できず、**見逃す側に倒れる** |
///
/// どちらも Linux では正しく動くため、書いた本人は緑を見て終わる。
/// 第 3 回監査の「前提が崩れると自動的に通る」に当たる
/// （docs/AUDIT-CHECKLIST.md 観点 4）。
///
/// **パスを文字列として比べるときは、必ずここを通すこと。**
library;

import 'dart:io';

/// パス区切りを `/` にそろえる。
String posixPath(String path) => path.replaceAll(r'\', '/');

/// [dir] の下にある、拡張子が [extension] のファイルを集める。
///
/// 返すパスは `/` 区切りにそろえてある。`node_modules` は除く。
List<({File file, String path})> filesUnder(
  String dir, {
  String extension = '.dart',
}) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return const [];

  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => (file: file, path: posixPath(file.path)))
      .where((entry) => entry.path.endsWith(extension))
      .where((entry) => !entry.path.contains('/node_modules/'))
      .toList();
}
