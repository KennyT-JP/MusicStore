/// firebase を起動するすべての入口に、同じ手当てが入っているか
///
/// **回帰テスト。** 2026-08-07 に、同じ設定を片方だけに入れて失敗した。
///
/// 関数の中身を読む工程には **10 秒の制限**がある。Node の版が
/// `functions/package.json` の指定（22）と違うと、ここを超えて
/// `Cannot determine backend specification` になる。
///
/// エミュレータの起動でこれに当たり、`functions/serve.mjs` で待ち時間を
/// 延ばした。**`scripts/deploy.mjs` を忘れた。** 数十分後、同じエラーで
/// 配信が止まった。
///
/// 第 3 回監査の申し送りに「**片側だけ塞ぐと、もう片側で同じことが
/// 起きる**」と自分で書いた翌ターンの出来事だった
/// （docs/AUDIT-CHECKLIST.md 観点 4）。
///
/// **申し送りを読むだけでは守れない。** 数えられるものは数える。
///
/// なお、この見張り自身も一度空振りした。最初は「その名前が
/// ファイルのどこかに出てくるか」で見ていたため、**設定を消しても
/// エラー案内の文に名前が残っていて通ってしまった**。
/// いまは**代入の形**（`名前:`）で見る。
/// 見張りを足したら、わざと壊して落ちることを確かめること。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/repo_files.dart';

/// firebase を起動する入口。増やしたらここにも足すこと。
///
/// `needsFunctions` が true のものは、関数を読み込むので待ち時間が要る。
const _launchers = <({String path, bool needsFunctions, String why})>[
  (
    path: 'scripts/deploy.mjs',
    needsFunctions: true,
    why: '配信の前に関数の一覧を読み取る',
  ),
  (
    path: 'scripts/dev-emulators.mjs',
    needsFunctions: true,
    why: '--only を付けずに起動するので functions も立ち上がる',
  ),
  (
    path: 'functions/serve.mjs',
    needsFunctions: true,
    why: '統合テスト用に functions を立ち上げる',
  ),
  (
    path: 'rules-test/run.mjs',
    needsFunctions: false,
    why: 'firestore と storage しか起動しない',
  ),
];

void main() {
  group('firebase を起動する入口', () {
    test('挙げた入口が実在する', () {
      // 名前を変えたのに、この一覧を直し忘れると見張りが空振りする。
      for (final launcher in _launchers) {
        expect(
          File(launcher.path).existsSync(),
          isTrue,
          reason: '${launcher.path} が見つかりません',
        );
      }
    });

    test('関数を起動する入口すべてに、読み取りの待ち時間が入っている', () {
      final missing = <String>[];

      for (final launcher in _launchers) {
        if (!launcher.needsFunctions) continue;
        final source = File(launcher.path).readAsStringSync();
        // **代入の形で確かめる。** 名前が出てくるだけでは足りない。
        // 案内の文に名前が残っていると、設定を消しても通ってしまう。
        if (!RegExp(r'FUNCTIONS_DISCOVERY_TIMEOUT\s*:').hasMatch(source)) {
          missing.add('${launcher.path}（${launcher.why}）');
        }
      }

      expect(
        missing,
        isEmpty,
        reason:
            '待ち時間の指定が入っていない入口があります。\n'
            'Node の版が違う環境で、関数が 1 つも読み込まれないまま\n'
            '起動・配信されます: $missing',
      );
    });

    test('要らない入口には入れない（意味の無い設定を増やさない）', () {
      for (final launcher in _launchers) {
        if (launcher.needsFunctions) continue;
        final source = File(launcher.path).readAsStringSync();
        expect(
          RegExp(r'FUNCTIONS_DISCOVERY_TIMEOUT\s*:').hasMatch(source),
          isFalse,
          reason: '${launcher.path} は${launcher.why}ので要りません',
        );
      }
    });

    test('firebase を起動する場所を、ほかに作っていない', () {
      // **一覧から漏れた入口は、この見張りの外側になる。**
      final found = <String>[];
      for (final dir in ['scripts', 'functions', 'rules-test']) {
        for (final extension in ['.mjs', '.js']) {
          for (final entry in filesUnder(dir, extension: extension)) {
            final source = entry.file.readAsStringSync();
            if (source.contains("'emulators:start'") ||
                source.contains("'emulators:exec'") ||
                source.contains("'deploy',")) {
              // **`/` にそろえてから比べる。** Windows では円記号区切りで
              // 返るため、そのままだと一覧と一致しない（2026-08-07）。
              found.add(entry.path);
            }
          }
        }
      }

      final known = _launchers.map((l) => l.path).toSet();
      expect(
        found.where((p) => !known.contains(p)).toList(),
        isEmpty,
        reason: '一覧に無い起動口が増えています。_launchers に足してください',
      );
    });
  });
}
