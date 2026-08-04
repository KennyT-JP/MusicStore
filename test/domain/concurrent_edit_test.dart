/// 同時編集の検出のテスト（仕様書 6.3）
///
/// バックアップを持たない方針（12.3）のため、
/// 他人の変更を知らないまま上書きする事故を防ぐ。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/concurrent_edit.dart';

void main() {
  final opened = DateTime.utc(2026, 8, 4, 12, 0);

  test('開いてから変わっていなければ保存できる', () {
    expect(
      ConcurrentEditGuard.check(openedWith: opened, currentOnServer: opened),
      SaveDecision.proceed,
    );
  });

  test('他の人が更新していたら保存を中止する', () {
    final updatedByOther = opened.add(const Duration(seconds: 30));
    expect(
      ConcurrentEditGuard.check(
        openedWith: opened,
        currentOnServer: updatedByOther,
      ),
      SaveDecision.conflict,
    );
  });

  test('同じ時刻なら別インスタンスでも保存できる', () {
    expect(
      ConcurrentEditGuard.check(
        openedWith: DateTime.utc(2026, 8, 4, 12),
        currentOnServer: DateTime.utc(2026, 8, 4, 12),
      ),
      SaveDecision.proceed,
    );
  });

  test('更新日時が取れないときは衝突扱いにする', () {
    // 上書き事故を避けるため、判断できない場合は保存させない。
    expect(
      ConcurrentEditGuard.check(openedWith: null, currentOnServer: opened),
      SaveDecision.conflict,
    );
    expect(
      ConcurrentEditGuard.check(openedWith: opened, currentOnServer: null),
      SaveDecision.conflict,
    );
    expect(
      ConcurrentEditGuard.check(openedWith: null, currentOnServer: null),
      SaveDecision.conflict,
    );
  });
}
