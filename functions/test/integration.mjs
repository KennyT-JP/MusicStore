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

  r = await call('deleteSiteUser', { uid: madeUid }, siteAdmin.idToken);
  check('ユーザーを削除できる（11.1）', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  const deletedUser = await doc(`users/${madeUid}`);
  check('削除すると users も消える', deletedUser === null || deletedUser.fields === undefined,
        deletedUser === null ? '消えている' : '残っている');

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

  r = await call('withdrawAccount', {}, leaver.idToken);
  check('退会できる（3.5）', r.status === 200, JSON.stringify(r.body).slice(0, 80));

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

  const afterLower = await doc(`users/${premiumUser.localId}`);
  check('上限を下げても、使った人のプレミアムは消えない（D1）',
        !!nested(afterLower, 'premium', 'until')?.timestampValue,
        String(nested(afterLower, 'premium', 'until')?.timestampValue));

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

  const quotaDoc = await doc(`users/${premiumUser.localId}`);
  check('人ごとの上限が反映される',
        nested(quotaDoc, 'storage', 'quotaBytes')?.integerValue === String(4 * GB),
        String(nested(quotaDoc, 'storage', 'quotaBytes')?.integerValue));

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
    const storageOf = async (uid, key) =>
      Number(nested(await doc(`users/${uid}`), 'storage', key)?.integerValue ?? 0);

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

    // 集計は保存のあとに走る。**待ち時間は既定（長め）に任せる。**
    const counted = bucket !== null && await waitUntil(
      async () => (await storageOf(freeUser.localId, 'usedBytes')) === SIZE,
    );
    check('アップロードが「人ごとの合計」に足される（容量の数字）', counted,
          `${await storageOf(freeUser.localId, 'usedBytes')} / ${SIZE}`);

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
