/**
 * サイト管理者によるユーザーの追加・無効化・削除（仕様書 11.1）
 *
 * 判断そのものは `domain/user_admin.ts` にある（通信なしでテストできる）。
 * ここは、その判断に従って Auth と Firestore を実際に書き換える場所。
 *
 * ---
 *
 * ## 無効と削除
 *
 * **無効は戻せる。削除は戻せない。** 迷ったら無効にする。
 *
 * | | 無効 | 削除 |
 * | --- | --- | --- |
 * | Auth のアカウント | 残す（`disabled`） | 消す |
 * | `users` ドキュメント | 残す | 消す |
 * | 参加中のリスト | 外す | 外す |
 * | 登録した曲・音源ファイル | 残す | **消す** |
 * | 書いたコメント | 残す | **残す**（「退会したユーザー」表示） |
 *
 * コメントを残すのは依頼者の指示（2026-08-09）。**会話は文脈で、
 * 1 つ抜けると前後が読めなくなる。** 表示名は `users` が消えることで
 * 自動的に「退会したユーザー」になる（仕様書 3.5）。
 */
import { getAuth } from 'firebase-admin/auth';
import { getStorage } from 'firebase-admin/storage';
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import * as logger from 'firebase-functions/logger';
import { onCall } from 'firebase-functions/v2/https';

import { REGION, paths } from '../config';
import {
  rejectNewUser,
  rejectUserAdminAction,
  type UserAdminAction,
} from '../domain/user_admin';
import {
  countSiteAdmins,
  requireSiteAdmin,
  requireString,
  syncSiteAdminCount,
} from './access';
import { fail } from '../errors';

/**
 * 対象の状態を集め、その操作を行ってよいかを確かめる。
 *
 * **自分自身は対象にできない。** 締め出しと、サイト管理者 0 人を防ぐ。
 */
async function ensureAllowed(
  action: UserAdminAction,
  actorUid: string,
  targetUid: string
): Promise<{ isSiteAdmin: boolean }> {
  const auth = getAuth();

  const target = await auth.getUser(targetUid).catch(() => null);
  if (target === null) throw fail('not-found', 'userNotFound');

  const isSiteAdmin = target.customClaims?.siteAdmin === true;

  // **人数を数えるのは、相手がサイト管理者のときだけ。** 全ユーザーの
  // 走査になるため、要らないときに呼ぶと無駄に重い。
  const siteAdminCount = isSiteAdmin ? await countSiteAdmins() : 0;

  const rejection = rejectUserAdminAction({
    action,
    actorUid,
    target: { uid: targetUid, isSiteAdmin },
    siteAdminCount,
  });
  if (rejection !== null) {
    throw fail('failed-precondition', rejection);
  }

  return { isSiteAdmin };
}

/**
 * 参加中のリストから外す（仕様書 5.4）。
 *
 * 無効化・削除だけでなく、本人の退会（site_admin.ts の withdrawAccount）
 * もここを通る。**外す対象と失敗の扱いを 1 か所に集める**ため
 * （退会だけ viewers を外し忘れていた／監査 第4回）。
 *
 * **`where('__name__', '==', uid)` は成立しない。** collectionGroup を
 * documentId() で引く場合、値は完全なドキュメントパスでなければならず、
 * 素の uid は「セグメント数が奇数」として拒否される（監査 S14）。
 * メンバーのドキュメントが持つ `uid` の項目で引く。
 *
 * **引けなかったら、そこで止める。** 握り潰して先へ進むと、
 * members に残ったままアカウントだけ消える。
 */
export async function leaveAllLists(uid: string): Promise<void> {
  const db = getFirestore();

  const memberships = await db
    .collectionGroup('members')
    .where('uid', '==', uid)
    .get()
    .then((snapshot) => snapshot.docs)
    .catch((error) => {
      logger.error('参加中のリストを引けませんでした', {
        uid,
        error: error instanceof Error ? error.message : String(error),
      });
      return null;
    });

  if (memberships === null) throw fail('internal', 'listNotFound');

  await Promise.all(
    memberships.map((doc) => doc.ref.delete().catch(() => undefined))
  );

  // 参加せずに見ているリストからも外す（仕様書 3.3）。
  //
  // **こちらも、引けなかったらそこで止める。** ここだけ握り潰して
  // 空の一覧にすると、失敗しても黙って空振りし、viewers に残ったまま
  // アカウントだけが消える——members で塞いだ穴と同じ形（監査 第4回）。
  const viewers = await db
    .collectionGroup('viewers')
    .where('uid', '==', uid)
    .get()
    .then((snapshot) => snapshot.docs)
    .catch((error) => {
      logger.error('閲覧中のリストを引けませんでした', {
        uid,
        error: error instanceof Error ? error.message : String(error),
      });
      return null;
    });

  if (viewers === null) throw fail('internal', 'listNotFound');

  await Promise.all(
    viewers.map((doc) => doc.ref.delete().catch(() => undefined))
  );
}

