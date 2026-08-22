/**
 * Cloud Functions の統合テスト（仕様書 5.1 / 5.2 / 3.3 / 4.5 / 13.4）
 *
 * エミュレータ上で実際に関数を呼び出し、Firestore の状態を確かめる。
 * 本番・検証プロジェクトには一切触れない。
 *
 * ```sh
 * # ターミナル 1
 * cd functions && npm run serve
 *
 * # ターミナル 2
 * cd functions && npm run test:integration
 * ```
 *
 * **実行するとエミュレータの Auth と Firestore を初期化する。**
 * 前回のサイト管理者が残っていると「最後の 1 人」の判定が変わるため。
 */
import { readFileSync, readdirSync } from 'node:fs';

const FN = 'http://127.0.0.1:5001/demo-musiclist/asia-northeast1';
const AUTH = 'http://127.0.0.1:9099';
const FS = 'http://127.0.0.1:8080/v1/projects/demo-musiclist/databases/(default)/documents';

const stamp = Date.now();
const results = [];
const check = (label, ok, detail = '') => {
  results.push(ok);
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? '  — ' + detail : ''}`);
};

async function signUp(tag) {
  const started = Date.now();
  const r = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=k`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: `${tag}-${stamp}@example.com`, password: 'password', returnSecureToken: true }),
  });
  const user = await r.json();

  // **メール確認済みにしてからトークンを取り直す。**
  // 呼び出し可能関数は email_verified を確かめる（仕様書 3.1／監査 S3）。
  // 確認していないアカウントのトークンでは、以降がすべて弾かれる。
  await fetch(
    `${AUTH}/identitytoolkit.googleapis.com/v1/projects/demo-musiclist/accounts:update`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer owner' },
    body: JSON.stringify({ localId: user.localId, emailVerified: true }),
  });

  const result = { ...user, ...(await refresh(user)) };
  spent.auth += Date.now() - started;
  spent.auths += 1;
  return result;
}

/** メール確認をしていない利用者（3.1 の検証用）。 */
async function signUpUnverified(tag) {
  const r = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=k`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: `${tag}-${stamp}@example.com`, password: 'password', returnSecureToken: true }),
  });
  return r.json();
}
async function refresh(user) {
  const r = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=k`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: user.email, password: 'password', returnSecureToken: true }),
  });
  return r.json();
}
/**
 * 1 回の呼び出しを諦めるまでの時間。
 *
 * **これは速さの基準ではなく、止まったまま戻らない事故の歯止め。**
 *
 * 以前は 45 秒だった。`scripts/check.mjs` が検証を並列に走らせるように
 * してから、**配信が 2 回、ここで止まった**（2026-08-08）。
 * エミュレータは JVM と Node の上で動き、同じ機械で `flutter test` と
 * `dart analyze` が同時に走ると割り当てが減る。実際、統合テストだけで
 * 280 秒だったものが 550 秒かかっていた。**関数は正しく動いていて、
 * ただ遅かっただけ**である。
 *
 * 遅いだけの実行を失敗にすると、「赤いのは環境のせい」に慣れてしまい、
 * 本物の後退を見逃す側に倒れる（docs/AUDIT-CHECKLIST.md 観点 2）。
 * **歯止めとしての役目は残したまま、余裕を持たせる。**
 */
const CALL_TIMEOUT_MS = 180000;

/**
 * どこで時間を使ったかの記録（最後にまとめて出す）。
 *
 * **「遅い」の調査は、まず内訳から（2026-08-09）。**
 * 関数の実行時間（エミュレータのログの Finished in Xms）を合計しても
 * 38 秒で、全体の 250 秒と大きく開いていた。残りがどこへ行ったかを
 * 出せるように、呼び出しと待ちの実測を常に取っておく。
 */
const spent = { call: 0, calls: [], wait: 0, waits: 0, auth: 0, auths: 0 };

/**
 * 接続が切れた 1 回だけで、実行全体を落とさないための再試行つき fetch。
 *
 * 並列検証で機械が混むと、エミュレータへの接続がまれにリセットされる
 * （ECONNRESET / UND_ERR_SOCKET ／メッセージは "fetch failed"）。それが
 * call() や waitUntil の述語の中で**未捕捉例外**になり、61 件のテストが
 * 1 件も走らないまま落ちた。**「遅いだけで落とさない」方針
 * （CALL_TIMEOUT_MS / waitUntil）の残っていた穴**である（監査 第4回）。
 *
 * 再試行するのは**接続系のエラーだけ**。時間切れ（AbortSignal）は
 * CALL_TIMEOUT_MS が受け持つ歯止めなので繰り返さないし、HTTP のエラー
 * 応答は例外にならず、関数側の本物の答えとしてそのまま呼び出し元へ返る。
 * 回数は 2 回・間隔は短く。長い待ちの面倒は waitUntil の仕事で、
 * ここで粘ると失敗の形が「時間切れ」から「原因不明の遅さ」に変わる。
 */
function isConnectionError(error) {
  if (error?.name === 'TimeoutError' || error?.name === 'AbortError') return false;
  const text = [error?.message, error?.code, error?.cause?.message, error?.cause?.code]
    .filter((part) => typeof part === 'string')
    .join(' ');
  return /ECONNRESET|ECONNREFUSED|EPIPE|UND_ERR|fetch failed|socket|syscall/i.test(text);
}
async function fetchRetry(url, options) {
  for (let attempt = 0; ; attempt += 1) {
    try {
      return await fetch(url, options);
    } catch (error) {
      if (attempt >= 2 || !isConnectionError(error)) throw error;
      await sleep(250 * (attempt + 1));
    }
  }
}

async function call(name, data, token) {
  const started = Date.now();
  const r = await fetchRetry(`${FN}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify({ data }), signal: AbortSignal.timeout(CALL_TIMEOUT_MS),
  });
  const result = { status: r.status, body: await r.json().catch(() => ({})) };
  const ms = Date.now() - started;
  spent.call += ms;
  spent.calls.push({ name, ms });
  return result;
}
// Firestore エミュレータの REST は Authorization ヘッダが要る。
const FS_HEADERS = { Authorization: 'Bearer owner' };
async function doc(path) {
  const r = await fetchRetry(`${FS}/${path}`, { headers: FS_HEADERS });
  return r.ok ? r.json() : null;
}
async function list(path) {
  const r = await fetchRetry(`${FS}/${path}`, { headers: FS_HEADERS });
  return r.ok ? (await r.json()).documents ?? [] : [];
}
/** ドキュメントを直接書く（トリガーを動かすため）。 */
async function setDoc(path, fields) {
  const r = await fetchRetry(`${FS}/${path}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', ...FS_HEADERS },
    body: JSON.stringify({ fields }),
  });
  return r.ok;
}
const sv = (d, k) => d?.fields?.[k]?.stringValue ?? d?.fields?.[k]?.integerValue ?? d?.fields?.[k]?.booleanValue;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * 条件が満たされるまで待つ。満たされたら true、時間切れなら false。
 *
 * **固定の待ち時間を書かない。** 以前は「6 秒待ってから確かめる」と
 * 書いていた。トリガーの初回起動はそれより遅いことがあり、
 * **エミュレータを起動した直後の 1 回目だけ落ちる**という出方をした。
 * 2 回目は通るので、原因を掴むまで環境のせいに見える。
 *
 * 待つのは「起きるはずのこと」だけにする。「起きないはずのこと」を
 * これで待つと、毎回かならず時間切れまで待たされる。
 *
 * **待ち時間の既定値は長めに取る。** ここを短くすると、機械が混んで
 * いるときに「時間切れ」ではなく**確かめたい条件が満たされなかった**
 * 形で落ちる。時間切れなら理由が分かるが、こちらは本物の後退と
 * 見分けがつかない。歯止めとしての役目は果たしつつ、混んでいるだけの
 * ときに落ちないところまで伸ばす（2026-08-08）。
 */
async function waitUntil(predicate, { timeoutMs = 180000, intervalMs = 500 } = {}) {
  const started = Date.now();
  const deadline = started + timeoutMs;
  try {
    for (;;) {
      if (await predicate()) return true;
      if (Date.now() >= deadline) return false;
      await sleep(intervalMs);
    }
  } finally {
    spent.wait += Date.now() - started;
    spent.waits += 1;
  }
}

/**
 * 始める前に、相手が「このテストの想定どおりのエミュレータ」か確かめる。
 *
 * **噛み合っていないまま走らせると、意味の無い PASS が混ざる。**
 * 実際に、エミュレータが別のプロジェクト ID で立ち上がっていたときに
 * 24 件が FAIL する一方で、「本人には届かない」「参加していない人には
 * 届かない」といった**何も起きていないだけの確認が PASS になった**。
 * 緑の表示は「確かめた」という意味でなければならない。
 *
 * よくある原因は `--project demo-musiclist` の付け忘れ。付け忘れると
 * `.firebaserc` の既定（検証環境）で立ち上がり、関数の URL も
 * カスタムクレームの付与先も変わってしまう。
 */
async function preflight() {
  const stop = (...lines) => {
    console.error('');
    for (const line of lines) console.error(line);
    console.error('');
    console.error('  エミュレータごと実行する（ウィンドウは 1 つで済みます）:');
    console.error('    cd functions');
    console.error('    npm run test:integration');
    console.error('');
    console.error('  すでに動いているエミュレータへ繋ぐ場合は、そちらの窓で');
    console.error('  npm run serve が動いたままか確かめてください。');
    console.error('');
    process.exit(1);
  };

  // 1. 関数エミュレータが、このプロジェクト ID で関数を配っているか。
  //    トークンを付けずに呼ぶので、正しければ「未認証」が返る。
  //    404 は「そんな関数は無い」。原因は 2 通りある。
  //
  //    **すぐには諦めない。** エミュレータは「All emulators ready!」を
  //    出したあとで関数を 1 つずつ組み立てる。自分で起動して続けて
  //    実行する形（npm run test:integration）では、まだ配られていない
  //    時点でここへ来る。**用意できるまで待ってから判断する。**
  //    それでも来なければ、下の 2 つの原因を案内する。
  const READY_TIMEOUT_MS = 120000;
  let res = null;
  let lastError = null;
  const appeared = await waitUntil(async () => {
    try {
      res = await call('submitListRequest', {});
      lastError = null;
    } catch (error) {
      res = null;
      lastError = error;
      return false;
    }
    return res.status !== 404;
  }, { timeoutMs: READY_TIMEOUT_MS, intervalMs: 1000 });

  if (!appeared && lastError) {
    stop(`関数エミュレータへ接続できません（${FN}）。`, `  ${lastError.message}`);
  }
  if (!appeared) {
    // **原因を 1 つに決めつけない（2026-08-07）。**
    // 以前はここで「プロジェクト ID が違います」とだけ出していた。
    // 実際の原因は「関数が 1 つも読み込まれていない」ほうで、
    // 読み込みに失敗しても All emulators ready! は出るため、
    // 起動したウィンドウを見ない限り気づけない。
    // 誤った原因を断定すると、そこから先の調査が全部無駄になる。
    stop(
      '関数エミュレータは動いていますが、submitListRequest が見つかりません。',
      '',
      '  考えられる原因は 2 つです。起動したウィンドウの出力を見てください。',
      '',
      '  【1】関数が 1 つも読み込まれていない',
      '     次の 1 行が出ていませんか。',
      '       Failed to load function definition from source:',
      '       Cannot determine backend specification. Timeout after 10000.',
      '     出ていたら、読み込みが制限時間を超えています。',
      '     npm run serve は待ち時間を 120 秒に延ばしてあります。',
      '     それでも出るなら、まず npm run build が通るか確かめてください。',
      '',
      '  【2】プロジェクト ID が違う',
      '     このテストは demo-musiclist を相手にしています。',
      '     --project demo-musiclist を付けずに起動すると、.firebaserc の',
      '     既定（検証環境 music-storage-dev）で立ち上がり、噛み合いません。',
      '     npm run serve を使えば付け忘れは起きません。'
    );
  }

  // 2. Auth エミュレータが同じプロジェクトか。
  //    サイト管理者のクレームを付けるのに使う。
  const auth = await fetch(
    `${AUTH}/emulator/v1/projects/demo-musiclist/config`
  ).catch(() => null);
  if (!auth || !auth.ok) {
    stop(
      'Auth エミュレータが demo-musiclist で動いていません。',
      `  応答: ${auth ? auth.status : '接続できません'}`
    );
  }
}

