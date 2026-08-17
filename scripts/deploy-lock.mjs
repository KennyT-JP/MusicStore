/**
 * 配信の多重起動を防ぐファイルロック（監査 第5回・群C・AP-76）
 *
 * ビルドと配信は build/web・.last-check.json・git タグ deploy/<環境> を
 * 共有する。2 つ同時に走ると、片方の中間生成物をもう片方が配信しうる。
 * ここで排他ファイルを 1 本だけ作り、重い処理へ入る前に握る。
 *
 * **純関数だけを置く。** deploy.mjs のように import しただけで配信が
 * 走ることは無いので、テストからそのまま呼べる（deploy-lock.test.mjs）。
 *
 * ## 残留ロックへの構え
 *
 * ロックには持ち主の pid を書く。配信がクラッシュしてロックが残っても、
 * その pid のプロセスが消えていれば「古いロック」と見なして奪う。
 * どうしても外れないときは `--force`（acquireLock の force）で解除する。
 * クラッシュ後に詰まらないための逃げ道。
 */
import { closeSync, existsSync, mkdirSync, openSync, readFileSync, unlinkSync, writeSync } from 'node:fs';
import { hostname } from 'node:os';
import { dirname } from 'node:path';

/**
 * その pid のプロセスが生きているか。シグナル 0 は送らず存在確認だけ。
 * ESRCH＝居ない。EPERM＝居るが権限が無い（＝生きている）。Windows でも同じ。
 */
function isAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return e.code === 'EPERM';
  }
}

/** ロックの中身を読む。壊れている／読めないときは null（＝残留扱いにできる）。 */
function readLock(path) {
  try {
    return JSON.parse(readFileSync(path, 'utf8'));
  } catch {
    return null;
  }
}

/**
 * 排他ロックを取る。取れたら { path, pid, startedAt, host } を返す。
 *
 * - 既にロックがあり、その pid が**生きている**なら多重起動。ELOCKED を投げる。
 * - 既にロックがあるが pid が消えている（残留）なら奪って取り直す。
 * - force:true のときは、生きている pid のロックでも強制的に奪う。
 *
 * build/ が無い初回でも動くよう、必要なら親ディレクトリを作る。
 */
export function acquireLock(path, { force = false } = {}) {
  mkdirSync(dirname(path), { recursive: true });
  // 残留を奪ったあと別プロセスに先を越される競合に備え、数回だけ取り直す。
  for (let attempt = 0; attempt < 5; attempt++) {
    let fd;
    try {
      // 'wx'＝既にあれば EEXIST で失敗する原子的な排他作成。
      fd = openSync(path, 'wx');
    } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      const existing = readLock(path);
      const stale = !existing || !isAlive(existing.pid);
      if (!force && !stale) {
        const err = new Error(
          `別の配信が実行中です（pid ${existing.pid} / ${existing.startedAt} 開始 / ${existing.host ?? '?'}）。` +
            '終わるのを待つか、確実に止まっているなら --force で解除してください。',
        );
        err.code = 'ELOCKED';
        err.holder = existing;
        throw err;
      }
      // 残留（プロセス消滅）か --force。ロックを消して取り直す。
      try { unlinkSync(path); } catch { /* 競合で誰かが先に消した */ }
      continue;
    }
    const info = { pid: process.pid, startedAt: new Date().toISOString(), host: hostname() };
    writeSync(fd, JSON.stringify(info, null, 2));
    closeSync(fd);
    return { path, ...info };
  }
  const err = new Error(`ロックを取得できませんでした（競合が続いています）: ${path}`);
  err.code = 'ELOCKED';
  throw err;
}

/**
 * ロックを外す。**自分のロックだけ**消す。
 *
 * 引数はハンドル（acquireLock の戻り値）でもパス文字列でもよい。
 * 奪い合いのあと他人のロックを消さないよう、いま置かれているロックの
 * pid が自分（＝ハンドルの pid、無ければ現プロセス）と違えば触らない。
 * 何度呼んでも安全（既に無ければ何もしない）。
 */
export function releaseLock(handle) {
  const path = typeof handle === 'string' ? handle : handle?.path;
  if (!path || !existsSync(path)) return;
  const ownerPid = (typeof handle === 'object' && handle?.pid) ? handle.pid : process.pid;
  const current = readLock(path);
  if (current && current.pid !== ownerPid) return; // 別プロセスのロック。触らない
  try { unlinkSync(path); } catch { /* 既に無い／競合 */ }
}
