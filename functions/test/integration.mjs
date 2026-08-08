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

  return { ...user, ...(await refresh(user)) };
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

async function call(name, data, token) {
  const r = await fetch(`${FN}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify({ data }), signal: AbortSignal.timeout(CALL_TIMEOUT_MS),
  });
  return { status: r.status, body: await r.json().catch(() => ({})) };
}
// Firestore エミュレータの REST は Authorization ヘッダが要る。
const FS_HEADERS = { Authorization: 'Bearer owner' };
async function doc(path) {
  const r = await fetch(`${FS}/${path}`, { headers: FS_HEADERS });
  return r.ok ? r.json() : null;
}
async function list(path) {
  const r = await fetch(`${FS}/${path}`, { headers: FS_HEADERS });
  return r.ok ? (await r.json()).documents ?? [] : [];
}
/** ドキュメントを直接書く（トリガーを動かすため）。 */
async function setDoc(path, fields) {
  const r = await fetch(`${FS}/${path}`, {
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
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    if (await predicate()) return true;
    if (Date.now() >= deadline) return false;
    await sleep(intervalMs);
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

// 実行のたびに初期化する。前回のサイト管理者が残っていると
// 「最後の 1 人」の判定が変わってしまうため。
await fetch(`${AUTH}/emulator/v1/projects/demo-musiclist/accounts`, { method: 'DELETE' });
await fetch('http://127.0.0.1:8080/emulator/v1/projects/demo-musiclist/databases/(default)/documents', { method: 'DELETE' });
await sleep(1500);

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

  await sleep(4000);
  const notifs = await list(`users/${applicant.localId}/notifications`);
  check('承認が申請者へ通知される', notifs.some((n) => sv(n, 'type') === 'requestApproved'),
        notifs.map((n) => sv(n, 'type')).join(','));

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
  check('参加すると Read Only で入る（INITIAL_JOIN_ROLE）', sv(im, 'role') === 'readOnly',
        sv(im, 'role'));

  // 役割を渡して作ったリンクでも、結果は変わらない。
  // ここで listAdmin が付いていたら、リンクからリスト管理者を作れてしまう。
  const ignoredUser = await signUp('ign');
  r = await call('acceptShareLink', { linkId: ignored, mode: 'join' }, ignoredUser.idToken);
  check('渡した役割は効かない', r.status === 200, r.body?.error?.status);
  const ignoredMember = await doc(`lists/${listId}/members/${ignoredUser.localId}`);
  check('リンクからは Read Only より上にならない', sv(ignoredMember, 'role') === 'readOnly',
        sv(ignoredMember, 'role'));

  // --- 何度でも・複数人（3.3） ---
  // **ここが以前と逆になっている。** 以前は「二度目は使えない」ことを
  // 確かめていた。いまは「二度目も使える」ことを確かめる。
  const second = await signUp('inv2');
  r = await call('acceptShareLink', { linkId, mode: 'join' }, second.idToken);
  check('同じリンクを別の人がもう一度使える', r.body?.result?.listId === listId,
        r.body?.error?.message ?? r.body?.error?.status);

  const im2 = await doc(`lists/${listId}/members/${second.localId}`);
  check('2 人目も Read Only で入る', sv(im2, 'role') === 'readOnly', sv(im2, 'role'));

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

  r = await call('rejectListRequest', { requestId: rejectId, reason: '重複' }, siteAdmin.idToken);
  check('リスト作成申請を却下できる（5.2.1）', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  // **却下したら名前の予約を解放すること。** 解放し忘れると、その名前が
  // 永久に使えなくなる（監査で無検証だった箇所）。
  const nameDoc = await doc(`listNames/${`却下される${stamp}`.toLowerCase()}`);
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

  const revoked = await signUp('rvk');
  r = await call('acceptShareLink', { linkId: revokeToken, mode: 'join' }, revoked.idToken);
  check('取り消したリンクは使えない', r.status !== 200, r.body?.error?.status);

  r = await call('acceptShareLink', { linkId: revokeToken, mode: 'view' }, revoked.idToken);
  check('取り消したリンクは閲覧にも使えない', r.status !== 200, r.body?.error?.status);

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

  // --- 管理者不在リストへの指名（5.6） ---
  r = await call('assignListAdmin', { listId, uid: joiner.localId }, siteAdmin.idToken);
  check('サイト管理者はリスト管理者を指名できる（5.6）', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  const promoted = await doc(`lists/${listId}/members/${joiner.localId}`);
  check('指名で listAdmin になる', sv(promoted, 'role') === 'listAdmin', sv(promoted, 'role'));

  // --- 退会（3.5） ---
  const leaver = await signUp('lv');
  await call('submitJoinRequest', { listId }, leaver.idToken);
  await call('approveJoinRequest', { listId, uid: leaver.localId, role: 'readOnly' }, applicantFresh.idToken);

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

  // invitee はリンクから入った Read Only、joiner はこの時点で listAdmin。
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

console.log(`\n=== ${results.filter(Boolean).length} / ${results.length} 成功 ===`);
process.exit(results.every(Boolean) ? 0 : 1);
