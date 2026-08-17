/**
 * 配信の多重起動ロックを固定する（AP-76）
 *
 *   node --test scripts/deploy-lock.test.mjs
 *
 * acquireLock / releaseLock の「二重取得で失敗」「解放後に再取得可」
 * 「残留（pid 死亡相当）を奪える」「--force で生きているロックを奪える」
 * 「他プロセスのロックは解放で消さない」を固定する。
 */
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

import { acquireLock, releaseLock } from './deploy-lock.mjs';

/** テストごとに使い捨ての作業場所を作る（build/ が無い初回も兼ねて未作成の子を使う）。 */
function scratch() {
  const dir = mkdtempSync(join(tmpdir(), 'deploy-lock-'));
  // build/.deploy.lock を模して、まだ無いサブディレクトリの下に置く。
  const path = join(dir, 'build', '.deploy.lock');
  return { dir, path, cleanup: () => rmSync(dir, { recursive: true, force: true }) };
}

test('取れる。親ディレクトリが無くても作る', () => {
  const { path, cleanup } = scratch();
  try {
    const lock = acquireLock(path);
    assert.equal(lock.path, path);
    assert.equal(lock.pid, process.pid);
    assert.ok(existsSync(path), 'ロックファイルができている');
    const written = JSON.parse(readFileSync(path, 'utf8'));
    assert.equal(written.pid, process.pid);
    releaseLock(lock);
  } finally {
    cleanup();
  }
});

test('二重取得は失敗する（生きている pid のロックがある）', () => {
  const { path, cleanup } = scratch();
  try {
    const lock = acquireLock(path);
    assert.throws(
      () => acquireLock(path),
      (e) => e.code === 'ELOCKED',
      '同じロックをもう一度取ろうとすると ELOCKED',
    );
    releaseLock(lock);
  } finally {
    cleanup();
  }
});

test('解放したあとは再取得できる', () => {
  const { path, cleanup } = scratch();
  try {
    const first = acquireLock(path);
    releaseLock(first);
    assert.ok(!existsSync(path), '解放でロックファイルが消える');
    const second = acquireLock(path); // 例外にならないこと
    assert.equal(second.pid, process.pid);
    releaseLock(second);
  } finally {
    cleanup();
  }
});

test('残留（pid が消えている）ロックは奪える', () => {
  const { path, cleanup } = scratch();
  try {
    // まず親ディレクトリを作るためだけに一度取って外す。
    releaseLock(acquireLock(path));
    // まず存在しない pid のロックを置く（＝クラッシュして残った状態）。
    const deadPid = 999999999; // このプロセス番号は存在しない → isAlive=false
    writeFileSync(path, JSON.stringify({ pid: deadPid, startedAt: '2000-01-01T00:00:00.000Z', host: 'dead' }));
    const lock = acquireLock(path); // 残留を奪って取り直せる
    assert.equal(lock.pid, process.pid, '自分の pid で握り直している');
    releaseLock(lock);
  } finally {
    cleanup();
  }
});

test('--force は生きているロックでも奪う', () => {
  const { path, cleanup } = scratch();
  try {
    acquireLock(path); // 現プロセス（生きている）が握る
    assert.throws(() => acquireLock(path), (e) => e.code === 'ELOCKED', 'force 無しは奪えない');
    const forced = acquireLock(path, { force: true }); // 強制解除
    assert.equal(forced.pid, process.pid);
    assert.ok(existsSync(path));
    // 注: 奪われた側の解放が「いま握っているロックを消さない」ことは、
    // pid で判定するため**別プロセス間**でのみ意味を持つ（この単一プロセスでは
    // 両ハンドルが同じ pid になり区別できない）。その担保は次のテストで行う。
    releaseLock(forced);
    assert.ok(!existsSync(path));
  } finally {
    cleanup();
  }
});

test('解放は他プロセスのロックを消さない', () => {
  const { path, cleanup } = scratch();
  try {
    releaseLock(acquireLock(path)); // 親ディレクトリを用意
    // 別プロセスが握っているように見せる（pid が自分と違う）。
    writeFileSync(path, JSON.stringify({ pid: 424242, startedAt: '2030-01-01T00:00:00.000Z', host: 'other' }));
    releaseLock({ path, pid: 111 }); // 自分のものでないので消さない
    assert.ok(existsSync(path), '他プロセスのロックは残る');
  } finally {
    cleanup();
  }
});