await preflight();

// --- ウォームアップ：全関数のワーカーを同時に立ち上げる ---
//
// **各関数は、最初の 1 回だけ呼び出しに約 5 秒かかる（2026-08-09 実測）。**
// エミュレータが関数ごとに、最初の呼び出しでワーカー（node プロセス）を
// 立ち上げるため。呼び出し 51 回の内訳を取ると、関数の数と同じ 19 回
// だけがきれいに 5 秒前後に固まり、残り 29 回は 0.3 秒未満だった。
// テストの流れの中で直列に払うと、これだけで約 95 秒になる。
//
// そこで先に、トークン無しの呼び出しを全関数へ**同時に**投げて、
// 立ち上げを重ねて払う。返事は「未認証」でよい（ワーカーは立ち上がる）。
// 関数の一覧は src/callable から読む。手で並べると、増えた関数だけ
// 5 秒のまま残って、原因に気づきにくい。
{
  const started = Date.now();
  const src = new URL('../src/callable/', import.meta.url);
  // 空白は `\s` で受ける。`export const NAME =` の直後で改行される
  // 書き方だと、1 行前提の正規表現では新しい関数を拾えず、その関数だけ
  // 初回 5 秒のまま残る（setup_doc.test.ts と同じ穴／監査 第4回）。
  const names = readdirSync(src).flatMap((file) =>
    [...readFileSync(new URL(file, src), 'utf8')
      .matchAll(/export\s+const\s+(\w+)\s*=\s*onCall\b/g)].map((m) => m[1]));
  await Promise.all(names.map((name) =>
    fetch(`${FN}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{"data":{}}',
      signal: AbortSignal.timeout(CALL_TIMEOUT_MS),
    }).catch(() => null)));
  console.log(`    ウォームアップ: ${names.length} 関数 / ${Math.round((Date.now() - started) / 1000)} 秒`);
}

// 実行のたびに初期化する。前回のサイト管理者が残っていると
// 「最後の 1 人」の判定が変わってしまうため。
//
// **固定の待ち時間を置かない（waitUntil の説明を参照）。**
// 消えたことを実際に見る。空の一覧が返れば消えている。
await fetch(`${AUTH}/emulator/v1/projects/demo-musiclist/accounts`, { method: 'DELETE' });
await fetch('http://127.0.0.1:8080/emulator/v1/projects/demo-musiclist/databases/(default)/documents', { method: 'DELETE' });
await waitUntil(async () => (await list('users')).length === 0);

// --- 準備：サイト管理者を作る ---
let siteAdmin = await signUp('sa');
const applicant = await signUp('app');
const invitee = await signUp('inv');

// 最初のサイト管理者は手作業で付与する（仕様書 4.4）。ここでは Auth エミュレータ経由。
const claimRes = await fetch(
  `${AUTH}/identitytoolkit.googleapis.com/v1/projects/demo-musiclist/accounts:update`, {
  method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer owner' },
  body: JSON.stringify({ localId: siteAdmin.localId, customAttributes: JSON.stringify({ siteAdmin: true }) }),
});
if (!claimRes.ok) {
  console.error('');
  console.error(`サイト管理者のクレームを付けられませんでした（${claimRes.status}）。`);
  console.error('  以降の確認はすべて意味を持たないので、ここで止めます。');
  console.error('');
  process.exit(1);
}
siteAdmin = { ...siteAdmin, ...(await refresh(siteAdmin)) };

// --- リスト作成申請 → 承認（5.1） ---
let r = await call('submitListRequest',
  { listName: `バンド練習${stamp}`, purpose: '練習', estimatedTrackCount: 20, expectedUserCount: 4 },
  applicant.idToken);
const requestId = r.body?.result?.requestId;
check('申請できる', !!requestId);

r = await call('approveListRequest', { requestId }, siteAdmin.idToken);
const listId = r.body?.result?.listId;
check('サイト管理者は承認できる', !!listId, JSON.stringify(r.body).slice(0, 120));

// **リストが作れなければ、以降はすべて土台が無い。**
// そのまま走らせると `lists/undefined/...` を相手にすることになり、
// 「何も起きなかった」ことを「期待どおり起きなかった」と読み違える。
if (!listId) {
  console.error('');
  console.error('リストを作れなかったため、ここで止めます。');
  console.error('  以降の確認は土台が無く、結果を信用できません。');
  console.error('');
  process.exit(1);
}

{
  const l = await doc(`lists/${listId}`);
  check('リストが作られる', !!l && sv(l, 'name') === `バンド練習${stamp}`);
  const stats = await doc(`lists/${listId}/meta/stats`);
  check('stats が初期化される（nextSeq=1）', sv(stats, 'nextSeq') === '1', `nextSeq=${sv(stats,'nextSeq')} quota=${sv(stats,'quotaBytes')}`);
  const member = await doc(`lists/${listId}/members/${applicant.localId}`);
  check('申請者がリスト管理者になる', sv(member, 'role') === 'listAdmin');

  // **固定の待ち時間を置かない（waitUntil の説明を参照）。**
  // 通知は onCall の中で書かれるので普通は即座に見えるが、
  // 混んでいる機械では遅れる。届くまで待つ。
  const approvalNotified = async () =>
    (await list(`users/${applicant.localId}/notifications`))
      .some((n) => sv(n, 'type') === 'requestApproved');
  await waitUntil(approvalNotified);
  check('承認が申請者へ通知される', await approvalNotified());

  // --- 二重承認はできない ---
  r = await call('approveListRequest', { requestId }, siteAdmin.idToken);
  check('同じ申請は二度承認できない', r.body?.error?.status === 'FAILED_PRECONDITION',
        r.body?.error?.status);

  // --- 共有リンク（3.3） ---
  const applicantFresh = await refresh(applicant);
  r = await call('createShareLink', { listId }, applicantFresh.idToken);
  const linkId = r.body?.result?.linkId;
  check('リスト管理者は共有リンクを発行できる', !!linkId, `len=${linkId?.length ?? 0}`);

  // **リンクは役割を持たない（3.3）。** 発行したドキュメントに
  // role を書いていないことを、実物を見て確かめる。
  // ここに役割があると、URL を渡すこと自体が権限を配ることになる。
  const linkDoc = await doc(`shareLinks/${linkId}`);
  // **先に「読めている」ことを確かめる。** 読めていないときも
  // role は undefined になり、何も確かめずに緑になってしまう。
  check('発行したリンクを読める（次の確認の土台）', sv(linkDoc, 'listId') === listId,
        String(sv(linkDoc, 'listId')));
  check('発行したリンクは役割を持たない', sv(linkDoc, 'role') === undefined,
        String(sv(linkDoc, 'role')));

  // 役割を渡しても、リンクには載らない。
  r = await call('createShareLink', { listId, role: 'listAdmin' }, applicantFresh.idToken);
  const ignored = r.body?.result?.linkId;
  check('役割を渡しても発行は通る（無視される）', r.status === 200, r.body?.error?.status);
  const ignoredDoc = await doc(`shareLinks/${ignored}`);
  check('渡した役割はリンクに載らない',
        sv(ignoredDoc, 'listId') === listId && sv(ignoredDoc, 'role') === undefined,
        String(sv(ignoredDoc, 'role')));

  r = await call('acceptShareLink', { linkId, mode: 'join' }, invitee.idToken);
  check('リンクから参加できる', r.body?.result?.listId === listId, JSON.stringify(r.body).slice(0, 120));

  const im = await doc(`lists/${listId}/members/${invitee.localId}`);
  check('参加すると Super User で入る（INITIAL_JOIN_ROLE）', sv(im, 'role') === 'superUser',
        sv(im, 'role'));

  // 役割を渡して作ったリンクでも、結果は変わらない。
  // ここで listAdmin が付いていたら、リンクからリスト管理者を作れてしまう。
  // **リンクに何を書いても、役割はサーバー側の 1 か所が決める**（3.3）。
  const ignoredUser = await signUp('ign');
  r = await call('acceptShareLink', { linkId: ignored, mode: 'join' }, ignoredUser.idToken);
  check('渡した役割は効かない', r.status === 200, r.body?.error?.status);
  const ignoredMember = await doc(`lists/${listId}/members/${ignoredUser.localId}`);
  check('リンクに書いた役割（listAdmin）は使われない',
        sv(ignoredMember, 'role') === 'superUser', sv(ignoredMember, 'role'));

  // --- 何度でも・複数人（3.3） ---
  // **ここが以前と逆になっている。** 以前は「二度目は使えない」ことを
  // 確かめていた。いまは「二度目も使える」ことを確かめる。
  const second = await signUp('inv2');
  r = await call('acceptShareLink', { linkId, mode: 'join' }, second.idToken);
  check('同じリンクを別の人がもう一度使える', r.body?.result?.listId === listId,
        r.body?.error?.message ?? r.body?.error?.status);

  const im2 = await doc(`lists/${listId}/members/${second.localId}`);
  check('2 人目も Super User で入る', sv(im2, 'role') === 'superUser', sv(im2, 'role'));

  // 同じ人が二度開いても弾かれない。
  r = await call('acceptShareLink', { linkId, mode: 'join' }, second.idToken);
  check('同じ人が二度開いても通る', r.status === 200, r.body?.error?.status);

  // --- 参加せずに見るだけ（3.3） ---
  const viewer = await signUp('viewer');
  r = await call('acceptShareLink', { linkId, mode: 'view' }, viewer.idToken);
  check('参加せずに見るを選べる', r.body?.result?.joined === false,
        JSON.stringify(r.body?.result));

  const vm = await doc(`lists/${listId}/members/${viewer.localId}`);
  check('見るだけの人はメンバーにならない', vm === null || vm.fields === undefined,
        JSON.stringify(vm?.fields ?? null).slice(0, 80));

  const vv = await doc(`lists/${listId}/viewers/${viewer.localId}`);
  check('見るだけの人は viewers に入る', sv(vv, 'uid') === viewer.localId, sv(vv, 'uid'));

  // 見るだけを選んだあとで参加できる。
  r = await call('acceptShareLink', { linkId, mode: 'join' }, viewer.idToken);
  check('あとから参加できる', r.body?.result?.joined === true,
        JSON.stringify(r.body?.result));

  // --- メンバー数の集計（13.4） ---
  //
  // ここまでに参加したのは次の人たち。
  //
  //   1. applicant    … リストを作った人（listAdmin）
  //   2. invitee      … リンクから参加
  //   3. ignoredUser  … 役割を渡して作ったリンクから参加（役割は効かない／3.3）
  //   4. second       … 同じリンクから参加（複数人が使える／3.3）
  //   5. viewer       … 見るだけを選んだあと、参加に切り替えた（3.3）
  //
  // **見るだけのままの人は数に入らない。** viewer は途中で参加へ
  // 切り替えたので入っている。切り替えなければ 4 のままになる。
  //
  // **数を書き写さない。** 以前はここに人数を直接書き、上の一覧に
  // 「人を増やしたらこの数も直すこと」と添えていた。増やしたときに
  // 直されず、統合テストを実行できない環境だったため、赤いまま
  // 本番まで配信された（2026-08-08 に判明）。
  // 注意書きは仕組みではないので、members を実際に数えて比べる。
  // memberCount は onMemberWritten が後から更新する。追いつくまで待つ。
  const memberDocs = await list(`lists/${listId}/members`);
  await waitUntil(async () =>
    sv(await doc(`lists/${listId}`), 'memberCount') === String(memberDocs.length));
  const l2 = await doc(`lists/${listId}`);
  // **先に「読めている」ことを確かめる。** members が読めていないと 0 件になり、
  // memberCount も 0 なら一致してしまう（前提が崩れると自動的に通る形）。
  check('members を読める（次の確認の土台）', memberDocs.length > 0,
        `members=${memberDocs.length}`);
  check('memberCount が更新される',
        sv(l2, 'memberCount') === String(memberDocs.length),
        `memberCount=${sv(l2,'memberCount')} members=${memberDocs.length} adminCount=${sv(l2,'adminCount')}`);
  check('adminCount は増えない（リンクでは付与できない）', sv(l2, 'adminCount') === '1',
        `adminCount=${sv(l2,'adminCount')}`);

  // --- 最後のサイト管理者は降格できない（4.5） ---
  r = await call('revokeSiteAdmin', { uid: siteAdmin.localId }, siteAdmin.idToken);
  check('最後のサイト管理者は降格できない', r.body?.error?.status === 'FAILED_PRECONDITION',
        r.body?.error?.message?.slice(0, 40) ?? r.body?.error?.status);

  // --- 参加申請（5.2） ---
  const joiner = await signUp('join');
  r = await call('submitJoinRequest', { listId }, joiner.idToken);
  check('参加を申請できる', r.status === 200, JSON.stringify(r.body).slice(0, 100));

  r = await call('approveJoinRequest', { listId, uid: joiner.localId, role: 'listAdmin' }, applicantFresh.idToken);
  check('承認でリスト管理者は付与できない', r.body?.error?.status === 'INVALID_ARGUMENT', r.body?.error?.status);

  r = await call('approveJoinRequest', { listId, uid: joiner.localId, role: 'readOnly' }, applicantFresh.idToken);
  check('参加申請を承認できる', r.status === 200, JSON.stringify(r.body).slice(0, 100));

  const jm = await doc(`lists/${listId}/members/${joiner.localId}`);
  check('承認した役割で登録される', sv(jm, 'role') === 'readOnly', sv(jm, 'role'));
}

// ---------------------------------------------------------------------------
// 2026-08-06 の監査 S11 で追加。
//
// 22 本の関数のうち 14 本がテスト 0 件だった。とくに壊れても気づけず、
// かつ復旧できない処理から先に埋める。
// ---------------------------------------------------------------------------

{
  // 前のブロックのローカル変数は見えないので取り直す。
  const applicantFresh = await refresh(applicant);
  const joiner = { localId: (await call('listSiteUsers', {}, siteAdmin.idToken))
    .body?.result?.users?.find((u) => u.email?.startsWith('join-'))?.uid };

  // --- メール確認が済むまで呼べない（3.1／監査 S3） ---
  const unverified = await signUpUnverified('unv');
  let r = await call('submitListRequest',
    { listName: `未確認${stamp}`, purpose: 'x', estimatedTrackCount: 1, expectedUserCount: 1 },
    unverified.idToken);
  check('メール未確認では申請できない（3.1）',
        r.body?.error?.status === 'PERMISSION_DENIED', r.body?.error?.status);

  // --- リスト作成申請の却下（5.2.1） ---
  const rejectApplicant = await signUp('rej');
  r = await call('submitListRequest',
    { listName: `却下される${stamp}`, purpose: 'x', estimatedTrackCount: 1, expectedUserCount: 1 },
    rejectApplicant.idToken);
  const rejectId = r.body?.result?.requestId;
  check('却下用の申請を作れる', !!rejectId);

  // **先に、予約が実在することを見る。** 予約がそもそも作られていないと、
  // 下の「解放される」は何も無かっただけで緑になる（前提が崩れると
  // 自動的に通る形／監査 第4回）。
  const namePath = `listNames/${`却下される${stamp}`.toLowerCase()}`;
  const reservedDoc = await doc(namePath);
  check('申請で名前が予約される（次の確認の土台）',
        reservedDoc !== null && reservedDoc.fields !== undefined,
        reservedDoc === null ? '予約が無い' : '予約あり');

  r = await call('rejectListRequest', { requestId: rejectId, reason: '重複' }, siteAdmin.idToken);
  check('リスト作成申請を却下できる（5.2.1）', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  // **却下したら名前の予約を解放すること。** 解放し忘れると、その名前が
  // 永久に使えなくなる（監査で無検証だった箇所）。
  const nameDoc = await doc(namePath);
  check('却下で名前の予約が解放される（13.3）', nameDoc === null, nameDoc ? '残っている' : '解放済み');

  r = await call('rejectListRequest', { requestId: rejectId, reason: '再' }, siteAdmin.idToken);
  check('同じ申請は二度却下できない',
        r.body?.error?.status === 'FAILED_PRECONDITION', r.body?.error?.status);

  // --- 参加申請の却下（5.2.1） ---
  const rejoiner = await signUp('rjn');
  await call('submitJoinRequest', { listId }, rejoiner.idToken);
  r = await call('rejectJoinRequest', { listId, uid: rejoiner.localId }, applicantFresh.idToken);
  check('参加申請を却下できる', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  r = await call('rejectJoinRequest', { listId, uid: rejoiner.localId }, applicantFresh.idToken);
  check('処理済みの参加申請は却下できない（監査 低-2）',
        r.body?.error?.status === 'FAILED_PRECONDITION', r.body?.error?.status);

  // --- 参加申請の連打で通知が積み上がらない（監査 S13） ---
  const spammer = await signUp('spam');
  await call('submitJoinRequest', { listId }, spammer.idToken);
  r = await call('submitJoinRequest', { listId }, spammer.idToken);
  check('審査中なら再申請しても素通りしない（S13）',
        r.body?.result?.alreadyPending === true, JSON.stringify(r.body?.result));

  // --- リンクの取消（3.3） ---
  // **期限が無いので、これが唯一の止める手段。**
  r = await call('createShareLink', { listId }, applicantFresh.idToken);
  const revokeToken = r.body?.result?.linkId;
  check('取消用のリンクを発行できる', !!revokeToken);

  r = await call('revokeShareLink', { linkId: revokeToken }, applicantFresh.idToken);
  check('リンクを取り消せる（3.3）', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  // **符号まで見る。** `status !== 200` だけだと、引数の間違いや
  // 未認証などの**別の理由で弾かれても緑**になる。取り消しの判断は
  // failed-precondition（membership.ts の shareLinkRevoked）と決まって
  // いるので、そこまで確かめる（監査 第4回）。
  const revoked = await signUp('rvk');
  r = await call('acceptShareLink', { linkId: revokeToken, mode: 'join' }, revoked.idToken);
  check('取り消したリンクは使えない', r.body?.error?.status === 'FAILED_PRECONDITION',
        r.body?.error?.status ?? String(r.status));

  r = await call('acceptShareLink', { linkId: revokeToken, mode: 'view' }, revoked.idToken);
  check('取り消したリンクは閲覧にも使えない', r.body?.error?.status === 'FAILED_PRECONDITION',
        r.body?.error?.status ?? String(r.status));

  // --- 容量上限の変更（7.2） ---
  r = await call('setListQuota', { listId, quotaBytes: 2 * 1024 * 1024 * 1024 }, siteAdmin.idToken);
  check('サイト管理者は容量上限を変えられる（7.2）', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  const stats = await doc(`lists/${listId}/meta/stats`);
  check('上限が反映される', sv(stats, 'quotaBytes') === '2147483648', sv(stats, 'quotaBytes'));

  r = await call('setListQuota', { listId, quotaBytes: 1024 }, applicantFresh.idToken);
  check('リスト管理者は容量上限を変えられない',
        r.body?.error?.status === 'PERMISSION_DENIED', r.body?.error?.status);

  // --- サイト管理者の一覧と昇格（11.1 / 4.3） ---
  r = await call('listSiteUsers', {}, siteAdmin.idToken);
  check('サイト管理者は利用者を一覧できる（11.1）',
        Array.isArray(r.body?.result?.users), typeof r.body?.result?.users);

  r = await call('listSiteUsers', {}, applicantFresh.idToken);
  check('一般利用者は一覧できない',
        r.body?.error?.status === 'PERMISSION_DENIED', r.body?.error?.status);

  const second = await signUp('sa2');
  r = await call('grantSiteAdmin', { uid: second.localId }, siteAdmin.idToken);
  check('サイト管理者を増やせる（4.3）', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  // 2 人になったので降格できるようになる（4.5）。
  r = await call('revokeSiteAdmin', { uid: second.localId }, siteAdmin.idToken);
  check('2 人いれば降格できる（4.5）', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  // --- 無効化した管理者は「最後の 1 人」の人数に入らない（4.5／監査 第4回） ---
  //
  // 修正前は user.disabled を見ずに数えていたため、管理者 2 人のうち
  // 1 人を無効化したあとでも「2 人いる」と数え、残る 1 人の降格が通って
  // **ログインできるサイト管理者が 0 人**になる経路があった。
  const disabledAdmin = await signUp('sa3');
  r = await call('grantSiteAdmin', { uid: disabledAdmin.localId }, siteAdmin.idToken);
  check('2 人目のサイト管理者を作れる（次の確認の土台）', r.status === 200,
        JSON.stringify(r.body).slice(0, 80));

  r = await call('disableSiteUser', { uid: disabledAdmin.localId }, siteAdmin.idToken);
  check('サイト管理者を無効化できる（次の確認の土台）', r.status === 200,
        JSON.stringify(r.body).slice(0, 80));

  r = await call('revokeSiteAdmin', { uid: siteAdmin.localId }, siteAdmin.idToken);
  check('無効化済みを除けば最後の 1 人なので、残る 1 人は降格できない（4.5）',
        r.body?.error?.status === 'FAILED_PRECONDITION', r.body?.error?.status);

  // 後片付け。有効に戻せば 2 人なので、降格して元の 1 人に戻す。
  r = await call('enableSiteUser', { uid: disabledAdmin.localId }, siteAdmin.idToken);
  check('無効化した管理者を有効に戻せる（後片付け）', r.status === 200,
        JSON.stringify(r.body).slice(0, 80));
  r = await call('revokeSiteAdmin', { uid: disabledAdmin.localId }, siteAdmin.idToken);
  check('有効に戻れば数に入り、降格できる（後片付け）', r.status === 200,
        JSON.stringify(r.body).slice(0, 80));

  // --- ユーザーの追加・無効化・削除（11.1） ---
  //
  // **消す・止める操作は、通しで一度は動かす。** 判断そのものは
  // functions/test/user_admin.test.ts が確かめているが、Auth と
  // Firestore を実際に書き換えるところは、ここでしか確かめられない。
  r = await call('createSiteUser', {
    email: `made-${stamp}@example.com`,
    password: 'password',
    displayName: `作られた人${stamp}`,
  }, siteAdmin.idToken);
  const madeUid = r.body?.result?.uid;
  check('サイト管理者はユーザーを追加できる（11.1）', r.status === 200 && !!madeUid,
        JSON.stringify(r.body).slice(0, 100));

  const madeUser = await doc(`users/${madeUid}`);
  check('追加したユーザーの表示名が入る', sv(madeUser, 'displayName') === `作られた人${stamp}`,
        sv(madeUser, 'displayName'));

  // **メールアドレスを誰でも読める側に置かない（2026-08-11）。**
  // `users/{uid}` はログイン済みなら誰でも ID 指定で読め、その取得は
  // ドキュメント全体を返す。ここに残っていると、**全会員のメールアドレスが
  // 他の利用者から引ける**。
  check('追加したユーザーの users にメールアドレスが入らない',
        sv(madeUser, 'email') === undefined, String(sv(madeUser, 'email')));

  const madePrivate = await doc(`users/${madeUid}/private/state`);
  check('メールアドレスは本人だけの場所（private/state）に入る',
        sv(madePrivate, 'email') === `made-${stamp}@example.com`,
        String(sv(madePrivate, 'email')));

  r = await call('createSiteUser', {
    email: `made-${stamp}@example.com`,
    password: 'password',
    displayName: '重複',
  }, siteAdmin.idToken);
  check('同じメールアドレスでは追加できない', r.body?.error?.status === 'ALREADY_EXISTS',
        r.body?.error?.status);

  r = await call('createSiteUser', {
    email: `short-${stamp}@example.com`, password: '12345', displayName: '短い',
  }, siteAdmin.idToken);
  check('短いパスワードは弾く', r.body?.error?.status === 'INVALID_ARGUMENT',
        r.body?.error?.status);

  r = await call('createSiteUser', {
    email: 'not-an-email', password: 'password', displayName: '形が違う',
  }, siteAdmin.idToken);
  check('メールアドレスの形が違えば弾く', r.body?.error?.status === 'INVALID_ARGUMENT',
        r.body?.error?.status);

  r = await call('disableSiteUser', { uid: madeUid }, siteAdmin.idToken);
  check('ユーザーを無効にできる（11.1）', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  const disabledUser = await doc(`users/${madeUid}`);
  check('無効にしても users は残る（データを消さない）', disabledUser !== null,
        disabledUser === null ? '消えている' : '残っている');

  r = await call('enableSiteUser', { uid: madeUid }, siteAdmin.idToken);
  check('無効にしたユーザーを有効に戻せる', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  r = await call('disableSiteUser', { uid: siteAdmin.localId }, siteAdmin.idToken);
  check('自分自身は無効にできない', r.body?.error?.status === 'FAILED_PRECONDITION',
        r.body?.error?.status);

  r = await call('deleteSiteUser', { uid: siteAdmin.localId }, siteAdmin.idToken);
  check('自分自身は削除できない', r.body?.error?.status === 'FAILED_PRECONDITION',
        r.body?.error?.status);

  // **ログイン済み・メール確認済みの一般利用者で試す。**
  // このブロックの joiner はトークンを持たない形で作り直されているため、
  // それを使うと「未ログイン」で弾かれ、確かめたい「サイト管理者では
  // ないから弾かれる」を通り越してしまう（2026-08-09 に実際にやった）。
  const ordinary = await signUp('ord');
  r = await call('deleteSiteUser', { uid: madeUid }, ordinary.idToken);
  check('サイト管理者でなければ削除できない', r.body?.error?.status === 'PERMISSION_DENIED',
        r.body?.error?.status);

  r = await call('disableSiteUser', { uid: madeUid }, ordinary.idToken);
  check('サイト管理者でなければ無効にもできない', r.body?.error?.status === 'PERMISSION_DENIED',
        r.body?.error?.status);

  // **通知を 1 件仕込んでから消す（2026-08-15）。**
  // 通知は users/{uid} の下にぶら下がるので、親を消しても残る。
  // 残ると、**到達できない場所に誰宛てか分からない通知が積まれたまま**になる。
  await setDoc(`users/${madeUid}/notifications/n1`, {
    type: { stringValue: 'itemAdded' },
    read: { booleanValue: false },
  });

  r = await call('deleteSiteUser', { uid: madeUid }, siteAdmin.idToken);
  check('ユーザーを削除できる（11.1）', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  {
    const left = await list(`users/${madeUid}/notifications`);
    check('削除すると通知も残らない（孤児データ）', left.length === 0,
          `${left.length} 件残っている`);
  }

  const deletedUser = await doc(`users/${madeUid}`);
  check('削除すると users も消える', deletedUser === null || deletedUser.fields === undefined,
        deletedUser === null ? '消えている' : '残っている');

  // **本人だけの控えも消えること。** サブコレクションは親を消しても
  // 残るため、明示的に消さないと**削除したはずの人のメールアドレスが
  // 親の無い孤児として残り続ける**。
  const deletedPrivate = await doc(`users/${madeUid}/private/state`);
  check('削除すると本人だけの控え（private/state）も消える',
        deletedPrivate === null || deletedPrivate.fields === undefined,
        deletedPrivate === null ? '消えている' : '残っている');

  // --- 管理者不在リストへの指名（5.6） ---
  r = await call('assignListAdmin', { listId, uid: joiner.localId }, siteAdmin.idToken);
  check('サイト管理者はリスト管理者を指名できる（5.6）', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  const promoted = await doc(`lists/${listId}/members/${joiner.localId}`);
  check('指名で listAdmin になる', sv(promoted, 'role') === 'listAdmin', sv(promoted, 'role'));

  // **uid の項目も見る（site_management.ts の「必ず uid を入れる」の見張り）。**
  // 入れ忘れると、指名された管理者はホームにこのリストが出ず、
  // 退会してもメンバーから外れない。role だけの検査では、この入れ忘れが
  // 再発しても緑のままだった（監査 第4回）。
  check('指名した行に uid が入る', sv(promoted, 'uid') === joiner.localId,
        String(sv(promoted, 'uid')));

  // --- サイト管理者がメンバーに加える（5.7） ---
  //
  // **役割を渡せること・渡せない役割を断ること・二重に入れないこと**の3点。
  // 「200 が返る」だけでは、役割が無視されていても緑になる。
  const added = await signUp('added');
  r = await call('addListMember',
                 { listId, uid: added.localId, role: 'readOnly' },
                 siteAdmin.idToken);
  check('サイト管理者はメンバーに加えられる（5.7）', r.status === 200,
        JSON.stringify(r.body).slice(0, 80));

  const addedMember = await doc(`lists/${listId}/members/${added.localId}`);
  check('渡した役割で入る（readOnly）', sv(addedMember, 'role') === 'readOnly',
        String(sv(addedMember, 'role')));
  check('加えた行にも uid が入る', sv(addedMember, 'uid') === added.localId,
        String(sv(addedMember, 'uid')));

  // **リスト管理者にはできない。** それは assignListAdmin の仕事で、
  // ここから付けられると「管理者不在」の判定を回り込める。
  r = await call('addListMember',
                 { listId, uid: added.localId, role: 'listAdmin' },
                 siteAdmin.idToken);
  check('listAdmin は付けられない（5.7）',
        r.body?.error?.details?.code === 'roleNotAllowed',
        JSON.stringify(r.body?.error?.details ?? r.body).slice(0, 80));

  // **すでにメンバーなら断る。** 黙って上書きすると、リスト管理者が
  // 決めた役割をサイト管理者が知らずに巻き戻す（5.4）。
  r = await call('addListMember',
                 { listId, uid: added.localId, role: 'superUser' },
                 siteAdmin.idToken);
  check('すでにメンバーなら断る（5.7）',
        r.body?.error?.details?.code === 'alreadyMember',
        JSON.stringify(r.body?.error?.details ?? r.body).slice(0, 80));

  const unchanged = await doc(`lists/${listId}/members/${added.localId}`);
  check('断ったとき役割は変わっていない', sv(unchanged, 'role') === 'readOnly',
        String(sv(unchanged, 'role')));

  // **サイト管理者でなければ呼べない。**
  // **トークンを持つ変数で呼ぶ。** この場面の `joiner` は listSiteUsers から
  // 作り直した `{localId}` だけの入れ物で、`idToken` を持たない。それで呼ぶと
  // 返るのは signInRequired（未ログイン）で、**確かめたい siteAdminOnly を
  // 一度も通らずに緑になる**（docs/AUDIT-CHECKLIST.md 観点4・同じ罠を再度踏んだ）。
  r = await call('addListMember',
                 { listId, uid: siteAdmin.localId, role: 'readOnly' },
                 added.idToken);
  check('サイト管理者でなければ加えられない（5.7）',
        r.body?.error?.details?.code === 'siteAdminOnly',
        JSON.stringify(r.body?.error?.details ?? r.body).slice(0, 80));

  // --- 退会（3.5） ---
  //
  // **参加が成立したことを確かめてから退会させる。** 申請か承認が失敗して
  // いると、下の「メンバーから消える」は最初から居なかっただけの
  // null 比較で空振り合格する（監査 第4回）。
  const leaver = await signUp('lv');
  r = await call('submitJoinRequest', { listId }, leaver.idToken);
  check('退会する人の参加申請が通る（次の確認の土台）', r.status === 200,
        JSON.stringify(r.body).slice(0, 80));
  r = await call('approveJoinRequest', { listId, uid: leaver.localId, role: 'readOnly' }, applicantFresh.idToken);
  check('退会する人の承認が通る（次の確認の土台）', r.status === 200,
        JSON.stringify(r.body).slice(0, 80));
  const joinedMember = await doc(`lists/${listId}/members/${leaver.localId}`);
  check('退会する人がメンバーに居る（次の確認の土台）',
        sv(joinedMember, 'uid') === leaver.localId, String(sv(joinedMember, 'uid')));

  // **本人だけの控えを作っておく。** 無ければ「消えた」の確認が、
  // 最初から無かっただけで空振り合格する（監査 第4回と同じ罠）。
  const leaverPrivateWritten = await setDoc(
    `users/${leaver.localId}/private/state`,
    { email: { stringValue: `lv-${stamp}@example.com` } });
  check('退会する人の private/state を作れる（次の確認の土台）',
        leaverPrivateWritten);

  r = await call('withdrawAccount', {}, leaver.idToken);
  check('退会できる（3.5）', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  // **退会したら本人だけの控えは消す（2026-08-11）。** Auth のアカウントごと
  // 消えるので、本人を含めて誰も二度と読まない。読まれないメールアドレスを
  // 持ち続ける理由が無い。
  const leftPrivate = await doc(`users/${leaver.localId}/private/state`);
  check('退会で private/state が消える（メールアドレスを残さない）',
        leftPrivate === null || leftPrivate.fields === undefined,
        leftPrivate === null ? '消えている' : '残っている');

  // **退会したらメンバーから消えること。** collectionGroup のクエリが
  // 成立しておらず、失敗も握り潰されていた（監査 S14）。
  const leftMember = await doc(`lists/${listId}/members/${leaver.localId}`);
  check('退会でメンバーから消える（監査 S14）', leftMember === null,
        leftMember ? '残っている' : '消えている');

  const leftUser = await doc(`users/${leaver.localId}`);
  check('退会しても users は残る（3.5）',
        leftUser !== null && sv(leftUser, 'isWithdrawn') === true,
        String(sv(leftUser, 'isWithdrawn')));

  // **見るだけの人も、退会で viewers から消えること（3.3／監査 第4回）。**
  // 退会は members しか外しておらず、viewers の行が残り続けていた。
  r = await call('createShareLink', { listId }, applicantFresh.idToken);
  const viewerLink = r.body?.result?.linkId;
  const leavingViewer = await signUp('lvv');
  r = await call('acceptShareLink', { linkId: viewerLink, mode: 'view' }, leavingViewer.idToken);
  check('退会する見るだけの人を作れる（次の確認の土台）',
        r.body?.result?.joined === false, JSON.stringify(r.body?.result));
  const viewingDoc = await doc(`lists/${listId}/viewers/${leavingViewer.localId}`);
  check('viewers に居る（次の確認の土台）',
        sv(viewingDoc, 'uid') === leavingViewer.localId, String(sv(viewingDoc, 'uid')));

  r = await call('withdrawAccount', {}, leavingViewer.idToken);
  check('見るだけの人も退会できる（3.5）', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  const leftViewer = await doc(`lists/${listId}/viewers/${leavingViewer.localId}`);
  check('退会で viewers からも消える（監査 第4回）',
        leftViewer === null || leftViewer.fields === undefined,
        leftViewer ? '残っている' : '消えている');

  // --- 曲が追加されたらメンバー全員へ通知（10.2） ---
  //
  // 以前はリスト管理者とサイト管理者だけが宛先だった。参加していても
  // 管理者でなければ曲の追加に気づけず、逆にサイト管理者には参加して
  // いないリストの曲まで届いていた。
  //
  // ここでは項目を直接書いて onItemCreated を動かす。
  const itemId = `song-${stamp}`;
  const wrote = await setDoc(`lists/${listId}/items/${itemId}`, {
    seq: { integerValue: '1' },
    date: { stringValue: '2026-08-06' },
    kind: { stringValue: 'url' },
    url: { stringValue: 'https://example.com/song' },
    title: { stringValue: `テスト曲${stamp}` },
    createdBy: { stringValue: applicant.localId },
    status: { stringValue: 'active' },
  });
  check('曲を追加できる（通知の検証用）', wrote);

  const itemAdded = async (uid) =>
    (await list(`users/${uid}/notifications`))
      .some((n) => sv(n, 'type') === 'itemAdded' && sv(n, 'itemId') === itemId);

  // **届くはずの人に届くまで待つ。** onItemCreated は非同期で、初回は
  // トリガーの起動に時間がかかる。ここで待たずに固定秒数で進むと、
  // エミュレータ起動直後の 1 回目だけ落ちる（下の waitUntil の説明を参照）。
  //
  // **「届かない」側はここでは待たない。** 待っても何も起きないので
  // 時間切れまで無駄に待つだけになる。届く側が揃った時点で、
  // 同じ配信は済んでいるとみなして全員分を一度に確かめる。
  await waitUntil(async () =>
    (await itemAdded(invitee.localId)) && (await itemAdded(joiner.localId)));

  // invitee はリンクから入った Super User、joiner はこの時点で listAdmin。
  // **通知は役割で絞らない（10.2）。** メンバーなら届く。
  check('参加しているだけの人にも届く（10.2）', await itemAdded(invitee.localId));
  check('リスト管理者にも届く（10.2）', await itemAdded(joiner.localId));
  check('追加した本人には届かない', !(await itemAdded(applicant.localId)));
  check('参加していない人には届かない', !(await itemAdded(revoked.localId)));

  // サイト管理者はこのリストのメンバーではない。参加していないリストの
  // 曲まで通知されると雑音になるため、役割だけを理由には送らない。
  check('サイト管理者でも参加していなければ届かない',
        !(await itemAdded(siteAdmin.localId)));

  // --- 通知設定は本人だけの場所から読む（10.3 / 2026-08-11） ---
  //
  // 通知設定を `users/{uid}` から `users/{uid}/private/state` へ移した。
  // **繋ぎ違えても「届く」ほうへ倒れる**ので（設定が読めなければ
  // 全部オンとして扱う仕様）、実物で「オフにしたら届かない」を確かめる。
  const muted = await signUp('mute');
  r = await call('acceptShareLink', { linkId: viewerLink, mode: 'join' }, muted.idToken);
  check('通知を止める人を参加させられる（次の確認の土台）',
        r.body?.result?.listId === listId, JSON.stringify(r.body?.result));

  const settingsWritten = await setDoc(`users/${muted.localId}/private/state`, {
    notificationSettings: {
      mapValue: { fields: { master: { booleanValue: false } } },
    },
  });
  check('通知設定を本人だけの場所へ書ける（次の確認の土台）', settingsWritten);

  const itemId2 = `song2-${stamp}`;
  const wrote2 = await setDoc(`lists/${listId}/items/${itemId2}`, {
    seq: { integerValue: '2' },
    date: { stringValue: '2026-08-11' },
    kind: { stringValue: 'url' },
    url: { stringValue: 'https://example.com/song2' },
    title: { stringValue: `テスト曲2${stamp}` },
    createdBy: { stringValue: applicant.localId },
    status: { stringValue: 'active' },
  });
  check('2 曲目を追加できる（通知設定の検証用）', wrote2);

  const item2Added = async (uid) =>
    (await list(`users/${uid}/notifications`))
      .some((n) => sv(n, 'type') === 'itemAdded' && sv(n, 'itemId') === itemId2);

  // **オンの人に届くまで待ってから、オフの人を見る。** 届いていない
  // だけの状態を「オフが効いた」と読み違えないため。
  await waitUntil(async () => await item2Added(invitee.localId));
  check('通知設定を切っていない人には届く（次の確認の土台）',
        await item2Added(invitee.localId));
  check('通知をオフにした人には届かない（10.3・新しい置き場所）',
        !(await item2Added(muted.localId)));
}

// ---------------------------------------------------------------------------
// プレミアム（docs/PREMIUM-DESIGN.md）
//
// **課金が絡むので、境界は実物で確かめる。** 判断そのものは
// functions/test/premium.test.ts が持っているが、トランザクションで
// 守っているもの——二重取り・人数の上限・名前の予約——は、実際に
// Firestore を動かさないと確かめられない。
// ---------------------------------------------------------------------------

{
  const GB = 1073741824;
  /** 入れ子の map の中身を取り出す（premium.until や storage.quotaBytes）。 */
  const nested = (d, outer, inner) =>
    d?.fields?.[outer]?.mapValue?.fields?.[inner];
  const codeOf = (r) => r.body?.error?.details?.code;

  const premiumUser = await signUp('prem');
  const freeUser = await signUp('free');

  // **users/{uid} を実際に作っておく。** 本来はクライアントが登録時に作る
  // （lib/data/repositories/auth_repository.dart の _ensureUserDocument）。
  // 作らないまま「users/{uid} に premium / storage が入っていない」を
  // 確かめると、**ドキュメントごと無いだけで緑になる**（前提が崩れると
  // 自動的に通る形／docs/AUDIT-CHECKLIST.md 観点 4）。
  for (const person of [premiumUser, freeUser]) {
    await setDoc(`users/${person.localId}`, {
      displayName: { stringValue: `p-${person.localId}` },
      isWithdrawn: { booleanValue: false },
    });
  }
  check('users/{uid} を用意できる（以降の「入っていない」の土台）',
        sv(await doc(`users/${premiumUser.localId}`), 'displayName')
          === `p-${premiumUser.localId}`);

  // --- 発行（D1 / D2 / D8） ---
  let r = await call('createCoupon', { months: 1, maxUses: 1 }, siteAdmin.idToken);
  const first = r.body?.result;
  check('サイト管理者はクーポンを発行できる（5）',
        !!first?.couponId && typeof first?.code === 'string',
        JSON.stringify(r.body).slice(0, 120));

  // **土台が無ければ以降は意味を持たない。**
  if (!first?.couponId) {
    console.error('\nクーポンを発行できなかったため、プレミアムの確認は行えません。\n');
    process.exit(1);
  }

  check('自動生成は 24 文字で、読み違えやすい文字を使わない（D8）',
        /^[A-HJ-NP-Z2-9]{24}$/.test(first.code ?? ''), first.code);

  r = await call('createCoupon', { months: 1, maxUses: 1 }, freeUser.idToken);
  check('サイト管理者でなければ発行できない', codeOf(r) === 'siteAdminOnly',
        JSON.stringify(r.body?.error?.details ?? r.body).slice(0, 80));

  r = await call('createCoupon', { months: 0, maxUses: 1 }, siteAdmin.idToken);
  check('月数 0 のクーポンは作れない', codeOf(r) === 'monthsInvalid', codeOf(r));

  r = await call('createCoupon', { months: 1, maxUses: 0 }, siteAdmin.idToken);
  check('使える人数 0 のクーポンは作れない', codeOf(r) === 'maxUsesInvalid', codeOf(r));

  r = await call('createCoupon', { code: `Spring${stamp}`, months: 1, maxUses: 3 },
                 siteAdmin.idToken);
  check('コードを指定して発行できる（D8）',
        r.body?.result?.code === `SPRING${stamp}`, r.body?.result?.code);

  r = await call('createCoupon', { code: `spring${stamp}`, months: 1, maxUses: 3 },
                 siteAdmin.idToken);
  check('同じコードは二度発行できない（大小・空白は同じ扱い）',
        codeOf(r) === 'couponCodeTaken', codeOf(r));

  // --- 引き換え（3 / 9-1） ---
  r = await call('redeemCoupon', { code: 'NOSUCHCODEXXXXXXXXXXXXXX' }, freeUser.idToken);
  check('無いコードは断る', codeOf(r) === 'couponNotFound', codeOf(r));

  const unverified = await signUpUnverified('unv2');
  r = await call('redeemCoupon', { code: first.code }, unverified.idToken);
  check('メール未確認では引き換えられない（3.1）',
        codeOf(r) === 'emailNotVerified', codeOf(r));

  r = await call('redeemCoupon', { code: first.code }, premiumUser.idToken);
  const until1 = r.body?.result?.premiumUntil;
  check('クーポンを引き換えるとプレミアムになる',
        typeof until1 === 'number' && until1 > Date.now(),
        JSON.stringify(r.body).slice(0, 120));

  // **二重取りができないこと（9-1）。**
  r = await call('redeemCoupon', { code: first.code }, premiumUser.idToken);
  check('同じ人は同じクーポンを二度使えない（9-1）',
        codeOf(r) === 'couponAlreadyUsed', codeOf(r));

  // **人数の上限を超えないこと（D1）。**
  r = await call('redeemCoupon', { code: first.code }, freeUser.idToken);
  check('使える人数を超えて引き換えられない（D1）',
        codeOf(r) === 'couponUsedUp', codeOf(r));

  // --- 2 枚目は月数が足される（D4） ---
  r = await call('createCoupon', { months: 2, maxUses: 5 }, siteAdmin.idToken);
  const second = r.body?.result;
  check('2 枚目のクーポンを発行できる（次の確認の土台）', !!second?.couponId);

  r = await call('redeemCoupon', { code: `  ${second.code.toLowerCase()}  ` },
                 premiumUser.idToken);
  const until2 = r.body?.result?.premiumUntil;
  check('小文字・前後の空白でも引き換えられる', typeof until2 === 'number',
        JSON.stringify(r.body).slice(0, 120));
  check('2 枚目は上書きではなく足される（D4）', until2 > until1,
        `${until1} -> ${until2}`);
  {
    // 1 か月 + 2 か月 = 3 か月先。差はおよそ 2 か月（59〜62 日）になる。
    const days = (until2 - until1) / 86400000;
    check('足されたのはおよそ 2 か月ぶん', days > 55 && days < 65, `${days.toFixed(1)} 日`);
  }

  // --- 上限を使用済みより下げる（D1 の補足） ---
  r = await call('updateCoupon', { couponId: second.couponId, maxUses: 1 },
                 siteAdmin.idToken);
  check('使用済みの人数より小さい上限にもできる（D1）', r.status === 200,
        JSON.stringify(r.body).slice(0, 80));

  // **プレミアムは本人だけの場所（private/state）にある（2026-08-11）。**
  const afterLower = await doc(`users/${premiumUser.localId}/private/state`);
  check('上限を下げても、使った人のプレミアムは消えない（D1）',
        !!nested(afterLower, 'premium', 'until')?.timestampValue,
        String(nested(afterLower, 'premium', 'until')?.timestampValue));

  // **誰でも読める側には残さない。** ここに premium があると、
  // 「誰がいつまでプレミアムか」が他の利用者に見える。
  const premiumProfile = await doc(`users/${premiumUser.localId}`);
  check('users/{uid} にプレミアムの期限が入っていない（移行後の形）',
        premiumProfile?.fields?.premium === undefined,
        JSON.stringify(premiumProfile?.fields?.premium ?? null).slice(0, 60));

  const late = await signUp('late');
  r = await call('redeemCoupon', { code: second.code }, late.idToken);
  check('上限を下げたあとは、それ以上使えない（D1）',
        codeOf(r) === 'couponUsedUp', codeOf(r));

  // --- 停止（5：消さずに止める） ---
  r = await call('updateCoupon', { couponId: second.couponId, disabled: true },
                 siteAdmin.idToken);
  check('クーポンを止められる（5）', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  r = await call('redeemCoupon', { code: second.code }, late.idToken);
  check('止めたクーポンは使えない', codeOf(r) === 'couponDisabled', codeOf(r));

  // --- 一覧と、使った人（5） ---
  r = await call('listCoupons', {}, siteAdmin.idToken);
  const listed = r.body?.result?.coupons ?? [];
  const firstRow = listed.find((c) => c.couponId === first.couponId);
  check('クーポンを一覧できる（5）', !!firstRow, `件数=${listed.length}`);
  check('使われた数と上限が分かる（5）',
        firstRow?.usedCount === 1 && firstRow?.maxUses === 1,
        JSON.stringify(firstRow));

  r = await call('listCoupons', {}, freeUser.idToken);
  check('一般利用者はクーポンを一覧できない（9-3）',
        codeOf(r) === 'siteAdminOnly', codeOf(r));

  r = await call('listCouponRedemptions', { couponId: first.couponId }, siteAdmin.idToken);
  check('誰が使ったかを見られる（5）',
        r.body?.result?.redemptions?.[0]?.uid === premiumUser.localId,
        JSON.stringify(r.body?.result).slice(0, 120));

  r = await call('listCouponRedemptions', { couponId: first.couponId }, freeUser.idToken);
  check('一般利用者は使った人を見られない', codeOf(r) === 'siteAdminOnly', codeOf(r));

  // --- 手動指定コードの最小強度（S1 / 監査 第5回・群B） ---
  // 総当たりのリスクは「管理者が作れる短い手動コード」に限られる。
  // createCoupon は手動指定時のみ、最小 8 文字かつ英字と数字の両方を課す
  // （invalid-argument = HTTP 400。details.code は載せないので状態で見る）。
  r = await call('createCoupon', { code: 'AB12', months: 1, maxUses: 1 }, siteAdmin.idToken);
  check('短すぎる手動コードは作れない（S1）', r.status === 400,
        `status=${r.status}`);

  r = await call('createCoupon', { code: 'ABCDEFGH', months: 1, maxUses: 1 }, siteAdmin.idToken);
  check('数字を含まない手動コードは作れない（S1）', r.status === 400, `status=${r.status}`);

  r = await call('createCoupon', { code: `Valid${stamp}`, months: 1, maxUses: 1 },
                 siteAdmin.idToken);
  check('8 文字以上で英数字混在なら手動コードを作れる（S1）',
        r.status === 200 && typeof r.body?.result?.code === 'string',
        `status=${r.status}`);

  // --- 引き換え失敗のレート制限（S1） ---
  // 失敗を続けても記録もペナルティも無いと、確認済みアカウント 1 つから
  // 短い手動コードを総当たりできる。uid ごとに一定回数で締め出す
  // （resource-exhausted = HTTP 429）。窓を過ぎれば自然に戻る。
  {
    const brute = await signUp('brute');
    let lockedStatus = 0;
    for (let i = 0; i < 12; i += 1) {
      const rr = await call('redeemCoupon',
                            { code: 'NOSUCHCODEBRUTEXXXXXXXXX' }, brute.idToken);
      if (rr.status === 429) { lockedStatus = 429; break; }
    }
    check('引き換えの失敗を続けると総当たりが止められる（S1）', lockedStatus === 429,
          `最後の状態=${lockedStatus}`);
  }

  // --- 申請なしのリスト作成（4.2） ---
  const directName = `直接作成${stamp}`;
  r = await call('createListDirectly', { listName: directName }, premiumUser.idToken);
  const directId = r.body?.result?.listId;
  check('プレミアムなら申請なしでリストを作れる（4.2）', !!directId,
        JSON.stringify(r.body).slice(0, 120));

  if (!directId) {
    console.error('\n直接作成に失敗したため、以降の確認は土台がありません。\n');
    process.exit(1);
  }

  {
    const l = await doc(`lists/${directId}`);
    check('作った人が createdBy になる', sv(l, 'createdBy') === premiumUser.localId,
          String(sv(l, 'createdBy')));

    const member = await doc(`lists/${directId}/members/${premiumUser.localId}`);
    check('作った人がリスト管理者になる（承認と同じ）',
          sv(member, 'role') === 'listAdmin' && sv(member, 'uid') === premiumUser.localId,
          `${sv(member, 'role')} / ${sv(member, 'uid')}`);

    const stats = await doc(`lists/${directId}/meta/stats`);
    check('stats が初期化される（nextSeq=1）', sv(stats, 'nextSeq') === '1',
          String(sv(stats, 'nextSeq')));

    // **作った人の合計の写し。** 画面はメンバーとして stats しか読めない。
    check('作った人の合計の写しが入る（ownerQuotaBytes は既定 2GB）',
          sv(stats, 'ownerQuotaBytes') === String(2 * GB) &&
            sv(stats, 'ownerUsedBytes') === '0',
          `${sv(stats, 'ownerQuotaBytes')} / ${sv(stats, 'ownerUsedBytes')}`);

    // **名前の予約を飛ばしていないこと（9-2）。**
    const reserved = await doc(`listNames/${directName.toLowerCase()}`);
    check('名前が予約される（承認と同じ道を通る／9-2）',
          sv(reserved, 'listId') === directId, String(sv(reserved, 'listId')));
  }

  // **プレミアムでない人は呼べない。符号まで確かめる。**
  r = await call('createListDirectly', { listName: `無償${stamp}` }, freeUser.idToken);
  check('プレミアムでない人は直接作成できない（PERMISSION_DENIED / premiumRequired）',
        r.body?.error?.status === 'PERMISSION_DENIED' && codeOf(r) === 'premiumRequired',
        `${r.body?.error?.status} / ${codeOf(r)}`);

  // **未ログインと取り違えていないこと。** 上と下で符号が違う。
  r = await call('createListDirectly', { listName: `未ログイン${stamp}` });
  check('未ログインのときは signInRequired（premiumRequired と区別する）',
        codeOf(r) === 'signInRequired', codeOf(r));

  // **サイト管理者は実効プレミアムで通る**（仕様書 4.1・旧・論点 18 を上書き）。
  // 自分がプレミアムを契約していなくても、上位の役割が下位の権限を包含する。
  r = await call('createListDirectly', { listName: `管理者直接${stamp}` },
                 siteAdmin.idToken);
  check('サイト管理者は申請なしで直接作成できる（実効プレミアム／仕様書 4.1）',
        !!r.body?.result?.listId, JSON.stringify(r.body).slice(0, 120));

  // --- 期限が切れた人は作れない（D3） ---
  r = await call('extendPremium', { uid: premiumUser.localId, months: -12 },
                 siteAdmin.idToken);
  check('サイト管理者は期限を縮められる（D4）',
        r.status === 200 && r.body?.result?.premiumUntil < Date.now(),
        JSON.stringify(r.body).slice(0, 100));

  r = await call('createListDirectly', { listName: `期限切れ${stamp}` },
                 premiumUser.idToken);
  check('期限が切れた人は作れない（D3）', codeOf(r) === 'premiumRequired', codeOf(r));

  {
    // **既存のリストは残る。** 「追加だけ止める」であって、消さない（D3）。
    const l = await doc(`lists/${directId}`);
    check('期限が切れても、作ったリストは残る（D3）',
          !!l && sv(l, 'name') === directName, String(sv(l, 'name')));
  }

  r = await call('extendPremium', { uid: premiumUser.localId, months: 12 },
                 siteAdmin.idToken);
  check('期限を延ばし直せる（次の確認の土台）',
        r.body?.result?.premiumUntil > Date.now(),
        JSON.stringify(r.body).slice(0, 100));

  r = await call('extendPremium', { uid: premiumUser.localId, months: 1 },
                 freeUser.idToken);
  check('一般利用者は期限を延ばせない', codeOf(r) === 'siteAdminOnly', codeOf(r));

  // --- 同じ名前のリストが 2 つ作れない（申請経由と直接作成を混ぜる／9-2） ---
  r = await call('createListDirectly', { listName: directName }, premiumUser.idToken);
  check('同じ名前で二度は作れない（9-2）', codeOf(r) === 'listNameTaken', codeOf(r));

  r = await call('submitListRequest',
                 { listName: directName, purpose: 'x', estimatedTrackCount: 1, expectedUserCount: 1 },
                 freeUser.idToken);
  check('直接作成した名前は、申請でも取れない（9-2）',
        codeOf(r) === 'listNameTaken', codeOf(r));

  const pendingName = `申請中${stamp}`;
  r = await call('submitListRequest',
                 { listName: pendingName, purpose: 'x', estimatedTrackCount: 1, expectedUserCount: 1 },
                 freeUser.idToken);
  const pendingRequestId = r.body?.result?.requestId;
  check('申請できる（次の確認の土台）', !!pendingRequestId,
        JSON.stringify(r.body).slice(0, 80));

  r = await call('createListDirectly', { listName: pendingName }, premiumUser.idToken);
  check('申請中の名前は、直接作成でも取れない（9-2）',
        codeOf(r) === 'listNameTaken', codeOf(r));

  // --- 人ごとの容量上限（「容量の数字」） ---
  r = await call('setUserQuota', { uid: premiumUser.localId, quotaBytes: 4 * GB },
                 siteAdmin.idToken);
  check('サイト管理者は人ごとの上限を変えられる', r.status === 200,
        JSON.stringify(r.body).slice(0, 80));

  const quotaDoc = await doc(`users/${premiumUser.localId}/private/state`);
  check('人ごとの上限が反映される',
        nested(quotaDoc, 'storage', 'quotaBytes')?.integerValue === String(4 * GB),
        String(nested(quotaDoc, 'storage', 'quotaBytes')?.integerValue));

  // **容量も誰でも読める側には残さない。** 使用量が見えると、
  // 「誰がどれだけ溜め込んでいるか」が他の利用者に分かる。
  const quotaProfile = await doc(`users/${premiumUser.localId}`);
  check('users/{uid} に容量が入っていない（移行後の形）',
        quotaProfile?.fields?.storage === undefined,
        JSON.stringify(quotaProfile?.fields?.storage ?? null).slice(0, 60));

  r = await call('setUserQuota', { uid: premiumUser.localId, quotaBytes: 4 * GB },
                 freeUser.idToken);
  check('一般利用者は人ごとの上限を変えられない',
        codeOf(r) === 'siteAdminOnly', codeOf(r));

  r = await call('setUserQuota', { uid: premiumUser.localId, quotaBytes: 0 },
                 siteAdmin.idToken);
  check('0 以下の上限は受け付けない', codeOf(r) === 'invalidQuota', codeOf(r));

  // -------------------------------------------------------------------------
  // 実際にファイルを置いて、人ごとの合計で止まることを確かめる
  //
  // **ここだけは実物で動かす。** 上限の強制は Storage のトリガーでしか
  // 行えず（ルールからは人ごとの合計を参照できない）、その判定を
  // 「リストごと」から「人ごと」へ移したのがこの版で一番大きな変更である。
  // 純関数の境界は functions/test/premium.test.ts が持っているが、
  // **繋ぎ違えていても単体テストは緑のまま**になる。
  //
  // 2GB を実際に埋めるわけにはいかないので、上限のほうを小さくして
  // 同じ境界を作る（`setUserQuota` で 1000 バイトにする）。
  // -------------------------------------------------------------------------
  {
    const SIZE = 1024;
    const STORAGE = 'http://127.0.0.1:9199';

    // 申請中だったリストを承認して、**無償の人が作ったリスト**を用意する。
    r = await call('approveListRequest', { requestId: pendingRequestId }, siteAdmin.idToken);
    const freeListId = r.body?.result?.listId;
    check('無償の人のリストを用意できる（次の確認の土台）', !!freeListId,
          JSON.stringify(r.body).slice(0, 80));

    const upload = async (bucket, path) => {
      const res = await fetchRetry(
        `${STORAGE}/v0/b/${bucket}/o?name=${encodeURIComponent(path)}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'audio/mpeg', Authorization: 'Bearer owner' },
          body: Buffer.alloc(SIZE, 7),
        }
      ).catch(() => null);
      return res?.ok === true;
    };
    const exists = async (bucket, path) => {
      const res = await fetchRetry(
        `${STORAGE}/v0/b/${bucket}/o/${encodeURIComponent(path)}`,
        { headers: { Authorization: 'Bearer owner' } }
      ).catch(() => null);
      return res?.ok === true;
    };
    // 容量は本人だけの場所（private/state）にある（2026-08-11）。
    const storageOf = async (uid, key) =>
      Number(nested(await doc(`users/${uid}/private/state`), 'storage', key)
        ?.integerValue ?? 0);

    r = await call('setUserQuota', { uid: freeUser.localId, quotaBytes: 1000 },
                   siteAdmin.idToken);
    check('無償の人の上限を小さくできる（次の確認の土台）', r.status === 200,
          JSON.stringify(r.body).slice(0, 80));

    // **バケット名は決め打ちにしない。** firebase-tools の版で既定が
    // 変わる（appspot.com / firebasestorage.app）。
    //
    // **置けたバケットが正解。** 集計が動いたかどうかで選ばない。
    // 以前は「30 秒待って集計されたほう」を採っていたが、混んでいる
    // ときは正しいバケットでも 30 秒に間に合わず、**そのあと存在しない
    // ほうを試して失敗**していた（並列で検証したときに実際に落ちた）。
    // **時間制限は歯止めであって、速さの基準ではない**
    // （docs/AUDIT-CHECKLIST.md 観点 2・4）。
    let bucket = null;
    for (const candidate of [
      'demo-musiclist.appspot.com',
      'demo-musiclist.firebasestorage.app',
    ]) {
      if (await upload(candidate, `lists/${freeListId}/items/probe/take.mp3`)) {
        bucket = candidate;
        break;
      }
    }
    check('音源を置けるバケットがある（次の確認の土台）', bucket !== null,
          bucket ?? 'どのバケットにも置けなかった');

    // -----------------------------------------------------------------------
    // ファイルの差し替え（6.3 / 13.7・2026-08-14）
    //
    // **旧ファイルは消さずに previousFiles へ積む。** そこはクライアント
    // から書けない場所なので、Functions を通す経路そのものを確かめる。
    // -----------------------------------------------------------------------
    if (bucket !== null) {
      const replaceItemId = `replace${stamp}`;
      const oldPath = `lists/${freeListId}/items/${replaceItemId}/old.mp3`;
      const newPath = `lists/${freeListId}/items/${replaceItemId}/new.mp3`;

      await upload(bucket, oldPath);
      await setDoc(`lists/${freeListId}/items/${replaceItemId}`, {
        seq: { integerValue: '1' },
        date: { stringValue: '2026-08-14' },
        kind: { stringValue: 'file' },
        status: { stringValue: 'active' },
        createdBy: { stringValue: freeUser.localId },
        file: {
          mapValue: {
            fields: {
              storagePath: { stringValue: oldPath },
              fileName: { stringValue: 'old.mp3' },
              sizeBytes: { integerValue: String(SIZE) },
              contentType: { stringValue: 'audio/mpeg' },
            },
          },
        },
      });

      // **まだ置いていないファイルは指せない。** 先に呼べてしまうと、
      // 実体の無い場所を指した項目ができる。
      r = await call('replaceItemFile',
                     { listId: freeListId, itemId: replaceItemId,
                       storagePath: newPath, fileName: 'new.mp3' },
                     freeUser.idToken);
      check('置いていないファイルには差し替えられない',
            codeOf(r) === 'uploadNotFound', codeOf(r));

      await upload(bucket, newPath);

      // **他人のリストのパスは受け付けない**（監査 S1 と同じ形）。
      r = await call('replaceItemFile',
                     { listId: freeListId, itemId: replaceItemId,
                       storagePath: `lists/OTHER/items/X/victim.mp3`,
                       fileName: 'victim.mp3' },
                     freeUser.idToken);
      check('別のリストのパスには差し替えられない',
            codeOf(r) === 'fileNotInThisItem', codeOf(r));

      // **参加していない人は差し替えられない。**
      r = await call('replaceItemFile',
                     { listId: freeListId, itemId: replaceItemId,
                       storagePath: newPath, fileName: 'new.mp3' },
                     premiumUser.idToken);
      check('参加していない人は差し替えられない',
            codeOf(r) === 'cannotEditItem', codeOf(r));

      r = await call('replaceItemFile',
                     { listId: freeListId, itemId: replaceItemId,
                       storagePath: newPath, fileName: 'new.mp3' },
                     freeUser.idToken);
      check('本人はファイルを差し替えられる（6.3）', r.status === 200,
            JSON.stringify(r.body).slice(0, 100));

      {
        const item = await doc(`lists/${freeListId}/items/${replaceItemId}`);
        const file = item?.fields?.file?.mapValue?.fields;
        check('項目が新しいファイルを指す',
              file?.storagePath?.stringValue === newPath,
              String(file?.storagePath?.stringValue));

        // **大きさは Storage の実物から読む。** 申告値だと集計とずれる。
        check('大きさは実物から読む', file?.sizeBytes?.integerValue === String(SIZE),
              String(file?.sizeBytes?.integerValue));

        const previous = item?.fields?.previousFiles?.arrayValue?.values ?? [];
        const first = previous[0]?.mapValue?.fields;
        check('旧ファイルが猶予つきで残る（消さない）',
              first?.storagePath?.stringValue === oldPath
                && !!first?.purgeAt?.timestampValue,
              JSON.stringify(first ?? null).slice(0, 120));

        // **実体も残っている。** ここで消していると、依頼者の決定
        //（旧ファイルの容量も数える）と食い違う。
        check('旧ファイルの実体は消していない', await exists(bucket, oldPath));
      }

      // ---------------------------------------------------------------------
      // 掃除の通し確認（13.4・2026-08-15）
      //
      // **定期実行（毎日 4:00）は自動テストから呼べない。** 同じ中身を
      // 呼ぶサイト管理者向けの入口（runPurgeNow）で、最後まで動かす。
      // ここを確かめないままにしていた（BACKLOG「定期実行の関数の確認」）。
      // ---------------------------------------------------------------------
      {
        const purgeItemId = `purge${stamp}`;
        const purgePath = `lists/${freeListId}/items/${purgeItemId}/gone.mp3`;
        await upload(bucket, purgePath);
        await setDoc(`lists/${freeListId}/items/${purgeItemId}`, {
          seq: { integerValue: '2' },
          date: { stringValue: '2026-08-14' },
          kind: { stringValue: 'file' },
          status: { stringValue: 'deleted' },
          createdBy: { stringValue: freeUser.localId },
          // **猶予を過ぎている**（昨日）。
          purgeAt: { timestampValue: new Date(Date.now() - 86400000).toISOString() },
          file: { mapValue: { fields: {
            storagePath: { stringValue: purgePath },
            fileName: { stringValue: 'gone.mp3' },
            sizeBytes: { integerValue: String(SIZE) },
            contentType: { stringValue: 'audio/mpeg' },
          } } },
        });

        r = await call('runPurgeNow', {}, freeUser.idToken);
        check('掃除は誰でも動かせるわけではない', codeOf(r) === 'siteAdminOnly',
              codeOf(r));

        r = await call('runPurgeNow', {}, siteAdmin.idToken);
        check('サイト管理者は掃除を動かせる（13.4）', r.status === 200,
              JSON.stringify(r.body).slice(0, 100));

        check('猶予を過ぎたファイルが実際に消える',
              !(await exists(bucket, purgePath)));

        // **生きているファイルは巻き添えにしない。** ここが壊れると、
        // 消してはいけない音源が消える（戻せない）。
        check('差し替えたばかりの新しいファイルは残る',
              await exists(bucket, newPath));

        const purged = await doc(`lists/${freeListId}/items/${purgeItemId}`);
        check('掃除のあと、消した印が付く（次回の対象から外れる）',
              purged?.fields?.purgedAt !== undefined,
              JSON.stringify(purged?.fields?.purgeAt ?? null).slice(0, 60));
      }

      // ---------------------------------------------------------------------
      // 通知の定期削除（P2・監査 第5回・群B）
      //
      // **既読かつ保持期間（既定 90 日）を過ぎた通知だけ**を消す。
      // 未読は消さない（気づかないうちに消える事故を避ける）。最近の既読も
      // 残す。上のファイル掃除と同じ入口（runPurgeNow）から動く。
      // エミュレータは索引を強制しないので、本番の索引欠落はここでは
      // 気づけない——索引は firestore.indexes.json に明示している。
      // ---------------------------------------------------------------------
      {
        const notifBase = `users/${freeUser.localId}/notifications`;
        const old = new Date(Date.now() - 100 * 86400000).toISOString();
        const fresh = new Date().toISOString();
        await setDoc(`${notifBase}/oldRead${stamp}`, {
          type: { stringValue: 'itemAdded' },
          isRead: { booleanValue: true },
          createdAt: { timestampValue: old },
        });
        await setDoc(`${notifBase}/oldUnread${stamp}`, {
          type: { stringValue: 'itemAdded' },
          isRead: { booleanValue: false },
          createdAt: { timestampValue: old },
        });
        await setDoc(`${notifBase}/recentRead${stamp}`, {
          type: { stringValue: 'itemAdded' },
          isRead: { booleanValue: true },
          createdAt: { timestampValue: fresh },
        });

        r = await call('runPurgeNow', {}, siteAdmin.idToken);
        check('掃除を動かせる（通知の検証用）', r.status === 200,
              JSON.stringify(r.body).slice(0, 100));

        check('既読で保持期間を過ぎた通知は消える（P2）',
              (await doc(`${notifBase}/oldRead${stamp}`)) === null);
        check('未読は保持期間を過ぎても残す（P2）',
              (await doc(`${notifBase}/oldUnread${stamp}`)) !== null);
        check('最近の既読は残す（P2）',
              (await doc(`${notifBase}/recentRead${stamp}`)) !== null);
      }

      // **削除済みの項目には差し替えられない**（猶予の判定が二重になる）。
      await setDoc(`lists/${freeListId}/items/${replaceItemId}`, {
        status: { stringValue: 'deleted' },
      });
      r = await call('replaceItemFile',
                     { listId: freeListId, itemId: replaceItemId,
                       storagePath: newPath, fileName: 'new.mp3' },
                     freeUser.idToken);
      check('削除済みの項目には差し替えられない',
            codeOf(r) === 'itemDeleted', codeOf(r));
    }

    // 集計は保存のあとに走る。**待ち時間は既定（長め）に任せる。**
    const counted = bucket !== null && await waitUntil(
      async () => (await storageOf(freeUser.localId, 'usedBytes')) === SIZE,
    );
    check('アップロードが「人ごとの合計」に足される（容量の数字）', counted,
          `${await storageOf(freeUser.localId, 'usedBytes')} / ${SIZE}`);

    // **集計の書き戻し先も本人だけの場所であること。** ここが誰でも
    // 読める側へ戻ると、ファイルが増減するたびに使用量が漏れ直す。
    const freeProfile = await doc(`users/${freeUser.localId}`);
    check('集計しても users/{uid} に容量が入らない（移行後の形）',
          freeProfile?.fields?.storage === undefined,
          JSON.stringify(freeProfile?.fields?.storage ?? null).slice(0, 60));

    if (bucket) {
      const stats = await doc(`lists/${freeListId}/meta/stats`);
      check('リストごとの使用量も引き続き数える（表示に要る）',
            sv(stats, 'usedBytes') === String(SIZE), String(sv(stats, 'usedBytes')));
      check('作った人の合計が stats に写る（ownerUsedBytes / ownerQuotaBytes）',
            sv(stats, 'ownerUsedBytes') === String(SIZE) &&
              sv(stats, 'ownerQuotaBytes') === '1000',
            `${sv(stats, 'ownerUsedBytes')} / ${sv(stats, 'ownerQuotaBytes')}`);

      // **無償の人は拡張されない。** 上限（1000）を超えて使っていても、
      // 上限は動かない。
      check('プレミアムでない人は自動拡張されない（容量の数字）',
            (await storageOf(freeUser.localId, 'quotaBytes')) === 1000,
            String(await storageOf(freeUser.localId, 'quotaBytes')));

      // **サイト管理から足した上限（土台）が、集計のたびに消えないこと。**
      // 戻す先を既定の 2GB に決め打ちすると、移行の手当てが黙って消える
      // （PREMIUM-DESIGN「既存の利用者への影響」）。
      check('無償の人の土台は、容量が増減しても保たれる',
            (await storageOf(freeUser.localId, 'quotaBytesBase')) === 1000,
            String(await storageOf(freeUser.localId, 'quotaBytesBase')));

      // すでに超えている状態からの追加は取り消される（7.5 / 監査 S5）。
      // **判定の材料は人ごとの合計**で、リストごとの上限（1GB）ではない。
      const blocked = `lists/${freeListId}/items/blocked/take.mp3`;
      check('超過後のアップロードを行える（次の確認の土台）',
            await upload(bucket, blocked));
      const removed = await waitUntil(
        async () => !(await exists(bucket, blocked)),
        { timeoutMs: 60000 }
      );
      check('上限を超えた状態からのアップロードは取り消される（7.5 / S5）',
            removed, removed ? '取り消された' : '残ったまま');

      // --- プレミアムは自動で増える（「自動拡張の作り」） ---
      r = await call('setUserQuota', { uid: premiumUser.localId, quotaBytes: 1000 },
                     siteAdmin.idToken);
      check('プレミアムの人の上限を小さくできる（次の確認の土台）', r.status === 200,
            JSON.stringify(r.body).slice(0, 80));

      const kept = `lists/${directId}/items/expand/take.mp3`;
      check('プレミアムの人がアップロードできる（次の確認の土台）',
            await upload(bucket, kept));

      const grew = await waitUntil(
        async () => (await storageOf(premiumUser.localId, 'quotaBytes')) > 1000,
        { timeoutMs: 60000 }
      );
      check('プレミアムは 90% を超えると上限が自動で増える', grew,
            String(await storageOf(premiumUser.localId, 'quotaBytes')));
      check('増える幅は 2GB（2→4→6→8→10 の 1 段）',
            (await storageOf(premiumUser.localId, 'quotaBytes')) === 1000 + 2 * GB,
            String(await storageOf(premiumUser.localId, 'quotaBytes')));

      // **黙って増やさない。** 増えた理由が分からないと、請求が増えたときに
      // 利用者にも運営にも説明できない。
      const expandNotified = async () =>
        (await list(`users/${premiumUser.localId}/notifications`))
          .some((n) => sv(n, 'type') === 'quotaExpanded');
      await waitUntil(expandNotified);
      check('増やしたことを通知する（自動拡張の作り）', await expandNotified());

      check('自動で増えたので、ファイルは取り消されない', await exists(bucket, kept));

      check('自動拡張は土台を書き換えない',
            (await storageOf(premiumUser.localId, 'quotaBytesBase')) === 1000,
            String(await storageOf(premiumUser.localId, 'quotaBytesBase')));

      // --- 期限が切れたら、上限は「土台」に戻る（既定の 2GB ではない） ---
      r = await call('extendPremium', { uid: premiumUser.localId, months: -120 },
                     siteAdmin.idToken);
      check('期限を切らせる（次の確認の土台）',
            r.body?.result?.premiumUntil < Date.now(),
            JSON.stringify(r.body).slice(0, 100));

      // 集計が動く機会を作る。上限を超えるのでこのファイルは取り消されるが、
      // 上限の計算はその前に行われる。
      check('切れたあともアップロードは試せる（次の確認の土台）',
            await upload(bucket, `lists/${directId}/items/expired/take.mp3`));

      const returned = await waitUntil(
        async () => (await storageOf(premiumUser.localId, 'quotaBytes')) === 1000,
        { timeoutMs: 60000 }
      );
      check('期限が切れたら上限は土台へ戻る（既定の 2GB ではない）', returned,
            String(await storageOf(premiumUser.localId, 'quotaBytes')));
      check('戻っても既存のファイルは消えない（D3）', await exists(bucket, kept));
    }
  }
}

