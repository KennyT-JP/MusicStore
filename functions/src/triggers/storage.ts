/**
 * 使用容量の集計（仕様書 7.3 / 13.4）
 *
 * Storage へのファイル保存・削除を検知して usedBytes を加減算する。
 * クライアントからは書けないため、この数字が正となる。
 */
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import * as logger from 'firebase-functions/logger';
import { onObjectDeleted, onObjectFinalized } from 'firebase-functions/v2/storage';

import { REGION, paths, parseItemStoragePath } from '../config';
import {
  levelToNotify,
  shouldResetNotice,
  shouldResetWarning,
} from '../domain/quota';
import { listAdminUids, notifyUsers } from '../notifications';

/** ファイルが保存されたら加算し、しきい値を超えたら通知する。 */
export const onFileUploaded = onObjectFinalized(
  { region: REGION },
  async (event) => {
    const parsed = parseItemStoragePath(event.data.name);
    if (!parsed) return; // 項目のファイル以外には反応しない

    const size = Number(event.data.size ?? 0);
    if (!Number.isFinite(size) || size <= 0) return;

    await applyDelta(parsed.listId, size);
  }
);

/** ファイルが削除されたら減算し、しきい値を下回ったらフラグを戻す。 */
export const onFileDeleted = onObjectDeleted(
  { region: REGION },
  async (event) => {
    const parsed = parseItemStoragePath(event.data.name);
    if (!parsed) return;

    const size = Number(event.data.size ?? 0);
    if (!Number.isFinite(size) || size <= 0) return;

    await applyDelta(parsed.listId, -size);
  }
);

/**
 * usedBytes を加減算し、通知の要否を判定する。
 *
 * 集計と通知フラグの更新はトランザクションで行う。
 * 同時にアップロードされても数字がずれないようにするため。
 */
async function applyDelta(listId: string, deltaBytes: number): Promise<void> {
  const db = getFirestore();
  const statsRef = db.doc(paths.listStats(listId));

  const outcome = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(statsRef);
    if (!snapshot.exists) {
      // リストが削除された直後などに起こりうる。集計対象がないので何もしない。
      logger.info('stats が見つからないため集計をとばします', { listId });
      return null;
    }

    const data = snapshot.data() ?? {};
    const quotaBytes = Number(data.quotaBytes ?? 0);
    const before = Number(data.usedBytes ?? 0);
    // 減算が行き過ぎて負にならないようにする。
    const after = Math.max(0, before + deltaBytes);

    const noticeSent = data.notifiedNotice80 === true;
    const warningSent = data.notifiedWarning90 === true;
    const status = { usedBytes: after, quotaBytes };

    const level = levelToNotify(status, noticeSent, warningSent);
    const resetNotice = shouldResetNotice(status, noticeSent);
    const resetWarning = shouldResetWarning(status, warningSent);

    tx.update(statsRef, {
      usedBytes: after,
      ...(level === 'notice' ? { notifiedNotice80: true } : {}),
      ...(level === 'warning'
        ? { notifiedWarning90: true, notifiedNotice80: true }
        : {}),
      ...(resetNotice ? { notifiedNotice80: false } : {}),
      ...(resetWarning ? { notifiedWarning90: false } : {}),
    });

    return { level };
  });

  if (!outcome?.level) return;

  // 通知はトランザクションの外で行う。トランザクションが再試行されたときに
  // 通知を重複して作らないようにするため。
  await notifyUsers(await listAdminUids(listId), {
    type: outcome.level === 'warning' ? 'quotaWarning' : 'quotaNotice',
    listId,
  });
}
