/// 表示名の解決のテスト（仕様書 3.5 / 5.4 / 13.3）
///
/// 「退会したユーザー」と表示する条件は 2 つある。
/// 1. アカウント退会（isWithdrawn）
/// 2. そのリストの members にいない（除外された／自分で抜けた）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/display_name.dart';

void main() {
  const withdrawnLabel = '退会したユーザー';

  const activeUser = UserNameSource(displayName: '佐藤', isWithdrawn: false);
  const withdrawnUser = UserNameSource(displayName: '鈴木', isWithdrawn: true);

  test('参加中のメンバーは本人の表示名が出る', () {
    final result = DisplayNameResolver.resolveInList(
      uid: 'u1',
      user: activeUser,
      currentMemberUids: {'u1', 'u2'},
      withdrawnLabel: withdrawnLabel,
    );
    expect(result.text, '佐藤');
    expect(result.isAnonymized, isFalse);
  });

  test('退会したユーザーは元の名前を出さない（3.5）', () {
    final result = DisplayNameResolver.resolveInList(
      uid: 'u2',
      user: withdrawnUser,
      currentMemberUids: {'u1', 'u2'},
      withdrawnLabel: withdrawnLabel,
    );
    expect(result.text, withdrawnLabel);
    expect(result.isAnonymized, isTrue);
  });

  test('除外された・抜けた人も「退会したユーザー」表示（5.4）', () {
    // 本人は退会していないが、そのリストの members にはいない。
    final result = DisplayNameResolver.resolveInList(
      uid: 'u3',
      user: activeUser,
      currentMemberUids: {'u1', 'u2'},
      withdrawnLabel: withdrawnLabel,
    );
    expect(result.text, withdrawnLabel);
    expect(result.isAnonymized, isTrue);
  });

  test('メンバー集合を渡さなければ退会フラグだけで判断する', () {
    // 通知一覧など、リストの文脈を持たない画面で使う。
    final active = DisplayNameResolver.resolveInList(
      uid: 'u3',
      user: activeUser,
      currentMemberUids: null,
      withdrawnLabel: withdrawnLabel,
    );
    expect(active.text, '佐藤');

    final withdrawn = DisplayNameResolver.resolveInList(
      uid: 'u3',
      user: withdrawnUser,
      currentMemberUids: null,
      withdrawnLabel: withdrawnLabel,
    );
    expect(withdrawn.text, withdrawnLabel);
  });

  test('ユーザー情報が取れないときも元の名前を出さない', () {
    final result = DisplayNameResolver.resolveInList(
      uid: 'u9',
      user: null,
      currentMemberUids: {'u9'},
      withdrawnLabel: withdrawnLabel,
    );
    expect(result.text, withdrawnLabel);
    expect(result.isAnonymized, isTrue);
  });

  test('表示名が空文字なら退会扱いの表示にする', () {
    final result = DisplayNameResolver.resolveInList(
      uid: 'u1',
      user: const UserNameSource(displayName: '   ', isWithdrawn: false),
      currentMemberUids: {'u1'},
      withdrawnLabel: withdrawnLabel,
    );
    expect(result.text, withdrawnLabel);
  });

  _initialDisplayNameTests();
}

/// 登録直後の表示名（仕様書 3.4）
///
/// **回帰テスト。** 実際に、登録画面で入力した名前ではなく
/// メールアドレスの `@` より前が表示される不具合が出た。
/// Firebase の `updateDisplayName` はサーバー側を更新するだけで、
/// 手元の User オブジェクトの表示名は `reload` するまで空のままなのに、
/// そちらを先に見ていたのが原因。
void _initialDisplayNameTests() {
  group('登録直後の表示名', () {
    test('入力された名前を最優先にする', () {
      expect(
        DisplayNameResolver.initial(
          entered: '藤田 剛',
          // Auth 側はまだ空（updateDisplayName の直後はこうなる）。
          authDisplayName: null,
          email: 't-fujita@example.ne.jp',
          fallback: 'ユーザー',
        ),
        '藤田 剛',
      );
    });

    test('Auth 側に古い値が残っていても入力を優先する', () {
      expect(
        DisplayNameResolver.initial(
          entered: '新しい名前',
          authDisplayName: '古い名前',
          email: 'someone@example.com',
          fallback: 'ユーザー',
        ),
        '新しい名前',
      );
    });

    test('入力がなければ Google の表示名を使う', () {
      expect(
        DisplayNameResolver.initial(
          entered: null,
          authDisplayName: '藤田 剛',
          email: 'mobile.fujita@example.com',
          fallback: 'ユーザー',
        ),
        '藤田 剛',
      );
    });

    test('空白だけの入力は無視する', () {
      expect(
        DisplayNameResolver.initial(
          entered: '   ',
          authDisplayName: 'Google の名前',
          email: 'a@example.com',
          fallback: 'ユーザー',
        ),
        'Google の名前',
      );
    });

    test('どちらもなければメールアドレスの @ より前', () {
      expect(
        DisplayNameResolver.initial(
          entered: null,
          authDisplayName: null,
          email: 't-fujita@example.ne.jp',
          fallback: 'ユーザー',
        ),
        't-fujita',
      );
    });

    test('メールアドレスもなければ既定の呼び名', () {
      expect(
        DisplayNameResolver.initial(
          entered: null,
          authDisplayName: null,
          email: null,
          fallback: 'ユーザー',
        ),
        'ユーザー',
      );
    });

    test('前後の空白は落とす', () {
      expect(
        DisplayNameResolver.initial(
          entered: '  藤田 剛  ',
          fallback: 'ユーザー',
        ),
        '藤田 剛',
      );
    });
  });
}
