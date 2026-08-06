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
async function call(name, data, token) {
  const r = await fetch(`${FN}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify({ data }), signal: AbortSignal.timeout(45000),
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
const sv = (d, k) => d?.fields?.[k]?.stringValue ?? d?.fields?.[k]?.integerValue ?? d?.fields?.[k]?.booleanValue;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

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
console.log('claim set:', claimRes.status);
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

if (listId) {
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

  // --- 招待 URL（3.3） ---
  const applicantFresh = await refresh(applicant);
  r = await call('createInvite', { listId, role: 'superUser' }, applicantFresh.idToken);
  const inviteId = r.body?.result?.inviteId;
  check('リスト管理者は招待を発行できる', !!inviteId, `len=${inviteId?.length ?? 0}`);

  r = await call('createInvite', { listId, role: 'listAdmin' }, applicantFresh.idToken);
  check('招待でリスト管理者は付与できない', r.body?.error?.status === 'INVALID_ARGUMENT', r.body?.error?.status);

  r = await call('acceptInvite', { inviteId }, invitee.idToken);
  check('招待を受諾できる', r.body?.result?.listId === listId, JSON.stringify(r.body).slice(0, 120));

  const im = await doc(`lists/${listId}/members/${invitee.localId}`);
  check('受諾で指定の役割が付く', sv(im, 'role') === 'superUser', sv(im, 'role'));

  // --- ワンタイム性（3.3） ---
  const second = await signUp('inv2');
  r = await call('acceptInvite', { inviteId }, second.idToken);
  check('同じ招待は二度使えない（ワンタイム）', r.body?.error?.status === 'FAILED_PRECONDITION',
        r.body?.error?.message ?? r.body?.error?.status);

  // --- メンバー数の集計（13.4） ---
  await sleep(5000);
  const l2 = await doc(`lists/${listId}`);
  check('memberCount が更新される', sv(l2, 'memberCount') === '2', `memberCount=${sv(l2,'memberCount')} adminCount=${sv(l2,'adminCount')}`);

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

  // --- 招待の取消（3.3） ---
  r = await call('createInvite', { listId, role: 'readOnly' }, applicantFresh.idToken);
  const revokeToken = r.body?.result?.inviteId ?? r.body?.result?.token;
  check('取消用の招待を発行できる', !!revokeToken);

  r = await call('revokeInvite', { inviteId: revokeToken }, applicantFresh.idToken);
  check('招待を取り消せる（3.3）', r.status === 200, JSON.stringify(r.body).slice(0, 80));

  const revoked = await signUp('rvk');
  r = await call('acceptInvite', { inviteId: revokeToken }, revoked.idToken);
  check('取り消した招待は使えない', r.status !== 200, r.body?.error?.status);

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
}

console.log(`\n=== ${results.filter(Boolean).length} / ${results.length} 成功 ===`);
process.exit(results.every(Boolean) ? 0 : 1);
