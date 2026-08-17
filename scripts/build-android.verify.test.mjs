#!/usr/bin/env node
/**
 * verifyLibapp の固定テスト（node --test）
 *
 *   node --test scripts\build-android.verify.test.mjs
 *
 * 実ビルド（flutter build appbundle、約 3 分）を回さずに、検査ロジックだけ
 * を固定する。狙いは監査 第5回・AP-71 の再発防止——**アプリのコードが
 * 入っていない抜け殻の成果物**を、サイズと記号の 2 条件で確実に弾けること。
 *
 * ダミー Buffer で以下を確かめる:
 *   ・5MB 以上 かつ "MusicListApp" を含む → ok
 *   ・空 / 5MB 未満                        → fail（サイズ不足）
 *   ・"MusicListApp" を含まない            → fail（記号なし）
 */
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { verifyLibapp } from './build-android.mjs';

const MIN = 5 * 1024 * 1024;
const SYMBOL = 'MusicListApp';

/**
 * 指定サイズのダミー libapp.so を作る。needle を含めると記号あり相当。
 * ネイティブバイナリを模して 0x00 埋めのなかに ASCII 記号を 1 箇所置く。
 */
function fakeLibapp(sizeBytes, { withSymbol } = { withSymbol: true }) {
  const buf = Buffer.alloc(sizeBytes); // 0x00 埋め
  if (withSymbol && sizeBytes >= SYMBOL.length) {
    // 中ほどに記号を書き込む（先頭・末尾どちらでもないところ）。
    Buffer.from(SYMBOL, 'ascii').copy(buf, Math.floor(sizeBytes / 2));
  }
  return buf;
}

test('5MB 以上かつ MusicListApp を含む → ok', () => {
  const buf = fakeLibapp(MIN + 1024, { withSymbol: true });
  const r = verifyLibapp(buf);
  assert.equal(r.ok, true);
  assert.equal(r.hasSymbol, true);
  assert.equal(r.sizeBytes, MIN + 1024);
  assert.equal(r.reason, null);
});

test('ちょうど下限（5MB）かつ記号あり → ok（境界は「以上」で通す）', () => {
  const buf = fakeLibapp(MIN, { withSymbol: true });
  const r = verifyLibapp(buf);
  assert.equal(r.ok, true);
});

test('空 Buffer → fail（サイズ不足・記号なし）', () => {
  const r = verifyLibapp(Buffer.alloc(0));
  assert.equal(r.ok, false);
  assert.equal(r.sizeBytes, 0);
  assert.equal(r.hasSymbol, false);
  assert.ok(r.reason && r.reason.length > 0);
});

test('5MB 未満（記号は含む）→ fail（サイズ不足）', () => {
  // 空 APK 事故時の実測 ≈ 1.97MB を模す。
  const buf = fakeLibapp(Math.floor(1.97 * 1024 * 1024), { withSymbol: true });
  const r = verifyLibapp(buf);
  assert.equal(r.ok, false);
  assert.equal(r.hasSymbol, true); // 記号はあるが
  assert.ok(r.reason.includes('下限')); // サイズで落ちる
});

test('5MB 以上だが MusicListApp を含まない → fail（記号なし）', () => {
  const buf = fakeLibapp(MIN + 1024, { withSymbol: false });
  const r = verifyLibapp(buf);
  assert.equal(r.ok, false);
  assert.equal(r.hasSymbol, false);
  assert.ok(r.reason.includes(SYMBOL)); // 記号名が理由に出る
});

test('options で下限・記号を上書きできる（純関数として設定に依存しない）', () => {
  const buf = fakeLibapp(1024, { withSymbol: false });
  // 下限を 512B、記号を Buffer に実在する 0x00 由来ではなく別語に。
  const withCustomSymbol = Buffer.concat([buf, Buffer.from('HELLO', 'ascii')]);
  const r = verifyLibapp(withCustomSymbol, { minBytes: 512, symbol: 'HELLO' });
  assert.equal(r.ok, true);
  assert.equal(r.hasSymbol, true);
});