/**
 * ユーザーを追加する（仕様書 11.1）。
 *
 * **パスワードはサイト管理者が決める**（2026-08-09 の依頼者指示）。
 * 決めた本人が知っている状態になるので、**渡したあとで本人に変えて
 * もらうこと**を画面で案内している。
 *
 * **メール確認は済んだ扱いにする。** サイト管理者が宛先を承知のうえで
 * 作るためで、こうしないと本人は確認メールを待つ画面から先へ進めない
 * （仕様書 3.1）。自己登録の経路では、従来どおり確認を求める。
 */
export const createSiteUser = onCall({ region: REGION }, async (request) => {
  requireSiteAdmin(request);

  const email = requireString(request.data, 'email', { maxLength: 254 }).trim();
  const password = requireString(request.data, 'password', { maxLength: 128 });
  const displayName = requireString(request.data, 'displayName', { maxLength: 50 }).trim();

  const rejection = rejectNewUser({ email, password });
  if (rejection !== null) throw fail('invalid-argument', rejection);

  const auth = getAuth();

  const created = await auth
    .createUser({ email, password, displayName, emailVerified: true })
    .catch((error: unknown) => {
      const code =
        typeof error === 'object' && error !== null && 'code' in error
          ? String((error as { code: unknown }).code)
          : '';
      if (code === 'auth/email-already-exists') {
        throw fail('already-exists', 'emailAlreadyInUse');
      }
      if (code === 'auth/invalid-email') {
        throw fail('invalid-argument', 'emailInvalid');
      }
      if (code === 'auth/invalid-password') {
        throw fail('invalid-argument', 'passwordTooShort');
      }
      throw error;
    });

  // 表示名は users ドキュメントが正（仕様書 3.4）。
  // **表示言語は決め打ちにしない。** 作った管理者の言語で固定すると、
  // 英語の利用者に日本語の画面が出る（監査 第 3 回）。
  const db = getFirestore();
  await db
    .doc(paths.user(created.uid))
    .set(
      {
        displayName,
        isWithdrawn: false,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

  // **メールアドレスは本人だけの場所へ（2026-08-11）。**
  // `users/{uid}` はログイン済みなら誰でも ID 指定で読めるので、
  // ここに置いていた頃は**全会員のメールアドレスが他の利用者に見えていた**。
  // サイト管理者には `listSiteUsers` が Auth から取って返す。
  await db
    .doc(paths.userPrivate(created.uid))
    .set({ email, updatedAt: FieldValue.serverTimestamp() }, { merge: true });

  return { ok: true, uid: created.uid };
});

/**
 * ユーザーを無効にする（仕様書 11.1）。
 *
 * **ログインだけできなくする。データは消さない。**
 * 参加中のリストからは外す（退会と同じ／2026-08-09 の依頼者指示）。
 * 曲・音源ファイル・コメントはそのまま残る。
 */
export const disableSiteUser = onCall({ region: REGION }, async (request) => {
  const actorUid = requireSiteAdmin(request);
  const uid = requireString(request.data, 'uid', { maxLength: 128 });

  const { isSiteAdmin } = await ensureAllowed('disable', actorUid, uid);

  await leaveAllLists(uid);

  // **先に Firestore、最後に Auth。** 逆にすると、途中で失敗したときに
  // 「ログインはできないが、どのリストにも残っている」状態が生まれる。
  await getFirestore()
    .doc(paths.user(uid))
    .set(
      {
        isWithdrawn: true,
        withdrawnAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

  await getAuth().updateUser(uid, { disabled: true });

  // 無効な管理者は「最後の 1 人」の人数に入れない（access.ts の
  // scanSiteAdmins）。siteConfig の控え（人数と通知の宛先）も
  // その場で実態に合わせる（監査 第4回）。
  if (isSiteAdmin) await syncSiteAdminCount();

  return { ok: true };
});

/**
 * 無効にしたユーザーを、また使えるようにする（仕様書 11.1）。
 *
 * **参加していたリストには戻らない。** 外した記録しか残っていないため、
 * どこに戻すべきかを機械的に決められない。あらためて招待する。
 * その旨は画面に書いてある。
 */
export const enableSiteUser = onCall({ region: REGION }, async (request) => {
  const actorUid = requireSiteAdmin(request);
  const uid = requireString(request.data, 'uid', { maxLength: 128 });

  const { isSiteAdmin } = await ensureAllowed('enable', actorUid, uid);

  await getAuth().updateUser(uid, { disabled: false });

  await getFirestore()
    .doc(paths.user(uid))
    .set(
      {
        isWithdrawn: false,
        withdrawnAt: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

  // 有効へ戻った管理者は、また人数に入る。控えも合わせ直す（監査 第4回）。
  if (isSiteAdmin) await syncSiteAdminCount();

  return { ok: true };
});

/**
 * ユーザーを削除する（仕様書 11.1）。**戻せない。**
 *
 * 消すもの：Auth のアカウント、`users` ドキュメント、参加情報、
 * **その人が登録した曲と音源ファイル**。
 *
 * 残すもの：**書いたコメント**（2026-08-09 の依頼者指示）。
 * 会話は文脈なので、1 つ抜けると前後が読めなくなる。
 * `users` が消えることで表示名は「退会したユーザー」になる（仕様書 3.5）。
 *
 * **曲は本当に消す。** ソフト削除（`status: 'deleted'`）ではない。
 * 猶予期間つきの削除は「あとで戻せるように」する仕組みで、
 * 物理削除の求めに対しては答えになっていない。
 */
export const deleteSiteUser = onCall({ region: REGION }, async (request) => {
  const actorUid = requireSiteAdmin(request);
  const uid = requireString(request.data, 'uid', { maxLength: 128 });

  const { isSiteAdmin } = await ensureAllowed('delete', actorUid, uid);

  const db = getFirestore();

  await leaveAllLists(uid);

  // --- その人が登録した曲と、音源ファイル ---
  //
  // **ファイルを先に消し、そのあとで項目を消す。** 逆にすると、
  // 項目が消えた時点で storagePath を辿れなくなり、ファイルだけが
  // 残って容量を食い続ける（孤児ファイルの掃除に任せる手もあるが、
  // 「消してほしい」と言われた操作を先送りにしない）。
  const items = await db
    .collectionGroup('items')
    .where('createdBy', '==', uid)
    .get()
    .then((snapshot) => snapshot.docs)
    .catch((error) => {
      logger.error('登録した曲を引けませんでした', {
        uid,
        error: error instanceof Error ? error.message : String(error),
      });
      return null;
    });

  if (items === null) throw fail('internal', 'itemNotFound');

  const bucket = getStorage().bucket();

  for (const doc of items) {
    const data = doc.data();
    const paths_: string[] = [];

    if (typeof data.file?.storagePath === 'string') {
      paths_.push(data.file.storagePath);
    }
    if (Array.isArray(data.previousFiles)) {
      for (const old of data.previousFiles) {
        if (typeof old?.storagePath === 'string') paths_.push(old.storagePath);
      }
    }

    await Promise.all(
      paths_.map((path) =>
        bucket
          .file(path)
          .delete()
          .catch((error: unknown) => {
            // 既に無いファイルは、消えているのだから困らない。
            // それ以外は記録に残す（容量が合わなくなる手がかりになる）。
            logger.warn('音源ファイルを消せませんでした', {
              uid,
              path,
              error: error instanceof Error ? error.message : String(error),
            });
          })
      )
    );

    await doc.ref.delete().catch(() => undefined);
  }

  // --- 本体 ---
  //
  // **コメントには触れない。** 残す判断（上の説明）。
  //
  // **本人だけの控え（private/state）も消す。** サブコレクションは
  // 親を消しても残る——Firestore の削除は親 1 件だけで、下に付いた
  // ドキュメントには届かない。**消したはずの人のメールアドレス・
  // プレミアム・容量が、親の無い孤児として残り続ける。**
  // 消す順は private が先。親だけ消えて下が残る状態を作らない。
  // **通知も消す**（2026-08-15。監査 第4回で「直さず記録」に回した項目）。
  //
  // これも親の下にぶら下がったコレクションなので、users/{uid} を消しても
  // 残る。**到達できない場所に、誰宛てか分からない通知が積まれたまま**に
  // なり、消す手段も無くなる。
  await deleteCollection(db.collection(paths.userNotifications(uid)));

  await db.doc(paths.userPrivate(uid)).delete().catch(() => undefined);
  await db.doc(paths.user(uid)).delete().catch(() => undefined);

  await getAuth().deleteUser(uid);

  // 消したのがサイト管理者なら、siteConfig の控え（人数と uid の一覧）も
  // 実態に合わせ直す。残したままだと、消えた uid が通知の宛先に混ざり
  // 続け、画面の人数も減らない（監査 第4回）。
  if (isSiteAdmin) await syncSiteAdminCount();

  return { ok: true, deletedItems: items.length };
});


/**
 * コレクションの中身をまとめて消す。
 *
 * **一度に全部読まない。** 件数が多い人の通知を一括で読むと、
 * 実行時間の上限で毎回落ちるようになる（監査 S8 と同じ形）。
 * 500 件ずつ、無くなるまで繰り返す。
 */
async function deleteCollection(
  ref: FirebaseFirestore.CollectionReference
): Promise<number> {
  let removed = 0;
  for (;;) {
    const page = await ref.limit(500).get();
    if (page.empty) return removed;

    const batch = ref.firestore.batch();
    for (const doc of page.docs) batch.delete(doc.ref);
    await batch.commit();
    removed += page.size;

    // **同じ大きさで返ってこなければ、それが最後。**
    if (page.size < 500) return removed;
  }
}
