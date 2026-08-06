/**
 * 定期実行：削除ファイルの完全削除と、行き場を失ったファイルの掃除
 * （仕様書 13.4 / 7.5）
 *
 * 1 日 1 回動かす。
 */
import { Timestamp, getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import * as logger from 'firebase-functions/logger';
import { onSchedule } from 'firebase-functions/v2/scheduler';

import { REGION, paths, parseItemStoragePath, readSiteConfig } from '../config';
import { isPathOwnedByItem } from '../domain/paths';

/**
 * 1 回の実行で処理する上限。
 *
 * 時間切れで途中終了しても、次の実行で続きを片づけられるようにする。
 */
const MAX_ITEMS_PER_RUN = 500;
/**
 * 1 回の実行で走査するオブジェクトの上限。
 *
 * 削除件数だけを絞っても、走査そのものが総ファイル数に比例すると
 * いずれ実行時間の上限を超えて毎回途中で落ちる（監査 S8）。
 */
const MAX_SCANNED_PER_RUN = 2000;

const MAX_ORPHANS_PER_RUN = 500;

export const purgeDeletedFiles = onSchedule(
  {
    region: REGION,
    // 毎日 4:00（日本時間）。利用の少ない時間帯に寄せる。
    schedule: '0 4 * * *',
    timeZone: 'Asia/Tokyo',
    timeoutSeconds: 540,
  },
  async () => {
    const config = await readSiteConfig();
    const purged = await purgeExpiredItems();
    const orphans = await purgeOrphanFiles(config.orphanFileGraceHours);

    logger.info('定期削除を実行しました', {
      purgedItems: purged,
      purgedOrphans: orphans,
    });
  }
);

/**
 * 猶予期間を過ぎた削除項目のファイルを、Storage から完全に削除する。
 *
 * 項目のドキュメント自体は残す。連番の欠番を維持し
 * 「削除されました」と表示し続けるため（仕様書 6.2）。
 * usedBytes は Storage の削除トリガーが減らす（仕様書 13.4）。
 */
async function purgeExpiredItems(): Promise<number> {
  const db = getFirestore();
  const now = Timestamp.now();

  const expired = await db
    .collectionGroup('items')
    .where('status', '==', 'deleted')
    .where('purgeAt', '<=', now)
    .limit(MAX_ITEMS_PER_RUN)
    .get();

  if (expired.empty) return 0;

  const bucket = getStorage().bucket();
  let count = 0;

  for (const doc of expired.docs) {
    const data = doc.data();

    // ドキュメントのパスから、この項目が属するリストと項目 ID を得る。
    // lists/{listId}/items/{itemId}
    const listId = doc.ref.parent.parent?.id;
    const itemId = doc.ref.id;

    try {
      if (!listId) {
        logger.warn('リスト ID を特定できないため飛ばします', {
          path: doc.ref.path,
        });
        continue;
      }

      // **消す前に、そのパスがこの項目のものか必ず確かめる。**
      // storagePath はクライアントが書けるため、他人のリストのパスを
      // 書き込んでおけば、サーバーの権限でそのファイルを消させられる
      // （監査 S1）。ルール側でも塞いでいるが、消す側でも確かめる。
      const candidates: unknown[] = [
        data.file?.storagePath,
        ...(Array.isArray(data.previousFiles)
          ? data.previousFiles.map((old: { storagePath?: unknown }) => old?.storagePath)
          : []),
      ];

      for (const candidate of candidates) {
        if (candidate == null) continue;
        if (!isPathOwnedByItem(candidate, listId, itemId)) {
          logger.error('項目に属さないファイルパスを検出しました（削除しません）', {
            path: doc.ref.path,
            storagePath: String(candidate),
          });
          continue;
        }
        // ignoreNotFound を付け、既に消えている場合も失敗にしない。
        await bucket.file(candidate).delete({ ignoreNotFound: true });
      }

      // 消し終えた印を付け、次回以降の対象から外す。
      await doc.ref.update({
        purgeAt: null,
        purgedAt: Timestamp.now(),
        file: null,
        previousFiles: null,
      });
      count++;
    } catch (error) {
      // 1 件の失敗で全体を止めない。次回の実行で再度拾われる。
      logger.warn('ファイルの完全削除に失敗しました', {
        path: doc.ref.path,
        error,
      });
    }
  }

  return count;
}

/**
 * 行き場を失ったファイルを削除する（仕様書 7.5）。
 *
 * アップロードは完了したが項目の作成に至らなかったファイルが対象。
 * アップロードから一定時間（既定 24 時間）経過したものだけを消す。
 * 完了から項目作成までの短い間に消してしまわないようにするため。
 */
async function purgeOrphanFiles(graceHours: number): Promise<number> {
  const db = getFirestore();
  const bucket = getStorage().bucket();
  const cutoff = Date.now() - graceHours * 60 * 60 * 1000;

  // **一括取得しない。** 以前は prefix 配下の全オブジェクトを一度に
  // メモリへ載せていたため、孤児が 0 件でも総ファイル数に比例して
  // 重くなり、いずれ実行時間の上限で毎回落ちるようになる（監査 S8）。
  // ページ単位で受け取り、走査した件数にも上限を置く。
  //
  // **続きの位置を持ち越す。** 以前は `pageToken` を渡しておらず、
  // 毎回バケットの先頭 2000 件しか見ていなかった。オブジェクト名は
  // `lists/{listId}/…` の辞書順なので、総数が上限を超えると
  // **後ろのリストの孤児は永久に消えない**。ログには
  // 「残りは次回に持ち越します」と出るため、監視していても気づけない
  // （監査 第2回）。
  const cursorRef = db.doc(paths.siteConfig);
  const savedToken = (await cursorRef.get()).data()?.orphanScanPageToken;
  const pageToken = typeof savedToken === 'string' && savedToken
    ? savedToken
    : undefined;

  const [files, nextQuery] = await bucket.getFiles({
    prefix: 'lists/',
    maxResults: MAX_SCANNED_PER_RUN,
    autoPaginate: false,
    ...(pageToken ? { pageToken } : {}),
  });

  // 続きがあれば次回の開始位置を保存し、無ければ消して先頭へ戻す。
  // 一巡したら最初から見直す。ファイルは増減するため。
  const nextToken =
    (nextQuery as { pageToken?: string } | null)?.pageToken ?? null;
  await cursorRef.set(
    { orphanScanPageToken: nextToken },
    { merge: true }
  );

  let count = 0;
  let scanned = 0;

  for (const file of files) {
    if (count >= MAX_ORPHANS_PER_RUN) break;
    if (scanned >= MAX_SCANNED_PER_RUN) break;
    scanned++;

    const parsed = parseItemStoragePath(file.name);
    if (!parsed) continue;

    const created = Date.parse(String(file.metadata.timeCreated ?? ''));
    // **猶予期間内のものは Firestore を読む前に弾く。** 以前は正常な
    // ファイル 1 件ごとに読み取りが走っていた（監査 S8）。
    if (!Number.isFinite(created) || created > cutoff) continue;

    try {
      const item = await db
        .doc(paths.listItem(parsed.listId, parsed.itemId))
        .get();

      // 項目が存在し、かつこのファイルを指しているなら残す。
      if (item.exists) {
        const current = item.data()?.file?.storagePath;
        if (current === file.name) continue;

        // 差し替えの旧ファイルは、項目が保持している間は消さない。
        const previous = item.data()?.previousFiles;
        if (
          Array.isArray(previous) &&
          previous.some((old) => old?.storagePath === file.name)
        ) {
          continue;
        }
      }

      await file.delete({ ignoreNotFound: true });
      count++;
      logger.info('行き場を失ったファイルを削除しました', { path: file.name });
    } catch (error) {
      logger.warn('孤児ファイルの削除に失敗しました', {
        path: file.name,
        error,
      });
    }
  }

  if (nextToken) {
    logger.info('走査の上限に達しました。続きは次回から見ます', {
      scanned,
      deleted: count,
    });
  } else {
    logger.info('バケットを一巡しました。次回は先頭から見ます', {
      scanned,
      deleted: count,
    });
  }

  return count;
}