// ---------------------------------------------------------------------------
// オフライン用ダウンロードの権限確認（docs/DOWNLOAD-DESIGN.md 5.1 / 8.2）
//
// **この関数の答えは、端末のファイル削除に直結する**（10 節の危険 4）。
// 判断の中身は functions/test/downloads.test.ts が境界ごとに固定している。
// ここで確かめるのは、実際の Auth と Firestore を通したときに
// **同じ答えが返ること**と、**符号を取り違えていないこと**。
//
// **とくに「プレミアムでないことを例外にしていない」ことを実物で見る。**
// 例外にすると、呼び出し側は圏外・タイムアウトと区別できず、
// 電波の悪い場所で 1 回失敗しただけで全曲が消える。
// ---------------------------------------------------------------------------
{
  const codeOf = (res) => res.body?.error?.details?.code;
  let r;

  const dlMember = await signUp('dlmem');
  const dlViewer = await signUp('dlview');
  const dlUnverified = await signUpUnverified('dlunv');

  // --- 土台：Read Only のメンバーで、プレミアムの人 ---
  //
  // **Read Only で作る。** 論点 9 は「メンバーのみ（Read Only を含む）」
  // なので、いちばん弱い役割で通ることを確かめる側に倒す。
  r = await call('addListMember',
                 { listId, uid: dlMember.localId, role: 'readOnly' },
                 siteAdmin.idToken);
  check('土台：Read Only のメンバーを用意できる（論点 9）', r.status === 200,
        JSON.stringify(r.body).slice(0, 80));

  r = await call('extendPremium', { uid: dlMember.localId, months: 12 },
                 siteAdmin.idToken);
  check('土台：その人をプレミアムにできる',
        r.body?.result?.premiumUntil > Date.now(),
        JSON.stringify(r.body).slice(0, 80));

  // --- 土台：閲覧者（viewers に居て、members に居ない人） ---
  //
  // `acceptShareLink` が書くのと同じ形を直接置く。**members には入れない。**
  await setDoc(`lists/${listId}/viewers/${dlViewer.localId}`,
               { uid: { stringValue: dlViewer.localId } });
  const viewerRow = await doc(`lists/${listId}/viewers/${dlViewer.localId}`);
  const viewerMember = await doc(`lists/${listId}/members/${dlViewer.localId}`);
  check('土台：閲覧者が viewers に居て、members に居ない（論点 9）',
        sv(viewerRow, 'uid') === dlViewer.localId &&
          (viewerMember === null || viewerMember.fields === undefined),
        `${sv(viewerRow, 'uid')} / ${JSON.stringify(viewerMember?.fields ?? null).slice(0, 40)}`);

  // **閲覧者もプレミアムにしておく。** プレミアムが無いまま確かめると、
  // 「閲覧者だから notMember」ではなく「プレミアムでないから」で
  // 落ちていても緑になる（AUDIT-CHECKLIST 観点 4）。
  r = await call('extendPremium', { uid: dlViewer.localId, months: 12 },
                 siteAdmin.idToken);
  check('土台：閲覧者もプレミアムにできる（判定を混ぜないため）',
        r.body?.result?.premiumUntil > Date.now(),
        JSON.stringify(r.body).slice(0, 80));

  // --- メンバーかつプレミアムなら許可（論点 9・12） ---
  const before = Date.now();
  r = await call('verifyDownloadAccess', { listIds: [listId] }, dlMember.idToken);
  const after = Date.now();
  check('メンバーかつプレミアムなら許可（premiumActive: true / member）',
        r.status === 200 &&
          r.body?.result?.premiumActive === true &&
          r.body?.result?.lists?.[listId] === 'member',
        JSON.stringify(r.body).slice(0, 160));

  check('verifiedAt はサーバーの時刻（呼び出し前後に挟まれる／4.2）',
        typeof r.body?.result?.verifiedAt === 'number' &&
          r.body.result.verifiedAt >= before &&
          r.body.result.verifiedAt <= after,
        `${before} <= ${r.body?.result?.verifiedAt} <= ${after}`);

  // --- 閲覧者は不許可（論点 9）。**例外ではない。** ---
  r = await call('verifyDownloadAccess', { listIds: [listId] }, dlViewer.idToken);
  check('閲覧者は notMember（viewers に居ても members に無い／論点 9）',
        r.status === 200 && r.body?.result?.lists?.[listId] === 'notMember',
        JSON.stringify(r.body).slice(0, 160));
  check('閲覧者でも例外は投げない（プレミアムの答えも返る）',
        r.body?.error === undefined && r.body?.result?.premiumActive === true,
        JSON.stringify(r.body?.error ?? r.body?.result).slice(0, 120));

  // --- サイト管理者は実効プレミアム。ただし「メンバーか」は別軸 ---
  //
  // **仕様書 4.1／4.2（旧・論点 18 を上書き）。** サイト管理者はプレミアム機能を
  // すべて持つので `premiumActive` は true。**メンバー軸もサイト管理者は例外**で、
  // 「全リストの項目を扱える」（4.2）に合わせ、members に居なくても `member` を
  // 返す（クライアントの `role != null || isSiteAdmin` と揃う）。
  const adminMember = await doc(`lists/${listId}/members/${siteAdmin.localId}`);
  check('土台：サイト管理者は members に居ない（roles.ts の説明どおり）',
        adminMember === null || adminMember.fields === undefined,
        JSON.stringify(adminMember?.fields ?? null).slice(0, 60));

  r = await call('verifyDownloadAccess', { listIds: [listId] }, siteAdmin.idToken);
  check('サイト管理者は premiumActive: true（実効プレミアム／仕様書 4.1）',
        r.status === 200 && r.body?.result?.premiumActive === true,
        JSON.stringify(r.body).slice(0, 160));
  check('サイト管理者はメンバーでなくても member（全リストでダウンロード可／仕様書 4.2）',
        r.body?.result?.lists?.[listId] === 'member',
        JSON.stringify(r.body).slice(0, 160));

  // --- プレミアムが切れたら不許可。**例外ではない**（危険 4） ---
  r = await call('extendPremium', { uid: dlMember.localId, months: -24 },
                 siteAdmin.idToken);
  check('土台：期限を切らせる',
        r.body?.result?.premiumUntil < Date.now(),
        JSON.stringify(r.body).slice(0, 100));

  r = await call('verifyDownloadAccess', { listIds: [listId] }, dlMember.idToken);
  check('プレミアムが切れても 200 で返る（premiumRequired を投げない／危険 4）',
        r.status === 200 && r.body?.error === undefined,
        `${r.status} / ${codeOf(r)}`);
  check('切れていたら premiumActive: false（正常応答の中身／論点 12）',
        r.body?.result?.premiumActive === false,
        JSON.stringify(r.body?.result).slice(0, 160));
  check('切れても「メンバーであること」は member のまま返る',
        r.body?.result?.lists?.[listId] === 'member',
        JSON.stringify(r.body?.result?.lists).slice(0, 120));

  // --- 符号を取り違えていないこと（8.2） ---
  //
  // **「未ログイン」と「権限なし」を混ぜない。** 端末は例外を
  // 「オフライン」として扱うので、どの符号かで案内の出し方が変わる。
  r = await call('verifyDownloadAccess', { listIds: [listId] });
  check('未ログインは signInRequired（premiumRequired と区別する）',
        codeOf(r) === 'signInRequired', codeOf(r));

  r = await call('verifyDownloadAccess', { listIds: [listId] },
                 dlUnverified.idToken);
  check('メール未確認は emailNotVerified（signInRequired ではない）',
        codeOf(r) === 'emailNotVerified', codeOf(r));

  // --- listIds の境界（8.2） ---
  const manyIds = (count) =>
    Array.from({ length: count }, (_, i) => `${listId}-${i}`);

  r = await call('verifyDownloadAccess', { listIds: manyIds(50) },
                 dlMember.idToken);
  check('50 件ちょうどは通る（境界／8.2）',
        r.status === 200 &&
          Object.keys(r.body?.result?.lists ?? {}).length === 50,
        `${r.status} / ${Object.keys(r.body?.result?.lists ?? {}).length} 件`);
  check('持っていないリストは notMember',
        r.body?.result?.lists?.[`${listId}-0`] === 'notMember',
        String(r.body?.result?.lists?.[`${listId}-0`]));

  r = await call('verifyDownloadAccess', { listIds: manyIds(51) },
                 dlMember.idToken);
  check('51 件は断る（境界／8.2）',
        // **符号は tooManyLists**（5.1）。以前は l10n を対で足せない都合で
        // fieldTooLong を代用していたが、専用の符号に付け替えた。
        // どの入力が悪いのかは details.field から読む。
        codeOf(r) === 'tooManyLists' &&
          r.body?.error?.details?.field === 'listIds',
        JSON.stringify(r.body?.error?.details ?? r.body).slice(0, 100));

  r = await call('verifyDownloadAccess', { listIds: 'not-an-array' },
                 dlMember.idToken);
  check('配列でなければ missingField', codeOf(r) === 'missingField', codeOf(r));

  r = await call('verifyDownloadAccess', { listIds: [`${listId}/items/x`] },
                 dlMember.idToken);
  check('ドキュメント ID として不正な値を断る（別の場所を指させない）',
        codeOf(r) === 'missingField', codeOf(r));

  r = await call('verifyDownloadAccess', { listIds: [] }, dlMember.idToken);
  check('1 曲も持っていない端末にも答える（lists は空・premiumActive は返る）',
        r.status === 200 &&
          Object.keys(r.body?.result?.lists ?? {}).length === 0 &&
          typeof r.body?.result?.premiumActive === 'boolean',
        JSON.stringify(r.body?.result).slice(0, 120));
}

