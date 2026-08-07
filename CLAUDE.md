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

実行するテストは次の 4 つです（件数は 2026-08-07 時点）。

| 実行するもの | 件数 | エミュレータ |
| --- | --- | --- |
| `flutter analyze` / `flutter test` | 274 | 不要 |
| `cd rules-test && npm test` | 124 | スクリプトが自動で起動・終了 |
| `cd functions && npm test` | 75 | 不要 |
| `cd functions && npm run test:integration` | 55 | **別のウィンドウで `npm run serve` が必要** |

## 開発の進め方

- 変更は必ずブランチ `claude/attachment-continuation-ryb7wv` に対して行う
- プルリクエストは、依頼者が明示的に求めたときだけ作る
- サービスアカウントの鍵は絶対にコミットしない（`.gitignore` で除外済み）
- `functions/.env*` はコミットするので、秘密の値を書かない
  （秘密は `firebase functions:secrets:set` で Secret Manager へ）

## エミュレータのプロジェクト ID

エミュレータは必ず `demo-musiclist`（架空のプロジェクト）で起動する。
`.firebaserc` の既定は検証環境の `music-storage-dev` なので、
`--project demo-musiclist` を付け忘れると実在のプロジェクト ID で
立ち上がり、テストが噛み合わなくなる。

## 参照する文書

- `docs/HANDOVER.md` — **担当を交代したら最初にここ。** 現状と次の一手
- `docs/MusicListApp_Spec.md` — 仕様書。振る舞いを変えたらここも直す
- `docs/DEVLOG.md` — 経緯。同じ失敗を繰り返さないための記録
- `docs/AUDIT-CHECKLIST.md` — 監査で**見つけられなかった**欠陥の記録
- `docs/SETUP.md` — 環境構築と実行手順
- `docs/BACKLOG.md` — 後回しにしたこと
