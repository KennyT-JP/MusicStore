#!/usr/bin/env node
/**
 * マニュアルを、章単位のページに分けて `web/help/` へ生成する
 *
 *   node scripts/build-manual.mjs            生成する
 *   node scripts/build-manual.mjs --check    生成物が原本と一致するか見るだけ
 *
 * ---
 *
 * ## なぜ分けるか（AdSense の審査）
 *
 * 共有ドキュメント（`C:\Codes\共有ドキュメント\ナレッジベース.md` S-7）に
 * 別プロジェクトの経験が残っている。審査の 2 大指摘
 * 「コンテンツを含まない画面における広告」「有用性の低いコンテンツ」は、
 * たいてい同じ事実から出る——**広告のあるページに読めるテキストが無く、
 * テキストのあるページに広告が無い。**
 *
 * このアプリは CanvasKit（canvas 描画）なので、**アプリの画面には
 * HTML の文字が 1 つも残らない。** Googlebot は JS を実行するが、
 * 実行しても文字は増えない。だから
 *
 *   - **アプリの画面から広告のコードを完全に外す**（web/index.html）
 *   - **広告は「読み物」であるマニュアルに置く**
 *   - **1 ページを薄くしない**（目安 1,600 字以上。薄いページの量産は
 *     「有用性の低いコンテンツ」に戻る）
 *
 * という配置にする。マニュアルの本文は日本語で約 12,000 字しかないので、
 * **章を 1 つずつページにすると全部が薄くなる。** そこで
 * `PAGES` のまとまり（6 ページ）に束ねる。**見出し ID はそのまま残す**ので、
 * 画面のヘルプは `…/{ページ}.html#{節}` で今までと同じ場所へ着く。
 *
 * ## 原本と生成物
 *
 * | | 場所 | 形 |
 * | --- | --- | --- |
 * | 原本（マニュアル） | `docs/manual/{ja,en}.html` | 1 枚の完成ページ（`<style>` を含む） |
 * | 原本（法務） | `docs/manual/legal-{ja,en}.html` | 本文だけの断片（`<h1>` と `<h2>`） |
 * | 生成物 | `web/help/{ja,en}/*.html` | 目次 1 枚 + 章ページ 6 枚 + プライバシー 1 枚 |
 *
 * **原本は `web/` の外に置く。** 中に置くと 1 枚ページと分割ページの
 * 両方が配信されて、同じ文章が 2 か所に出る（重複コンテンツ）。
 *
 * **手で複製しないこと。** 章を移し替えるときは原本を直して生成し直す。
 * `test/domain/help_links_test.dart` が、原本の各章の文章が生成物の
 * どのページに入っているかまで見ている（生成し忘れると落ちる）。
 */
import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const checkOnly = process.argv.includes('--check');

/** AdSense のパブリッシャー ID。**秘密ではない**（広告を出すページのソースに必ず出る）。 */
const PUBLISHER_ID = 'ca-pub-3984824596223175';

/** 1 ページの本文の下限（タグを除いた文字数）。これを下回ったら生成を止める。 */
const MIN_CHARS = 1600;

/**
 * プライバシーポリシーに出す運営者と連絡先（2026-08-13 に依頼者が指定）。
 *
 * **ここが正本。** 日英の原本には差し込み用の目印だけを書き、値は書かない。
 * 2 か所に書くと、片方だけ直したときに**言語によって連絡先が違う**という
 * 状態になり、しかも誰も気づかない
 * （docs/AUDIT-CHECKLIST.md「同じ内容が 2 か所にあるなら、片方が正本」）。
 */
const OPERATOR = {
  name: "F's Factory",
  contact: 'support@session-concierge.jp',
};

/**
 * ページの束ね方。**日英で同じ**にする。
 *
 * 言語ごとに分け方を変えると、`lib/domain/help_links.dart` の
 * 「節 → ページ」の対応が言語ごとに変わり、片方だけリンク切れになる。
 */
