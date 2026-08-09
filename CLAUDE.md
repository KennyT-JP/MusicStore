# このリポジトリで作業するときの決めごと

## 配信（デプロイ）の前には必ずテストを通す

**テストを飛ばして配信することは、依頼者が明示的にそう言わない限りありません。**

配信してから不具合が出るのを防ぐためにテストがあります。
「テストは必須ではないので先に配信しても構いません」といった案内は
してはいけません。順序は常に次のとおりです。

1. テストを全件実行する
2. 全件成功したことを確認する
3. そのうえで配信する

テストが 1 件でも失敗している状態で配信してはいけません。
失敗したまま進めてよいかどうかを決めるのは依頼者です。こちらから
「影響が無いので進められます」と促さないこと。

**この順序は仕組みになっています。** `scripts/check.mjs` が全部緑だった
コミットの ID を `.last-check.json` に残し、`scripts/deploy.mjs` は
HEAD と一致しなければ**その場で検証を実行してから**配信します。
つまり **`deploy` だけ実行すれば、順序は自動的に守られます。**

検証だけを回すときは 1 コマンドです（約 4 分・並列・別窓なし）。

```
scripts\check.cmd        （Windows）
./scripts/check.sh       （macOS / Linux）
```

4 本を同時に走らせ、失敗があれば最後にまとめて出ます。

| 並列で実行されるもの | 件数 |
| --- | --- |
| `dart analyze --fatal-infos` | **指摘 0 件が基準**（info も失敗扱い） |
| `flutter test` | 314 |
| `functions` の単体テスト | 85 |
| エミュレータ系（統合 → ルールの順に直列） | 75 + 124 |

（件数は 2026-08-09 時点）

> **`flutter analyze` ではなく `dart analyze` を使います。**
> `flutter analyze` は**パスに日本語が含まれると異常終了します**
> （Flutter 3.44.9 で実測）。`dart analyze` は同じ解析器で同じ指摘を出します。

> **Java は 21 以上が要ります。** `firebase-tools` 15 以降の要件です。
> 17 では `Please install a JDK at version 21 or above` で止まります。
> 17 と 21 が両方入っていても、`check.mjs` が版を見て 21 以上を選びます。

## 開発の進め方

### 枝の使い分け（2026-08-08 の指示）

```
main   ← **本番はここからのみ配信する。** これが唯一の本番の出どころ
  ▲
  │ 確認が取れたらマージ
  │
dev    ← **検証環境（staging）専用。** 検証環境への配信はここから
```

| 環境 | 配信元の枝 | コマンド |
| --- | --- | --- |
| 検証（staging） | `dev` | `scripts\deploy.cmd` |
| **本番** | **`main` のみ** | `scripts\deploy.cmd prod` |

`deploy` は配信の前後で次を自動で行います（詳細は `scripts/deploy.mjs` の冒頭）。

- **変更のあった層だけ配信する。** 前回配信したコミット（git タグ
  `deploy/staging` / `deploy/prod`）からの差分で、ルール・索引・関数・
  Hosting のどれを出すか決める。関数だけの変更なら 5 分の Web ビルドを飛ばす
- **検証済みのコミットしか配信しない**（上の節）
- **新規 callable の呼び出し許可を自動で付け、配信後に全 callable と
  Hosting の疎通を実際に確かめる**（`internal` と Site Not Found を配信の中で捕まえる）

- **配信の前にコミットする。** 検証環境へ出すなら `dev` へ、本番へ出すなら
  `main` へコミットしてから配信します。**`scripts/deploy.mjs` が枝と
  未コミットの変更を見ていて、条件を満たさなければ配信しません**
- **本番へは、依頼者が検証環境で確認してから**（2026-08-08 の指示）。
  検証環境へ配信したら、そこで止まって依頼者の確認を待つ。
  **検証環境と本番へ続けて配信しない。** 依頼者が明示したときだけ例外
- 確認が取れたものだけを `main` へ入れます（`git switch main && git merge --no-ff dev`）。
  **`main` へのマージ自体が「確認済み」の意味を持つ**ので、確認前にマージしない
- プルリクエストは、依頼者が明示的に求めたときだけ作る
- サービスアカウントの鍵は絶対にコミットしない（`.gitignore` で除外済み）
- `functions/.env*` はコミットするので、秘密の値を書かない
  （秘密は `firebase functions:secrets:set` で Secret Manager へ）

## エミュレータのプロジェクト ID

エミュレータは必ず `demo-musiclist`（架空のプロジェクト）で起動する。
`.firebaserc` の既定は検証環境の `music-storage-dev` なので、
`--project demo-musiclist` を付け忘れると実在のプロジェクト ID で
立ち上がり、テストが噛み合わなくなる。

## 接続設定を作り直したら firebase.json を確かめる

`scripts/configure-firebase.cmd`（中身は `flutterfire configure`）は、
**`firebase.json` を 1 行に潰して書き換えます。** キャッシュ指定が
丸ごと消え、アイコンが出ない不具合（2026-08-07）が再発します。

```
git status                       ← firebase.json が modified になっていないか
git checkout -- firebase.json    ← なっていたら捨てる。リポジトリ側が正本
```

**残すのは `lib/env/firebase_options_staging.dart` と `_prod.dart` の 2 つだけ**
です。それ以外の変更は捨ててください。

## `git reset --hard` を使わない

接続設定の 2 ファイルは「リポジトリ側は `REPLACE_ME`、手元だけ実際の値」
という作りなので、**作業ツリーを巻き戻すと巻き添えで消えます。**
消えると配信できません（2026-08-09 に実際にやりました）。

枝の位置だけを戻したいときは、**別の枝に切り替えてから** `git branch -f`
を使ってください。作業ツリーに触れません。

```
git switch dev
git branch -f main <戻したい位置>
```

やむを得ず巻き戻したときは、接続設定を作り直してください
（`scripts\configure-firebase.cmd` と `… prod`。そのあと
`firebase.json` が壊れていないか `git status` で確認）。

## 参照する文書

- `docs/HANDOVER.md` — **担当を交代したら最初にここ。** 現状と次の一手
- `docs/MusicListApp_Spec.md` — 仕様書。振る舞いを変えたらここも直す
- `docs/DEVLOG.md` — 経緯。同じ失敗を繰り返さないための記録
- `docs/AUDIT-CHECKLIST.md` — 監査で**見つけられなかった**欠陥の記録
- `docs/SETUP.md` — 環境構築と実行手順
- `docs/BACKLOG.md` — 後回しにしたこと
- `docs/CONVERSATION-LOG.md` — 依頼者とのやりとりの原文。**要約では落ちる言い回しを確かめたいとき**に見る
