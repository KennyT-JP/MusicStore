/// クーポン（docs/PREMIUM-DESIGN.md 3.2 / 5）
///
/// **クライアントから Firestore を直接読めない。** ルールで全面禁止に
/// してあり（設計 9 の 3「コードの漏れ」）、一覧も発行も停止も
/// 呼び出し可能関数を通す。ここにあるのは、その戻り値の受け皿。
library;

/// 呼び出し可能関数が返す日時を DateTime にする。
///
/// **形を決め打ちしない。** callable の戻り値は JSON になるため、
/// Firestore の Timestamp がどの形で降りてくるかは
/// サーバー側の書き方で変わる（ISO 文字列・ミリ秒・`{_seconds}`）。
/// どれで来ても読めるようにしておき、読めなければ null にする。
/// **0 や「いま」へ倒さない**——期限切れの判定が狂う。
DateTime? parseServerTime(Object? value) {
  switch (value) {
    case null:
      return null;
    case DateTime v:
      return v;
    case num v:
      // ミリ秒。秒で来た場合（10 桁）も拾えるようにする。
      final ms = v.abs() < 100000000000 ? v * 1000 : v;
      return DateTime.fromMillisecondsSinceEpoch(ms.round(), isUtc: true)
          .toLocal();
    case String v:
      return DateTime.tryParse(v)?.toLocal();
    case Map v:
      final seconds = v['_seconds'] ?? v['seconds'];
      if (seconds is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          (seconds * 1000).round(),
          isUtc: true,
        ).toLocal();
      }
      return null;
    default:
      return null;
  }
}

/// クーポン 1 枚。
class Coupon {
  const Coupon({
    required this.id,
    required this.code,
    required this.months,
    required this.maxUses,
    required this.usedCount,
    required this.disabled,
    this.expiresAt,
    this.createdAt,
  });

  final String id;

  /// 配る文字列。**照合はサーバーが codeHash で行う**（設計 3.2）。
  final String code;

  /// 付与する月数（D2）。
  final int months;

  /// 何人まで使えるか（D1）。**あとから変更できる。**
  final int maxUses;

  /// すでに使われた数。
  final int usedCount;

  /// 配ったあとに止めたときに立つ（D1／消さない）。
  final bool disabled;

  /// クーポン自体の有効期限。無期限なら null。
  final DateTime? expiresAt;

  final DateTime? createdAt;

  /// 使える人数が尽きているか。
  ///
  /// **上限を使用済みより下げられる**（D1 の補足）ので、
  /// 「ちょうど」ではなく「以上」で見る。
  bool get isUsedUp => usedCount >= maxUses;

  factory Coupon.fromMap(Map<String, dynamic> map) => Coupon(
    id: map['id'] as String? ?? '',
    code: map['code'] as String? ?? '',
    months: (map['months'] as num?)?.toInt() ?? 0,
    maxUses: (map['maxUses'] as num?)?.toInt() ?? 0,
    usedCount: (map['usedCount'] as num?)?.toInt() ?? 0,
    disabled: map['disabled'] as bool? ?? false,
    expiresAt: parseServerTime(map['expiresAt']),
    createdAt: parseServerTime(map['createdAt']),
  );
}

/// クーポンを使った人（`coupons/{couponId}/redemptions/{uid}`）。
class CouponRedemption {
  const CouponRedemption({required this.uid, this.redeemedAt});

  final String uid;
  final DateTime? redeemedAt;

  factory CouponRedemption.fromMap(Map<String, dynamic> map) =>
      CouponRedemption(
        uid: map['uid'] as String? ?? '',
        redeemedAt: parseServerTime(map['redeemedAt']),
      );
}
