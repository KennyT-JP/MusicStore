/// 死蔵コードが増えていないことの確認
///
/// **回帰テスト。** 2 回の監査で毎回同じ指摘が出た。
///
/// 判定ロジックを `lib/domain/` に切り出してテストを厚く書いたのに、
/// **画面やリポジトリはそれを呼ばず、同じ判定を直接書いていた**。
/// テストは緑のまま、本番では別のコードが動いている状態が続いた
/// （監査 S8・S11・第2回）。
///
/// - `Permissions` の 6 メソッドが本番から 0 参照
/// - `sequence.dart` と `invite.dart` が本番から 0 参照
///   （どちらも仕様 12.6 が「自動テスト必須」に挙げた領域）
///
/// **テストがあることと、守られていることは別。**
/// 呼ばれているかどうかは機械的に確かめられるので、ここで固定する。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/repo_files.dart';

/// `lib/` のうち、本番コードとみなす場所。
///
/// `lib/domain/` 自身は「定義側」なので、参照元としては数えない。
/// **除外は `/` にそろえたパスで行う。** Windows では円記号区切りで
/// 返るため、そのままだと `lib/domain/` を除外できず、
/// **定義側どうしの参照を「本番から呼ばれている」と数えてしまう**
/// （見逃す側に倒れる／2026-08-07）。
List<File> _productionFiles() => filesUnder('lib')
    .where((e) => !e.path.startsWith('lib/domain/'))
    .where((e) => !e.path.startsWith('lib/l10n/')) // 生成物
    .map((e) => e.file)
    .toList();

void main() {
  late String production;

  setUpAll(() {
    production = _productionFiles().map((f) => f.readAsStringSync()).join('\n');
  });

  test('Permissions のメソッドはすべて本番から呼ばれている', () {
    final source = File('lib/domain/permissions.dart').readAsStringSync();
    final methods = RegExp(r'static bool (\w+)')
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();

    expect(methods, isNotEmpty, reason: '判定関数を 1 つも見つけられていない');

    final unused = methods
        .where((m) => !production.contains('Permissions.$m'))
        .toList()
      ..sort();

    expect(
      unused,
      isEmpty,
      reason:
          '本番から呼ばれていない判定関数: $unused\n'
          '画面が同じ判定を直接書いていないか確かめてください。'
          '使わないなら消してください。',
    );
  });

  test('lib/domain のモジュールはすべて本番から使われている', () {
    final modules = filesUnder('lib/domain')
        .map((e) => e.path.split('/').last)
        .toList();

    expect(modules, isNotEmpty);

    final unused = modules
        .where((name) => !production.contains('domain/$name'))
        .toList()
      ..sort();

    expect(
      unused,
      isEmpty,
      reason:
          '本番から使われていないモジュール: $unused\n'
          '実際に動いている実装が別の場所にないか確かめてください。',
    );
  });

  test('リポジトリの公開メソッドが本番から呼ばれている', () {
    // 呼び出し元の無い公開メソッドは、たいてい「同じことを別の場所で
    // 直接やっている」印。isListNameTaken と canWithdraw がそうだった。
    final repositories = filesUnder('lib/data/repositories').map((e) => e.file);

    final unused = <String>[];
    for (final file in repositories) {
      final source = file.readAsStringSync();
      final name = file.uri.pathSegments.last;
      for (final match in RegExp(
        r'^  (?:Future<[^>]*>|Stream<[^>]*>|void|bool|String) (\w+)\(',
        multiLine: true,
      ).allMatches(source)) {
        final method = match.group(1)!;
        if (method.startsWith('_')) continue;
        // 自分自身のファイル以外からの参照を数える。
        //
        // **`.name(` だけを探すと足りない。** コールバックとして
        // 関数そのものを渡す書き方（`_run(auth.signInWithGoogle)`）が
        // あるため、括弧の無い参照も数える。
        final calls = _productionFiles()
            .where((f) => f.uri.pathSegments.last != name)
            .where((f) {
              final source = f.readAsStringSync();
              return RegExp('\\.$method\\b').hasMatch(source);
            })
            .length;
        if (calls == 0) unused.add('$name の $method');
      }
    }

    expect(
      unused,
      isEmpty,
      reason:
          '本番から呼ばれていないリポジトリのメソッド: $unused\n'
          '同じことを画面が直接していないか確かめてください。',
    );
  });
}
