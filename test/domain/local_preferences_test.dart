/// 端末に残す表示の好み（仕様書 6.4）
///
/// **仕様は「端末側に保持し、次に開いたときも維持する」**だが、
/// 実装はメモリ上だけで、画面を開き直すと既定に戻っていた
/// （監査 第2回。2026-08-15 に対応）。
///
/// ここでは**実物**（`SharedPreferences` の差し替え可能な実装）を使って
/// 読み書きを確かめる。規則を写して確かめると、本番を壊しても緑になる。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/local_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('既定では削除済みも出す（6.4）', () async {
    final prefs = LocalPreferences(await SharedPreferences.getInstance());
    expect(prefs.showDeletedItems, isTrue);
  });

  test('切り替えると、次に開いたときも保たれる', () async {
    final prefs = LocalPreferences(await SharedPreferences.getInstance());
    await prefs.setShowDeletedItems(false);

    // **開き直したときと同じ経路で読む。** 同じインスタンスを見るだけでは
    // 「保存された」ことの確認にならない。
    final reopened = LocalPreferences(await SharedPreferences.getInstance());
    expect(reopened.showDeletedItems, isFalse);
  });

  test('元に戻せる', () async {
    final prefs = LocalPreferences(await SharedPreferences.getInstance());
    await prefs.setShowDeletedItems(false);
    await prefs.setShowDeletedItems(true);
    expect(prefs.showDeletedItems, isTrue);
  });

  test('保存されていない端末では既定に倒す', () async {
    // 保存領域が空（初回・利用者が消したあと）。
    SharedPreferences.setMockInitialValues({});
    final prefs = LocalPreferences(await SharedPreferences.getInstance());
    expect(prefs.showDeletedItems, isTrue);
  });
}
