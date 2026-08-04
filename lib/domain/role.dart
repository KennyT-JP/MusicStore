/// 役割と権限階層（仕様書 4.1 / 4.2）
///
/// ```
/// サイト管理者 ＞ リスト管理者 ＞ Super User ＞ Read Only
/// ```
///
/// 上位の役割は下位の役割の権限をすべて包含する。
library;

/// リスト内での役割。
///
/// サイト管理者はここに含めない。サイト管理者は Auth のカスタムクレームで
/// 保持し、リストのメンバー登録を持たないため（仕様書 13.3 / 13.5）。
enum ListRole {
  /// 閲覧のみ。追加・コメントは一切不可（4.2）。
  readOnly('readOnly', 1),

  /// リストへの項目追加・アップロード、コメント・返信（4.2）。
  superUser('superUser', 2),

  /// 自分が管理するリスト内の全権限（4.2）。
  listAdmin('listAdmin', 3);

  const ListRole(this.wireName, this.rank);

  /// Firestore に保存する文字列。
  final String wireName;

  /// 権限の強さ。大きいほど上位。
  final int rank;

  /// Firestore の値から復元する。未知の値は [readOnly] に倒す。
  ///
  /// 不明な役割を強い権限として扱うと、仕様外の値が入り込んだときに
  /// 権限昇格になってしまうため、必ず最弱へ倒す。
  static ListRole? tryParse(String? value) {
    if (value == null) return null;
    for (final role in ListRole.values) {
      if (role.wireName == value) return role;
    }
    return null;
  }

  /// この役割が [other] 以上の権限を持つか。
  bool isAtLeast(ListRole other) => rank >= other.rank;
}

/// 「今このユーザーが、このリストに対して何ができるか」を表す文脈。
///
/// サイト管理者は全リストでリスト管理者と同等に扱う（4.2）。
class ListAccess {
  const ListAccess({required this.isSiteAdmin, required this.role});

  /// メンバーではない（かつサイト管理者でもない）状態。
  const ListAccess.none() : isSiteAdmin = false, role = null;

  /// サイト管理者としてのアクセス。
  const ListAccess.siteAdmin() : isSiteAdmin = true, role = null;

  /// Auth のカスタムクレーム由来（13.5）。
  final bool isSiteAdmin;

  /// `lists/{listId}/members/{uid}` 由来。メンバーでなければ null。
  final ListRole? role;

  /// 実効的な役割。サイト管理者は常にリスト管理者以上として扱う。
  ListRole? get effectiveRole {
    if (isSiteAdmin) return ListRole.listAdmin;
    return role;
  }

  /// このリストの中身を見られるか（5.3）。
  bool get canView => effectiveRole != null;

  /// 実効的な役割が [required] 以上か。
  bool hasAtLeast(ListRole required) {
    final effective = effectiveRole;
    if (effective == null) return false;
    return effective.isAtLeast(required);
  }
}
