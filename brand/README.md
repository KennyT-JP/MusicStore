> 元は依頼者から受領した brand フォルダの README。正本としてリポジトリに取り込んだ（2026-08-10）。

# 音源創庫 / TRACK CABINET — ブランドアセット

コンセプトは **Resonance（共鳴の輪）**。中心のアップロードアイコンから左右へ音の輪が広がる形で、
「誰かが上げた音源が、みんなに広がっていく」を表しています。寒色（ネイビー→ブルー→シアン）で
Cool な印象に統一しています。

---

## カラーパレット

| 役割 | HEX | 用途 |
|---|---|---|
| Deep Navy | `#071426` | 背景グラデーションの起点、最も暗い面 |
| Navy | `#0B2648` | アイコン内グリフ、ライト背景での文字色（`#0B2648`） |
| Midnight Blue | `#0F3560` | 背景グラデーション中間 |
| Ocean Blue | `#12557F` | 背景グラデーション終点 |
| Primary Blue | `#3B82F6` | リング下端、アクセント |
| Sky | `#7DD3FC` | 補助・装飾 |
| Cyan | `#67E8F9` / `#5EE0F7` | コア、英字ロゴ、リンクやフォーカス |
| Ice | `#A5F3FC` | リング上端、最も明るいハイライト |
| Text on dark | `#EAF6FF` | 暗背景の見出し・ワードマーク |
| Text sub | `#9FC2E4` | 暗背景の本文・キャプション |

グラデーションはいずれも左上→右下（`x1=0 y1=0 x2=1 y2=1`）。

---

## ファイル一覧

### SVG（マスター / 拡大縮小自由）

| ファイル | 用途 |
|---|---|
| `icon.svg` | アプリアイコン本体（512基準・角丸タイル） |
| `favicon.svg` | 16〜64px 用の簡略版（外側リング省略・線を太く） |
| `icon-maskable.svg` | PWA maskable 用（全面塗り＋セーフゾーン対応） |
| `icon-mono.svg` | 単色版・背景透明。`currentColor` で着色可 |
| `logo-inline-dark.svg` | **サイトトップ用 横一列ロックアップ / 暗背景用** |
| `logo-inline-light.svg` | **サイトトップ用 横一列ロックアップ / 明背景用** |
| `logo-inline-dark-notile.svg` | 同上・濃紺ヘッダー用（アイコンの角丸タイルなし） |
| `logo-horizontal-dark.svg` | 横組み2段ロゴ / 暗背景用 |
| `logo-horizontal-light.svg` | 横組み2段ロゴ / 明背景用 |
| `logo-vertical-dark.svg` | 縦組みロゴ / 暗背景用 |
| `logo-vertical-light.svg` | 縦組みロゴ / 明背景用 |
| `og-image.svg` | OGP / Twitter Card 用 1200×630 |
| `favicon.ico` | 16/32/48 マルチサイズ ICO |

### PNG（`png/` 配下）

| ファイル | サイズ |
|---|---|
| `icon-512 / 256 / 192 / 128.png` | アプリ・PWA 各サイズ |
| `apple-touch-icon.png` | 180×180（iOS ホーム画面） |
| `favicon-16 / 32 / 48 / 64.png` | ファビコン各サイズ |
| `icon-maskable-512 / 192.png` | PWA maskable |
| `icon-mono-navy-512.png` / `icon-mono-white-512.png` | 単色・背景透明 |
| `logo-inline-dark(@2x/@3x).png` / `logo-inline-light(…)` / `logo-inline-dark-notile(…)` | 高さ 39 / 78 / 117 |
| `logo-horizontal-dark(@2x).png` / `logo-horizontal-light(@2x).png` | 600×256 / 1200×512 |
| `logo-vertical-dark.png` / `logo-vertical-light.png` | 520×420 |
| `og-image.png` | 1200×630 |

---

## Web への組み込み

`web/index.html` の `<head>` に:

