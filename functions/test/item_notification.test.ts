/**
 * 曲が追加されたときの通知の宛先（仕様書 10.2 / 10.3）
 *
 * **回帰テスト。**
 *
 * 以前は「リスト管理者＋サイト管理者（全リスト）」だけが宛先だった。
 * そのため、
 * - リストに参加していても、管理者でなければ曲の追加に気づけなかった
 * - サイト管理者には、参加していないリストの曲まで通知されていた
 *
 * 宛先を「そのリストのメンバー全員」に改めた。ここではその宛先の作り方と、
 * 通知設定（10.3）による絞り込みを、Firestore を差し替えて確かめる。
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

/** users/{uid} の中身。テストごとに差し替える。 */
let users: Record<string, unknown> = {};
/** lists/{listId}/members の顔ぶれ。 */
let members: Record<string, string[]> = {};
/** 実際に作られた通知（宛先 uid → 中身の配列）。 */
let written: { uid: string; data: Record<string, unknown> }[] = [];

vi.mock('firebase-admin/firestore', () => ({
  FieldValue: { serverTimestamp: () => 'ts' },
  getFirestore: () => ({
    doc: (path: string) => ({
      get: async () => {
        const uid = path.replace('users/', '');
        return { data: () => users[uid] };
      },
    }),
    collection: (path: string) => {
      const notifyMatch = /^users\/(.+)\/notifications$/.exec(path);
      if (notifyMatch) {
        return {
          add: async (data: Record<string, unknown>) => {
            written.push({ uid: notifyMatch[1], data });
          },
        };
      }
      const memberMatch = /^lists\/(.+)\/members$/.exec(path);
      if (memberMatch) {
        const uids = members[memberMatch[1]] ?? [];
        return { get: async () => ({ docs: uids.map((uid) => ({ id: uid })) }) };
      }
      throw new Error(`想定していないパス: ${path}`);
    },
  }),
}));

vi.mock('firebase-functions/logger', () => ({
  error: () => undefined,
  warn: () => undefined,
  info: () => undefined,
}));

const { listMemberUids, notifyUsers } = await import('../src/notifications');

/** 通知を受け取った人を並べる（順序は問わないので並べ替える）。 */
const recipients = () => written.map((w) => w.uid).sort();

beforeEach(() => {
  written = [];
  users = {};
  members = {};
});

describe('listMemberUids', () => {
  it('役割を問わずメンバー全員を返す', async () => {
    members.l1 = ['admin', 'super', 'reader'];
    expect((await listMemberUids('l1')).sort()).toEqual([
      'admin',
      'reader',
      'super',
    ]);
  });

  it('メンバーがいなければ空', async () => {
    expect(await listMemberUids('empty')).toEqual([]);
  });
});

describe('曲が追加されたときの通知', () => {
  it('リストのメンバー全員に届く（閲覧のみの人も含む）', async () => {
    members.l1 = ['admin', 'super', 'reader'];

    await notifyUsers(await listMemberUids('l1'), {
      type: 'itemAdded',
      listId: 'l1',
      itemId: 'i1',
    });

    expect(recipients()).toEqual(['admin', 'reader', 'super']);
  });

  it('追加した本人には届かない', async () => {
    members.l1 = ['admin', 'super', 'reader'];

    await notifyUsers(await listMemberUids('l1'), {
      type: 'itemAdded',
      listId: 'l1',
      itemId: 'i1',
      actorUid: 'super',
    });

    expect(recipients()).toEqual(['admin', 'reader']);
  });

  it('リストに参加していない人には届かない', async () => {
    members.l1 = ['admin'];
    members.l2 = ['stranger'];

    await notifyUsers(await listMemberUids('l1'), {
      type: 'itemAdded',
      listId: 'l1',
      itemId: 'i1',
    });

    expect(recipients()).toEqual(['admin']);
  });

  it('種別をオフにしている人には届かない（10.3）', async () => {
    members.l1 = ['on', 'off'];
    users.off = {
      notificationSettings: {
        master: true,
        types: { itemAdded: { inApp: false } },
      },
    };

    await notifyUsers(await listMemberUids('l1'), {
      type: 'itemAdded',
      listId: 'l1',
      itemId: 'i1',
    });

    expect(recipients()).toEqual(['on']);
  });

  it('別の種別をオフにしていても曲の通知は届く', async () => {
    members.l1 = ['u1'];
    users.u1 = {
      notificationSettings: {
        master: true,
        types: { commentAdded: { inApp: false } },
      },
    };

    await notifyUsers(await listMemberUids('l1'), {
      type: 'itemAdded',
      listId: 'l1',
      itemId: 'i1',
    });

    expect(recipients()).toEqual(['u1']);
  });

  it('すべての通知をオフにしている人には届かない（マスタースイッチ）', async () => {
    members.l1 = ['on', 'off'];
    users.off = { notificationSettings: { master: false } };

    await notifyUsers(await listMemberUids('l1'), {
      type: 'itemAdded',
      listId: 'l1',
      itemId: 'i1',
    });

    expect(recipients()).toEqual(['on']);
  });

  it('退会した人には届かない（3.5）', async () => {
    members.l1 = ['active', 'gone'];
    users.gone = { isWithdrawn: true };

    await notifyUsers(await listMemberUids('l1'), {
      type: 'itemAdded',
      listId: 'l1',
      itemId: 'i1',
    });

    expect(recipients()).toEqual(['active']);
  });

  it('設定が無い人には届く（初期状態は全てオン）', async () => {
    members.l1 = ['newcomer'];

    await notifyUsers(await listMemberUids('l1'), {
      type: 'itemAdded',
      listId: 'l1',
      itemId: 'i1',
    });

    expect(recipients()).toEqual(['newcomer']);
  });

  it('通知には曲の場所が入っている（タップで開けるように）', async () => {
    members.l1 = ['u1'];

    await notifyUsers(await listMemberUids('l1'), {
      type: 'itemAdded',
      listId: 'l1',
      itemId: 'i1',
      actorUid: 'u2',
    });

    expect(written[0].data).toMatchObject({
      type: 'itemAdded',
      listId: 'l1',
      itemId: 'i1',
      actorUid: 'u2',
      isRead: false,
    });
  });

  it('同じ人が二重に宛先に入っても 1 件だけ作る', async () => {
    members.l1 = ['u1', 'u1'];

    await notifyUsers(await listMemberUids('l1'), {
      type: 'itemAdded',
      listId: 'l1',
      itemId: 'i1',
    });

    expect(written).toHaveLength(1);
  });
});
