/// ユーザー（仕様書 13.3 `users/{uid}`）
library;

import 'package:cloud_firestore/cloud_firestore.dart';

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
      for (final entry in types.entries) entry.key.wireName: entry.value.toMap(),
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
  bool inAppEnabled(NotificationType type) =>
      master && settingFor(type).inApp;

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