const PAGES = [
  {
    slug: 'start',
    title: { ja: 'はじめる（できること・登録・ログイン）', en: 'Getting started (sign-up and sign-in)' },
    chapters: ['getting-started', 'account', 'sign-in'],
  },
  {
    slug: 'lists',
    title: { ja: 'リストを作る・見る', en: 'Creating and viewing lists' },
    chapters: ['home', 'list-request', 'my-requests', 'list'],
  },
  {
    slug: 'items',
    title: { ja: '曲を追加する・聴く', en: 'Adding and playing tracks' },
    chapters: ['item', 'item-form', 'playback'],
  },
  {
    slug: 'sharing',
    title: { ja: '人を招く（共有リンクと参加申請）', en: 'Inviting people (share links and requests)' },
    chapters: ['share-link', 'join-request'],
  },
  {
    slug: 'members',
    title: { ja: 'メンバーと役割', en: 'Members and roles' },
    chapters: ['members', 'list-settings', 'roles'],
  },
  {
    slug: 'manage',
    title: { ja: '容量・通知・設定・サイト管理', en: 'Storage, notifications, settings, site admin' },
    chapters: ['storage', 'notifications', 'settings', 'site-admin'],
  },
];

/** 目次と法務ページ（広告を置かない）。 */
const INDEX_SLUG = 'index';
const PRIVACY_SLUG = 'privacy';

const LANGUAGES = ['ja', 'en'];

const TEXT = {
  ja: {
    contents: '目次',
    contentsTitle: '音源創庫 使い方',
    other: 'English',
    backToContents: '目次へ戻る',
    prev: '前へ',
    next: '次へ',
    privacy: 'プライバシーポリシー',
    adNotice: 'このページには広告が表示されます。',
    inThisPage: 'このページの内容',
  },
  en: {
    contents: 'Contents',
    contentsTitle: 'Track Cabinet — User guide',
    other: '日本語',
    backToContents: 'Back to contents',
    prev: 'Previous',
    next: 'Next',
    privacy: 'Privacy policy',
    adNotice: 'This page shows advertisements.',
    inThisPage: 'On this page',
  },
};

// ---------------------------------------------------------------------------
// 原本の読み取り
// ---------------------------------------------------------------------------

const plain = (html) => html.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();

/** 原本 1 枚を、共通部分と章に分解する。 */
function readSource(lang) {
  const html = readFileSync(join(root, `docs/manual/${lang}.html`), 'utf8');

  const style = html.match(/<style>[\s\S]*?<\/style>/);
  if (!style) throw new Error(`docs/manual/${lang}.html に <style> がありません`);

  const h1 = html.match(/<h1>([\s\S]*?)<\/h1>/);
  const lede = html.match(/<p class="lede">([\s\S]*?)<\/p>/);
  if (!h1 || !lede) throw new Error(`docs/manual/${lang}.html に <h1> か .lede がありません`);

  // **章は行頭の <h2 id="..."> で始まる。** 目次の中の h2（nav.toc の
  // 「目次」）には id が無いので、id つきだけを拾えば混ざらない。
  const body = html.slice(html.search(/^<h2 id="/m));
  const chapters = new Map();
  for (const block of body.split(/(?=^<h2 id=")/m)) {
    const m = block.match(/^<h2 id="([^"]+)">([\s\S]*?)<\/h2>/);
    if (!m) continue;
    // footer 以降は落とす（生成側で作り直す）。
    const content = block.slice(0, block.search(/^<footer>/m) === -1 ? undefined : block.search(/^<footer>/m));
    chapters.set(m[1], { id: m[1], heading: m[2], html: content.trimEnd() });
  }

  return { style: style[0], h1: h1[1], lede: lede[1], chapters };
}

/** 法務ページの原本（本文だけの断片）。運営者と連絡先を差し込む。 */
function readLegal(lang) {
  const path = `docs/manual/legal-${lang}.html`;
  let html = readFileSync(join(root, path), 'utf8');

  const h1 = html.match(/<h1>([\s\S]*?)<\/h1>/);
  if (!h1) throw new Error(`${path} に <h1> がありません`);

  const body = html
    .slice(html.indexOf('</h1>') + 5)
    .replaceAll('%OPERATOR_NAME%', OPERATOR.name)
    .replaceAll('%OPERATOR_CONTACT%', OPERATOR.contact)
    .trim();

  // **差し込み漏れを配信しない。** 目印を書き間違えると、その文字列が
  // そのまま公開される（運営者名の代わりに目印が出ているポリシーは、
  // 無いのと同じ扱いになる）。
  const leftover = body.match(/%[A-Z_]+%/);
  if (leftover) {
    throw new Error(`${path} に差し込めない目印が残っています: ${leftover[0]}`);
  }
  if (!OPERATOR.name || !OPERATOR.contact) {
    throw new Error('scripts/build-manual.mjs の OPERATOR が空です');
  }

  return { title: h1[1], html: body };
}

// ---------------------------------------------------------------------------
// 生成
// ---------------------------------------------------------------------------

/** どの節がどのページにあるか。**リンクの書き換えに使う。** */
const pageOfAnchor = new Map();
for (const page of PAGES) {
  for (const id of page.chapters) pageOfAnchor.set(id, page.slug);
}

/**
 * ページ内リンク（`#節`）を、分割後の行き先へ書き換える。
 *
 * **ここを飛ばすと、リンクは押せるのに動かない。** 同じページの中なら
 * `#節` のまま、別のページなら `{ページ}.html#節` にする
 * （共有ドキュメント AP-40「部品を取り出せば動くと思い込む」）。
 */
function rewriteLinks(html, currentSlug) {
  return html.replace(/href="#([^"]+)"/g, (whole, anchor) => {
    const slug = pageOfAnchor.get(anchor);
    if (!slug) return whole; // 章の見出し以外（ページ内の小見出し）はそのまま
    return slug === currentSlug ? `href="#${anchor}"` : `href="${slug}.html#${anchor}"`;
  });
}

