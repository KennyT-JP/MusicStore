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

**実行するのは 1 つのコマンドです。**

```
scripts\test-all.cmd        （Windows）
./scripts/test-all.sh       （macOS / Linux）
```

中で次の 5 つを順に実行し、**1 つでも赤ければそこで止まります**。
エミュレータの起動と後片付けは中で行うので、**ウィンドウは 1 つで済みます。**

| 実行されるもの | 件数 | エミュレータ |
| --- | --- | --- |
| `dart analyze` | — | 不要 |
| `flutter test` | 278 | 不要 |
| `cd functions && npm test` | 75 | 不要 |
| `cd rules-test && npm test` | 124 | 自動で起動・終了 |
| `cd functions && npm run test:integration` | 61 | 自動で起動・終了 |

（件数は 2026-08-08 時点）

> **`flutter analyze` ではなく `dart analyze` を使います。**
> `flutter analyze` は**パスに日本語が含まれると異常終了します**
> （Flutter 3.44.9 で実測）。`dart analyze` は同じ解析器で同じ指摘を出します。

> **Java は 21 以上が要ります。** `firebase-tools` 15 以降の要件です。
> 17 では `Please install a JDK at version 21 or above` で止まります。

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

- **配信の前にコミットする。** 検証環境へ出すなら `dev` へ、本番へ出すなら
  `main` へコミットしてから配信します。**`scripts/deploy.mjs` が枝と
  未コミットの変更を見ていて、条件を満たさなければ配信しません**
- 確認が取れたものだけを `main` へ入れます（`git switch main && git merge --no-ff dev`）
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

## 参照する文書

- `docs/HANDOVER.md` — **担当を交代したら最初にここ。** 現状と次の一手
- `docs/MusicListApp_Spec.md` — 仕様書。振る舞いを変えたらここも直す
- `docs/DEVLOG.md` — 経緯。同じ失敗を繰り返さないための記録
- `docs/AUDIT-CHECKLIST.md` — 監査で**見つけられなかった**欠陥の記録
- `docs/SETUP.md` — 環境構築と実行手順
- `docs/BACKLOG.md` — 後回しにしたこと
- `docs/CONVERSATION-LOG.md` — 依頼者とのやりとりの原文。**要約では落ちる言い回しを確かめたいとき**に見る
