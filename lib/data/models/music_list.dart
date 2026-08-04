/// リストとその内部情報（仕様書 13.3）
///
/// `lists/{listId}` には公開してよい情報だけを置き、容量・連番などの
/// 内部情報は `lists/{listId}/meta/stats` に分ける（仕様書 13.2）。
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/quota.dart';
import '../../domain/role.dart';

/// リスト（公開してよい情報のみ）。
class MusicList {
  const MusicList({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.adminCount,
    required this.memberCount,
    this.createdAt,
  });

  final String id;
  final String name;
  final String createdBy;

  /// リスト管理者の人数。0 なら管理者不在（仕様書 5.6）。
  final int adminCount;

  final int memberCount;
  final DateTime? createdAt;

  /// 管理者不在のリストか（仕様書 5.6）。
  bool get hasNoAdmin => adminCount <= 0;

  factory MusicList.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return MusicList(
      id: doc.id,
      name: data['name'] as String? ?? '',
      createdBy: data['createdBy'] as String? ?? '',
      adminCount: (data['adminCount'] as num?)?.toInt() ?? 0,
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// リストの内部情報（メンバーのみ読める）。
class ListStats {
  const ListStats({
    required this.nextSeq,
    required this.usedBytes,
    required this.quotaBytes,
    this.notifiedNotice80 = false,
    this.notifiedWarning90 = false,
  });

  /// 次に採番する連番（仕様書 6.2）。
  final int nextSeq;

  final int usedBytes;
  final int quotaBytes;
  final bool notifiedNotice80;
  final bool notifiedWarning90;

  QuotaStatus get quota =>
      QuotaStatus(usedBytes: usedBytes, quotaBytes: quotaBytes);

  factory ListStats.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return ListStats(
      nextSeq: (data['nextSeq'] as num?)?.toInt() ?? 1,
      usedBytes: (data['usedBytes'] as num?)?.toInt() ?? 0,
      quotaBytes: (data['quotaBytes'] as num?)?.toInt() ?? kDefaultQuotaBytes,
      notifiedNotice80: data['notifiedNotice80'] as bool? ?? false,
      notifiedWarning90: data['notifiedWarning90'] as bool? ?? false,
    );
  }
}

/// リストのメンバー（仕様書 13.3 `lists/{listId}/members/{uid}`）。
class ListMember {
  const ListMember({
    required this.uid,
    required this.role,
    this.joinedAt,
    this.addedBy,
    this.via,
  });

  final String uid;
  final ListRole role;
  final DateTime? joinedAt;
  final String? addedBy;

  /// `invite` / `request` / `founder`。
  final String? via;

  factory ListMember.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return ListMember(
      uid: doc.id,
      // 未知の役割は最弱に倒す（権限昇格を防ぐ／domain/role.dart）。
      role: ListRole.tryParse(data['role'] as String?) ?? ListRole.readOnly,
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate(),
      addedBy: data['addedBy'] as String?,
      via: data['via'] as String?,
    );
  }
}
