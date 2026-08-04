/// 申請と通知と招待（仕様書 5.1 / 5.2 / 10 / 13.3）
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_user.dart';

/// 申請の状態（仕様書 5.2.1）。
enum RequestStatus {
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  const RequestStatus(this.wireName);

  final String wireName;

  static RequestStatus tryParse(String? value) {
    for (final s in RequestStatus.values) {
      if (s.wireName == value) return s;
    }
    return RequestStatus.pending;
  }
}

/// リスト作成申請（仕様書 5.1 `listRequests/{requestId}`）。
class ListRequest {
  const ListRequest({
    required this.id,
    required this.listName,
    required this.estimatedTrackCount,
    required this.expectedUserCount,
    required this.purpose,
    required this.requestedBy,
    required this.status,
    this.requestedAt,
    this.createdListId,
  });

  final String id;
  final String listName;
  final int estimatedTrackCount;
  final int expectedUserCount;
  final String purpose;
  final String requestedBy;
  final RequestStatus status;
  final DateTime? requestedAt;

  /// 承認時に作成されたリストの ID。
  final String? createdListId;

  factory ListRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return ListRequest(
      id: doc.id,
      listName: data['listName'] as String? ?? '',
      estimatedTrackCount: (data['estimatedTrackCount'] as num?)?.toInt() ?? 0,
      expectedUserCount: (data['expectedUserCount'] as num?)?.toInt() ?? 0,
      purpose: data['purpose'] as String? ?? '',
      requestedBy: data['requestedBy'] as String? ?? '',
      status: RequestStatus.tryParse(data['status'] as String?),
      requestedAt: (data['requestedAt'] as Timestamp?)?.toDate(),
      createdListId: data['createdListId'] as String?,
    );
  }
}

/// 参加申請（仕様書 5.2 `lists/{listId}/joinRequests/{uid}`）。
class JoinRequest {
  const JoinRequest({
    required this.uid,
    required this.listId,
    required this.status,
    this.requestedAt,
  });

  final String uid;
  final String listId;
  final RequestStatus status;
  final DateTime? requestedAt;

  factory JoinRequest.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String listId,
  }) {
    final data = doc.data() ?? const {};
    return JoinRequest(
      uid: doc.id,
      listId: listId,
      status: RequestStatus.tryParse(data['status'] as String?),
      requestedAt: (data['requestedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// アプリ内通知（仕様書 10 / 13.3）。
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.isRead,
    this.listId,
    this.itemId,
    this.commentId,
    this.actorUid,
    this.createdAt,
  });

  final String id;

  /// 未知の種別は null。将来 Functions 側に種別が増えても画面が壊れないようにする。
  final NotificationType? type;

  final bool isRead;
  final String? listId;
  final String? itemId;
  final String? commentId;
  final String? actorUid;
  final DateTime? createdAt;

  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return AppNotification(
      id: doc.id,
      type: NotificationType.tryParse(data['type'] as String?),
      isRead: data['isRead'] as bool? ?? false,
      listId: data['listId'] as String?,
      itemId: data['itemId'] as String?,
      commentId: data['commentId'] as String?,
      actorUid: data['actorUid'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// サイト管理画面に出すユーザー（Functions の listSiteUsers が返す）。
class SiteUser {
  const SiteUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.isSiteAdmin,
    required this.isWithdrawn,
  });

  final String uid;
  final String email;
  final String displayName;

  /// Auth のカスタムクレーム由来（仕様書 13.5）。
  final bool isSiteAdmin;

  final bool isWithdrawn;

  factory SiteUser.fromMap(Map<String, dynamic> map) => SiteUser(
    uid: map['uid'] as String? ?? '',
    email: map['email'] as String? ?? '',
    displayName: map['displayName'] as String? ?? '',
    isSiteAdmin: map['isSiteAdmin'] as bool? ?? false,
    isWithdrawn: map['isWithdrawn'] as bool? ?? false,
  );
}
