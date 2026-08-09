/**
 * Storage セキュリティルールのテスト（仕様書 13.5 / 13.7）
 *
 * ファイル配置は lists/{listId}/items/{itemId}/{ファイル名}。
 *
 * ## かつてスキップしていた経緯（残す）
 *
 * storage.rules は、メンバーかどうかを判定するために Firestore を参照する
 * （`firestore.exists()` / `firestore.get()`）。以前ここには
 * 「Storage エミュレータは cross-service の firestore.exists() に対応して
 * いないため検証できない」と書かれており、8 件を `describe.skip` にしていた。
 *
 * **これは誤りだった。** 2026-08-06 のゼロベース監査で実際に skip を外して
 * 実行したところ、8 件すべてが期待どおりに動いた。しかもこの誤った前提は
 * README・SETUP.md・DEVLOG.md にも転記され、増幅していた。
 *
 * 教訓：**「〜できない」と書かれた箇所こそ、まず試すこと。**
 */
import { afterAll, beforeAll, beforeEach, describe, test } from 'vitest';
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
  allow,
  asAnonymous,
  asSiteAdmin,
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
  await maybeReseed(env, { clearStorage: true });
  // 既存ファイルを 1 つ置いておく。
  // **この upload が毎回 dirty の印を付けるので、Storage 側は実質
  // 毎回作り直しになる。** 13 件しかないので、その単純さを取る。
  await mutateAsAdmin(env, async (ctx) => {
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
    await deny(
      uploadBytes(ref(storage, filePath('existing.mp3')), audio()),
    );
  });

  test('クライアントからは削除できない（Functions が猶予期間後に削除／13.4）', async () => {
    // allow delete: if false。誤操作でファイルだけ先に消えると復元できない。
    const storage = asUser(env, UID.listAdmin).storage();
    await deny(deleteObject(ref(storage, filePath('existing.mp3'))));
  });

  test('サイト管理者でも削除できない', async () => {
    const storage = asSiteAdmin(env).storage();
    await deny(deleteObject(ref(storage, filePath('existing.mp3'))));
  });

  test('定義していないパスは読み書きとも拒否する', async () => {
    const storage = asSiteAdmin(env).storage();
    await deny(
      uploadBytes(ref(storage, 'somewhere/else.mp3'), audio()),
    );
    await deny(getDownloadURL(ref(storage, 'somewhere/else.mp3')));
  });

  test('未ログインでは読めない', async () => {
    const storage = asAnonymous(env).storage();
    await deny(getDownloadURL(ref(storage, filePath('existing.mp3'))));
  });
});

// ---------------------------------------------------------------------------
// メンバー判定を伴うルール
//
// storage.rules から Firestore の members を参照して判定する部分。
// エミュレータでも検証できる（冒頭の経緯を参照）。
// ---------------------------------------------------------------------------

describe('メンバー判定を伴うルール', () => {
  // **この確認が落ちたら、以降の「〜できない」はすべて信用できない。**
  //
  // storage.rules は `firestore.exists()` で Firestore を参照する。
  // この参照が失敗すると、ライブラリ側は握り潰して「見つからない」を返すため、
  // **メンバー判定が常に false になる**。つまり全員が拒否される。
  //
  // その状態では「Read Only はアップロードできない」「未参加者は読めない」
  // といった否定側の 4 件が**すべて緑になる**。土台が壊れているほど
  // 緑が増えるという、いちばん質の悪い出方になる（監査 第2回）。
  //
  // 実際に、ルールの上書き禁止をわざと壊した対照実験で、
  // 参照が生きていれば検出できた後退が、参照が壊れていると見逃された。
  //
  // そこで、否定側を動かす前に「参照が生きていること」を確かめて、
  // 生きていなければその場で理由を出して止める。
  beforeAll(async () => {
    const storage = asUser(env, UID.readOnly).storage();
    // データが無ければ作る（あればそのまま使う）。直後の upload が
    // dirty の印を付けるので、次のテストは作り直しから始まる。
    await maybeReseed(env);
    await mutateAsAdmin(env, async (ctx) => {
      await uploadBytes(
        ref(ctx.storage(), filePath('existing.mp3')),
        new Uint8Array([1, 2, 3]),
      );
    });

    try {
      await getDownloadURL(ref(storage, filePath('existing.mp3')));
    } catch (error) {
      throw new Error(
        [
          'メンバー判定（storage.rules の firestore.exists()）が働いていません。',
          'この状態では否定側のテストが「拒否された」ことだけを見て緑になり、',
          'ルールの後退を見逃します。以降の結果は信用できません。',
          '',
          'よくある原因: firebase-tools は NO_PROXY を見ずに 127.0.0.1 宛の',
          '通信までプロキシへ流します。プロキシがそれを拒否すると、',
          'Storage のルールランタイムから Firestore を引けなくなります。',
          '',
          `元の例外: ${error?.code ?? error}`,
        ].join('\n'),
      );
    }
  });

  test('Read Only も再生・ダウンロードできる（4.2）', async () => {
    const storage = asUser(env, UID.readOnly).storage();
    await allow(
      getDownloadURL(ref(storage, filePath('existing.mp3'))),
    );
  });

  test('サイト管理者はメンバー登録がなくても読める', async () => {
    const storage = asSiteAdmin(env).storage();
    await allow(
      getDownloadURL(ref(storage, filePath('existing.mp3'))),
    );
  });

  test('Super User はアップロードできる（4.2）', async () => {
    const storage = asUser(env, UID.superUser).storage();
    await allow(
      uploadBytes(ref(storage, filePath('new.mp3')), audio()),
    );
  });

  test('リスト管理者もアップロードできる', async () => {
    const storage = asUser(env, UID.listAdmin).storage();
    await allow(
      uploadBytes(ref(storage, filePath('admin.mp3')), audio()),
    );
  });

  test('Read Only はアップロードできない（4.2）', async () => {
    const storage = asUser(env, UID.readOnly).storage();
    await deny(
      uploadBytes(ref(storage, filePath('new.mp3')), audio()),
    );
  });

  test('未参加者は読めない（5.3）', async () => {
    const storage = asUser(env, UID.outsider).storage();
    await deny(getDownloadURL(ref(storage, filePath('existing.mp3'))));
  });

  test('未参加者はアップロードできない', async () => {
    const storage = asUser(env, UID.outsider).storage();
    await deny(
      uploadBytes(ref(storage, filePath('new.mp3')), audio()),
    );
  });

  test('参加していないリストにはアップロードできない', async () => {
    const storage = asUser(env, UID.superUser).storage();
    await deny(
      uploadBytes(ref(storage, 'lists/list-2/items/x/song.mp3'), audio()),
    );
  });
});
