/// 表示名の解決（仕様書 3.4 / 3.5 / 5.4 / 13.3）
///
/// 項目・コメントには uid のみを持ち、名前は表示時に `users` から引く。
/// 「退会したユーザー」と表示する条件は 2 つある（13.3）。
///
/// 1. `users/{uid}.isWithdrawn` が true（アカウント退会／3.5）
/// 2. その uid がそのリストの `members` に存在しない
///    （除外された／自分で抜けた／5.4）
library;

/// 表示名の解決に使うユーザー情報。
class UserNameSource {
  const UserNameSource({required this.displayName, required this.isWithdrawn});

  final String displayName;
  final bool isWithdrawn;
}

/// 表示名の解決結果。
class ResolvedName {
  const ResolvedName({required this.text, required this.isAnonymized});

  final String text;

  /// 「退会したユーザー」に置き換えられたか。
  ///
  /// 画面側でグレー表示にするなど、扱いを変えたいときに使う。
  final bool isAnonymized;
}

/// 表示名の解決。
class DisplayNameResolver {
  const DisplayNameResolver._();

  /// リスト内での表示名を解決する。
  ///
  /// [user] が null（ユーザードキュメントが取れない）場合も、
  /// 元の名前を出さずに [withdrawnLabel] を返す。
  ///
  /// [currentMemberUids] はそのリストの現在のメンバーの uid 集合。
  /// これを渡さない（null）場合はメンバー判定を行わず、退会フラグのみで判断する。
  /// リストの文脈を持たない画面（通知一覧など）で使う。
  static ResolvedName resolveInList({
    required String uid,
    required UserNameSource? user,
    required Set<String>? currentMemberUids,
    required String withdrawnLabel,
  }) {
    if (user == null || user.isWithdrawn) {
      return ResolvedName(text: withdrawnLabel, isAnonymized: true);
    }
    if (currentMemberUids != null && !currentMemberUids.contains(uid)) {
      return ResolvedName(text: withdrawnLabel, isAnonymized: true);
    }
    if (user.displayName.trim().isEmpty) {
      return ResolvedName(text: withdrawnLabel, isAnonymized: true);
    }
    return ResolvedName(text: user.displayName, isAnonymized: false);
  }
}
