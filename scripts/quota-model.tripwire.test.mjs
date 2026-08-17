/**
 * 容量モデルの要点を固定する仕掛け線（監査 第5回・群C・AP-46）
 *
 *   node --test scripts/quota-model.tripwire.test.mjs
 *
 * ここで固定しているのは「容量の単位と既定」——リストごと 1GB、人ごとの
 * 土台 2GB、通知しきい値、自動拡張の刻みと上限、そして
 * check-quota-impact.mjs が数える基準（NEW_QUOTA_BYTES=2GB）。
 *
 * ############################################################################
 * # これが赤くなったら、容量の単位／既定を変えたということです。            #
 * # 本番の実データで scripts/check-quota-impact.mjs を流し、               #
 * # 影響を受ける人（使える量が減る人・すでに超えている人）を数えたか       #
 * # 必ず確認してください。数え漏れると、昨日までできた追加が止まります。     #
 * # 変更が正しいなら、下の期待値をあわせて更新してください。               #
 * ############################################################################
 *
 * 対象ファイル（functions/* と scripts/*）は別タスク・別レイヤなので
 * import せず、ソースを**テキストとして読んで**定数の値を取り出して固定する
 * （import すると check-quota-impact.mjs は本番へ接続しにいってしまう）。
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');

const CONFIG = join(root, 'functions', 'src', 'config.ts');
const QUOTA = join(root, 'functions', 'src', 'domain', 'quota.ts');
const CHECK = join(root, 'scripts', 'check-quota-impact.mjs');

/**
 * `NAME = <式>;` または `NAME: <数>,`（オブジェクト内）の右辺を取り出して
 * 数値に評価する。右辺は数字・小数点・空白・`* + - ( )` だけを許す
 * （`2 * 1024 * 1024 * 1024` のような自前ソースの定数式を想定）。
 * 見つからない／数式でないときは投げる＝赤くする（定義の移動・改名の検知）。
 */
function numericConst(file, name) {
  const text = readFileSync(file, 'utf8');
  const re = new RegExp(`\\b${name}\\b\\s*[:=]\\s*([0-9.\\s*+()\\-]+?)\\s*[;,]`);
  const m = text.match(re);
  if (!m) {
    throw new Error(`${name} を ${file} から取り出せませんでした（定義が移動／改名された可能性）`);
  }
  const expr = m[1].trim();
  if (!/^[0-9.\s*+()\-]+$/.test(expr)) {
    throw new Error(`${name} の右辺が数式ではありません: ${JSON.stringify(expr)}`);
  }
  // 算術だけを含む自前ソースの式。上の検査で文字を弾いてから評価する。
  // eslint-disable-next-line no-new-func
  return Function(`"use strict"; return (${expr});`)();
}

const GB = 1024 * 1024 * 1024;

test('リストごとの既定は 1GB（config.ts defaultQuotaBytes）', () => {
  // 容量の「単位」の土台。ここを変えると全リストの初期上限が変わる。
  assert.equal(numericConst(CONFIG, 'defaultQuotaBytes'), 1 * GB);
});

test('人ごとの土台の既定は 2GB（quota.ts USER_DEFAULT_QUOTA_BYTES）', () => {
  // アップロードを止めるかどうかを決める土台。単位変更の本体。
  assert.equal(numericConst(QUOTA, 'USER_DEFAULT_QUOTA_BYTES'), 2 * GB);
});

test('通知しきい値は 0.8 / 0.9（quota.ts）', () => {
  // 「使いすぎ」の判定境界。ここを動かすと通知と拒否の起点が変わる。
  assert.equal(numericConst(QUOTA, 'NOTICE_THRESHOLD'), 0.8);
  assert.equal(numericConst(QUOTA, 'WARNING_THRESHOLD'), 0.9);
});

test('自動拡張は 1 回 2GB・上限 10GB（quota.ts）', () => {
  // プレミアムの自動拡張の刻みと天井。実効上限の形を決める。
  assert.equal(numericConst(QUOTA, 'EXPANSION_STEP_BYTES'), 2 * GB);
  assert.equal(numericConst(QUOTA, 'MAX_EXPANDED_QUOTA_BYTES'), 10 * GB);
});

test('影響者計数の基準は 2GB（check-quota-impact.mjs NEW_QUOTA_BYTES）', () => {
  // 影響者を数えるときの「新しい上限」。人ごとの土台と揃っている前提。
  assert.equal(numericConst(CHECK, 'NEW_QUOTA_BYTES'), 2 * GB);
});

test('影響者計数の基準は人ごとの土台と一致している', () => {
  // check-quota-impact.mjs は「人ごとの合計 2GB へ変える前提」で数える。
  // 土台の既定とズレると、数えた影響者が実配信とずれる。
  assert.equal(
    numericConst(CHECK, 'NEW_QUOTA_BYTES'),
    numericConst(QUOTA, 'USER_DEFAULT_QUOTA_BYTES'),
  );
});
