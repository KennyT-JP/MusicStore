/**
 * Firestore セキュリティルールのテスト（仕様書 13.5）
 *
 * 12.6 で「クライアントを信用しない最後の防波堤」として
 * 自動テスト必須にした領域。
 */
import { afterAll, beforeAll, beforeEach, describe, expect, test } from 'vitest';
import {
  collection,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';

import {
  COMMENT_ID,
  COUPON_ID,
  ITEM_ID,
  LIST_ID,
  UID,
  allow,
  asAnonymous,
  asSiteAdmin,
  asUnverified,
  asUser,
  createTestEnv,
  deny,
  maybeReseed,
  mutateAsAdmin,
} from './helpers.js';

let env;

beforeAll(async () => {
  env = await createTestEnv();
});

afterAll(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await maybeReseed(env);
});

const db = (ctx) => ctx.firestore();

describe('未ログイン（3.1.1）', () => {
  test('リスト名すら読めない', async () => {
    const anon = db(asAnonymous(env));
    await deny(getDoc(doc(anon, `lists/${LIST_ID}`)));
  });

  test('項目も読めない', async () => {
    const anon = db(asAnonymous(env));
    await deny(getDoc(doc(anon, `lists/${LIST_ID}/items/${ITEM_ID}`)));
  });

  test('共有リンクも読めない', async () => {
    // **ログインしていない人には、リンクを知っていても見せない（3.3）。**
    // 「参加せずに見る」もログインは要る、という決めごとがここで効く。
    const anon = db(asAnonymous(env));
    await deny(getDoc(doc(anon, 'shareLinks/link-1')));
  });

  test('参加せずに見る人の中身も、未ログインでは読めない', async () => {
    const anon = db(asAnonymous(env));
    await deny(getDoc(doc(anon, `lists/${LIST_ID}/items/${ITEM_ID}`)));
  });
});

describe('リストの列挙（5.3）', () => {
  test('一般ユーザーは全リストを列挙できない', async () => {
    // 列挙できると未参加者が全リスト名を知れてしまい、
    // 「全リストの一覧を公開する画面は作らない」に反する。
    const outsider = db(asUser(env, UID.outsider));
    await deny(getDocs(collection(outsider, 'lists')));
  });

  test('メンバーでも全リストは列挙できない', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await deny(getDocs(collection(listAdmin, 'lists')));
  });

  test('サイト管理者だけが全リストを列挙できる（11.1）', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await allow(getDocs(collection(siteAdmin, 'lists')));
  });

  test('ID を知っていれば取得できる（共有 URL の経路）', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await allow(getDoc(doc(outsider, `lists/${LIST_ID}`)));
  });
});

describe('未参加者から見たリスト（5.3）', () => {
  test('リスト名など最低限の情報は読める', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await allow(getDoc(doc(outsider, `lists/${LIST_ID}`)));
  });

  test('中身（項目）は読めない', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await deny(
      getDoc(doc(outsider, `lists/${LIST_ID}/items/${ITEM_ID}`)),
    );
  });

  test('コメントも読めない', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await deny(
      getDoc(
        doc(outsider, `lists/${LIST_ID}/items/${ITEM_ID}/comments/${COMMENT_ID}`),
      ),
    );
  });

  test('容量などの内部情報は読めない', async () => {
    // lists/{listId} を公開しても meta/stats は隠れる（13.2 の 2 段構成）。
    const outsider = db(asUser(env, UID.outsider));
    await deny(getDoc(doc(outsider, `lists/${LIST_ID}/meta/stats`)));
  });

  test('項目を追加できない', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await deny(
      setDoc(doc(outsider, `lists/${LIST_ID}/items/new-item`), {
        seq: 2,
        createdBy: UID.outsider,
        status: 'active',
      }),
    );
  });
});

describe('Read Only（4.2 / 9）', () => {
  test('項目を読める', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await allow(
      getDoc(doc(readOnly, `lists/${LIST_ID}/items/${ITEM_ID}`)),
    );
  });

  test('容量は読める（メンバーなので）', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await allow(getDoc(doc(readOnly, `lists/${LIST_ID}/meta/stats`)));
  });

  test('項目を追加できない', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await deny(
      setDoc(doc(readOnly, `lists/${LIST_ID}/items/new-item`), {
        seq: 2,
        createdBy: UID.readOnly,
        status: 'active',
      }),
    );
  });

  test('コメントを書けない', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await deny(
      setDoc(
        doc(readOnly, `lists/${LIST_ID}/items/${ITEM_ID}/comments/new`),
        { body: 'コメント', createdBy: UID.readOnly, status: 'active' },
      ),
    );
  });

  test('自分から抜けられる（5.4）', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await allow(
      deleteDoc(doc(readOnly, `lists/${LIST_ID}/members/${UID.readOnly}`)),
    );
  });

  test('他人を除外できない', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await deny(
      deleteDoc(doc(readOnly, `lists/${LIST_ID}/members/${UID.superUser}`)),
    );
  });
});

describe('Super User（4.2 / 6.3）', () => {
  test('項目を追加できる', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await allow(
      setDoc(doc(superUser, `lists/${LIST_ID}/items/new-item`), {
        seq: 2,
        date: '2026-08-04',
        kind: 'url',
        url: 'https://example.com/x',
        createdBy: UID.superUser,
        status: 'active',
      }),
    );
  });

  test('登録者を他人になりすまして追加できない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      setDoc(doc(superUser, `lists/${LIST_ID}/items/new-item`), {
        seq: 2,
        createdBy: UID.listAdmin,
        status: 'active',
      }),
    );
  });

  test('自分の項目は編集できる', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await allow(
      updateDoc(doc(superUser, `lists/${LIST_ID}/items/${ITEM_ID}`), {
        title: '曲名を付けた',
      }),
    );
  });

  test('連番は変更できない（6.2：振り直しなし）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, `lists/${LIST_ID}/items/${ITEM_ID}`), {
        seq: 99,
      }),
    );
  });

  test('登録者を書き換えられない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, `lists/${LIST_ID}/items/${ITEM_ID}`), {
        createdBy: UID.readOnly,
      }),
    );
  });

  test('項目を物理削除できない（6.2：ソフト削除）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      deleteDoc(doc(superUser, `lists/${LIST_ID}/items/${ITEM_ID}`)),
    );
  });

  test('メンバーを除外できない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      deleteDoc(doc(superUser, `lists/${LIST_ID}/members/${UID.readOnly}`)),
    );
  });

  test('容量を書き換えられない（13.3）', async () => {
    // 上限判定をすり抜けるための改ざんを防ぐ。
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, `lists/${LIST_ID}/meta/stats`), {
        usedBytes: 0,
      }),
    );
  });

  test('連番カウンタを直接書き換えられない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, `lists/${LIST_ID}/meta/stats`), {
        nextSeq: 1,
      }),
    );
  });
});

describe('他人の項目（6.3）', () => {
  test('Super User は他人の項目を編集できない', async () => {
    // ITEM_ID は superUser が作成したものなので、
    // listAdmin ではない別の Super User を作って確認する。
    await mutateAsAdmin(env, async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `lists/${LIST_ID}/members/u-other-super`),
        { role: 'superUser', via: 'request' },
      );
    });
    const other = db(asUser(env, 'u-other-super'));
    await deny(
      updateDoc(doc(other, `lists/${LIST_ID}/items/${ITEM_ID}`), {
        title: '勝手に変更',
      }),
    );
  });

  test('リスト管理者は他人の項目を編集できる', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await allow(
      updateDoc(doc(listAdmin, `lists/${LIST_ID}/items/${ITEM_ID}`), {
        title: '管理者が修正',
      }),
    );
  });

  test('リスト管理者は他人のコメントを編集できる（9）', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await allow(
      updateDoc(
        doc(
          listAdmin,
          `lists/${LIST_ID}/items/${ITEM_ID}/comments/${COMMENT_ID}`,
        ),
        { status: 'deleted' },
      ),
    );
  });
});

