/// Cloud Functions の呼び出し（仕様書 13.4）
///
/// 申請の承認・招待の受諾・サイト管理者の昇格など、クライアントを信用できない
/// 操作はすべて Cloud Functions を経由する。Firestore のセキュリティルールでも
/// 直接の書き込みを禁じている（仕様書 13.5）。
library;

import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/share_link.dart';
import '../../domain/role.dart';
import '../models/coupon.dart';
import '../models/requests.dart';

/// Functions の呼び出しが失敗したときに投げる。
///
/// 画面に出す文言を [message] に持つ。
class FunctionsCallException implements Exception {
  const FunctionsCallException(
    this.code,
    this.message, {
    this.reason,
    this.params = const {},
  });

  /// `already-exists` など、Functions が返したコード。
  final String code;

  /// サーバー側が用意した文（日本語）。
  ///
  /// **画面に出すのは最後の手段。** [reason] に対応する文言があるなら、
  /// そちらを使う。以前はこの文をそのまま出していたため、英語表示でも
  /// 申請・承認・招待・退会・容量変更のエラーが日本語で出ていた
  /// （監査 第2回）。
  final String message;

  /// 画面が文言を出し分けるための符号（functions/src/errors.ts）。
  final String? reason;

  /// 文言に差し込む値（リスト名など）。
  final Map<String, String> params;

  @override
  String toString() => 'FunctionsCallException($code/$reason): $message';
}

/// Cloud Functions の呼び出し口。
class FunctionsRepository {
  FunctionsRepository(this._functions);

  final FirebaseFunctions _functions;

  // -------------------------------------------------------------------
  // リスト作成申請（仕様書 5.1）
  // -------------------------------------------------------------------

  /// リスト作成を申請する。
  ///
  /// リスト名の重複チェックはサーバー側で行う。既に使われていれば
  /// [FunctionsCallException] の code が `already-exists` になる。
  Future<String> submitListRequest({
    required String listName,
    required String purpose,
    required int estimatedTrackCount,
    required int expectedUserCount,
  }) async {
    final result = await _call('submitListRequest', {
      'listName': listName,
      'purpose': purpose,
      'estimatedTrackCount': estimatedTrackCount,
      'expectedUserCount': expectedUserCount,
    });
    return result['requestId'] as String;
  }

  /// リスト作成申請を承認する（サイト管理者のみ）。
  Future<String> approveListRequest(String requestId) async {
    final result = await _call('approveListRequest', {'requestId': requestId});
    return result['listId'] as String;
  }

  /// リスト作成申請を却下する（サイト管理者のみ）。
  ///
  /// 却下しても申請者には通知しない（仕様書 10.2）。
  Future<void> rejectListRequest(String requestId) =>
      _call('rejectListRequest', {'requestId': requestId});

  // -------------------------------------------------------------------
  // 参加申請（仕様書 5.2 / 5.2.1）
  // -------------------------------------------------------------------

  /// 参加を申請する。役割は選べない。
  Future<void> submitJoinRequest(String listId) =>
      _call('submitJoinRequest', {'listId': listId});

  /// 参加申請を承認し、役割を決める（リスト管理者以上）。
  ///
  /// 付与できるのは Super User と Read Only のみ（仕様書 5.2）。
  Future<void> approveJoinRequest({
    required String listId,
    required String uid,
    required ListRole role,
  }) => _call('approveJoinRequest', {
    'listId': listId,
    'uid': uid,
    'role': role.wireName,
  });

  /// 参加申請を却下する。通知は送らない（仕様書 5.2.1）。
  Future<void> rejectJoinRequest({
    required String listId,
    required String uid,
  }) => _call('rejectJoinRequest', {'listId': listId, 'uid': uid});

  // -------------------------------------------------------------------
  // 共有リンク（仕様書 3.3）
  // -------------------------------------------------------------------

