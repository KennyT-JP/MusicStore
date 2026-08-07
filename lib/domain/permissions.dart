/// 権限判定（仕様書 4.2 / 6.3 / 9 / 14.5）
///
/// 12.6 で「自動テストを書く対象（必須）」に挙げた領域。
/// 画面側の出し分けはここを唯一の判断元とし、同じ規則を Firestore の
/// セキュリティルール（firestore.rules）でも二重に守る。
library;

import 'role.dart';

/// 権限判定の入口。すべて静的メソッドで、状態を持たない。
class Permissions {
  const Permissions._();

  // ---------------------------------------------------------------------
  // リストの閲覧
  // ---------------------------------------------------------------------

  /// リストの中身（項目・コメント）を閲覧できるか。
  ///
  /// 未参加者には共有 URL でリスト名しか見せない（5.3）。
  static bool canViewList(ListAccess access) => access.canView;

  // ---------------------------------------------------------------------
  // 項目（6 章）
  // ---------------------------------------------------------------------

  /// 項目を追加できるか。Super User 以上（4.2）。
  static bool canAddItem(ListAccess access) =>
      access.hasAtLeast(ListRole.superUser);

  /// 項目を編集できるか。
  ///
  /// 登録した本人、リスト管理者、サイト管理者（6.3）。
  /// 削除済みの項目は編集できない。
  static bool canEditItem(
    ListAccess access, {
    required String viewerUid,
    required String itemCreatedBy,
    required bool itemIsDeleted,
  }) {
    if (itemIsDeleted) return false;
    if (access.hasAtLeast(ListRole.listAdmin)) return true;
    if (!access.hasAtLeast(ListRole.superUser)) return false;
    return viewerUid == itemCreatedBy;
  }

  /// 項目を削除できるか。条件は編集と同じ（6.3）。
  static bool canDeleteItem(
    ListAccess access, {
    required String viewerUid,
    required String itemCreatedBy,
    required bool itemIsDeleted,
  }) => canEditItem(
    access,
    viewerUid: viewerUid,
    itemCreatedBy: itemCreatedBy,
    itemIsDeleted: itemIsDeleted,
  );

  /// 削除済み項目を復元できるか。
  ///
  /// 猶予期間中のみ、リスト管理者以上（6.3 / 13.4）。
  static bool canRestoreItem(
    ListAccess access, {
    required bool itemIsDeleted,
    required bool withinGracePeriod,
  }) {
    if (!itemIsDeleted) return false;
    if (!withinGracePeriod) return false;
    return access.hasAtLeast(ListRole.listAdmin);
  }

  // ---------------------------------------------------------------------
  // コメント（9 章）
  // ---------------------------------------------------------------------

  /// コメント・返信を書けるか。Super User 以上。Read Only は一切不可（9）。
  static bool canPostComment(ListAccess access) =>
      access.hasAtLeast(ListRole.superUser);

  /// コメントを編集できるか。
  ///
  /// 本人、リスト管理者、サイト管理者（9）。削除済みは編集できない。
  static bool canEditComment(
    ListAccess access, {
    required String viewerUid,
    required String commentCreatedBy,
    required bool commentIsDeleted,
  }) {
    if (commentIsDeleted) return false;
    if (access.hasAtLeast(ListRole.listAdmin)) return true;
    if (!access.hasAtLeast(ListRole.superUser)) return false;
    return viewerUid == commentCreatedBy;
  }

  /// コメントを削除できるか。条件は編集と同じ（9）。
  static bool canDeleteComment(
    ListAccess access, {
    required String viewerUid,
    required String commentCreatedBy,
    required bool commentIsDeleted,
  }) => canEditComment(
    access,
    viewerUid: viewerUid,
    commentCreatedBy: commentCreatedBy,
    commentIsDeleted: commentIsDeleted,
  );

  // ---------------------------------------------------------------------
  // リスト管理（5 章 / 11.2）
  // ---------------------------------------------------------------------

  /// メンバーの招待・承認・役割変更・除外ができるか（4.2）。
  static bool canManageMembers(ListAccess access) =>
      access.hasAtLeast(ListRole.listAdmin);

  /// 共有リンクを発行できるか。
  ///
  /// サイト管理者は誰に対しても、リスト管理者は自分のリストへのみ（3.3）。
  /// この関数は 1 つのリストに対する判定なので、両者とも同じ条件になる。
  static bool canCreateShareLink(ListAccess access) =>
      access.hasAtLeast(ListRole.listAdmin);

  /// リストを削除できるか。リスト管理者以上（5.5）。
  static bool canDeleteList(ListAccess access) =>
      access.hasAtLeast(ListRole.listAdmin);

  /// 容量使用量を把握できるか。リスト管理者以上（7.4）。
  static bool canViewQuota(ListAccess access) =>
      access.hasAtLeast(ListRole.listAdmin);

  /// メンバーを除外できるか。
  ///
  /// 自分自身は「除外」ではなく「離脱」で抜けるため、ここでは対象外にする（5.4）。
  static bool canRemoveMember(
    ListAccess access, {
    required String viewerUid,
    required String targetUid,
  }) {
    if (viewerUid == targetUid) return false;
    return access.hasAtLeast(ListRole.listAdmin);
  }

  /// 自分からリストを抜けられるか。
  ///
  /// メンバーであれば誰でも抜けられる（5.4）。
  /// サイト管理者はそもそもメンバー登録を持たないため対象外。
  static bool canLeaveList(ListAccess access) => access.role != null;

  // ---------------------------------------------------------------------
  // サイト管理（11.1）
  // ---------------------------------------------------------------------

  /// サイト管理画面に入れるか。
  static bool canAccessSiteAdmin(ListAccess access) => access.isSiteAdmin;

  /// サイト管理者が自分を降格・退会できるか（4.5）。
  ///
  /// 最後の 1 人は抜けられない。判定はサーバー側でも行う。
  static bool canStepDownAsSiteAdmin({
    required bool isSiteAdmin,
    required int siteAdminCount,
  }) {
    if (!isSiteAdmin) return true;
    return siteAdminCount > 1;
  }
}