describe('purgeAt（いつ消してよいか／6.3・2026-08-14）', () => {
  // **定期削除の唯一の判断材料**（functions/src/scheduled/purge.ts）。
  // 以前は update で自由に書けたため、**削除したはずのファイルを永久に
  // 残せた**（監査 第4回で「直さず記録」に回していた項目）。
  const itemPath = `lists/${LIST_ID}/items/${ITEM_ID}`;
  const days = (n) => new Date(Date.now() + n * 24 * 60 * 60 * 1000);

  test('削除するときは、猶予つきの時刻を入れられる', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await allow(
      updateDoc(doc(superUser, itemPath), {
        status: 'deleted',
        purgeAt: days(30),
      }),
    );
  });

  test('遠すぎる時刻は入れられない（実質「消えない」になる）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, itemPath), {
        status: 'deleted',
        purgeAt: days(3650),
      }),
    );
  });

  test('削除するのに purgeAt を入れないことはできない', async () => {
    // 入れずに消せると、**掃除の対象にならないまま残る**。
    const superUser = db(asUser(env, UID.superUser));
    await deny(updateDoc(doc(superUser, itemPath), { status: 'deleted' }));
  });

  test('ふつうの編集で purgeAt を伸ばせない', async () => {
    // 曲名を直すついでに猶予を伸ばす、ができないこと。
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, itemPath), {
        title: '曲名を付けた',
        purgeAt: days(300),
      }),
    );
  });

  test('復元するときは null に戻す', async () => {
    await mutateAsAdmin(env, async (ctx) => {
      await setDoc(doc(ctx.firestore(), itemPath), {
        seq: 1,
        date: '2026-08-04',
        kind: 'url',
        url: 'https://example.com/song',
        createdBy: UID.superUser,
        status: 'deleted',
        purgeAt: days(30),
      });
    });

    const listAdmin = db(asUser(env, UID.listAdmin));
    await allow(
      updateDoc(doc(listAdmin, itemPath), { status: 'active', purgeAt: null }),
    );
  });

  test('復元しながら purgeAt を残せない', async () => {
    // 残ると、**復元したのに掃除に消される**（active なのに purgeAt がある）。
    await mutateAsAdmin(env, async (ctx) => {
      await setDoc(doc(ctx.firestore(), itemPath), {
        seq: 1,
        date: '2026-08-04',
        kind: 'url',
        url: 'https://example.com/song',
        createdBy: UID.superUser,
        status: 'deleted',
        purgeAt: days(30),
      });
    });

    const listAdmin = db(asUser(env, UID.listAdmin));
    await deny(updateDoc(doc(listAdmin, itemPath), { status: 'active' }));
  });
});

describe('差し替えた旧ファイル（previousFiles／6.3・2026-08-14）', () => {
  // **Functions だけが書く場所**（callable/items.ts）。クライアントから
  // 書けると、他人のリストのパスを紛れ込ませてサーバーに消させられる
  // （監査 S1）。
  const itemPath = `lists/${LIST_ID}/items/${ITEM_ID}`;

  /** 差し替えを 1 度行ったあとの状態を作る。 */
  const withPreviousFiles = () =>
    mutateAsAdmin(env, async (ctx) => {
      await setDoc(doc(ctx.firestore(), itemPath), {
        seq: 1,
        date: '2026-08-04',
        kind: 'file',
        createdBy: UID.superUser,
        status: 'active',
        file: { storagePath: `lists/${LIST_ID}/items/${ITEM_ID}/new.mp3` },
        previousFiles: [
          { storagePath: `lists/${LIST_ID}/items/${ITEM_ID}/old.mp3` },
        ],
      });
    });

  test('クライアントからは書けない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, itemPath), {
        previousFiles: [{ storagePath: 'lists/OTHER/items/X/victim.mp3' }],
      }),
    );
  });

  test('消すこともできない', async () => {
    await withPreviousFiles();
    const superUser = db(asUser(env, UID.superUser));
    await deny(updateDoc(doc(superUser, itemPath), { previousFiles: null }));
  });

  test('差し替えたあとでも、曲名は編集できる', async () => {
    // **ここが本題。** 「無いか null」で塞ぐと、差し替えを 1 度でも
    // 行った項目は**それ以降まったく編集できなくなる**（update の
    // request.resource.data は書き換え後の全体なので、Functions が
    // 積んだ previousFiles が必ず入る）。
    await withPreviousFiles();
    const superUser = db(asUser(env, UID.superUser));
    await allow(
      updateDoc(doc(superUser, itemPath), { title: '曲名を直した' }),
    );
  });
});

describe('リスト名（5.1 / 13.3・2026-08-14）', () => {
  // **名前の一意性は listNames/{nameLower} の予約で守っている。**
  // name だけ書き換えると予約と食い違い、同じ名前のリストが 2 つできる。
  // 画面に変更の導線は無いので、ルールでも閉じる。
  test('リスト管理者でも、リスト名を書き換えられない', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await deny(
      updateDoc(doc(listAdmin, `lists/${LIST_ID}`), { name: '別の名前' }),
    );
  });

  test('サイト管理者でも、リスト名を書き換えられない', async () => {
    // 直すなら Functions 経由（予約の付け替えごと 1 つの処理で行う）。
    const siteAdmin = db(asSiteAdmin(env));
    await deny(
      updateDoc(doc(siteAdmin, `lists/${LIST_ID}`), { name: '別の名前' }),
    );
  });
});

describe('削除済みコメントの復元（9／監査 第4回）', () => {
  // items と同じ規則（restoreIsAllowed 相当）。以前は status に制約が無く、
  // リスト管理者が消したコメントを投稿者本人が active に書き戻して、
  // 削除を無かったことにできた。
  const commentPath = `lists/${LIST_ID}/items/${ITEM_ID}/comments/${COMMENT_ID}`;

  /** 前提づくり：コメントを削除済みの状態にする。 */
  const markDeleted = () =>
    mutateAsAdmin(env, async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), commentPath),
        {
          body: 'いいですね',
          parentId: null,
          path: [],
          depth: 0,
          createdBy: UID.superUser,
          status: 'deleted',
        },
      );
    });

  test('投稿者本人は deleted → active に戻せない', async () => {
    await markDeleted();
    const author = db(asUser(env, UID.superUser));
    await deny(updateDoc(doc(author, commentPath), { status: 'active' }));
  });

  test('リスト管理者は deleted → active に戻せる', async () => {
    await markDeleted();
    const listAdmin = db(asUser(env, UID.listAdmin));
    await allow(updateDoc(doc(listAdmin, commentPath), { status: 'active' }));
  });

  test('本人の削除（active → deleted）は今までどおりできる（9）', async () => {
    // 復元だけを縛ったことの確認。締めすぎると自分の発言を消せなくなる。
    const author = db(asUser(env, UID.superUser));
    await allow(updateDoc(doc(author, commentPath), { status: 'deleted' }));
  });
});

