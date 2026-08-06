/**
 * 使用容量の集計（仕様書 7.3 / 13.4）
 *
 * Storage へのファイル保存・削除を検知して usedBytes を加減算する。
 * クライアントからは書けないため、この数字が正となる。
 */
import { FieldValue, getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import * as logger from 'firebase-functions/logger';
import { onObjectDeleted, onObjectFinalized } from 'firebase-functions/v2/storage';

import { STORAGE_REGION, paths, parseItemStoragePath } from '../config';
import {
  type QuotaLevel,
  levelToNotify,
  shouldResetNotice,
  shouldResetWarning,
} from '../domain/quota';
import { listAdminUids, notifySafely } from '../notifications';

/**
 * ファイルが保存されたら加算し、しきい値を超えたら通知する。
 *
 * **上限を超えていたら、そのファイルを消す。**
 * ルールからは合計使用量を参照できないため、上限の強制はここでしか行えない。
 * クライアント側のチェック（7.5）は画面を経由しない呼び出しには効かず、
 * Storage の SDK を直接叩けば無視できる（監査 S5）。
 */
export const onFileUploaded = onObjectFinalized(
  { region: STORAGE_REGION },
  async (event) => {
    const parsed = parseItemStoragePath(event.data.name);
    if (!parsed) return; // 項目のファイル以外には反応しない

    const size = Number(event.data.size ?? 0);
    if (!Number.isFinite(size) || size <= 0) return;

    const result = await applyDelta(parsed.listId, size);

    if (result?.exceeded) {
      logger.warn('容量の上限を超えたためアップロードを取り消します', {
        path: event.data.name,
        listId: parsed.listId,
        usedBytes: result.usedBytes,
        quotaBytes: result.quotaBytes,
      });

      // 消した結果は onFileDeleted が拾って usedBytes を戻す。
      // ここで自分で減算すると二重に引かれる。
      await getStorage()
        .bucket(event.data.bucket)
        .file(event.data.name)
        .delete({ ignoreNotFound: true })
        .catch((error) => {
          logger.error('超過ファイルの削除に失敗しました', {
            path: event.data.name,
            error: error instanceof Error ? error.message : String(error),
          });
        });
    }
  }
);

/** ファイルが削除されたら減算し、しきい値を下回ったらフラグを戻す。 */
export const onFileDeleted = onObjectDeleted(
  { region: STORAGE_REGION },
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
interface DeltaOutcome {
  level: QuotaLevel | null;
  /** 上限を超えたか。超えていればアップロードを取り消す（7.5）。 */
  exceeded: boolean;
  usedBytes: number;
  quotaBytes: number;
}

async function applyDelta(
  listId: string,
  deltaBytes: number
): Promise<DeltaOutcome | null> {
  const db = getFirestore();
  const statsRef = db.doc(paths.listStats(listId));

  const outcome = await db.runTransaction<DeltaOutcome | null>(async (tx) => {
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

    return {
      level,
      // 加算のときだけ判定する。削除で減った結果を超過とは呼ばない。
      exceeded: deltaBytes > 0 && quotaBytes > 0 && after > quotaBytes,
      usedBytes: after,
      quotaBytes,
    };
  });

  if (!outcome) return null;

  if (outcome.level) {
    // 通知はトランザクションの外で行う。トランザクションが再試行されたときに
    // 通知を重複して作らないようにするため。
    await notifySafely(() => listAdminUids(listId), {
      type: outcome.level === 'warning' ? 'quotaWarning' : 'quotaNotice',
      listId,
    });
  }

  return outcome;
}