/** 広告のコード（読み物ページだけに入れる）。 */
function adCode(lang) {
  // **自動広告を使う。** 手動のユニット（ins 要素）には、コンソールで
  // 作った枠の ID（data-ad-slot）が要る。審査前は発行できないので、
  // まずスクリプトだけ置き、配置は Google に任せる。
  // 審査に通ったあと手動ユニットを足すなら、ここへ ins を並べる。
  return `<script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=${PUBLISHER_ID}" crossorigin="anonymous"></script>`;
}

/** 1 ページを組み立てる。 */
function renderPage({ lang, style, slug, title, h1, lede, bodyHtml, ads, nav }) {
  const t = TEXT[lang];
  const other = lang === 'ja' ? 'en' : 'ja';
  // 言語切り替えは**同じページ**へ渡す。目次に落とすと、読んでいた場所が消える。
  const otherHref = slug === INDEX_SLUG ? `../${other}/` : `../${other}/${slug}.html`;

  return `<!DOCTYPE html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<meta name="description" content="${plain(lede).slice(0, 110)}">
<link rel="alternate" hreflang="${other}" href="${otherHref}">
${ads ? adCode(lang) : '<!-- このページに広告は置かない（目次・法務ページ） -->'}
${style}
</head>
<body>
<div class="wrap">

<header>
  <h1>${h1}</h1>
  <p class="lede">${lede}</p>
</header>

<p class="langswitch"><a href="${otherHref}">${t.other}</a>${slug === INDEX_SLUG ? '' : ` ／ <a href="./">${t.backToContents}</a>`}</p>

${nav}

${bodyHtml}

<footer>
  <p class="totop"><a href="./">${t.backToContents}</a> ／ <a href="${slug === PRIVACY_SLUG ? './' : 'privacy.html'}">${t.privacy}</a> ／ <a href="${otherHref}">${t.other}</a></p>
</footer>

</div>
</body>
</html>
`;
}

/** 章ページの「このページの内容」（節が 2 つ以上あるときだけ出す）。 */
function pageNav(lang, chapters) {
  if (chapters.length < 2) return '';
  const items = chapters
    .map((c) => `    <li><a href="#${c.id}">${c.heading}</a></li>`)
    .join('\n');
  return `<nav class="toc">
  <h2>${TEXT[lang].inThisPage}</h2>
  <ol>
${items}
  </ol>
</nav>`;
}

/** 目次ページ。**薄いので広告は置かない。** */
function indexNav(lang, source) {
  const t = TEXT[lang];
  const items = PAGES.map((page) => {
    const inner = page.chapters
      .map((id) => `<a href="${page.slug}.html#${id}">${source.chapters.get(id).heading}</a>`)
      .join(' ／ ');
    return `    <li><a href="${page.slug}.html"><strong>${page.title[lang]}</strong></a><br>${inner}</li>`;
  }).join('\n');

  return `<nav class="toc">
  <h2>${t.contents}</h2>
  <ol>
${items}
  </ol>
</nav>`;
}

