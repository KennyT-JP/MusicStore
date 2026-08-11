/// ユーザー（仕様書 13.3 `users/{uid}`）
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/quota.dart';

/// 通知種別（仕様書 10.2 / 13.3）。
enum NotificationType {
  itemAdded('itemAdded'),
  commentAdded('commentAdded'),
  quotaNotice('quotaNotice'),
  quotaWarning('quotaWarning'),
  listRequested('listRequested'),
  joinRequested('joinRequested'),
  requestApproved('requestApproved');

  const NotificationType(this.wireName);

  final String wireName;

  static NotificationType? tryParse(String? value) {
    for (final t in NotificationType.values) {
      if (t.wireName == value) return t;
    }
    return null;
  }
}

/// 1 種別ぶんの通知設定。
///
/// プッシュ通知は初期リリースでは画面に出さないが、値は最初から保持する
/// （仕様書 12.7）。
class NotificationChannelSetting {
  const NotificationChannelSetting({this.inApp = true, this.push = true});

  final bool inApp;
  final bool push;

  factory NotificationChannelSetting.fromMap(Map<String, dynamic>? map) =>
      NotificationChannelSetting(
        inApp: map?['inApp'] as bool? ?? true,
        push: map?['push'] as bool? ?? true,
      );

  Map<String, dynamic> toMap() => {'inApp': inApp, 'push': push};

  NotificationChannelSetting copyWith({bool? inApp, bool? push}) =>
      NotificationChannelSetting(
        inApp: inApp ?? this.inApp,
        push: push ?? this.push,
      );
}

/// 通知設定（仕様書 10.3）。初期状態は全てオン。
class NotificationSettings {
  const NotificationSettings({this.master = true, this.types = const {}});

  /// 全体を一括で切り替えるマスタースイッチ。
  final bool master;

  final Map<NotificationType, NotificationChannelSetting> types;

  factory NotificationSettings.fromMap(Map<String, dynamic>? map) {
    final rawTypes = map?['types'] as Map<String, dynamic>?;
    return NotificationSettings(
      master: map?['master'] as bool? ?? true,
      types: {
        for (final type in NotificationType.values)
          type: NotificationChannelSetting.fromMap(
            rawTypes?[type.wireName] as Map<String, dynamic>?,
          ),
      },
    );
  }

  Map<String, dynamic> toMap() => {
    'master': master,
    'types': {
      for (final entry in types.entries)
        entry.key.wireName: entry.value.toMap(),
    },
  };

  /// 既定値（すべてオン）。
  factory NotificationSettings.defaults() => NotificationSettings(
    types: {
      for (final type in NotificationType.values)
        type: const NotificationChannelSetting(),
    },
  );

  NotificationChannelSetting settingFor(NotificationType type) =>
      types[type] ?? const NotificationChannelSetting();

  /// この種別のアプリ内通知を出すか。マスターがオフなら全て出さない。
  bool inAppEnabled(NotificationType type) => master && settingFor(type).inApp;

  NotificationSettings copyWith({
    bool? master,
    Map<NotificationType, NotificationChannelSetting>? types,
  }) => NotificationSettings(
    master: master ?? this.master,
    types: types ?? this.types,
  );

  NotificationSettings withType(
    NotificationType type,
    NotificationChannelSetting setting,
  ) => copyWith(types: {...types, type: setting});
}

/// 自分の合計の容量（`users/{uid}.storage`）。
///
/// **本人だけが読める**（firestore.rules）。上限は人ごとの合計で、
/// リストごとの上限は使わない（docs/PREMIUM-DESIGN.md D5 の補足）。
class UserStorage {
  const UserStorage({required this.usedBytes, required this.quotaBytes});

  final int usedBytes;
  final int quotaBytes;

  QuotaStatus get quota =>
      QuotaStatus(usedBytes: usedBytes, quotaBytes: quotaBytes);

  /// **無ければ null を返す。** 0 で埋めると「まだ集計されていない」と
  /// 「使っていない」が区別できず、届く前に確定した数を出してしまう
  /// （docs/AUDIT-CHECKLIST.md 観点 2）。
  static UserStorage? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final used = (map['usedBytes'] as num?)?.toInt();
    final quota = (map['quotaBytes'] as num?)?.toInt();
    if (used == null || quota == null) return null;
    return UserStorage(usedBytes: used, quotaBytes: quota);
  }
}

/// ユーザー。
class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.locale,
    required this.isWithdrawn,
    required this.notificationSettings,
    this.photoUrl,
    this.premiumUntil,
    this.storage,
  });

  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;

  /// 表示言語（`ja` / `en`）。
  final String locale;

  /// 退会済みか（仕様書 3.5）。退会してもドキュメントは残す。
  final bool isWithdrawn;

  final NotificationSettings notificationSettings;

  /// プレミアムの期限（`premium.until`）。
  ///
  /// **無ければプレミアムでない**（docs/PREMIUM-DESIGN.md 7 節）。
  /// 判定は `PremiumPolicy.isActive` を通す。
  final DateTime? premiumUntil;

  /// 自分の合計の容量。**他人のドキュメントでは常に null**（読めない）。
  final UserStorage? storage;

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return AppUser(
      uid: doc.id,
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      photoUrl: data['photoURL'] as String?,
      locale: data['locale'] as String? ?? 'ja',
      isWithdrawn: data['isWithdrawn'] as bool? ?? false,
      notificationSettings: NotificationSettings.fromMap(
        data['notificationSettings'] as Map<String, dynamic>?,
      ),
      premiumUntil:
          ((data['premium'] as Map<String, dynamic>?)?['until'] as Timestamp?)
              ?.toDate(),
      storage: UserStorage.fromMap(data['storage'] as Map<String, dynamic>?),
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'displayName': displayName,
    'email': email,
    if (photoUrl != null) 'photoURL': photoUrl,
    'locale': locale,
    'isWithdrawn': false,
    'notificationSettings': notificationSettings.toMap(),
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
