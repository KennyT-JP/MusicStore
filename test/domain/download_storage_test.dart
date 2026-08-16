/// 保存先と Web ビルドの静的な見張り（docs/DOWNLOAD-DESIGN.md 8.4）
///
/// **ここで守るものは、どれも「間違えても動く」。**
///
/// | 破れると | 何が起きるか |
/// | --- | --- |
/// | `getApplicationDocumentsDirectory()` に変える | iOS で `UIFileSharingEnabled` を 1 行足された瞬間、**ファイル App から音源が丸見えになる**。依頼者の要求（1.1）に直接反する |
/// | `getTemporaryDirectory()` に変える | **OS が容量不足のときに勝手に消す。** 論点 7 の「自動で消える場面は 2 つだけ」に反し、消えたことに気づけない |
/// | `getExternalStorageDirectory()` に変える | 外部ストレージ。ほかのアプリから読める |
/// | 共通コードに `dart:io` を書く | **`flutter build web` が落ち、`scripts/deploy.mjs` の配信が止まる** |
/// | 拡張子の白リストを 2 つ目に書く | 「一覧に再生ボタンが出るのに落とせない曲」ができる（3.3・2.3） |
///
/// **上の 3 つは、間違えてもテストが通り、ダウンロードも再生もできる。**
/// 気づくのは、誰かが別の目的で `Info.plist` に 1 行足したときである
/// （10 節の 2）。**実行時に気づく手段が無い**ので、ここで止める。
///
/// **コメントを取り除いてから当てる。** このリポジトリは「なぜそれを
/// 使わないか」を長い注記で残す流儀なので、素の `contains` だと
/// **説明文に残った名前のせいで、実際に呼んでいても呼んでいなくても
/// 同じ結果になる**（`test/domain/android_platform_test.dart` の冒頭と
/// 同じ手当て）。
library;

import 'package:flutter_test/flutter_test.dart';

import '../support/repo_files.dart';

/// `//` と `///` のコメント行、`/* */` の塊を取り除く。
///
/// 行の途中から始まるコメント（`foo(); // 説明`）も落とす。
/// 文字列リテラル内の `//`（URL など）を巻き添えにしないよう、
/// 直前が `:` のもの（`https://`）は残す
/// （`test/domain/no_dead_code_test.dart` と同じ規則）。
///
/// **改行コードを先にそろえる。** `.` は `\r` に一致しないので、
/// ファイルが CRLF だと `//.*$` が**行末（`\r` の手前）で止まって
/// `$` に届かず、1 行もコメントを落とせない。**
/// そして落とせないほうへ倒れるので、**このテストは緑のまま何も守らなくなる**
/// （docs/AUDIT-CHECKLIST.md 観点 4「前提が崩れると自動的に通る」）。
/// `.gitattributes` が LF に統一しているとはいえ、
/// 編集の仕方ひとつで CRLF は混ざる（2026-08-16 に実際に混ざった）。
String _stripComments(String source) => source
    .replaceAll('\r\n', '\n')
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((line) => line.replaceFirst(RegExp(r'(?<!:)//.*$'), ''))
    .join('\n');

/// `lib/` の Dart ファイルを、コメントを落とした中身と組で返す。
List<({String path, String source})> _libSources() => filesUnder('lib')
    .where((e) => !e.path.startsWith('lib/l10n/')) // 生成物
    .map(
      (e) => (path: e.path, source: _stripComments(e.file.readAsStringSync())),
    )
    .toList();

