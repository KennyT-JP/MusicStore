/// 手動テストケース台帳が、数えられる形になっているか（仕様書 12.6）
///
/// **4 回の監査で「手動側の網羅性を測定できない」と書かれ続けた。**
/// 台帳が無く、`docs/SETUP.md` にチェックボックスが 12 個あるだけで、
/// ID も事前条件も期待結果も実施記録も無かったためである。
///
/// 台帳を置いただけでは同じことになる。**空欄のまま増える／実在しない
/// 仕様の節を指す／ID が重なる**と、数えても意味が無い。ここで機械的に
/// 確かめる（AUDIT-CHECKLIST「注意書きを、仕組みと数えない」）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _ledger = 'docs/TEST-CASES.md';

/// 台帳の行（表のヘッダと区切りを除く）。
List<List<String>> _rows() {
  final lines = File(_ledger).readAsLinesSync();
  return lines
      .where((l) => l.startsWith('| M-'))
      .map(
        (l) => l
            .split('|')
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList(),
      )
      .toList();
}

void main() {
  test('台帳が存在する（空振り防止）', () {
    expect(File(_ledger).existsSync(), isTrue);
    expect(_rows().length, greaterThan(5), reason: '行を読めていない');
  });

  test('ID が重なっていない', () {
    final ids = _rows().map((r) => r.first).toList();
    expect(ids.toSet().length, ids.length, reason: '同じ ID が 2 つある: $ids');
  });

  test('どの欄も空でない', () {
    // **空欄のまま増えるのがいちばん質が悪い。** 数えられるのに、
    // 数えても中身が無い状態になる。
    for (final row in _rows()) {
      expect(
        row.length,
        7,
        reason: '${row.first} の欄が足りない（ID・対象・事前条件・手順・'
            '期待結果・自動テストとの関係・最終実施 の 7 つ）: $row',
      );
      for (final cell in row) {
        expect(cell, isNotEmpty, reason: '${row.first} に空の欄がある');
      }
    }
  });

  test('「対象」が実在する仕様の節を指している', () {
    // 節を消したり番号を振り直したりしたときに、台帳だけ古くなるのを防ぐ。
    final spec = File('docs/MusicListApp_Spec.md').readAsStringSync();
    for (final row in _rows()) {
      for (final section in row[1].split('/').map((s) => s.trim())) {
        expect(
          spec.contains('### $section') || spec.contains('## $section'),
          isTrue,
          reason: '${row.first} が指す仕様 $section が見つからない',
        );
      }
    }
  });

  test('「自動テストとの関係」が指すファイルは実在する', () {
    // **「〜が守っている」と書いてあるのに、そのファイルが無い**のが
    // いちばん危ない。守られていると思い込んで手動確認を省く。
    final paths = RegExp(r'`((?:test|functions|rules-test)/[^`]+\.(?:dart|ts|js|mjs))`');
    for (final row in _rows()) {
      for (final m in paths.allMatches(row[5])) {
        expect(
          File(m.group(1)!).existsSync(),
          isTrue,
          reason: '${row.first} が指す ${m.group(1)} が無い',
        );
      }
    }
  });

  test('「最終実施」は日付か 未実施', () {
    // 「済」「OK」のような書き方を許すと、いつのことか分からなくなる。
    final date = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    for (final row in _rows()) {
      final done = row[6];
      expect(
        done == '未実施' || date.hasMatch(done),
        isTrue,
        reason: '${row.first} の最終実施が「$done」。'
            'YYYY-MM-DD か 未実施 のどちらかにしてください',
      );
    }
  });

  test('件数の書き写しが実際の行数と合っている', () {
    // 本文に「全 N 件」と書いてあるので、行を足したときに直し忘れないよう
    // 突き合わせる。書き写した数は必ず古くなる（監査 第3回）。
    final body = File(_ledger).readAsStringSync();
    final declared = RegExp(r'\*\*全 (\d+) 件\*\*').firstMatch(body);
    expect(declared, isNotNull, reason: '「全 N 件」の記載が見つからない');
    expect(
      int.parse(declared!.group(1)!),
      _rows().length,
      reason: '本文の件数と、表の行数が合っていない',
    );
  });
}
