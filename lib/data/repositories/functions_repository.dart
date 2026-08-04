/// Cloud Functions の呼び出し（仕様書 13.4）
///
/// 申請の承認・招待の受諾・サイト管理者の昇格など、クライアントを信用できない
/// 操作はすべて Cloud Functions を経由する。Firestore のセキュリティルールでも
/// 直接の書き込みを禁じている（仕様書 13.5）。
library;

import 'package:cloud_functions/cloud_functions.dart';

import '../../domain/invite.dart';
import '../../domain/role.dart';
import '../models/requests.dart';

/// Functions の呼び出しが失敗したときに投げる。
///
/// 画面に出す文言を [message] に持つ。
class FunctionsCallException implements Exception {
  const FunctionsCallException(this.code, this.message);

  /// `already-exists` など、Functions が返したコード。
  final String code;

  final String message;

  @override
  String toString() => 'FunctionsCallException($code): $message';
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
  // 招待 URL（仕様書 3.3）
  // -------------------------------------------------------------------

  /// 招待 URL を発行する（リスト管理者以上）。
  ///
  /// 返る ID がそのまま `/invite/{inviteId}` の URL になる。
  Future<({String inviteId, DateTime expiresAt})> createInvite({
    required String listId,
    required ListRole role,
  }) async {
    final result = await _call('createInvite', {
      'listId': listId,
      'role': role.wireName,
    });
    return (
      inviteId: result['inviteId'] as String,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (result['expiresAt'] as num).toInt(),
      ),
    );
  }

  /// 招待を受諾する。
  ///
  /// 有効期限は受諾した時点で判定される（仕様書 3.3）。
  /// 受け入れられない場合は [InviteRejection] に対応する例外を投げる。
  Future<String> acceptInvite(String inviteId) async {
    try {
      final result = await _call('acceptInvite', {'inviteId': inviteId});
      return result['listId'] as String;
    } on FunctionsCallException catch (e) {
      throw InviteRejectedException(_rejectionFrom(e.message));
    }
  }

  /// 招待を取り消す（リスト管理者以上）。
  Future<void> revokeInvite(String inviteId) =>
      _call('revokeInvite', {'inviteId': inviteId});

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

  /// リストの容量上限を設定する（仕様書 7.2）。
  Future<void> setListQuota({
    required String listId,
    required int quotaBytes,
  }) => _call('setListQuota', {'listId': listId, 'quotaBytes': quotaBytes});

  /// 管理者不在のリストにリスト管理者を指名する（仕様書 5.6）。
  Future<void> assignListAdmin({required String listId, required String uid}) =>
      _call('assignListAdmin', {'listId': listId, 'uid': uid});

  /// 退会する（仕様書 3.5）。
  ///
  /// 投稿・履歴は残り、表示名だけ「退会したユーザー」になる。
  /// 最後のサイト管理者は退会できない（仕様書 4.5）。
  Future<void> withdrawAccount() => _call('withdrawAccount', const {});

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
      throw FunctionsCallException(e.code, e.message ?? '処理に失敗しました。');
    }
  }

  /// Functions が返したメッセージを [InviteRejection] に対応づける。
  ///
  /// 招待の失敗理由は画面で出し分けたいので、文言ではなくコードで返している。
  InviteRejection _rejectionFrom(String message) {
    if (message.contains('invite-expired')) return InviteRejection.expired;
    if (message.contains('invite-already-used')) {
      return InviteRejection.alreadyUsed;
    }
    if (message.contains('invite-revoked')) return InviteRejection.revoked;
    if (message.contains('invite-already-member')) {
      return InviteRejection.alreadyMember;
    }
    return InviteRejection.notFound;
  }
}

/// 招待を受諾できなかったときに投げる（仕様書 3.3）。
class InviteRejectedException implements Exception {
  const InviteRejectedException(this.reason);

  final InviteRejection reason;
}
