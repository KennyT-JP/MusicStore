/// 端末に残しておく表示の好み（仕様書 6.4）
///
/// **アプリ全体で 1 つ**（2026-08-14 の依頼者の判断）。リストごとに
/// 覚えると、どこで切ったか分からなくなる。
///
/// ここに置くのは「**消えても困らないもの**」だけにすること。
/// 端末の保存領域は利用者が消せるし、別の端末では引き継がれない。
library;

import 'package:shared_preferences/shared_preferences.dart';

/// 削除済みの項目を一覧に出すか。
///
/// 既定は出す（仕様書 6.4）。**読めなかったときも既定に倒す**——
/// 保存領域が使えないだけで一覧が出なくなるのは割に合わない。
class LocalPreferences {
  const LocalPreferences(this._prefs);

  final SharedPreferences _prefs;

  static const _showDeletedKey = 'showDeletedItems';

  bool get showDeletedItems => _prefs.getBool(_showDeletedKey) ?? true;

  Future<void> setShowDeletedItems(bool value) async {
    // **書けなくても画面は動かす。** 覚えられないだけで、
    // その場の切り替えは効いている。
    try {
      await _prefs.setBool(_showDeletedKey, value);
    } catch (_) {
      // 端末側の都合（容量・権限）。次に開いたとき既定に戻るだけ。
    }
  }
}