describe('リスト管理者（5.4 / 5.5）', () => {
  test('メンバーの役割を変更できる', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await allow(
      updateDoc(doc(listAdmin, `lists/${LIST_ID}/members/${UID.readOnly}`), {
        role: 'superUser',
      }),
    );
  });

  test('メンバーを除外できる', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await allow(
      deleteDoc(doc(listAdmin, `lists/${LIST_ID}/members/${UID.readOnly}`)),
    );
  });

  test('リストを削除できる', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await allow(deleteDoc(doc(listAdmin, `lists/${LIST_ID}`)));
  });

  test('集計フィールドは書き換えられない', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await deny(
      updateDoc(doc(listAdmin, `lists/${LIST_ID}`), { memberCount: 999 }),
    );
  });

  test('メンバーを直接追加できない（承認・招待は Functions 経由）', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await deny(
      setDoc(doc(listAdmin, `lists/${LIST_ID}/members/${UID.outsider}`), {
        role: 'superUser',
        via: 'request',
      }),
    );
  });

  test('他のリストは操作できない', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await deny(deleteDoc(doc(listAdmin, `lists/list-2`)));
  });
});

describe('サイト管理者（4.2 / 13.5）', () => {
  test('メンバー登録がなくても中身を読める', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await allow(
      getDoc(doc(siteAdmin, `lists/${LIST_ID}/items/${ITEM_ID}`)),
    );
  });

  test('どのリストの項目も編集できる', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await allow(
      updateDoc(doc(siteAdmin, `lists/${LIST_ID}/items/${ITEM_ID}`), {
        title: 'サイト管理者が修正',
      }),
    );
  });

  test('どのリストも削除できる（5.5）', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await allow(deleteDoc(doc(siteAdmin, `lists/list-2`)));
  });

  test('サイト設定を変更できる', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await allow(
      updateDoc(doc(siteAdmin, 'siteConfig/global'), {
        inviteExpiryHours: 48,
      }),
    );
  });

  test('siteAdminCount は書き換えられない（4.5）', async () => {
    // 最後の 1 人の判定を迂回されないようにする。
    const siteAdmin = db(asSiteAdmin(env));
    await deny(
      updateDoc(doc(siteAdmin, 'siteConfig/global'), { siteAdminCount: 5 }),
    );
  });

  // **回帰テスト（監査 第2回）。**
  //
  // 通知の宛先を集めるためのサイト管理者 uid 一覧と、定期削除の走査位置を
  // サーバー側で持つことにした。siteConfig/global は利用者も読めるため、
  // これらは読めない場所（siteConfig/internal）へ分けている。
  test('内部用のサイト設定はサイト管理者でも読めない', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await deny(getDoc(doc(siteAdmin, 'siteConfig/internal')));
  });

  test('内部用のサイト設定は誰も書けない', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await deny(
      setDoc(doc(siteAdmin, 'siteConfig/internal'), { siteAdminUids: ['x'] }),
    );
  });

  test('一般の利用者も内部用のサイト設定は読めない', async () => {
    const member = db(asUser(env, UID.readOnly));
    await deny(getDoc(doc(member, 'siteConfig/internal')));
  });

  test('サイト管理者でなければサイト設定を変更できない', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await deny(
      updateDoc(doc(listAdmin, 'siteConfig/global'), {
        inviteExpiryHours: 48,
      }),
    );
  });

  test('容量も直接は書き換えられない（Functions のみ）', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await deny(
      updateDoc(doc(siteAdmin, `lists/${LIST_ID}/meta/stats`), {
        usedBytes: 0,
      }),
    );
  });
});

describe('参加申請（5.2 / 5.2.1）', () => {
  test('本人は申請できる', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await allow(
      setDoc(doc(outsider, `lists/${LIST_ID}/joinRequests/${UID.outsider}`), {
        status: 'pending',
      }),
    );
  });

  test('他人の名前で申請できない', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await deny(
      setDoc(doc(outsider, `lists/${LIST_ID}/joinRequests/other-uid`), {
        status: 'pending',
      }),
    );
  });

  test('申請時に役割を指定できない（5.2）', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await deny(
      setDoc(doc(outsider, `lists/${LIST_ID}/joinRequests/${UID.outsider}`), {
        status: 'pending',
        assignedRole: 'listAdmin',
      }),
    );
  });

  test('自分で承認できない', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await deny(
      setDoc(doc(outsider, `lists/${LIST_ID}/joinRequests/${UID.outsider}`), {
        status: 'approved',
      }),
    );
  });

  test('却下後に再申請できる（5.2.1）', async () => {
    await mutateAsAdmin(env, async (ctx) => {
      await setDoc(
        doc(
          ctx.firestore(),
          `lists/${LIST_ID}/joinRequests/${UID.outsider}`,
        ),
        { status: 'rejected', decidedBy: UID.listAdmin },
      );
    });
    const outsider = db(asUser(env, UID.outsider));
    await allow(
      setDoc(doc(outsider, `lists/${LIST_ID}/joinRequests/${UID.outsider}`), {
        status: 'pending',
      }),
    );
  });

  test('リスト管理者は申請を読める', async () => {
    await mutateAsAdmin(env, async (ctx) => {
      await setDoc(
        doc(
          ctx.firestore(),
          `lists/${LIST_ID}/joinRequests/${UID.outsider}`,
        ),
        { status: 'pending' },
      );
    });
    const listAdmin = db(asUser(env, UID.listAdmin));
    await allow(
      getDoc(doc(listAdmin, `lists/${LIST_ID}/joinRequests/${UID.outsider}`)),
    );
  });
});

describe('リスト作成申請（5.1）', () => {
  test('誰でも申請できる', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await allow(
      setDoc(doc(outsider, 'listRequests/req-2'), {
        listName: 'あたらしいリスト',
        nameLower: 'あたらしいりすと',
        requestedBy: UID.outsider,
        status: 'pending',
      }),
    );
  });

  test('自分で承認済みにできない', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await deny(
      setDoc(doc(outsider, 'listRequests/req-2'), {
        listName: 'あたらしいリスト',
        requestedBy: UID.outsider,
        status: 'approved',
      }),
    );
  });

  test('申請者本人は自分の申請を読める（5.2.1）', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await allow(getDoc(doc(outsider, 'listRequests/req-1')));
  });

  test('他人の申請は読めない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(getDoc(doc(superUser, 'listRequests/req-1')));
  });

  test('サイト管理者は読める', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await allow(getDoc(doc(siteAdmin, 'listRequests/req-1')));
  });

  test('承認・却下はクライアントからできない（Functions のみ）', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await deny(
      updateDoc(doc(siteAdmin, 'listRequests/req-1'), { status: 'approved' }),
    );
  });
});

describe('リスト名の重複チェック（5.1 / 13.3）', () => {
  test('ID 直接指定なら存在を確認できる', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await allow(getDoc(doc(outsider, 'listNames/テストリスト')));
  });

  test('クライアントからは書けない', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await deny(
      setDoc(doc(outsider, 'listNames/よこどり'), { listId: 'x' }),
    );
  });
});

describe('ユーザー（3.4 / 3.5）', () => {
  test('表示名の解決のため、ログイン済みなら誰でも読める', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await allow(getDoc(doc(readOnly, `users/${UID.superUser}`)));
  });

  test('自分の表示名は変えられる', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await allow(
      updateDoc(doc(superUser, `users/${UID.superUser}`), {
        displayName: '新しい名前',
      }),
    );
  });

  test('他人の表示名は変えられない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, `users/${UID.readOnly}`), {
        displayName: 'いたずら',
      }),
    );
  });

  test('退会フラグは自分でも立てられない（Functions が処理する）', async () => {
    // 最後のサイト管理者の退会を止めるため、サーバー側で判定する（4.5）。
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, `users/${UID.superUser}`), {
        isWithdrawn: true,
      }),
    );
  });

  test('ユーザードキュメントは削除できない（3.5：投稿は残す）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(deleteDoc(doc(superUser, `users/${UID.superUser}`)));
  });
});