// どこで時間を使ったかの内訳（調べるときの手がかり。判定には使わない）。
{
  const sec = (ms) => `${Math.round(ms / 1000)}s`;
  const total = Date.now() - stamp;
  const slowest = [...spent.calls].sort((a, b) => b.ms - a.ms).slice(0, 5)
    .map((c) => `${c.name} ${c.ms}ms`).join('、');
  console.log('\n--- 時間の内訳 ---');
  console.log(`  テスト全体            : ${sec(total)}`);
  console.log(`  関数の呼び出し（往復）: ${sec(spent.call)}（${spent.calls.length} 回）`);
  console.log(`  結果待ち（waitUntil） : ${sec(spent.wait)}（${spent.waits} 回）`);
  console.log(`  アカウント作成        : ${sec(spent.auth)}（${spent.auths} 人）`);
  console.log(`  遅い呼び出し上位      : ${slowest}`);

  // 分布を調べたいときのために、呼び出しごとの記録も残しておく。
  try {
    const { writeFileSync } = await import('node:fs');
    writeFileSync(new URL('./.last-timing.json', import.meta.url),
      JSON.stringify(spent, null, 2));
  } catch { /* 記録できなくても本題ではない */ }
}

console.log(`\n=== ${results.filter(Boolean).length} / ${results.length} 成功 ===`);
process.exit(results.every(Boolean) ? 0 : 1);
