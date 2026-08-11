/**
 * 使用容量の集計（仕様書 7.3 / 13.4 / docs/PREMIUM-DESIGN.md「容量の数字」）
 *
 * Storage へのファイル保存・削除を検知して usedBytes を加減算する。
 * クライアントからは書けないため、この数字が正となる。
 *
 * **上限は「人ごとの合計」に変わった。** リストごとの `stats.usedBytes` は
 * 表示のために数え続けるが、**アップロードを止めるかどうかを決めるのは
 * 「そのリストを作った人（`lists.createdBy`）の合計」**である。
 * リストが無制限に作れるため、リストごとの上限では 1 人が持てる総量に
 * 上限が無くなり、費用の裏口が開く（PREMIUM-DESIGN D5 の補足）。
 *
 * **誰がアップロードしても、作った人の枠から引く。** 「自分の場所に人を
 * 招いて集める」という使い方と揃い、誰が入っても費用の上限が読める。
 */
import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import * as logger from 'firebase-functions/logger';
import { onObjectDeleted, onObjectFinalized } from 'firebase-functions/v2/storage';

import { STORAGE_REGION, paths, parseItemStoragePath } from '../config';
import { isPremiumActive } from '../domain/premium';
import {
  type QuotaLevel,
  USER_DEFAULT_QUOTA_BYTES,
  levelToNotify,
  resolveUserQuota,
  shouldRejectUpload,
  shouldResetNotice,
  shouldResetWarning,
} from '../domain/quota';
import { listAdminUids, notifySafely } from '../notifications';

/**
 * ファイルが保存されたら加算し、しきい値を超えたら通知する。
 *
 * **上限を無視した呼び出しだけ、そのファイルを消す。**
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

    if (!result) return;

    if (!result.exceeded) return;

    // **すり抜けたぶんは残す（仕様書 7.5）。**
    // このファイルで初めて上限を超えたなら、利用者の正当な
    // アップロードなので消さない。以後のアップロードはブロックされる。
    if (
      !shouldRejectUpload({
        usedBytesAfter: result.usedBytes,
        sizeBytes: size,
        quotaBytes: result.quotaBytes,
      })
    ) {
      logger.info('上限を超えましたが、このファイルは受け入れます（7.5）', {
        path: event.data.name,
        listId: parsed.listId,
        usedBytes: result.usedBytes,
        quotaBytes: result.quotaBytes,
      });
      return;
    }

    // 足す前からすでに超えていた＝ブロックされているはずの呼び出し。
    logger.warn('上限を超えた状態でのアップロードを取り消します', {
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
  /** 判定に使った合計。作った人が分かればその合計、分からなければリストのもの。 */
  usedBytes: number;
  quotaBytes: number;
  /** 自動拡張が起きたなら、増えたあとの上限。起きていなければ null。 */
  expandedTo: number | null;
  /** リストを作った人。分からなければ null。 */
  ownerUid: string | null;
}

