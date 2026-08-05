/**
 * 通知の失敗が本処理を巻き込まないこと（仕様書 10.2）
 *
 * **回帰テスト。**
 *
 * 申請や承認などの本処理が終わったあとに通知を送るが、宛先を集める段階
 * （サイト管理者を探すための Auth 走査など）で例外が出ると、呼び出し全体が
 * internal で失敗していた。利用者からは「エラーが出たのに実際は登録されて
 * いる」という分かりにくい状態に見える。
 *
 * notifySafely は宛先集めごと包んで失敗を握る。通知は副次的なものなので、
 * ログに残して本処理は成功として返す。
 *
 * トリガー側にも同じ扱いが要る。例外を投げると失敗扱いになり、
 * 再試行が延々と繰り返されるため。
 */
import { describe, expect, it, vi } from 'vitest';

// firebase-admin を実際に初期化させないための差し替え。
// notifySafely の検証には Firestore は要らない（宛先集めの段階で失敗させる）。
vi.mock('firebase-admin/firestore', () => ({
  getFirestore: () => {
    throw new Error('この経路に来てはいけない');
  },
  FieldValue: { serverTimestamp: () => null },
}));

const logged: unknown[] = [];
vi.mock('firebase-functions/logger', () => ({
  error: (...args: unknown[]) => logged.push(args),
  warn: (...args: unknown[]) => logged.push(args),
  info: () => undefined,
}));

const { notifySafely } = await import('../src/notifications');

describe('notifySafely', () => {
  it('宛先を集める処理が失敗しても例外を投げない', async () => {
    await expect(
      notifySafely(
        async () => {
          // Auth の走査が権限不足で失敗する状況を模す。
          throw new Error('PERMISSION_DENIED: listUsers');
        },
        { type: 'listRequested', requestId: 'r1', actorUid: 'u1' }
      )
    ).resolves.toBeUndefined();
  });

  it('失敗はログに残す', async () => {
    logged.length = 0;
    await notifySafely(
      async () => {
        throw new Error('とにかく失敗');
      },
      { type: 'joinRequested', listId: 'l1', actorUid: 'u1' }
    );
    expect(logged.length).toBeGreaterThan(0);
  });

  it('宛先が空なら Firestore に触らない', async () => {
    // getFirestore を呼ぶと投げるように差し替えてあるので、
    // 例外なく終われば触っていないと言える。
    await expect(
      notifySafely(() => [], { type: 'itemAdded', listId: 'l1' })
    ).resolves.toBeUndefined();
  });

  it('本人しか宛先にいない場合も Firestore に触らない', async () => {
    // 自分の操作の通知が自分に届くのは雑音にしかならないので送らない。
    await expect(
      notifySafely(() => ['u1'], { type: 'itemAdded', listId: 'l1', actorUid: 'u1' })
    ).resolves.toBeUndefined();
  });
});
