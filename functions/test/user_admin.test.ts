/**
 * ユーザーの追加・無効化・削除の判断（仕様書 11.1）
 *
 * **消す・止める判断は、通信なしで確かめられる形に切り出してある。**
 * ここが崩れると、サイト管理者が 0 人になったり、自分で自分を
 * 締め出したりできてしまう。
 */
import { describe, expect, it } from 'vitest';

import {
  rejectNewUser,
  rejectUserAdminAction,
} from '../src/domain/user_admin';

const OTHER = { uid: 'other', isSiteAdmin: false };
const OTHER_ADMIN = { uid: 'other', isSiteAdmin: true };

describe('ユーザーに対する操作の可否（11.1）', () => {
  it('他人は無効にできる', () => {
    expect(
      rejectUserAdminAction({
        action: 'disable',
        actorUid: 'me',
        target: OTHER,
        siteAdminCount: 1,
      })
    ).toBeNull();
  });

  it('他人は削除できる', () => {
    expect(
      rejectUserAdminAction({
        action: 'delete',
        actorUid: 'me',
        target: OTHER,
        siteAdminCount: 1,
      })
    ).toBeNull();
  });

  it('自分自身は無効にできない', () => {
    // 締め出しを防ぐ。自分をやめるときは設定の退会を使う（3.5）。
    expect(
      rejectUserAdminAction({
        action: 'disable',
        actorUid: 'me',
        target: { uid: 'me', isSiteAdmin: true },
        siteAdminCount: 5,
      })
    ).toBe('selfNotAllowed');
  });

  it('自分自身は削除できない', () => {
    expect(
      rejectUserAdminAction({
        action: 'delete',
        actorUid: 'me',
        target: { uid: 'me', isSiteAdmin: false },
        siteAdminCount: 5,
      })
    ).toBe('selfNotAllowed');
  });

  it('最後のサイト管理者は止められない（4.5）', () => {
    // 誰も承認できなくなり、リストが 1 つも作れなくなる。
    expect(
      rejectUserAdminAction({
        action: 'disable',
        actorUid: 'me',
        target: OTHER_ADMIN,
        siteAdminCount: 1,
      })
    ).toBe('lastSiteAdmin');
    expect(
      rejectUserAdminAction({
        action: 'delete',
        actorUid: 'me',
        target: OTHER_ADMIN,
        siteAdminCount: 1,
      })
    ).toBe('lastSiteAdmin');
  });

  it('サイト管理者が 2 人以上いれば、片方は止められる', () => {
    expect(
      rejectUserAdminAction({
        action: 'disable',
        actorUid: 'me',
        target: OTHER_ADMIN,
        siteAdminCount: 2,
      })
    ).toBeNull();
  });

  it('有効に戻すのは、いつでも通る', () => {
    // 誰も締め出さないし、誰も消えない。止める理由が無い。
    for (const target of [OTHER, OTHER_ADMIN, { uid: 'me', isSiteAdmin: true }]) {
      expect(
        rejectUserAdminAction({
          action: 'enable',
          actorUid: 'me',
          target,
          siteAdminCount: 0,
        })
      ).toBeNull();
    }
  });
});

describe('新しいユーザーの入力（11.1）', () => {
  it('普通の入力は通る', () => {
    expect(
      rejectNewUser({ email: 'a@example.com', password: 'password' })
    ).toBeNull();
  });

  it('メールアドレスの形が違えば弾く', () => {
    for (const email of ['', 'a', 'a@', '@b.com', 'a@b', 'a b@c.com']) {
      expect(rejectNewUser({ email, password: 'password' })).toBe(
        'emailInvalid'
      );
    }
  });

  it('パスワードが 6 文字未満なら弾く', () => {
    // Firebase の要件。ここで弾かないと、読みにくい英語のエラーになる。
    expect(rejectNewUser({ email: 'a@example.com', password: '12345' })).toBe(
      'passwordTooShort'
    );
    expect(
      rejectNewUser({ email: 'a@example.com', password: '123456' })
    ).toBeNull();
  });
});
