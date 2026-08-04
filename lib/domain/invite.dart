/// 招待 URL の検証（仕様書 3.3 / 13.3）
///
/// 12.6 で「自動テストを書く対象（必須）」に挙げた領域。
/// ワンタイム性と有効期限の判定をここに集約する。
///
/// 実際の受諾（members への登録と status の更新）は Cloud Functions の
/// トランザクションで行う。ここはその判定ロジックと、画面に出す
/// メッセージの決定を担う。
library;

/// 招待 URL の状態（`invites/{inviteId}.status`）。
enum InviteStatus {
  /// まだ使われていない。
  active('active'),

  /// すでに誰かが使った（ワンタイム）。
  used('used'),

  /// 発行者が取り消した。
  revoked('revoked');

  const InviteStatus(this.wireName);

  final String wireName;

  static InviteStatus? tryParse(String? value) {
    if (value == null) return null;
    for (final s in InviteStatus.values) {
      if (s.wireName == value) return s;
    }
    return null;
  }
}

/// 招待を受諾できない理由。
enum InviteRejection {
  /// 招待そのものが存在しない（URL が誤っている）。
  notFound,

  /// 有効期限を過ぎている（3.3）。
  expired,

  /// すでに使用済み（ワンタイム／3.3）。
  alreadyUsed,

  /// 発行者が取り消した。
  revoked,

  /// すでにそのリストのメンバーである。
  alreadyMember,
}

/// 招待の受諾可否の判定結果。
class InviteValidation {
  const InviteValidation._(this.accepted, this.rejection);

  const InviteValidation.accept() : this._(true, null);
  const InviteValidation.reject(InviteRejection rejection)
    : this._(false, rejection);

  final bool accepted;
  final InviteRejection? rejection;
}

/// 検証に必要な招待の情報。
class InviteSnapshot {
  const InviteSnapshot({
    required this.listId,
    required this.status,
    required this.expiresAt,
  });

  final String listId;
  final InviteStatus status;
  final DateTime expiresAt;
}

/// 招待 URL の検証。
class InvitePolicy {
  const InvitePolicy._();

  /// 招待を受諾できるか（3.3）。
  ///
  /// [now] は受諾しようとしている時刻。**URL を開いた時刻ではなく、実際に
  /// 参加処理が走る瞬間**を渡す。サインアップやメール確認を挟むため、
  /// 有効期限は受諾時点で判定すると仕様書で定めている（3.3）。
  ///
  /// [alreadyMember] は、そのユーザーがすでにこのリストのメンバーかどうか。
  static InviteValidation validate({
    required InviteSnapshot? invite,
    required DateTime now,
    required bool alreadyMember,
  }) {
    if (invite == null) {
      return const InviteValidation.reject(InviteRejection.notFound);
    }
    switch (invite.status) {
      case InviteStatus.used:
        return const InviteValidation.reject(InviteRejection.alreadyUsed);
      case InviteStatus.revoked:
        return const InviteValidation.reject(InviteRejection.revoked);
      case InviteStatus.active:
        break;
    }
    if (!now.isBefore(invite.expiresAt)) {
      return const InviteValidation.reject(InviteRejection.expired);
    }
    if (alreadyMember) {
      return const InviteValidation.reject(InviteRejection.alreadyMember);
    }
    return const InviteValidation.accept();
  }

  /// 発行時の有効期限を求める（3.3）。
  ///
  /// [expiryHours] はサイト設定 `siteConfig.inviteExpiryHours`（初期値 24）。
  static DateTime expiresAtFrom(DateTime issuedAt, int expiryHours) =>
      issuedAt.add(Duration(hours: expiryHours));
}
