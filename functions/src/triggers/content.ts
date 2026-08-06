/**
 * 項目・コメントの通知とメンバー数の集計（仕様書 10.2 / 13.4）
 */
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentWritten,
} from 'firebase-functions/v2/firestore';

import * as logger from 'firebase-functions/logger';

import { REGION, paths } from '../config';
import {
  listAdminUids,
  listMemberUids,
  notifySafely,
  siteAdminUids,
} from '../notifications';

/**
 * 曲（項目）が追加されたら、そのリストのメンバー全員へ通知する（仕様書 10.2）。
 *
 * **宛先はリストのメンバー全員**。役割は問わない。曲が増えたことは、
 * そのリストに参加している人みんなにとっての知らせなので、
 * 閲覧のみ（Read Only）の人も受け取る。リスト管理者もメンバーなので含まれる。
 *
 * **サイト管理者だからという理由では送らない。** 以前は全リストの項目追加が
 * サイト管理者に届いていたが、参加していないリストの曲まで通知されるのは
 * 雑音でしかない。サイト管理者も、そのリストのメンバーであれば受け取る。
 *
 * URL の項目もファイルの項目も同じ扱い（どちらも「曲が 1 つ増えた」）。
 *
 * 受け取るかどうかは各自の通知設定で切り替えられる（仕様書 10.3）。
 */
export const onItemCreated = onDocumentCreated(
  { region: REGION, document: 'lists/{listId}/items/{itemId}' },
  async (event) => {
    const { listId, itemId } = event.params;
    const data = event.data?.data();
    if (!data) return;

    // 宛先集めから通知までを包む。ここで例外を出すとトリガーが失敗扱いになり、
    // 再試行が延々と繰り返される。通知は本処理の副次的なものなので、
    // 失敗はログに残して先へ進む。
    await notifySafely(() => listMemberUids(listId), {
      type: 'itemAdded',
      listId,
      itemId,
      actorUid: data.createdBy,
    });
  }
);

/**
 * コメントが付いたら通知する（仕様書 10.2）。
 *
 * 受信者は次の 3 種類。
 * - 該当リストのリスト管理者
 * - サイト管理者（全リスト）
 * - **自分の投稿・コメントにコメントが付いた本人**
 */
export const onCommentCreated = onDocumentCreated(
  {
    region: REGION,
    document: 'lists/{listId}/items/{itemId}/comments/{commentId}',
  },
  async (event) => {
    const { listId, itemId, commentId } = event.params;
    const data = event.data?.data();
    if (!data) return;

    const db = getFirestore();
    const recipients = new Set<string>();

    const [admins, siteAdmins] = await Promise.all([
      listAdminUids(listId),
      siteAdminUids(),
    ]);
    admins.forEach((uid) => recipients.add(uid));
    siteAdmins.forEach((uid) => recipients.add(uid));

    // 返信なら親コメントの投稿者、ルートコメントなら項目の登録者。
    const parentId = data.parentId as string | undefined | null;
    if (parentId) {
      const parent = await db
        .doc(`${paths.listItem(listId, itemId)}/comments/${parentId}`)
        .get();
      const parentAuthor = parent.data()?.createdBy;
      if (typeof parentAuthor === 'string') recipients.add(parentAuthor);
    } else {
      const item = await db.doc(paths.listItem(listId, itemId)).get();
      const itemAuthor = item.data()?.createdBy;
      if (typeof itemAuthor === 'string') recipients.add(itemAuthor);
    }

    await notifySafely(() => [...recipients], {
      type: 'commentAdded',
      listId,
      itemId,
      commentId,
      actorUid: data.createdBy,
    });
  }
);

/**
 * メンバーの増減に合わせて memberCount / adminCount を更新する（仕様書 13.4）。
 *
 * adminCount が 0 になったリストは「管理者不在」として
 * サイト管理画面で抽出できるようにする（仕様書 5.6）。
 */
/**
 * 項目の増減を stats.itemCount に反映する（仕様書 7.4 / 14.2）。
 *
 * **ホーム画面が件数を出すためだけに全項目を購読していた**（監査 S6）。
 * 参加リスト M 件 × 平均項目 N 件で、画面を開くだけで M 本の常時接続と
 * M×N 件の読み取りが発生していた。件数はサーバー側で持たせる。
 *
 * 削除はソフト削除（status を deleted にする）なので、
 * **作成・削除だけでなく status の変化も見る**必要がある。
 * 差分で増減させるのは、全件数え直しが項目数に比例して重くなるため。
 */
export const onItemWritten = onDocumentWritten(
  { region: REGION, document: 'lists/{listId}/items/{itemId}' },
  async (event) => {
    const { listId } = event.params;

    const wasActive = event.data?.before.exists
      ? event.data.before.data()?.status !== 'deleted'
      : false;
    const isActive = event.data?.after.exists
      ? event.data.after.data()?.status !== 'deleted'
      : false;

    if (wasActive === isActive) return; // 件数に影響しない更新

    const delta = isActive ? 1 : -1;
    const statsRef = getFirestore().doc(paths.listStats(listId));

    await statsRef
      .update({ itemCount: FieldValue.increment(delta) })
      .catch((error) => {
        // リストごと削除された直後などに起こりうる。集計対象が無いだけ。
        logger.info('itemCount を更新できませんでした', {
          listId,
          error: error instanceof Error ? error.message : String(error),
        });
      });
  }
);

export const onMemberWritten = onDocumentWritten(
  { region: REGION, document: 'lists/{listId}/members/{uid}' },
  async (event) => {
    const { listId } = event.params;
    const db = getFirestore();

    // 件数はその都度数え直す。差分の積み上げだと、トリガーの再実行や
    // 取りこぼしでずれたまま戻らなくなるため。
    const members = await db.collection(paths.listMembers(listId)).get();
    const memberCount = members.size;
    const adminCount = members.docs.filter(
      (doc) => doc.data().role === 'listAdmin'
    ).length;

    const listRef = db.doc(paths.list(listId));
    const list = await listRef.get();
    if (!list.exists) return; // リストごと削除された場合

    await listRef.update({
      memberCount,
      adminCount,
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
);

/**
 * リストが削除されたら、配下のデータとファイルをすべて消す（仕様書 5.5）。
 *
 * クライアントから全件を消すと、途中で失敗したときに中途半端な状態が残る。
 * ここでまとめて処理する。
 */
export const onListDeleted = onDocumentDeleted(
  { region: REGION, document: 'lists/{listId}' },
  async (event) => {
    const { listId } = event.params;
    const db = getFirestore();
    const data = event.data?.data();

    // 名前の予約を解放する（仕様書 13.3）。
    const nameLower = data?.nameLower;
    if (typeof nameLower === 'string' && nameLower) {
      await db.doc(paths.listName(nameLower)).delete().catch(() => undefined);
    }

    // 配下のドキュメントを再帰的に削除する。
    await db.recursiveDelete(db.doc(paths.list(listId)));

    // Storage のファイルも消す（仕様書 5.5：ファイル・コメントもすべて削除）。
    const { getStorage } = await import('firebase-admin/storage');
    await getStorage()
      .bucket()
      .deleteFiles({ prefix: `lists/${listId}/` })
      .catch(() => undefined);
  }
);