async function applyDelta(
  listId: string,
  deltaBytes: number
): Promise<DeltaOutcome | null> {
  const db = getFirestore();
  const statsRef = db.doc(paths.listStats(listId));
  const listRef = db.doc(paths.list(listId));
  const nowMs = Date.now();

  const outcome = await db.runTransaction<DeltaOutcome | null>(async (tx) => {
    const snapshot = await tx.get(statsRef);
    if (!snapshot.exists) {
      // リストが削除された直後などに起こりうる。集計対象がないので何もしない。
      logger.info('stats が見つからないため集計をとばします', { listId });
      return null;
    }

    const data = snapshot.data() ?? {};

    // **リストごと消している最中は触らない。** onListDeleted が
    // 合計から一括で引いており、ここでも引くと二重に減る（下の注記）。
    if (data.deleting === true) {
      logger.info('リストの削除中なので集計をとばします', { listId });
      return null;
    }

    const list = await tx.get(listRef);
    const ownerUid = String(list.data()?.createdBy ?? '') || null;
    const userRef = ownerUid ? db.doc(paths.user(ownerUid)) : null;
    const owner = userRef ? await tx.get(userRef) : null;

    const before = Number(data.usedBytes ?? 0);
    // 減算が行き過ぎて負にならないようにする。
    const after = Math.max(0, before + deltaBytes);

    // --- 判定に使う数字を決める ---
    //
    // **作った人の合計が正。** 分からないとき（リストのドキュメントが
    // 消えている・createdBy が無い古いデータ）だけ、リストの数字で
    // これまでどおり判定する。判定材料が無いことを理由に
    // 上限を素通しさせない。
    let usedForCheck = after;
    let quotaForCheck = Number(data.quotaBytes ?? 0);
    let expandedTo: number | null = null;
    let ownerUsedAfter = 0;
    let ownerQuotaAfter = 0;

    if (owner) {
      const storage = owner.data()?.storage;
      const until = owner.data()?.premium?.until;
      const premiumActive = isPremiumActive(
        until instanceof Timestamp ? until.toMillis() : null,
        nowMs
      );

      ownerUsedAfter = Math.max(
        0,
        Number(storage?.usedBytes ?? 0) + deltaBytes
      );

      // **土台と実効値は別（domain/quota.ts の USER_DEFAULT_QUOTA_BYTES）。**
      // 土台はサイト管理者が決める値で、ここでは読むだけ。書き換えると、
      // 移行の手当てで足した上限が集計のたびに動いてしまう。
      const quotaBase = Number(
        storage?.quotaBytesBase ?? USER_DEFAULT_QUOTA_BYTES
      );
      const quotaBefore = Number(storage?.quotaBytes ?? quotaBase);

      // **自動拡張も期限切れの戻しも、この 1 か所で決まる**（純関数）。
      // プレミアムなら 90% を超えたぶんだけ 2GB ずつ足し（実効値 10GB まで）、
      // プレミアムでなければ土台へ戻す。
      ownerQuotaAfter = resolveUserQuota({
        usedBytes: ownerUsedAfter,
        quotaBytes: quotaBefore,
        quotaBytesBase: quotaBase,
        premiumActive,
      });
      if (ownerQuotaAfter > quotaBefore) expandedTo = ownerQuotaAfter;

      usedForCheck = ownerUsedAfter;
      quotaForCheck = ownerQuotaAfter;
    }

    // **送信済みの印はリストごとのまま残してある。**
    // 判定の材料（割合）は人ごとの合計に変えたが、印を人ごとに移すと
    // `users` に通知の状態まで持たせることになる。いまの形だと、
    // 同じ人が複数のリストを持っているとき、リストの数だけ 80%/90% の
    // 知らせが届きうる（同じリストで繰り返しは届かない）。
    // 宛先を人ごとに寄せるのは PREMIUM-DESIGN「波及するところ」の
    // 積み残しで、通知の作り（10.2）ごと見直すときにまとめて直すこと。
    const noticeSent = data.notifiedNotice80 === true;
    const warningSent = data.notifiedWarning90 === true;
    const status = { usedBytes: usedForCheck, quotaBytes: quotaForCheck };

    const level = levelToNotify(status, noticeSent, warningSent);
    const resetNotice = shouldResetNotice(status, noticeSent);
    const resetWarning = shouldResetWarning(status, warningSent);

    tx.update(statsRef, {
      usedBytes: after,
      // **作った人の合計の写し（PREMIUM-DESIGN「波及するところ」）。**
      // 画面側がメンバーとして読めるのは stats だけで、他人の users
      // ドキュメントは読めないため、ここに写す。
      // **書くのは、いま書いているこのリストの stats だけ。** 他のリストの
      // 写しは、そのリストのファイルが次に増減したときに更新される。
      // 多少古くても、**本当の判定はサーバー側**（この関数）で行うので安全。
      ...(owner
        ? { ownerUsedBytes: ownerUsedAfter, ownerQuotaBytes: ownerQuotaAfter }
        : {}),
      ...(level === 'notice' ? { notifiedNotice80: true } : {}),
      ...(level === 'warning'
        ? { notifiedWarning90: true, notifiedNotice80: true }
        : {}),
      ...(resetNotice ? { notifiedNotice80: false } : {}),
      ...(resetWarning ? { notifiedWarning90: false } : {}),
    });

    if (userRef && owner) {
      tx.set(
        userRef,
        { storage: { usedBytes: ownerUsedAfter, quotaBytes: ownerQuotaAfter } },
        { merge: true }
      );
    }

    return {
      level,
      // 加算のときだけ判定する。削除で減った結果を超過とは呼ばない。
      exceeded: deltaBytes > 0 && quotaForCheck > 0 && usedForCheck > quotaForCheck,
      usedBytes: usedForCheck,
      quotaBytes: quotaForCheck,
      expandedTo,
      ownerUid,
    };
  });

  if (!outcome) return null;

  // 通知はトランザクションの外で行う。トランザクションが再試行されたときに
  // 通知を重複して作らないようにするため。

  // **増やしたことを必ず伝える（PREMIUM-DESIGN「自動拡張の作り」）。**
  // 黙って増えると、請求が増えた理由が利用者にも運営にも分からない。
  if (outcome.expandedTo !== null && outcome.ownerUid) {
    logger.info('容量を自動拡張しました', {
      listId,
      uid: outcome.ownerUid,
      quotaBytes: outcome.expandedTo,
    });
    await notifySafely(() => [outcome.ownerUid as string], {
      type: 'quotaExpanded',
      listId,
    });
  }

  if (outcome.level) {
    await notifySafely(() => listAdminUids(listId), {
      type: outcome.level === 'warning' ? 'quotaWarning' : 'quotaNotice',
      listId,
    });
  }

  return outcome;
}