```html
<link rel="icon" type="image/svg+xml" href="/brand/favicon.svg">
<link rel="icon" type="image/png" sizes="32x32" href="/brand/png/favicon-32.png">
<link rel="icon" type="image/png" sizes="16x16" href="/brand/png/favicon-16.png">
<link rel="apple-touch-icon" sizes="180x180" href="/brand/png/apple-touch-icon.png">
<link rel="manifest" href="/manifest.json">
<meta name="theme-color" content="#0B2044">

<meta property="og:title" content="音源創庫 | TRACK CABINET">
<meta property="og:description" content="みんなで音源をアップして、共有する。">
<meta property="og:image" content="https://music-storage-d79b2.web.app/brand/png/og-image.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:type" content="website">
<meta name="twitter:card" content="summary_large_image">
```

`manifest.json`:

```json
{
  "name": "音源創庫",
  "short_name": "音源創庫",
  "description": "みんなで音源をアップして、共有する。",
  "background_color": "#071426",
  "theme_color": "#0B2044",
  "display": "standalone",
  "icons": [
    { "src": "/brand/png/icon-192.png", "sizes": "192x192", "type": "image/png", "purpose": "any" },
    { "src": "/brand/png/icon-512.png", "sizes": "512x512", "type": "image/png", "purpose": "any" },
    { "src": "/brand/png/icon-maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
    { "src": "/brand/png/icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
```

---

## サイトトップ（ヘッダー）へのロゴ設置

`logo-inline-*.svg` は「アイコン → 音源創庫 → TRACK CABINET」を横一列に並べた
ヘッダー専用のロックアップです。寸法は次の関係で組んであります。

- 行の高さ ＝ 日本語「音源創庫」の字面高さ **35.25**（font-size 38 のまま）
- アイコン ＝ その **110% = 38.78**（＝ロゴ全体の高さ）
- 日本語・英語・アイコンはすべて上下中央でそろえてある
- 文字幅は `textLength` で固定してあるため、フォント環境が変わってもレイアウトが崩れない

```html
<!-- 高さだけ指定すれば横幅は縦横比なりに決まる -->
<a class="site-logo" href="/">
  <img src="/brand/logo-inline-dark.svg" alt="音源創庫 TRACK CABINET" height="40">
</a>
```

```css
.site-logo img { height: 40px; width: auto; display: block; }
@media (max-width: 600px) { .site-logo img { height: 32px; } }
```

背景による使い分け:

| ヘッダーの地色 | 使うファイル |
|---|---|
| 白・淡いグレー | `logo-inline-light.svg` |
| 濃紺（`#0B2044` 前後）・黒 | `logo-inline-dark-notile.svg` |
| 写真やグラデーションの上 | `logo-inline-dark.svg`（アイコンのタイルが輪郭になる） |

`logo-inline-dark.svg` はアイコンが角丸タイル付きなので、地色がネイビー系だとタイルが
背景に溶けます。濃紺ヘッダーにはタイルなしの `-notile` を使ってください。

---

## 使い方のルール

- **余白**：ロゴの周囲には、アイコンの高さの 1/4 以上の余白を確保する。
- **最小サイズ**：横一列ロックアップは高さ 28px 以上（それ以下では英語が潰れるので
  アイコン単体か縦組みに切り替える）。横組み2段ロゴは幅 120px 以上、アイコン単体は 16px 以上。
  16〜64px では `icon.svg` ではなく `favicon.svg`（簡略版）を使う。
- **背景**：明背景には `-light`、暗背景には `-dark` を使う。中間的な写真の上に置く場合は
  暗いオーバーレイを敷いた上で `-dark` を使う。
- **やってはいけないこと**：ロゴの縦横比を変える／配色を寒色系以外に置き換える／
  リングとコアの間隔を詰める／ワードマークを別フォントで組み直す。

## フォントについて

ワードマークは `Noto Sans JP` Bold（フォールバック：Hiragino Kaku Gothic ProN → Yu Gothic → Meiryo）
で組んでいます。SVG はテキスト要素のまま持っているため、Web で使う場合は Noto Sans JP を読み込むか、
フォント環境に依存しない `png/` 内のラスタ版を使ってください。

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Noto+Sans+JP:wght@400;600;700&display=swap" rel="stylesheet">
```

## PNG の再書き出し

SVG を編集したあと、`png/` 以下を作り直す手順:

```bash
pip install resvg-py pillow
python export.py
```

（`export.py` は本ディレクトリに同梱。resvg は SVG 内の引用符付きフォントスタックを
解決できないため、書き出し時にフォント名を実名へ差し替えています。）