  /// 共有リンクを発行する（リスト管理者以上）。
  ///
  /// 返る ID がそのまま `/s/{linkId}` の URL になる。
  ///
  /// **無期限で、何度でも、複数人が使える。** [itemId] を渡すと、
  /// その曲を指すリンクになる。
  ///
  /// **役割は指定できない。** リンクは 1 種類だけで、受け取った人が
  /// 「参加する」か「参加せずに見る」かを選ぶ。参加した人の役割は
  /// サーバーが決める（`functions/src/domain/roles.ts` の
  /// `INITIAL_JOIN_ROLE`。「メンバーになる」を選んだ人は Super User）。
  Future<String> createShareLink({
    required String listId,
    String? itemId,
  }) async {
    final result = await _call('createShareLink', {
      'listId': listId,
      'itemId': ?itemId,
    });
    return result['linkId'] as String;
  }

  /// 共有リンクを開いた人を受け入れる。
  ///
  /// [join] が true ならメンバーになり、false なら参加せずに見るだけ。
  Future<ShareLinkResult> acceptShareLink(
    String linkId, {
    required bool join,
  }) async {
    try {
      final result = await _call('acceptShareLink', {
        'linkId': linkId,
        'mode': join ? 'join' : 'view',
      });
      return ShareLinkResult(
        listId: result['listId'] as String,
        itemId: result['itemId'] as String?,
        joined: result['joined'] == true,
      );
    } on FunctionsCallException catch (e) {
      // **リンクそのものの理由でない失敗を、リンクの失敗に潰さない。**
      // 以前はあらゆる例外を丸め、既定を「見つかりません」にしていた。
      // 未ログイン・メール未確認・通信の失敗でも「URL をご確認ください」
      // と出て、利用者は直しようのないことを指示されていた（監査 第2回）。
      final rejection = _rejectionFrom(e.reason);
      if (rejection == null) rethrow;
      throw ShareLinkRejectedException(rejection);
    }
  }

  /// 共有リンクを取り消す（リスト管理者以上）。
  ///
  /// **期限が無いので、これが唯一の止める手段。**
  Future<void> revokeShareLink(String linkId) =>
      _call('revokeShareLink', {'linkId': linkId});

  // -------------------------------------------------------------------
  // サイト管理者と退会（仕様書 4.4 / 4.5 / 3.5）
  // -------------------------------------------------------------------

  /// サイト管理者に昇格させる。
  ///
  /// 対象のユーザーは**再ログインするまで反映されない**（仕様書 13.5）。
  Future<void> grantSiteAdmin(String uid) =>
      _call('grantSiteAdmin', {'uid': uid});

  /// サイト管理者から外す。最後の 1 人は外せない（仕様書 4.5）。
  Future<void> revokeSiteAdmin(String uid) =>
      _call('revokeSiteAdmin', {'uid': uid});

  // -------------------------------------------------------------------
  // サイト管理画面（仕様書 11.1 / 7.2 / 5.6）
  // -------------------------------------------------------------------

