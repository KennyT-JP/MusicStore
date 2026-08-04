/**
 * Storage セキュリティルールのテスト（仕様書 13.5 / 13.7）
 *
 * ファイル配置は lists/{listId}/items/{itemId}/{ファイル名}。
 *
 * ## エミュレータの制約（重要）
 *
 * storage.rules は、メンバーかどうかを判定するために Firestore を参照する
 * （`firestore.exists()` / `firestore.get()`）。これは**本番の Cloud Storage
 * では動くが、Storage エミュレータでは動かない**。エミュレータ上では
 * `firestore.exists()` が常に偽となり、すべてのアクセスが拒否される。
 *
 * 実際に次を確認済み：
 * - `allow read: if request.auth != null` … 期待どおり許可される
 * - `allow read: if firestore.exists(...)` … メンバーが存在しても拒否される
 *
 * このため、**「メンバーだから許可される」ことを確認するテストは
 * エミュレータでは検証できない**。該当するテストは `describe.skip` にして
 * 理由を明示し、検証環境（ステージング）での手動確認に回す。
 * 手順は docs/SETUP.md を参照。
 *
 * 逆に「拒否される」ことを確認するテストは、エミュレータ上ではすべてが
 * 拒否されるため**通ってしまう**。合格しても保証にはならないので、
 * これらもステージングで併せて確認する。
 */
import { afterAll, beforeAll, beforeEach, describe, test } from 'vitest';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  deleteObject,
  getDownloadURL,
  ref,
  uploadBytes,
} from 'firebase/storage';

import {
  ITEM_ID,
  LIST_ID,
  UID,
  asAnonymous,
  asSiteAdmin,
  asUser,
  createTestEnv,
  seed,
} from './helpers.js';

let env;

beforeAll(async () => {
  env = await createTestEnv();
});

afterAll(async () => {
  await env?.cleanup();
});

beforeEach(async () => {
  await seed(env);
  await env.clearStorage();
  // 既存ファイルを 1 つ置いておく。
  await env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(
      ref(ctx.storage(), filePath('existing.mp3')),
      new Uint8Array([1, 2, 3]),
    );
  });
});

const filePath = (name) => `lists/${LIST_ID}/items/${ITEM_ID}/${name}`;
const audio = () => new Uint8Array([1, 2, 3, 4]);

// ---------------------------------------------------------------------------
// エミュレータで意味のある検証
//
// Firestore を参照せずに結果が決まるルール（`if false` など）は、
// エミュレータ上でも正しく検証できる。
// ---------------------------------------------------------------------------

describe('Firestore を参照せずに決まるルール', () => {
  test('既存ファイルを上書きできない（差し替えは別名で保存／13.7）', async () => {
    // allow update: if false なので、メンバーかどうかに関係なく拒否される。
    const storage = asUser(env, UID.superUser).storage();
    await assertFails(
      uploadBytes(ref(storage, filePath('existing.mp3')), audio()),
    );
  });

  test('クライアントからは削除できない（Functions が猶予期間後に削除／13.4）', async () => {
    // allow delete: if false。誤操作でファイルだけ先に消えると復元できない。
    const storage = asUser(env, UID.listAdmin).storage();
    await assertFails(deleteObject(ref(storage, filePath('existing.mp3'))));
  });

  test('サイト管理者でも削除できない', async () => {
    const storage = asSiteAdmin(env).storage();
    await assertFails(deleteObject(ref(storage, filePath('existing.mp3'))));
  });

  test('定義していないパスは読み書きとも拒否する', async () => {
    const storage = asSiteAdmin(env).storage();
    await assertFails(
      uploadBytes(ref(storage, 'somewhere/else.mp3'), audio()),
    );
    await assertFails(getDownloadURL(ref(storage, 'somewhere/else.mp3')));
  });

  test('未ログインでは読めない', async () => {
    const storage = asAnonymous(env).storage();
    await assertFails(getDownloadURL(ref(storage, filePath('existing.mp3'))));
  });
});

// ---------------------------------------------------------------------------
// エミュレータでは検証できない（ステージングで手動確認する）
//
// Storage エミュレータが cross-service の firestore.exists() に対応して
// いないため、「メンバーだから許可される」を確認できない。
// ---------------------------------------------------------------------------

describe.skip('メンバー判定を伴うルール（要ステージング確認）', () => {
  test('Read Only も再生・ダウンロードできる（4.2）', async () => {
    const storage = asUser(env, UID.readOnly).storage();
    await assertSucceeds(
      getDownloadURL(ref(storage, filePath('existing.mp3'))),
    );
  });

  test('サイト管理者はメンバー登録がなくても読める', async () => {
    const storage = asSiteAdmin(env).storage();
    await assertSucceeds(
      getDownloadURL(ref(storage, filePath('existing.mp3'))),
    );
  });

  test('Super User はアップロードできる（4.2）', async () => {
    const storage = asUser(env, UID.superUser).storage();
    await assertSucceeds(
      uploadBytes(ref(storage, filePath('new.mp3')), audio()),
    );
  });

  test('リスト管理者もアップロードできる', async () => {
    const storage = asUser(env, UID.listAdmin).storage();
    await assertSucceeds(
      uploadBytes(ref(storage, filePath('admin.mp3')), audio()),
    );
  });

  test('Read Only はアップロードできない（4.2）', async () => {
    const storage = asUser(env, UID.readOnly).storage();
    await assertFails(
      uploadBytes(ref(storage, filePath('new.mp3')), audio()),
    );
  });

  test('未参加者は読めない（5.3）', async () => {
    const storage = asUser(env, UID.outsider).storage();
    await assertFails(getDownloadURL(ref(storage, filePath('existing.mp3'))));
  });

  test('未参加者はアップロードできない', async () => {
    const storage = asUser(env, UID.outsider).storage();
    await assertFails(
      uploadBytes(ref(storage, filePath('new.mp3')), audio()),
    );
  });

  test('参加していないリストにはアップロードできない', async () => {
    const storage = asUser(env, UID.superUser).storage();
    await assertFails(
      uploadBytes(ref(storage, 'lists/list-2/items/x/song.mp3'), audio()),
    );
  });
});
