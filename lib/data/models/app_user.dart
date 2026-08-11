/// ユーザー（仕様書 13.3 `users/{uid}` と `users/{uid}/private/state`）
///
/// **公開されるものと私的なものを、型ごと分けてある**（2026-08-11）。
///
/// `users/{uid}` は表示名を解決するためにログイン済みなら誰でも読める。
/// そこにメールアドレス・プレミアムの期限・容量の使用量まで置いていたため、
/// 他の利用者からも見えていた。私的な項目は `users/{uid}/private/state` へ
/// 移し、**[AppUser] からは持てないようにした**。他人のぶんは読めないので、
/// 型の上でも「持っているかもしれない」状態を作らない。
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

/// 自分の合計の容量（`users/{uid}/private/state.storage`）。
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

/// ユーザーの**公開される**ぶん（`users/{uid}`）。
///
/// ログイン済みなら誰でも読める。表示名を解決するために必要な項目だけを
/// 置く。**私的な項目をここへ足さないこと**（[UserPrivate] へ入れる）。
class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.isWithdrawn,
    this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String? photoUrl;

  /// 退会済みか（仕様書 3.5）。退会してもドキュメントは残す。
  final bool isWithdrawn;

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      AppUser.fromMap(doc.id, doc.data());

  /// 保存されている中身から作る。
  ///
  /// **私的な項目が混ざっていても取り出さない。** 移行の途中は
  /// `users/{uid}` にも古い項目が残っていることがあるが、ここを通る限り
  /// 画面までは届かない（`DocumentSnapshot` は模擬できないので、
  /// テストはこちらを直に呼ぶ）。
  factory AppUser.fromMap(String uid, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    return AppUser(
      uid: uid,
      displayName: map['displayName'] as String? ?? '',
      photoUrl: map['photoURL'] as String?,
      isWithdrawn: map['isWithdrawn'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toCreateMap() => {
    'displayName': displayName,
    if (photoUrl != null) 'photoURL': photoUrl,
    'isWithdrawn': false,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

/// ユーザーの**私的な**ぶん（`users/{uid}/private/state`）。
///
/// **本人しか読めない**（firestore.rules）。したがって、このクラスの値は
/// 「自分のもの」以外には存在しない。他人の分を作れてしまうと、画面が
/// うっかり他人のメールアドレスや容量を出す形が書けてしまうので、
/// [AppUser] とは合流させない。
class UserPrivate {
  const UserPrivate({
    required this.locale,
    required this.notificationSettings,
    // サーバーだけが書く項目は、クライアントから作るときに渡さない。
    this.email = '',
    this.premiumUntil,
    this.storage,
  });

  /// ログインに使っているメールアドレス。
  ///
  /// **画面には出さない**（2026-08-11 の判断）。**書くのはサーバーだけ**で、
  /// クライアントは読むだけ（[toCreateMap] にも入れない）。
  final String email;

  /// 表示言語（`ja` / `en`）。
  final String locale;

  final NotificationSettings notificationSettings;

  /// プレミアムの期限（`premium.until`）。
  ///
  /// **無ければプレミアムでない**（docs/PREMIUM-DESIGN.md 7 節）。
  /// 判定は `PremiumPolicy.isActive` を通す。
  final DateTime? premiumUntil;

  /// 自分の合計の容量。**まだ集計されていなければ null**（0 で埋めない）。
  final UserStorage? storage;

  factory UserPrivate.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      UserPrivate.fromMap(doc.data());

  /// 保存されている中身から作る。
  ///
  /// **無いものを 0 や既定値で埋めない。** 容量とプレミアムの期限は
  /// null のまま返し、「まだ届いていない」を画面まで伝える。
  factory UserPrivate.fromMap(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    return UserPrivate(
      email: map['email'] as String? ?? '',
      locale: map['locale'] as String? ?? 'ja',
      notificationSettings: NotificationSettings.fromMap(
        map['notificationSettings'] as Map<String, dynamic>?,
      ),
      premiumUntil:
          ((map['premium'] as Map<String, dynamic>?)?['until'] as Timestamp?)
              ?.toDate(),
      storage: UserStorage.fromMap(map['storage'] as Map<String, dynamic>?),
    );
  }

  /// クライアントから作るときに書く中身。
  ///
  /// **本人が書けるのは `locale` と `notificationSettings` だけ**
  /// （firestore.rules）。`email` はログイン情報、`premium` と `storage` は
  /// 課金と集計の結果なので、いずれもサーバーだけが書く。ここへ足すと
  /// 書き込みごとルールに断られ、**登録そのものが失敗する。**
  Map<String, dynamic> toCreateMap() => {
    'locale': locale,
    'notificationSettings': notificationSettings.toMap(),
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