describe('通知（10 / 13.3）', () => {
  beforeEach(async () => {
    await mutateAsAdmin(env, async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${UID.superUser}/notifications/n1`),
        { type: 'itemAdded', listId: LIST_ID, isRead: false },
      );
    });
  });

  test('本人だけが読める', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await allow(
      getDoc(doc(superUser, `users/${UID.superUser}/notifications/n1`)),
    );

    const readOnly = db(asUser(env, UID.readOnly));
    await deny(
      getDoc(doc(readOnly, `users/${UID.superUser}/notifications/n1`)),
    );
  });

  test('既読にできる', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await allow(
      updateDoc(doc(superUser, `users/${UID.superUser}/notifications/n1`), {
        isRead: true,
      }),
    );
  });

  test('既読以外は書き換えられない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, `users/${UID.superUser}/notifications/n1`), {
        type: 'listRequested',
      }),
    );
  });

  test('自分で通知を作れない（Functions のみ）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      setDoc(doc(superUser, `users/${UID.superUser}/notifications/n2`), {
        type: 'itemAdded',
        isRead: false,
      }),
    );
  });
});

describe('定義していないパス', () => {
  test('読み書きとも拒否する', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await deny(getDoc(doc(siteAdmin, 'secrets/anything')));
    await deny(setDoc(doc(siteAdmin, 'secrets/anything'), { a: 1 }));
  });
});


// ---------------------------------------------------------------------------
// 2026-08-06 のゼロベース監査で見つけた穴。再発させないための回帰テスト。
// ---------------------------------------------------------------------------

describe('監査 S2：users を列挙できない', () => {
  test('一般利用者は users を一覧できない（全会員のメール収集を防ぐ）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(getDocs(collection(superUser, 'users')));
  });

  test('ID を指定した取得は許す（表示名の解決に要る）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await allow(getDoc(doc(superUser, `users/${UID.listAdmin}`)));
  });

  test('サイト管理者は一覧できる（11.1）', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await allow(getDocs(collection(siteAdmin, 'users')));
  });
});

describe('監査 S3：メール確認が済むまで何もできない（3.1）', () => {
  test('未確認では他人のユーザー情報を読めない', async () => {
    const unverified = db(asUnverified(env, UID.superUser));
    await deny(getDoc(doc(unverified, `users/${UID.listAdmin}`)));
  });

  test('未確認ではリストを読めない', async () => {
    const unverified = db(asUnverified(env, UID.superUser));
    await deny(getDoc(doc(unverified, `lists/${LIST_ID}`)));
  });

  test('未確認では項目を追加できない', async () => {
    const unverified = db(asUnverified(env, UID.superUser));
    await deny(
      setDoc(doc(unverified, `lists/${LIST_ID}/items/new-item`), {
        seq: 99,
        createdBy: UID.superUser,
        status: 'active',
      }),
    );
  });

  test('未確認でも自分のユーザードキュメントは作れる（登録直後のため）', async () => {
    const unverified = db(asUnverified(env, 'u-brand-new'));
    await allow(
      setDoc(doc(unverified, 'users/u-brand-new'), { displayName: '新規' }),
    );
  });

  // **回帰テスト（監査 第2回）。**
  //
  // 「作れる」だけを確かめていて、「読める」を一度も試していなかった。
  // 登録処理は「読んで、無ければ作る」順で動くため、読みが拒否されると
  // その先の確認メール送信に到達しない。メールが届かないまま
  // 「エラーが発生しました」とだけ出る状態が配信されていた。
  //
  // 作れるのに読めない、という食い違いを二度と作らないために、
  // 両方を並べて確かめる。
  test('未確認でも自分のユーザードキュメントは読める（登録処理は書く前に読む）', async () => {
    const unverified = db(asUnverified(env, 'u-brand-new'));
    await allow(getDoc(doc(unverified, 'users/u-brand-new')));
  });

  test('未確認では他人のユーザードキュメントは読めない', async () => {
    const unverified = db(asUnverified(env, 'u-brand-new'));
    await deny(getDoc(doc(unverified, `users/${UID.listAdmin}`)));
  });

  test('未確認では他人のユーザードキュメントを作れない', async () => {
    const unverified = db(asUnverified(env, 'u-brand-new'));
    await deny(
      setDoc(doc(unverified, 'users/u-someone-else'), { displayName: '偽' }),
    );
  });
});

describe('監査 S1：項目に他リストのファイルパスを書けない', () => {
  test('自分のリスト配下のパスなら保存できる', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await allow(
      setDoc(doc(superUser, `lists/${LIST_ID}/items/ok-item`), {
        seq: 50,
        createdBy: UID.superUser,
        status: 'active',
        file: { storagePath: `lists/${LIST_ID}/items/ok-item/song.mp3` },
      }),
    );
  });

  test('他リストのパスは拒否する（定期削除に消させないため）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      setDoc(doc(superUser, `lists/${LIST_ID}/items/evil-item`), {
        seq: 51,
        createdBy: UID.superUser,
        status: 'active',
        file: { storagePath: 'lists/list-2/items/victim/precious.mp3' },
      }),
    );
  });

  test('別の項目のパスも拒否する', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      setDoc(doc(superUser, `lists/${LIST_ID}/items/evil-item-2`), {
        seq: 52,
        createdBy: UID.superUser,
        status: 'active',
        file: { storagePath: `lists/${LIST_ID}/items/other-item/x.mp3` },
      }),
    );
  });

  test('previousFiles はクライアントから書けない（Functions のみ）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      setDoc(doc(superUser, `lists/${LIST_ID}/items/evil-item-3`), {
        seq: 53,
        createdBy: UID.superUser,
        status: 'active',
        previousFiles: [{ storagePath: 'lists/list-2/items/victim/old.mp3' }],
      }),
    );
  });

  test('status に任意の文字列を入れられない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      setDoc(doc(superUser, `lists/${LIST_ID}/items/evil-item-4`), {
        seq: 54,
        createdBy: UID.superUser,
        status: 'purged',
      }),
    );
  });
});


// ---------------------------------------------------------------------------
// ホームの参加リスト一覧（仕様書 14.2）
//
// **回帰テスト。** 以前は collectionGroup を documentId() で引いており、
// 「値は完全なドキュメントパスでなければならない」という制約に触れて
// 常に失敗していた。そのためリストを作ってもホームに出なかった。
// メンバーが持つ uid 項目で引く。
// ---------------------------------------------------------------------------

describe('自分の参加リストを引く', () => {
  test('メンバーは自分の members を collectionGroup で引ける', async () => {
    const c = db(asUser(env, UID.superUser));
    await allow(
      getDocs(
        query(
          collectionGroup(c, 'members'),
          where('uid', '==', UID.superUser),
        ),
      ),
    );
  });

  test('サイト管理者も自分の members を引ける（兼任できる）', async () => {
    const c = db(asSiteAdmin(env));
    await allow(
      getDocs(
        query(
          collectionGroup(c, 'members'),
          where('uid', '==', UID.siteAdmin),
        ),
      ),
    );
  });

  test('自分の参加申請も引ける', async () => {
    const c = db(asUser(env, UID.outsider));
    await allow(
      getDocs(
        query(
          collectionGroup(c, 'joinRequests'),
          where('uid', '==', UID.outsider),
        ),
      ),
    );
  });
});


// ---------------------------------------------------------------------------
// 項目の追加（仕様書 6.2）
//
// **回帰テスト。** 連番の採番はクライアント側のトランザクションで行うのに、
// meta/stats の書き込みを全面禁止していたため、項目の追加が一度も
// 成功しなかった。コメントには「連番はトランザクション」と書いてあった。
// ---------------------------------------------------------------------------

describe('連番の採番（6.2）', () => {
  test('Super User は nextSeq を 1 進められる', async () => {
    const c = db(asUser(env, UID.superUser));
    await allow(
      updateDoc(doc(c, `lists/${LIST_ID}/meta/stats`), { nextSeq: 3 }),
    );
  });

  test('Read Only は進められない', async () => {
    const c = db(asUser(env, UID.readOnly));
    await deny(
      updateDoc(doc(c, `lists/${LIST_ID}/meta/stats`), { nextSeq: 3 }),
    );
  });

  test('2 以上飛ばせない（欠番を作れない）', async () => {
    const c = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(c, `lists/${LIST_ID}/meta/stats`), { nextSeq: 4 }),
    );
  });

  test('戻せない（振り直せない）', async () => {
    const c = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(c, `lists/${LIST_ID}/meta/stats`), { nextSeq: 1 }),
    );
  });

  test('使用容量は書き換えられない（Functions のみ）', async () => {
    const c = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(c, `lists/${LIST_ID}/meta/stats`), { usedBytes: 0 }),
    );
  });

  test('nextSeq と一緒に容量も書くことはできない', async () => {
    const c = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(c, `lists/${LIST_ID}/meta/stats`), {
        nextSeq: 3,
        usedBytes: 0,
      }),
    );
  });

  test('日本語のファイル名でも項目を追加できる（13.7）', async () => {
    const c = db(asUser(env, UID.superUser));
    await allow(
      setDoc(doc(c, `lists/${LIST_ID}/items/jp-name`), {
        seq: 10,
        createdBy: UID.superUser,
        status: 'active',
        kind: 'file',
        file: {
          storagePath: `lists/${LIST_ID}/items/jp-name/顔写真3.png`,
          fileName: '顔写真3.png',
          sizeBytes: 924672,
          contentType: 'image/png',
        },
      }),
    );
  });
});

/**
 * 参加せずに見るだけの人（仕様書 3.3）
 *
 * 共有リンクを開いて「参加しない」を選んだ人。
 * **読めるだけ。** メンバーではないので、書き込みは一切できない。
 */
describe('参加せずに見るだけの人（3.3）', () => {
  test('曲の一覧を読める', async () => {
    const viewer = db(asUser(env, UID.viewer));
    await allow(
      getDoc(doc(viewer, `lists/${LIST_ID}/items/${ITEM_ID}`)),
    );
  });

  test('コメントを読める', async () => {
    const viewer = db(asUser(env, UID.viewer));
    await allow(
      getDoc(doc(viewer, `lists/${LIST_ID}/items/${ITEM_ID}/comments/c1`)),
    );
  });

  test('連番などの内部情報も読める（欠番の表示に要る）', async () => {
    const viewer = db(asUser(env, UID.viewer));
    await allow(getDoc(doc(viewer, `lists/${LIST_ID}/meta/stats`)));
  });

  // ---- ここから「できないこと」。読めるだけであることを確かめる ----

  test('曲を追加できない', async () => {
    const viewer = db(asUser(env, UID.viewer));
    await deny(
      setDoc(doc(viewer, `lists/${LIST_ID}/items/from-viewer`), {
        seq: 2,
        createdBy: UID.viewer,
        status: 'active',
      }),
    );
  });

  test('コメントを書けない', async () => {
    const viewer = db(asUser(env, UID.viewer));
    await deny(
      setDoc(doc(viewer, `lists/${LIST_ID}/items/${ITEM_ID}/comments/new`), {
        body: 'コメント',
        createdBy: UID.viewer,
        status: 'active',
      }),
    );
  });

  test('メンバーになれない（自分で members に入れない）', async () => {
    // **ここが破れると、閲覧のつもりの経路から書き込み権限を取れる。**
    const viewer = db(asUser(env, UID.viewer));
    await deny(
      setDoc(doc(viewer, `lists/${LIST_ID}/members/${UID.viewer}`), {
        uid: UID.viewer,
        role: 'superUser',
        via: 'invite',
      }),
    );
  });

  test('自分で閲覧権を作れない（Functions だけが書ける）', async () => {
    // **ここが破れると、リンクを持っていない人が中身を読めてしまう。**
    const outsider = db(asUser(env, UID.outsider));
    await deny(
      setDoc(doc(outsider, `lists/${LIST_ID}/viewers/${UID.outsider}`), {
        uid: UID.outsider,
      }),
    );
  });

  test('リンクを持たない人は、やはり読めない', async () => {
    // 閲覧を許したことで、部外者まで読めるようになっていないこと。
    const outsider = db(asUser(env, UID.outsider));
    await deny(
      getDoc(doc(outsider, `lists/${LIST_ID}/items/${ITEM_ID}`)),
    );
  });

  test('自分から閲覧をやめられる', async () => {
    const viewer = db(asUser(env, UID.viewer));
    await allow(
      deleteDoc(doc(viewer, `lists/${LIST_ID}/viewers/${UID.viewer}`)),
    );
  });

  test('誰が見ているかはリスト管理者に分かる', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await allow(
      getDoc(doc(listAdmin, `lists/${LIST_ID}/viewers/${UID.viewer}`)),
    );
  });

  test('ほかのメンバーには、閲覧者の一覧を見せない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      getDoc(doc(superUser, `lists/${LIST_ID}/viewers/${UID.viewer}`)),
    );
  });
});

/**
 * 共有リンクそのもの（仕様書 3.3 / 13.3）
 */
describe('共有リンク（3.3）', () => {
  test('ID を知っていれば読める', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await allow(getDoc(doc(outsider, 'shareLinks/link-1')));
  });

  test('一覧としては引けない（すべてのリンクを集められない）', async () => {
    const outsider = db(asUser(env, UID.outsider));
    await deny(getDocs(collection(outsider, 'shareLinks')));
  });

  test('クライアントからは作れない', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await deny(
      setDoc(doc(listAdmin, 'shareLinks/forged'), { listId: LIST_ID }),
    );
  });

  test('クライアントからは取り消せない（Functions 経由のみ）', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await deny(
      updateDoc(doc(listAdmin, 'shareLinks/link-1'), { revoked: true }),
    );
  });
});

// ---------------------------------------------------------------------------
// プレミアム（docs/PREMIUM-DESIGN.md）
//
// **「〜できない」だけを並べない。** 拒否の確認は、前提が全部壊れていても
// 緑になる（AUDIT-CHECKLIST 観点 4）。クーポンが 1 件も無ければ、
// ルールが全開でも「読めない」は通ってしまう。だから
//
//   1. 前提そのもの（クーポンが実在すること）を最初に確かめる
//   2. 「できる」側（表示名の更新・premium 無しの登録）を同じ実行に置く
//
// の 2 つを必ず添える。
// ---------------------------------------------------------------------------

describe('クーポン：クライアントからは読めない（PREMIUM-DESIGN 3.2 / 5 / 9 の 3）', () => {
  test('前提：クーポンと使用記録が実在する', async () => {
    // **これが無いと、以下の拒否はすべて空振りでも緑になる。**
    await mutateAsAdmin(env, async (ctx) => {
      const coupon = await getDoc(doc(ctx.firestore(), `coupons/${COUPON_ID}`));
      expect(coupon.exists()).toBe(true);
      expect(coupon.data().code).toBe('CAMPAIGN2026');

      const redemption = await getDoc(
        doc(
          ctx.firestore(),
          `coupons/${COUPON_ID}/redemptions/${UID.superUser}`,
        ),
      );
      expect(redemption.exists()).toBe(true);
    });
  });

  test('未ログインでは読めない', async () => {
    const anon = db(asAnonymous(env));
    await deny(getDoc(doc(anon, `coupons/${COUPON_ID}`)));
    await deny(getDocs(collection(anon, 'coupons')));
  });

  test('一般の利用者は読めない', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await deny(getDoc(doc(readOnly, `coupons/${COUPON_ID}`)));
    await deny(getDocs(collection(readOnly, 'coupons')));
  });

  test('リスト管理者も読めない', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await deny(getDoc(doc(listAdmin, `coupons/${COUPON_ID}`)));
    await deny(getDocs(collection(listAdmin, 'coupons')));
  });

  test('サイト管理者も読めない（管理画面は呼び出し可能関数を通す）', async () => {
    // **ここが要。** 一覧を許すと、管理画面の便利さと引き換えに
    // クライアントへコードの全量が降りてくる。管理画面は Functions 経由
    // （サーバーはルールを迂回する）にして、ルールは全面禁止のままにする。
    const siteAdmin = db(asSiteAdmin(env));
    await deny(getDoc(doc(siteAdmin, `coupons/${COUPON_ID}`)));
    await deny(getDocs(collection(siteAdmin, 'coupons')));
  });

  test('対：サイト管理者は他のものを読める（拒否が「全部落ちている」わけではない）', async () => {
    // クーポンの拒否が、認証の壊れや接続不良で起きていないことを示す。
    const siteAdmin = db(asSiteAdmin(env));
    await allow(getDocs(collection(siteAdmin, 'users')));
  });
});

describe('クーポン：クライアントからは書けない（PREMIUM-DESIGN 5）', () => {
  test('未ログインでは作れない', async () => {
    const anon = db(asAnonymous(env));
    await deny(
      setDoc(doc(anon, 'coupons/forged'), { code: 'FREE', months: 12 }),
    );
  });

  test('一般の利用者は作れない・書き換えられない・消せない', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await deny(
      setDoc(doc(readOnly, 'coupons/forged'), { code: 'FREE', months: 12 }),
    );
    await deny(
      updateDoc(doc(readOnly, `coupons/${COUPON_ID}`), { maxUses: 9999 }),
    );
    await deny(deleteDoc(doc(readOnly, `coupons/${COUPON_ID}`)));
  });

  test('リスト管理者も書けない', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await deny(
      setDoc(doc(listAdmin, 'coupons/forged'), { code: 'FREE', months: 12 }),
    );
    await deny(
      updateDoc(doc(listAdmin, `coupons/${COUPON_ID}`), { disabled: true }),
    );
  });

  test('サイト管理者も書けない（発行・停止は呼び出し可能関数を通す）', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await deny(
      setDoc(doc(siteAdmin, 'coupons/forged'), { code: 'FREE', months: 12 }),
    );
    await deny(
      updateDoc(doc(siteAdmin, `coupons/${COUPON_ID}`), { disabled: true }),
    );
    await deny(deleteDoc(doc(siteAdmin, `coupons/${COUPON_ID}`)));
  });

  test('使用回数を戻せない（戻せると上限が無意味になる）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, `coupons/${COUPON_ID}`), { usedCount: 0 }),
    );
  });
});

describe('クーポンの使用記録：redemptions も同じ（PREMIUM-DESIGN 3.2）', () => {
  const redemption = `coupons/${COUPON_ID}/redemptions/${UID.superUser}`;

  test('本人でも自分の使用記録を読めない', async () => {
    // 記録は追跡と問い合わせ回答のためのもので、クライアントには要らない。
    // 見えると「まだ空きのあるコード」の当たりが付く。
    const superUser = db(asUser(env, UID.superUser));
    await deny(getDoc(doc(superUser, redemption)));
  });

  test('サイト管理者も読めない・一覧できない', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await deny(getDoc(doc(siteAdmin, redemption)));
    await deny(
      getDocs(collection(siteAdmin, `coupons/${COUPON_ID}/redemptions`)),
    );
  });

  test('自分で使用記録を作れない（二重取りの判定はサーバーだけ）', async () => {
    // ここが書けると、引き換えを通さずに「使った」ことにできる。
    const readOnly = db(asUser(env, UID.readOnly));
    await deny(
      setDoc(
        doc(readOnly, `coupons/${COUPON_ID}/redemptions/${UID.readOnly}`),
        { redeemedAt: new Date() },
      ),
    );
  });

  test('自分の使用記録を消せない（消せると同じコードを二度使える）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(deleteDoc(doc(superUser, redemption)));
  });

  test('コレクショングループでも引けない', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await deny(getDocs(query(collectionGroup(siteAdmin, 'redemptions'))));
  });
});

describe('プレミアムの状態：読み（PREMIUM-DESIGN 3.1）', () => {
  test('本人は自分の premium / storage を読める（置き場所は private/state）', async () => {
    // **移した先で読めることを確かめる。** 「他人に見えない」だけを並べて
    // 本人まで読めなくなっていたら、プレミアムの表示が丸ごと壊れる。
    const superUser = db(asUser(env, UID.superUser));
    const snapshot = await allow(
      getDoc(doc(superUser, `users/${UID.superUser}/private/state`)),
    );
    expect(snapshot.data().premium).toBeTruthy();
    expect(snapshot.data().storage.quotaBytes).toBe(2147483648);
  });

  test('他人は premium を読めない（置き場所を分けたので閉じた）', async () => {
    // **以前はここに「見えてしまう」という事実を書き残していた。**
    // Firestore のルールに項目単位の読み取り制限は無く、users/{uid} は
    // 表示名の解決のため誰でも ID 指定で取得できるため、同じ取得で
    // premium も降りていた（BACKLOG「users ドキュメントが、ログイン済みなら
    // 誰にでも読める」）。**置き場所を users/{uid}/private/state へ
    // 分けたことで閉じた。** 詳しくは下の「私的な情報の置き場所」。
    const readOnly = db(asUser(env, UID.readOnly));
    await deny(getDoc(doc(readOnly, `users/${UID.superUser}/private/state`)));
  });

  test('移行前の古い premium が親に残っていれば、それは今も他人に見える', async () => {
    // **ルールでは隠せない。** 親の users/{uid} は表示名の解決のため
    // 誰でも読めるので、そこに残った残骸は一緒に降りてくる。
    // 消すのは移行の側の仕事で、ルールの仕事は「もう書けない」を保つこと
    // （下の「プレミアムの状態：書き」）。
    //
    // **ここに「他人は読めない」と書いてはいけない。**
    // 実際には見えるのに緑になり、嘘の安心だけが残る。
    const readOnly = db(asUser(env, UID.readOnly));
    const snapshot = await allow(
      getDoc(doc(readOnly, `users/${UID.superUser}`)),
    );
    expect(snapshot.data().premium).toBeTruthy();
  });

  test('未ログインでは、そもそも他人のユーザー情報を読めない', async () => {
    const anon = db(asAnonymous(env));
    await deny(getDoc(doc(anon, `users/${UID.superUser}`)));
  });
});

describe('プレミアムの状態：書き（PREMIUM-DESIGN 3.1 / 6 の 5）', () => {
  test('本人でも premium を書けない', async () => {
    // ここが開いていると、誰でも自分を無期限のプレミアムにできる。
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, `users/${UID.superUser}`), {
        premium: {
          until: new Date('2099-01-01T00:00:00Z'),
          updatedAt: new Date(),
        },
      }),
    );
  });

  test('本人でも premium の一部（until だけ）を伸ばせない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, `users/${UID.superUser}`), {
        'premium.until': new Date('2099-01-01T00:00:00Z'),
      }),
    );
  });

  test('本人でも storage を書けない（上限も使用量も）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, `users/${UID.superUser}`), {
        storage: { usedBytes: 0, quotaBytes: 10737418240 },
      }),
    );
    await deny(
      updateDoc(doc(superUser, `users/${UID.superUser}`), {
        'storage.quotaBytes': 10737418240,
      }),
    );
  });

  test('他人の premium はもちろん書けない', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await deny(
      updateDoc(doc(readOnly, `users/${UID.superUser}`), {
        premium: {
          until: new Date('2099-01-01T00:00:00Z'),
          updatedAt: new Date(),
        },
      }),
    );
  });

  test('サイト管理者も、クライアントからは premium を書けない（管理画面は関数経由）', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await deny(
      updateDoc(doc(siteAdmin, `users/${UID.superUser}`), {
        premium: {
          until: new Date('2099-01-01T00:00:00Z'),
          updatedAt: new Date(),
        },
      }),
    );
  });

  test('表示名に混ぜても通らない（許可された項目と一緒なら通る、になっていない）', async () => {
    // **1 回の更新でまとめて書く**のが、いちばん素直な抜け道。
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, `users/${UID.superUser}`), {
        displayName: '新しい名前',
        premium: {
          until: new Date('2099-01-01T00:00:00Z'),
          updatedAt: new Date(),
        },
      }),
    );
  });

  test('対：表示名だけの更新は引き続きできる（塞ぎすぎていない）', async () => {
    // 上の拒否が「users の更新が丸ごと壊れている」ために起きていないことを、
    // 同じ実行の中で示す（AUDIT-CHECKLIST 観点 4）。
    const superUser = db(asUser(env, UID.superUser));
    await allow(
      updateDoc(doc(superUser, `users/${UID.superUser}`), {
        displayName: '新しい名前',
      }),
    );
  });

  test('登録の 1 回目に premium を仕込めない', async () => {
    // **更新だけを塞いでも足りない。** ドキュメントがまだ無い人は
    // create で書けてしまう。
    const newcomer = 'u-newcomer';
    const context = db(asUser(env, newcomer));
    await deny(
      setDoc(doc(context, `users/${newcomer}`), {
        displayName: '新入り',
        isWithdrawn: false,
        premium: {
          until: new Date('2099-01-01T00:00:00Z'),
          updatedAt: new Date(),
        },
      }),
    );
  });

  test('登録の 1 回目に storage を仕込めない', async () => {
    const newcomer = 'u-newcomer-2';
    const context = db(asUser(env, newcomer));
    await deny(
      setDoc(doc(context, `users/${newcomer}`), {
        displayName: '新入り',
        storage: { usedBytes: 0, quotaBytes: 10737418240 },
      }),
    );
  });

  test('対：premium を含まなければ、登録は引き続きできる', async () => {
    // create を塞ぎすぎると、新規登録そのものが通らなくなる（3.1 の経緯）。
    const newcomer = 'u-newcomer-3';
    const context = db(asUser(env, newcomer));
    await allow(
      setDoc(doc(context, `users/${newcomer}`), {
        displayName: '新入り',
        isWithdrawn: false,
      }),
    );
  });

  test('対：退会フラグの扱いは変えていない（引き続き本人でも立てられない）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, `users/${UID.superUser}`), {
        isWithdrawn: true,
      }),
    );
  });

  test('対：ユーザードキュメントは引き続き削除できない（3.5）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(deleteDoc(doc(superUser, `users/${UID.superUser}`)));
  });
});

// ---------------------------------------------------------------------------
// 私的な情報の置き場所（users/{uid}/private/state）
//
// BACKLOG「users ドキュメントが、ログイン済みなら誰にでも読める」への対処。
// 親の users/{uid} は表示名の解決のため ID 指定で誰でも読めるので、
// **メールアドレス・プレミアムの期限・容量の使用量を子へ分けた。**
// Firestore のルールに項目単位の読み取り制限は無いため、分ける以外に
// 手は無い。
//
// **「できない」だけを並べない。** 読めなくしすぎれば、プレミアムの表示も
// 登録も壊れる。対になる「できる」を同じ実行の中に置く
// （docs/AUDIT-CHECKLIST.md 観点 4）。
// ---------------------------------------------------------------------------

const PRIVATE = (uid) => `users/${uid}/private/state`;

describe('私的な情報の置き場所：読み（users/{uid}/private/state）', () => {
  test('本人は読める', async () => {
    const superUser = db(asUser(env, UID.superUser));
    const snapshot = await allow(getDoc(doc(superUser, PRIVATE(UID.superUser))));
    expect(snapshot.data().email).toBe('super-user@example.com');
  });

  test('メール確認前でも本人は読める（登録処理は書く前に読む）', async () => {
    // **親の users を isSignedIn で読めるようにしてあるのと同じ理由。**
    // 登録処理は「読んで、無ければ作る」順で動く。ここを isVerified に
    // すると、登録直後の読みが拒否されて例外で止まり、その先の確認メールの
    // 送信に到達しない。メールが届かないまま「エラーが発生しました」と
    // だけ出る状態が、以前 1 度配信されている（監査 第2回）。
    const unverified = db(asUnverified(env, UID.superUser));
    await allow(getDoc(doc(unverified, PRIVATE(UID.superUser))));
  });

  test('他人（一般利用者）は読めない', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await deny(getDoc(doc(readOnly, PRIVATE(UID.superUser))));
  });

  test('リスト管理者も読めない（同じリストの仲間でも）', async () => {
    const listAdmin = db(asUser(env, UID.listAdmin));
    await deny(getDoc(doc(listAdmin, PRIVATE(UID.superUser))));
  });

  test('サイト管理者も読めない（管理画面はサーバー経由で取る）', async () => {
    // **ここだけは他と扱いが違う。** users の一覧や lists の全件は
    // サイト管理者に開いているが、この中身は開けない。管理画面が要る
    // 情報は listSiteUsers などの呼び出し可能関数から取る——Admin SDK は
    // ルールを迂回するので、それで足りる。足りるのにここを開けると、
    // 管理者の端末が乗っ取られたときに全員のメールアドレスが降りてくる
    // 経路を、わざわざ 1 本増やすことになる。
    const siteAdmin = db(asSiteAdmin(env));
    await deny(getDoc(doc(siteAdmin, PRIVATE(UID.superUser))));
  });

  test('未ログインは読めない', async () => {
    const anon = db(asAnonymous(env));
    await deny(getDoc(doc(anon, PRIVATE(UID.superUser))));
  });

  test('コレクショングループでも引けない（private を横断で読めない）', async () => {
    // **ID 指定を閉じても、横断の取得が開いていれば同じこと。**
    // 再帰ワイルドカードの match を書いていないので閉じている。
    // 誰かが members のような match を足したら、ここが赤くなる。
    const siteAdmin = db(asSiteAdmin(env));
    await deny(getDocs(query(collectionGroup(siteAdmin, 'private'))));

    const superUser = db(asUser(env, UID.superUser));
    await deny(getDocs(query(collectionGroup(superUser, 'private'))));
  });

  test('他人の private を一覧としても引けない', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await deny(getDocs(collection(readOnly, `users/${UID.superUser}/private`)));
  });
});

describe('私的な情報の置き場所：書き（自分の設定は書ける／サーバーのものは書けない）', () => {
  // **中身は「本人のもの」と「サーバーのもの」が混ざっている。**
  //
  //   本人が書いてよい : locale, notificationSettings
  //   サーバーだけ     : premium, storage
  //
  // 場所を分けたのは他人に見せないためであって、本人から取り上げるためでは
  // ない。**「全部書けない」にすると設定画面の保存が権限拒否になる。**
  // 拒否の確認と、対になる「保存できる」を同じ実行の中に置く。

  test('本人は locale を変えられる', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await allow(
      updateDoc(doc(superUser, PRIVATE(UID.superUser)), { locale: 'en' }),
    );
  });

  test('本人は notificationSettings を変えられる', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await allow(
      updateDoc(doc(superUser, PRIVATE(UID.superUser)), {
        notificationSettings: { itemAdded: false, commentAdded: false },
      }),
    );
  });

  test('設定画面の保存の形（set の merge）でも通る', async () => {
    // **画面側は最初の保存を set(merge: true) で行う。**
    // 既にある行では update として評価される。updateDoc だけを試して
    // 安心すると、画面が使う書き方を一度も確かめないままになる。
    const superUser = db(asUser(env, UID.superUser));
    await allow(
      setDoc(
        doc(superUser, PRIVATE(UID.superUser)),
        { locale: 'en', notificationSettings: { itemAdded: false } },
        { merge: true },
      ),
    );
  });

  test('まだドキュメントが無い人でも、自分の private/state を作れる', async () => {
    // **set(merge: true) は、行が無ければ create として評価される。**
    // update だけを許していると、ここで初回の保存が落ちる。
    const newcomer = 'u-newcomer-private-state';
    const context = db(asUser(env, newcomer));
    await allow(
      setDoc(
        doc(context, PRIVATE(newcomer)),
        { locale: 'ja', notificationSettings: { itemAdded: true } },
        { merge: true },
      ),
    );
  });

  test('メール確認前でも、自分の設定は保存できる（読みと揃えている）', async () => {
    const unverified = db(asUnverified(env, UID.superUser));
    await allow(
      updateDoc(doc(unverified, PRIVATE(UID.superUser)), { locale: 'en' }),
    );
  });

  test('本人でも premium は書けない', async () => {
    // **ここが開くと、誰でも自分を無期限のプレミアムにできる。**
    // 親で塞いだものが子で開いたら、場所を分けた意味が消える。
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, PRIVATE(UID.superUser)), {
        premium: {
          until: new Date('2099-01-01T00:00:00Z'),
          updatedAt: new Date(),
        },
      }),
    );
    await deny(
      updateDoc(doc(superUser, PRIVATE(UID.superUser)), {
        'premium.until': new Date('2099-01-01T00:00:00Z'),
      }),
    );
  });

  test('本人でも storage は書けない（上限も使用量も）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, PRIVATE(UID.superUser)), {
        storage: { usedBytes: 0, quotaBytes: 10737418240 },
      }),
    );
    await deny(
      updateDoc(doc(superUser, PRIVATE(UID.superUser)), {
        'storage.quotaBytes': 10737418240,
      }),
    );
  });

  test('書いてよい項目に混ぜても通らない（1 回の更新にまとめる形）', async () => {
    // **いちばん素直な抜け道。** 許された項目と一緒なら通る、に
    // なっていないことを確かめる（親の users/{uid} で「表示名に混ぜても
    // 通らない」を確かめているのと同じ形）。
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, PRIVATE(UID.superUser)), {
        locale: 'en',
        premium: {
          until: new Date('2099-01-01T00:00:00Z'),
          updatedAt: new Date(),
        },
      }),
    );
    await deny(
      setDoc(
        doc(superUser, PRIVATE(UID.superUser)),
        { locale: 'en', storage: { usedBytes: 0, quotaBytes: 10737418240 } },
        { merge: true },
      ),
    );
  });

  test('最初の 1 回（create）にも premium / storage を仕込めない', async () => {
    // **update だけ塞いでも足りない。** 行がまだ無い人は create で
    // 書けてしまう（親の users/{uid} と同じ経緯）。
    const newcomer = 'u-newcomer-private-premium';
    const context = db(asUser(env, newcomer));
    await deny(
      setDoc(doc(context, PRIVATE(newcomer)), {
        locale: 'ja',
        premium: { until: new Date('2099-01-01T00:00:00Z') },
      }),
    );

    const other = 'u-newcomer-private-storage';
    const otherContext = db(asUser(env, other));
    await deny(
      setDoc(doc(otherContext, PRIVATE(other)), {
        locale: 'ja',
        storage: { usedBytes: 0, quotaBytes: 10737418240 },
      }),
    );
  });

  test('丸ごとの上書きで premium を消せない（消す形の書き換え）', async () => {
    // merge を付けない set は、既にある premium / storage を落とす。
    // **項目が変わることに変わりはない**ので、ここも塞がっている。
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      setDoc(doc(superUser, PRIVATE(UID.superUser)), {
        email: 'super-user@example.com',
        locale: 'en',
      }),
    );
  });

  test('本人でも削除できない（消す形で premium を捨てられない）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(deleteDoc(doc(superUser, PRIVATE(UID.superUser))));
  });

  test('別の docId は生やせない（この下は state だけ）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      setDoc(doc(superUser, `users/${UID.superUser}/private/injected`), {
        locale: 'ja',
      }),
    );
  });

  test('サイト管理者も書けない（管理画面は関数経由）', async () => {
    const siteAdmin = db(asSiteAdmin(env));
    await deny(
      updateDoc(doc(siteAdmin, PRIVATE(UID.superUser)), {
        'premium.until': new Date('2099-01-01T00:00:00Z'),
      }),
    );
    // **書いてよいはずの項目でも、他人のぶんは書けない。**
    await deny(
      updateDoc(doc(siteAdmin, PRIVATE(UID.superUser)), { locale: 'en' }),
    );
  });

  test('他人の private には書けない（自分が書ける項目でも）', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    await deny(
      updateDoc(doc(readOnly, PRIVATE(UID.superUser)), { locale: 'en' }),
    );
    await deny(
      updateDoc(doc(readOnly, PRIVATE(UID.superUser)), {
        email: 'attacker@example.com',
      }),
    );
  });

  test('他人の private は、まだ無い状態でも作れない', async () => {
    // 行が無い相手なら create として評価される。uid の突き合わせは
    // create 側にも要る。
    const readOnly = db(asUser(env, UID.readOnly));
    await deny(
      setDoc(doc(readOnly, PRIVATE(UID.outsider)), { locale: 'en' }),
    );
  });
});

describe('私的な情報の置き場所：対になる「できる」（塞ぎすぎていない）', () => {
  // **拒否だけを並べると、users が丸ごと壊れていても緑になる。**
  // 表示名まわりが今までどおり動くことを、同じ実行の中で示す。

  test('対：表示名の解決（users/{uid} の ID 指定の取得）は引き続きできる', async () => {
    const readOnly = db(asUser(env, UID.readOnly));
    const snapshot = await allow(
      getDoc(doc(readOnly, `users/${UID.superUser}`)),
    );
    expect(snapshot.data().displayName).toBe('投稿者');
  });

  test('対：表示名の更新は引き続きできる', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await allow(
      updateDoc(doc(superUser, `users/${UID.superUser}`), {
        displayName: '新しい名前',
      }),
    );
  });

  test('対：users の一覧は引き続き禁じられている（監査 S2）', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(getDocs(collection(superUser, 'users')));
  });

  test('対：登録の create は引き続きできる（private が無くても通る）', async () => {
    // 新規登録は親の users を作るところから始まる。private は Functions が
    // 作るので、クライアントは触らない。
    const newcomer = 'u-newcomer-private';
    const context = db(asUser(env, newcomer));
    await allow(
      setDoc(doc(context, `users/${newcomer}`), {
        displayName: '新入り',
        isWithdrawn: false,
      }),
    );
  });

  test('対：退会フラグは引き続き本人でも立てられない', async () => {
    const superUser = db(asUser(env, UID.superUser));
    await deny(
      updateDoc(doc(superUser, `users/${UID.superUser}`), {
        isWithdrawn: true,
      }),
    );
  });

  test('対：自分の通知は引き続き読める（private の禁止を巻き込んでいない）', async () => {
    await mutateAsAdmin(env, async (ctx) => {
      await setDoc(
        doc(ctx.firestore(), `users/${UID.superUser}/notifications/n-private`),
        { type: 'itemAdded', listId: LIST_ID, isRead: false },
      );
    });
    const superUser = db(asUser(env, UID.superUser));
    await allow(
      getDoc(doc(superUser, `users/${UID.superUser}/notifications/n-private`)),
    );
  });
});
