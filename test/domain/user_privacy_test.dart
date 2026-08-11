/// 私的な情報の置き場所（2026-08-11 の分離）
///
/// **回帰テスト。** `users/{uid}` は表示名を解決するために、ログイン済み
/// なら誰でも読める。そこにメールアドレス・プレミアムの期限・容量の
/// 使用量まで置いていたため、**他の利用者からも見えていた**。
///
/// 私的な項目は `users/{uid}/private/state`（本人だけが読める）へ移した。
/// ここで固定するのは 2 つ。
///
/// 1. **公開されるほうへ私的な項目が戻ってこない。** [AppUser] は
///    読み取りでも書き込みでも公開されるものしか扱わない
/// 2. **私的なほうは、届いていないものを 0 や既定値で埋めない**
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/data/firestore_paths.dart';
import 'package:music_list_app/data/models/app_user.dart';

// `DocumentSnapshot` は sealed で模擬できないため、保存されている中身
// （Map）を直に渡す `fromMap` を確かめる。`fromDoc` はその薄い包みで、
// 取り出し方の判断はすべて `fromMap` にある。

void main() {
  group('置き場所', () {
    test('私的な情報は users/{uid}/private/state にある', () {
      expect(FirestorePaths.userPrivate('u1'), 'users/u1/private/state');
      // 公開されるほうは、いままでどおり。
      expect(FirestorePaths.user('u1'), 'users/u1');
    });
  });

  group('公開されるぶん（users/{uid}）', () {
    // **他人のドキュメントも同じ型で読む。** 私的な項目が混ざっていても
    // 取り出せないことを、ここで固定する。
    test('私的な項目が残っていても、公開されるものしか読まない', () {
      final user = AppUser.fromMap('u1', {
        'displayName': '太郎',
        'photoURL': 'https://example.com/a.png',
        'isWithdrawn': false,
        // 移行前の名残（サーバー側が消すまで残ることがある）。
        'email': 'taro@example.com',
        'locale': 'en',
        'notificationSettings': {'master': false},
        'premium': {'until': Timestamp.fromDate(DateTime(2027, 3, 31))},
        'storage': {'usedBytes': 1, 'quotaBytes': 2},
      });

      expect(user.uid, 'u1');
      expect(user.displayName, '太郎');
      expect(user.photoUrl, 'https://example.com/a.png');
      expect(user.isWithdrawn, isFalse);
      // 私的な項目は、型の上でも持てない（読み出す手段が無い）。
    });

    test('作るときも、公開されるものしか書かない', () {
      final map = const AppUser(
        uid: 'u1',
        displayName: '太郎',
        isWithdrawn: false,
      ).toCreateMap();

      expect(map.keys, contains('displayName'));
      expect(map.keys, contains('isWithdrawn'));
      // **誰でも読める場所へ私的な項目を書き戻さない。**
      expect(map.keys, isNot(contains('email')));
      expect(map.keys, isNot(contains('locale')));
      expect(map.keys, isNot(contains('notificationSettings')));
      expect(map.keys, isNot(contains('premium')));
      expect(map.keys, isNot(contains('storage')));
    });
  });

  group('私的なぶん（users/{uid}/private/state）', () {
    test('表示言語・通知設定・プレミアム・容量を読む', () {
      final private = UserPrivate.fromMap({
        'email': 'taro@example.com',
        'locale': 'en',
        'notificationSettings': {'master': false},
        'premium': {'until': Timestamp.fromDate(DateTime(2027, 3, 31))},
        'storage': {'usedBytes': 1024, 'quotaBytes': 4096},
      });

      expect(private.email, 'taro@example.com');
      expect(private.locale, 'en');
      expect(private.notificationSettings.master, isFalse);
      expect(private.premiumUntil, DateTime(2027, 3, 31));
      expect(private.storage?.usedBytes, 1024);
      expect(private.storage?.quotaBytes, 4096);
    });

    // **届いていないものを 0 で埋めない**（docs/AUDIT-CHECKLIST.md 観点 2）。
    // 「まだ集計されていない」と「使っていない」は別物。
    test('容量がまだ書かれていなければ null（0 にしない）', () {
      final private = UserPrivate.fromMap(const {});

      expect(private.storage, isNull);
      expect(private.premiumUntil, isNull);
      // 表示言語だけは、無ければ日本語から始める（仕様書 2 章）。
      expect(private.locale, 'ja');
    });

    // **本人が書けるのは表示言語と通知設定だけ**（firestore.rules）。
    // メールアドレス・プレミアム・容量を混ぜると、書き込みごと断られて
    // 登録そのものが失敗する。
    test('作るときは、本人が書けるものだけを書く', () {
      final map = UserPrivate(
        locale: 'ja',
        notificationSettings: NotificationSettings.defaults(),
      ).toCreateMap();

      expect(map.keys, contains('locale'));
      expect(map.keys, contains('notificationSettings'));
      expect(map.keys, isNot(contains('email')));
      expect(map.keys, isNot(contains('premium')));
      expect(map.keys, isNot(contains('storage')));
    });
  });
}
