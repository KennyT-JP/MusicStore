/// 非同期プロバイダを「まだ届いていないまま」読んでいないことの確認
///
/// **回帰テスト。2026-08-10 に実際に起きた。**
///
/// サイト管理のユーザー一覧に「リストに追加」を足したとき、リストの
/// 一覧をこう読んでいた。
///
/// ```dart
/// final lists = ref.read(allListsProvider).value ?? const <MusicList>[];
/// if (lists.isEmpty) { ...「リストがありません」... }
/// ```
///
/// `ref.read` は**購読を始めるだけで、最初の値を待たない**。
/// この画面（`/admin/users`）は直接開けるため、サイト管理のホームを
/// 経由しないと購読がまだ始まっておらず、`.value` は null になる。
/// **リストがあるのに「リストがありません」と出て、二度目に押すと出る。**
///
/// 失敗ではなく**既定値へ静かに倒れる**ので、動かしても原因が掴めない。
/// `await ref.read(プロバイダ.future)` なら、届くまで待つ。
///
/// **認証のプロバイダだけは例外。** `lib/app.dart` が復元の完了を待って
/// から画面を出すので、画面が動いている時点で必ず解決している。
library;

import 'package:flutter_test/flutter_test.dart';

import '../support/repo_files.dart';

/// `ref.read(なにかProvider).value` を拾う。
final _readValue = RegExp(r'ref\.read\((\w+Provider)\)\s*\.value');

/// 画面が出ている時点で必ず解決しているもの。
///
/// **増やすときは、その根拠を添えること。** 「たぶん読み終わっている」
/// で足すと、このテストは何も守らなくなる。
const _alwaysResolved = {
  // lib/app.dart が復元の完了を待ってから画面を出す。
  'firebaseUserProvider',
};

void main() {
  test('非同期プロバイダは .value ではなく .future で待つ', () {
    final offenders = <String>[];

    for (final entry in filesUnder('lib')) {
      if (entry.path.startsWith('lib/l10n/')) continue; // 生成物
      final source = entry.file.readAsStringSync();
      for (final match in _readValue.allMatches(source)) {
        final provider = match.group(1)!;
        if (_alwaysResolved.contains(provider)) continue;
        offenders.add('${entry.path}: $provider');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'ref.read(...).value は、まだ届いていないと既定値へ静かに倒れます。\n'
          'await ref.read(プロバイダ.future) で待つか、build の中なら\n'
          'ref.watch を使ってください。\n'
          '画面表示の時点で必ず解決していると言い切れるものだけ、\n'
          '_alwaysResolved に根拠を添えて足してください。\n'
          '該当: ${offenders.join(', ')}',
    );
  });

  test('走査するファイルがある（空振り防止）', () {
    expect(filesUnder('lib').length, greaterThan(20));
  });

  test('見張りが効いていること（違反を作れば拾える）', () {
    // **この見張り自身を試す。** 置いただけで安心しないため
    // （監査 第4回：6 つの見張り全部に抜け道があった）。
    const violation = 'final x = ref.read(someDataProvider).value ?? [];';
    final match = _readValue.firstMatch(violation);
    expect(match?.group(1), 'someDataProvider');
    expect(_alwaysResolved.contains('someDataProvider'), isFalse);
  });
}