void main() {
  group('保存先（3.1・10 節の 2）', () {
    test('getApplicationDocumentsDirectory を呼んでいない', () {
      final offenders = _libSources()
          .where((e) => e.source.contains('getApplicationDocumentsDirectory'))
          .map((e) => e.path)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            '$offenders が Documents を使っています。\n'
            'iOS では NSDocumentDirectory なので、Info.plist に '
            'UIFileSharingEnabled を書かれた瞬間にファイル App から'
            '丸見えになります（3.1）。'
            'getApplicationSupportDirectory() を使ってください。',
      );
    });

    test('getTemporaryDirectory を呼んでいない', () {
      final offenders = _libSources()
          .where((e) => e.source.contains('getTemporaryDirectory'))
          .map((e) => e.path)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            '$offenders が一時領域を使っています。\n'
            'iOS では NSCachesDirectory なので、OS が容量不足のときに'
            '勝手に消します（3.1）。論点 7「自動で消える場面は 2 つだけ」に'
            '反し、しかも消えたことに気づけません。',
      );
    });

    test('getExternalStorageDirectory を呼んでいない', () {
      final offenders = _libSources()
          .where((e) => e.source.contains('getExternalStorageDirectory'))
          .map((e) => e.path)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason: '$offenders が外部ストレージを使っています。ほかのアプリから読めます（3.1）。',
      );
    });

    test('getApplicationSupportDirectory を呼ぶ場所は 1 つだけ', () {
      // **保存先を知っている場所を増やさない。** 2 か所になると、
      // 片方だけ直したときに目録とファイルが別のディレクトリに分かれる。
      final callers = _libSources()
          .where((e) => e.source.contains('getApplicationSupportDirectory'))
          .map((e) => e.path)
          .toList();

      expect(callers, ['lib/data/downloads/download_file_system_io.dart']);
    });
  });

  group('Web を壊さない（10 節の 5）', () {
    test('dart:io は条件付き取り込みの裏にしか無い', () {
      // **`lib/` の共通コードに `dart:io` を書くと `flutter build web` が
      // 落ちる**（8.4）。書いてよいのは
      //
      // - `lib/platform/`（既存の条件付き取り込みの置き場）
      // - `_io.dart` で終わるファイル（`*_factory.dart` が
      //   `if (dart.library.io)` で選ぶ側）
      //
      // の 2 つだけ。
      final offenders = _libSources()
          .where((e) => e.source.contains("import 'dart:io'"))
          .map((e) => e.path)
          .where((path) => !path.startsWith('lib/platform/'))
          .where((path) => !path.endsWith('_io.dart'))
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            '$offenders が dart:io を直接取り込んでいます。\n'
            'flutter build web が落ち、scripts/deploy.mjs の配信が止まります。\n'
            'lib/data/downloads/download_file_system_factory.dart と'
            '同じ条件付き取り込みの形で分けてください。',
      );
    });

    test('_io.dart は、条件付き取り込みからしか使われていない', () {
      // **直接 import されたら、条件分けの意味が無い。**
      // Web ビルドでもその実装が引き込まれ、`dart:io` ごと入る。
      final offenders = _libSources()
          .where((e) => !e.path.endsWith('_factory.dart'))
          .where((e) => e.source.contains("download_file_system_io.dart"))
          .map((e) => e.path)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            '$offenders が io 側の実装を直に取り込んでいます。\n'
            'download_file_system_factory.dart を通してください。',
      );
    });

    test('条件付き取り込みは、既定を Web 側にしている', () {
      final factory = filesUnder('lib')
          .firstWhere(
            (e) => e.path.endsWith('download_file_system_factory.dart'),
          )
          .file
          .readAsStringSync();

      // **既定（`if` に当たらないとき）が stub であること。**
      // 逆にすると、Web ビルドが io 側を掴んで落ちる。
      expect(
        RegExp(
          r"export\s+'download_file_system_stub\.dart'\s*"
          r"if\s*\(dart\.library\.io\)\s*'download_file_system_io\.dart'",
        ).hasMatch(_stripComments(factory)),
        isTrue,
        reason: '既定を stub、dart:io があるときだけ io 側にすること',
      );
    });
  });

  group('目録は tmp + rename で書く（3.4）', () {
    test('別名へ書いてから rename している', () {
      // **結果からは確かめられない。** 直に書いても、最後まで走れば
      // 同じ中身になる。違いが出るのは**途中で電源が落ちたとき**だけで、
      // それはテストで起こせない。だから**書き方のほうを見張る。**
      final source = _stripComments(
        filesUnder('lib/data/downloads')
            .firstWhere((e) => e.path.endsWith('download_file_system_io.dart'))
            .file
            .readAsStringSync(),
      );

      final write = source.substring(source.indexOf('writeAsStringAtomically'));
      final body = write.substring(0, write.indexOf('\n  @override'));

      expect(body, contains('tempSuffix'), reason: '別名（.tmp）へ書くこと（3.4）');
      expect(body, contains('.rename('), reason: 'rename で置き換えること（3.4）');
      expect(
        body,
        contains('flush: true'),
        reason:
            'flush しないと、rename までは済んだのに中身がまだ書かれて'
            'いない、という並びになり得ます（3.4）',
      );
      // **本体へ直に書かないこと。** ここが `target.writeAsString(` に
      // なっていたら、途中で落ちたときに壊れた目録が残る。
      expect(body, isNot(contains('target.writeAsString(')));
    });
  });

  group('拡張子の白リストは 1 か所（3.3・2.3）', () {
    test('download_target.dart は playback.dart の集合を参照している', () {
      final source = _stripComments(
        filesUnder('lib/domain')
            .firstWhere((e) => e.path.endsWith('download_target.dart'))
            .file
            .readAsStringSync(),
      );

      expect(
        source,
        contains('kPlayableAudioExtensions'),
        reason:
            '音源の白リストは playback.dart の 1 か所だけにすること。\n'
            'ここに別の集合を書くと、「一覧に再生ボタンが出るのに'
            '落とせない曲」ができます（3.3）。',
      );
      // **音源の拡張子を自前で並べていないこと。**
      for (final ext in ['mp3', 'm4a', 'wav', 'flac', 'ogg', 'aac']) {
        expect(
          source,
          isNot(contains("'$ext'")),
          reason: '$ext を download_target.dart に直接書かないこと',
        );
      }
    });

    test('端末側のファイル名も、その白リストを通して決める', () {
      // `DownloadPaths` が自前で拡張子を並べ始めると、白リストが 2 つになる。
      final source = _stripComments(
        filesUnder('lib/data')
            .firstWhere((e) => e.path.endsWith('download_paths.dart'))
            .file
            .readAsStringSync(),
      );
      for (final ext in ['mp3', 'm4a', 'wav', 'flac', 'ogg', 'aac']) {
        expect(source, isNot(contains("'$ext'")));
      }
      // 拡張子の取り出しは playback.dart の fileExtension を使う。
      expect(source, contains('fileExtension('));
    });
  });

  group('取得方法（4.1・監査 L-9）', () {
    test('ダウンロードに getDownloadURL を使っていない', () {
      // **端末の目録が「無期限の鍵束」になるのを防ぐ**（4.1 の A/B 比較）。
      // ストリーミング再生（item_repository.downloadUrl）は従来どおり
      // 使い続けるので、**downloads/ の下だけを見る。**
      final offenders = _libSources()
          .where((e) => e.path.startsWith('lib/data/downloads/'))
          .where((e) => e.source.contains('getDownloadURL'))
          .map((e) => e.path)
          .toList();

      expect(
        offenders,
        isEmpty,
        reason:
            '$offenders が getDownloadURL を使っています。\n'
            '返る URL は無期限・認証不要（監査 L-9）で、曲数ぶんの'
            '無期限 URL が端末に並びます。writeToFile() を使ってください。',
      );
    });

    test('writeToFile で取る', () {
      final source = _stripComments(
        filesUnder('lib/data/downloads')
            .firstWhere((e) => e.path.endsWith('download_file_system_io.dart'))
            .file
            .readAsStringSync(),
      );
      expect(source, contains('writeToFile('));
      // **getData() は使わない。** 既定の上限が 10 MB で、上げても
      // ファイル全体が端末のメモリに載る（4.1）。
      expect(source, isNot(contains('getData(')));
    });
  });

  group('プレミアム失効の判定（5.1・10 節の危険 4）', () {
    test('クライアント側は premiumRequired を見て分岐していない', () {
      // **サーバーは投げない。** 投げられる前提のコードがあると、
      // 通信の失敗と「プレミアムでない」が混ざり、
      // **圏外で 1 回失敗しただけで全曲が消える。**
      final offenders = _libSources()
          .where((e) => e.path.startsWith('lib/data/downloads/'))
          .where((e) => e.source.contains('premiumRequired'))
          .map((e) => e.path)
          .toList();

      expect(offenders, isEmpty);
    });
  });
}