function buildLanguage(lang) {
  const source = readSource(lang);
  const legal = readLegal(lang);
  const files = new Map();
  /** ページごとの本文の文字数。**`<style>` の中身を数に入れないため、本文で測る。** */
  const bodyChars = new Map();

  // 章がどこかへ必ず入っていること。**原本に足した章を PAGES へ書き
  // 忘れると、その章は配信されない**（画面のヘルプが 404 になる）。
  const placed = new Set(PAGES.flatMap((p) => p.chapters));
  const orphans = [...source.chapters.keys()].filter((id) => !placed.has(id));
  if (orphans.length > 0) {
    throw new Error(
      `docs/manual/${lang}.html の章が PAGES に入っていません: ${orphans.join(', ')}\n` +
        'scripts/build-manual.mjs の PAGES に足してください。',
    );
  }
  const missing = [...placed].filter((id) => !source.chapters.has(id));
  if (missing.length > 0) {
    throw new Error(`PAGES が、原本に無い章を指しています: ${missing.join(', ')}`);
  }

  // 章ページ
  for (const page of PAGES) {
    const chapters = page.chapters.map((id) => source.chapters.get(id));
    const bodyHtml = rewriteLinks(chapters.map((c) => c.html).join('\n\n'), page.slug);

    // **薄いページを作らない。** 下回ったら束ね方を見直す合図。
    const length = plain(bodyHtml).length;
    if (length < MIN_CHARS) {
      throw new Error(
        `${lang}/${page.slug}.html の本文が ${length} 字で、下限 ${MIN_CHARS} 字を下回ります。\n` +
          'PAGES の束ね方を見直してください（薄いページを増やすと審査の指摘に戻ります）。',
      );
    }

    bodyChars.set(`${page.slug}.html`, length);
    files.set(`${page.slug}.html`, renderPage({
      lang,
      style: source.style,
      slug: page.slug,
      title: `${page.title[lang]} | ${plain(source.h1)}`,
      h1: page.title[lang],
      lede: source.lede,
      bodyHtml,
      ads: true,
      nav: pageNav(lang, chapters),
    }));
  }

  // 目次
  bodyChars.set('index.html', plain(indexNav(lang, source)).length);
  files.set('index.html', renderPage({
    lang,
    style: source.style,
    slug: INDEX_SLUG,
    title: TEXT[lang].contentsTitle,
    h1: source.h1,
    lede: source.lede,
    bodyHtml: '',
    ads: false,
    nav: indexNav(lang, source),
  }));

  // プライバシーポリシー
  bodyChars.set('privacy.html', plain(legal.html).length);
  files.set('privacy.html', renderPage({
    lang,
    style: source.style,
    slug: PRIVACY_SLUG,
    title: `${plain(legal.title)} | ${plain(source.h1)}`,
    h1: legal.title,
    lede: source.lede,
    bodyHtml: legal.html,
    ads: false,
    nav: '',
  }));

  return { files, bodyChars };
}

// ---------------------------------------------------------------------------
// 書き出し
// ---------------------------------------------------------------------------

let changed = 0;
for (const lang of LANGUAGES) {
  const dir = join(root, 'web/help', lang);
  const { files, bodyChars } = buildLanguage(lang);

  if (checkOnly) {
    for (const [name, content] of files) {
      const path = join(dir, name);
      const current = existsSync(path) ? readFileSync(path, 'utf8') : '';
      if (current !== content) {
        console.error(`古い: web/help/${lang}/${name}`);
        changed += 1;
      }
    }
    continue;
  }

  mkdirSync(dir, { recursive: true });

  // **消えた章のページを残さない。** 生成物のディレクトリは毎回作り直す。
  for (const name of existsSync(dir) ? readdirSync(dir) : []) {
    if (name.endsWith('.html') && !files.has(name)) {
      rmSync(join(dir, name));
      console.log(`削除: web/help/${lang}/${name}`);
    }
  }

  for (const [name, content] of files) {
    writeFileSync(join(dir, name), content);
    console.log(`生成: web/help/${lang}/${name}（本文 ${bodyChars.get(name)} 字）`);
  }
}

if (checkOnly) {
  if (changed > 0) {
    console.error(`\n生成物が原本と一致しません（${changed} 件）。`);
    console.error('  node scripts/build-manual.mjs');
    process.exit(1);
  }
  console.log('生成物は原本と一致しています。');
}