  /// ユーザーの一覧を取得する（サイト管理者のみ）。
  ///
  /// サイト管理者かどうかは Auth のカスタムクレームにしかないため、
  /// クライアントから直接は分からない（仕様書 13.5）。
  Future<List<SiteUser>> listSiteUsers() async {
    final result = await _call('listSiteUsers', const {});
    final users = result['users'] as List<dynamic>? ?? const [];
    return users
        .map((e) => SiteUser.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// ユーザーを追加する（仕様書 11.1）。
  ///
  /// **パスワードはサイト管理者が決める。** 決めた本人が知っている
  /// 状態になるので、渡したあとで本人に変えてもらう（画面に案内あり）。
  Future<void> createSiteUser({
    required String email,
    required String password,
    required String displayName,
  }) => _call('createSiteUser', {
    'email': email,
    'password': password,
    'displayName': displayName,
  });

  /// ユーザーを無効にする（仕様書 11.1）。**戻せる。**
  ///
  /// ログインできなくなり、参加中のリストからも外れる。
  /// 曲・音源ファイル・コメントは残る。
  Future<void> disableSiteUser(String uid) =>
      _call('disableSiteUser', {'uid': uid});

  /// 無効にしたユーザーを有効に戻す（仕様書 11.1）。
  ///
  /// **参加していたリストには戻らない。** 改めて案内する。
  Future<void> enableSiteUser(String uid) =>
      _call('enableSiteUser', {'uid': uid});

  /// ユーザーを削除する（仕様書 11.1）。**戻せない。**
  ///
  /// アカウントと、その人が登録した曲・音源ファイルを消す。
  /// **コメントは残る**（表示名が「退会したユーザー」になる）。
  Future<void> deleteSiteUser(String uid) =>
      _call('deleteSiteUser', {'uid': uid});

  /// リストの容量上限を設定する（仕様書 7.2）。
  Future<void> setListQuota({
    required String listId,
    required int quotaBytes,
  }) => _call('setListQuota', {'listId': listId, 'quotaBytes': quotaBytes});

  /// 管理者不在のリストにリスト管理者を指名する（仕様書 5.6）。
  Future<void> assignListAdmin({required String listId, required String uid}) =>
      _call('assignListAdmin', {'listId': listId, 'uid': uid});

  /// サイト管理者が、ユーザーをリストのメンバーに加える（仕様書 5.7）。
  ///
  /// [role] は `superUser` か `readOnly`。**リスト管理者にはできない**
  /// （それは [assignListAdmin]）。すでにメンバーなら失敗する
  /// （役割の上げ下げはリスト管理者の仕事・5.4）。
  Future<void> addListMember({
    required String listId,
    required String uid,
    required ListRole role,
  }) => _call('addListMember', {
    'listId': listId,
    'uid': uid,
    // **`name` ではなく `wireName`。** 今はたまたま同じ値だが、
    // Firestore に入る文字列を決めているのは `wireName` のほう。
    'role': role.wireName,
  });

  /// 退会する（仕様書 3.5）。
  ///
  /// 投稿・履歴は残り、表示名だけ「退会したユーザー」になる。
  /// 最後のサイト管理者は退会できない（仕様書 4.5）。
  Future<void> withdrawAccount() => _call('withdrawAccount', const {});

  // -------------------------------------------------------------------
  // プレミアム（docs/PREMIUM-DESIGN.md）
  // -------------------------------------------------------------------

  /// クーポンを引き換える（本人／設計 5）。
  ///
  /// 返るのは**引き換えた後の期限**。2 枚目のクーポンなら月数が足される
  /// （設計 6 のテスト項目）。上書きではないので、返ってきた値をそのまま
  /// 「いつまでプレミアムか」として出してよい。
  ///
  /// 失敗の符号は `couponNotFound` / `couponDisabled` / `couponExpired` /
  /// `couponUsedUp` / `couponAlreadyUsed`。**原因ごとに文言が違う**ので、
  /// 呼び出し側は describeFunctionsError を通すこと。
  Future<DateTime?> redeemCoupon(String code) async {
    final result = await _call('redeemCoupon', {'code': code});
    return parseServerTime(result['premiumUntil']);
  }

  /// 申請なしでリストを作る（プレミアムの本人／設計 4.2）。
  ///
  /// **名前の予約は承認の流れと同じものを通る。** プレミアムでなければ
  /// `premiumRequired`、名前が使われていれば `listNameTaken` が返る。
  Future<String> createListDirectly(String listName) async {
    final result = await _call('createListDirectly', {'listName': listName});
    return result['listId'] as String;
  }

  // --- クーポン管理（サイト管理者のみ／設計 5） ---

  /// クーポンを発行する。
  ///
  /// [code] を渡すとその文字列になり、渡さなければサーバーが作る（D8）。
  /// **指定したコードは短く覚えやすい＝推測されやすい**ので、
  /// 人数（[maxUses]）と期限（[expiresAt]）を必ず添える。
  Future<({String couponId, String code})> createCoupon({
    required int months,
    required int maxUses,
    String? code,
    DateTime? expiresAt,
  }) async {
    final result = await _call('createCoupon', {
      'code': ?code,
      'months': months,
      'maxUses': maxUses,
      // **UTC の ISO 文字列で送る。** callable の引数は JSON になるため
      // Timestamp をそのまま渡せない。時差で 1 日ずれないよう UTC に寄せる。
      'expiresAt': ?expiresAt?.toUtc().toIso8601String(),
    });
    return (
      couponId: result['couponId'] as String? ?? '',
      code: result['code'] as String? ?? '',
    );
  }

  /// 使える人数を変える、または止める（D1）。
  ///
  /// **消さない。** 消すと誰が使ったかの記録まで消える（設計 5）。
  Future<void> updateCoupon({
    required String couponId,
    int? maxUses,
    bool? disabled,
  }) => _call('updateCoupon', {
    'couponId': couponId,
    'maxUses': ?maxUses,
    'disabled': ?disabled,
  });

  /// クーポンの一覧。
  Future<List<Coupon>> listCoupons() async {
    final result = await _call('listCoupons', const {});
    final coupons = result['coupons'] as List<dynamic>? ?? const [];
    return coupons
        .map((e) => Coupon.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// そのクーポンを使った人（追跡と、問い合わせへの回答用／設計 5）。
  Future<List<CouponRedemption>> listCouponRedemptions(String couponId) async {
    final result = await _call('listCouponRedemptions', {'couponId': couponId});
    final redemptions = result['redemptions'] as List<dynamic>? ?? const [];
    return redemptions
        .map(
          (e) => CouponRedemption.fromMap(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  /// 利用者のプレミアムを延ばす（サイト管理者／D4）。
  ///
  /// クーポンを配らずに延ばす経路。**足し算**であって上書きではない。
  Future<DateTime?> extendPremium({
    required String uid,
    required int months,
  }) async {
    final result = await _call('extendPremium', {'uid': uid, 'months': months});
    return parseServerTime(result['premiumUntil']);
  }

  /// 利用者の容量上限を変える（サイト管理者）。
  ///
  /// **上限は人ごとの合計**（設計 D5 の補足）。リストごとの上限
  /// （[setListQuota]）とは別のもの。
  Future<void> setUserQuota({required String uid, required int quotaBytes}) =>
      _call('setUserQuota', {'uid': uid, 'quotaBytes': quotaBytes});

  // -------------------------------------------------------------------

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final result = await _functions.httpsCallable(name).call(data);
      final value = result.data;
      if (value is Map) return Map<String, dynamic>.from(value);
      return const {};
    } on FirebaseFunctionsException catch (e) {
      // details に符号が載っていれば取り出す（functions/src/errors.ts）。
      final details = e.details;
      final map = details is Map ? details : const {};
      final reason = map['code'];

      throw FunctionsCallException(
        e.code,
        // **ここで日本語を書かない。** 文言は画面が l10n から引く
        // （ui/widgets/error_message.dart）。空のときは画面側が
        // 一般的な文言に倒す（監査 第3回）。
        e.message ?? '',
        reason: reason is String ? reason : null,
        params: {
          for (final entry in map.entries)
            if (entry.key != 'code') '${entry.key}': '${entry.value}',
        },
      );
    }
  }

  /// Functions が返した符号を [InviteRejection] に対応づける。
  ///
  /// **当てはまらなければ null を返す。** 既定を notFound にすると、
  /// 招待と関係のない失敗まで「招待が見つかりません」になってしまう。
  ShareLinkRejection? _rejectionFrom(String? reason) => switch (reason) {
    'shareLinkRevoked' => ShareLinkRejection.revoked,
    'shareLinkNotFound' => ShareLinkRejection.notFound,
    _ => null,
  };
}

/// 共有リンクを受け入れられなかったときに投げる（仕様書 3.3）。
class ShareLinkRejectedException implements Exception {
  const ShareLinkRejectedException(this.reason);

  final ShareLinkRejection reason;
}

/// リンクを受け入れた結果（仕様書 3.3）。
class ShareLinkResult {
  const ShareLinkResult({
    required this.listId,
    required this.joined,
    this.itemId,
  });

  final String listId;

  /// 曲を指すリンクなら、その曲。
  final String? itemId;

  /// メンバーになったか。false なら閲覧だけ。
  final bool joined;
}
