/**
 * 項目のファイルを差し替える（仕様書 6.3 / 13.4 / 14.4）
 *
 * **なぜ Functions を通すのか。**
 *
 * 差し替えは「新しいファイルを指す」だけでは済まない。**古いファイルを
 * 猶予つきで残す**必要があり、その置き場所が `items.previousFiles` である。
 * ここはクライアントから書けないよう塞いである（firestore.rules の
 * `noPreviousFiles`）——書けると、**他人のリストのパスを紛れ込ませて
 * サーバーの権限で消させられる**（監査 S1）。
 *
 * **容量の数え方**（依頼者の決定・2026-08-14）。
 *
 * 旧ファイルは猶予のあいだ実際に置かれたままなので、**使用量に数える**。
 * 削除の扱い（30 日は容量を消費し続ける／6.2・7.3）と揃えてある。
 * 加減算そのものは Storage のトリガ（triggers/storage.ts）が行うので、
 * ここでは数えない——**同じ数を 2 か所で足すと必ずずれる。**
 *
 * **消えるまでの流れ。**
 *
 *   1. ここで `previousFiles` に積む（`purgeAt` つき）
 *   2. 猶予を過ぎると、掃除（scheduled/purge.ts）が実体を消す
 *   3. 消えた時点で `onFileDeleted` が使用量から引く
 */
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { onCall } from 'firebase-functions/v2/https';

import { REGION, paths, parseItemStoragePath, readSiteConfig } from '../config';
import { fail } from '../errors';
import { requireString, requireUid } from './access';

/**
 * 項目のファイルを差し替える。
 *
 * 呼ぶ前に、クライアントが**新しいファイルをその項目の場所へ
 * アップロードしておく**（置き場所は Storage のルールが守る）。
 * ここでは「項目の指す先を新しいファイルへ移し、古いほうを猶予つきで
 * 残す」だけを行う。
 */
export const replaceItemFile = onCall({ region: REGION }, async (request) => {
  const uid = requireUid(request);
  const listId = requireString(request.data, 'listId', { maxLength: 200 });
  const itemId = requireString(request.data, 'itemId', { maxLength: 200 });
  const storagePath = requireString(request.data, 'storagePath', {
    maxLength: 1024,
  });
  const fileName = requireString(request.data, 'fileName', { maxLength: 300 });

  // **置き場所は必ず確かめる。** クライアントの申告をそのまま信じると、
  // 他人のリストのファイルを自分の項目に紐づけられる（監査 S1）。
  const parsed = parseItemStoragePath(storagePath);
  if (!parsed || parsed.listId !== listId || parsed.itemId !== itemId) {
    throw fail('invalid-argument', 'fileNotInThisItem');
  }

  const db = getFirestore();
  const itemRef = db.doc(paths.listItem(listId, itemId));
  const [item, member] = await Promise.all([
    itemRef.get(),
    db.doc(paths.listMember(listId, uid)).get(),
  ]);

  if (!item.exists) throw fail('not-found', 'itemNotFound');

  const data = item.data() ?? {};
  if (data.status === 'deleted') {
    // 削除済みの項目に差し替えを許すと、**猶予の判定が二重になる。**
    throw fail('failed-precondition', 'itemDeleted');
  }

  // 編集できるのは本人とリスト管理者（6.3）。**画面の出し分けと同じ規則を
  // ここでも持つ**——画面だけの制限は API 直の呼び出しに効かない。
  const role = member.exists ? member.data()?.role : null;
  const isListAdmin = role === 'listAdmin';
  const canEdit = isListAdmin || (role === 'superUser' && data.createdBy === uid);
  if (!canEdit) throw fail('permission-denied', 'cannotEditItem');

  // **大きさと種類は Storage から読む。** 申告値を使うと、使用量の集計
  // （triggers/storage.ts が実物から数える）と食い違う。
  const object = getStorage().bucket().file(storagePath);
  const [exists] = await object.exists();
  if (!exists) throw fail('failed-precondition', 'uploadNotFound');
  const [metadata] = await object.getMetadata();
  const sizeBytes = Number(metadata.size ?? 0);
  const contentType = String(metadata.contentType ?? 'application/octet-stream');

  const previous = data.file;
  const samePath =
    previous && typeof previous === 'object'
      ? (previous as { storagePath?: unknown }).storagePath === storagePath
      : false;
  if (samePath) {
    // 同じ場所へ上書きされると、**古いほうを残せない**（実体が 1 つしかない）。
    // 置き場所はクライアントが決めるので、ここで気づけるようにしておく。
    throw fail('failed-precondition', 'sameStoragePath');
  }

  const config = await readSiteConfig();
  const purgeAt = Timestamp.fromMillis(
    Date.now() + config.itemPurgeGraceDays * 24 * 60 * 60 * 1000
  );

  await itemRef.update({
    kind: 'file',
    url: FieldValue.delete(),
    file: { storagePath, fileName, sizeBytes, contentType },
    // **古いほうは配列に積む。** 猶予のあいだは実体を残し、
    // 過ぎたら掃除が消す（domain/paths.ts の isOrphanFile が
    // purgeAt を見る）。
    ...(previous
      ? {
          previousFiles: FieldValue.arrayUnion({
            ...(previous as Record<string, unknown>),
            replacedAt: Timestamp.now(),
            purgeAt,
          }),
        }
      : {}),
    updatedBy: uid,
    updatedAt: FieldValue.serverTimestamp(),
  });

  return { ok: true, sizeBytes };
});
