# セットアップ手順

このリポジトリを動かすまでの手順です。仕様書の該当箇所を併記しています。

**Firebase プロジェクトを作らなくても、ローカルのエミュレータですぐ動かせます。** まずは「2. エミュレータで動かす」を試し、クラウドへの接続はそのあとで構いません。

---

## 1. 開発環境

| 必要なもの | バージョン | 確認コマンド |
| --- | --- | --- |
| Flutter SDK | 3.44 以上 | `flutter --version` |
| Node.js | 20 以上 | `node --version` |
| Java | 11 以上（Firestore エミュレータが JVM 上で動く） | `java -version` |
| Firebase CLI | 最新 | `firebase --version` |

```sh
# Firebase CLI
npm install -g firebase-tools

# FlutterFire CLI（クラウドに接続するときに使う）
dart pub global activate flutterfire_cli
```

`firebase login` は、クラウドのプロジェクトを操作するときだけ必要です。エミュレータだけならログイン不要です。

---

## 2. エミュレータで動かす（Firebase プロジェクト不要）

ローカルのエミュレータに接続してアプリを起動します。クラウドの検証環境にも触れないため、気兼ねなく試せます。

> **すべて「ご自身のパソコン」で実行してください。**
> エミュレータはインターネット上のどこかで動いているサービスではなく、
> コマンドを実行したマシンの中だけで動きます。
> このあと出てくる `127.0.0.1`（= localhost）は「いま自分が使っているマシン」を指すため、
> **エミュレータを起動したのと同じマシンのブラウザからでないと開けません。**
>
> はじめに、リポジトリを手元に取得してください。
>
> ```sh
> git clone https://github.com/KennyT-JP/MusicStore.git
> cd MusicStore
> ```

```sh
# ターミナル 1：エミュレータを起動（Functions のビルドもまとめて行う）
./scripts/dev-emulators.sh

# ターミナル 2：動作確認用のデータを入れる（初回のみ）
./scripts/seed.sh

# ターミナル 3：アプリを起動
flutter pub get
flutter run -d chrome --dart-define=USE_EMULATOR=true
```

**うまく繋がらないときは、まず診断を実行してください。**

```sh
node scripts/doctor.mjs
```

必要なコマンド・Functions のビルド状況・ポートの使用状況・接続可否を順に調べ、
問題があれば直し方を表示します。

`seed-emulator.js` が投入するもの：

| 内容 | 詳細 |
| --- | --- |
| ユーザー 4 人 | サイト管理者・リスト管理者・Super User・Read Only。パスワードはすべて `password` |
| リスト 1 つ | 「練習音源」 |
| 項目 3 件 | うち 1 件は削除済み（連番 3 が欠番として残る様子を確認できる） |
| コメント 4 件 | 3 段の入れ子を含む |

ログイン用のメールアドレス：

```
site-admin@example.com   サイト管理者
list-admin@example.com   山田（リスト管理者）
super-user@example.com   佐藤（Super User）
read-only@example.com    鈴木（Read Only）
```

エミュレータの管理画面は、**エミュレータを起動したマシンのブラウザ**から
<http://127.0.0.1:4000> で開けます（データの中身や登録済みユーザーを確認できます）。

> **開けない場合、まず「どこでエミュレータを起動したか」を確かめてください。**
>
> | 起動した場所 | ブラウザから開けるか |
> | --- | --- |
> | 自分のパソコン | 開けます |
> | WSL / Dev Container / Docker | **そのままでは開けません。** ポート転送が必要です |
> | 社内サーバー・クラウド上の環境に SSH 接続して起動 | **開けません。** SSH のポート転送が必要です |
>
> WSL2 の場合は通常そのまま開けますが、開けないときは WSL 側で
> `firebase emulators:start --host 0.0.0.0` のように待ち受けアドレスを広げるか、
> Windows 側から `netsh interface portproxy` で転送します。
>
> SSH 越しの場合は接続時にポートを転送します。
>
> ```sh
> ssh -L 4000:127.0.0.1:4000 -L 8080:127.0.0.1:8080 \
>     -L 9099:127.0.0.1:9099 -L 9199:127.0.0.1:9199 \
>     -L 5001:127.0.0.1:5001 ユーザー名@ホスト
> ```

> **本番環境ではエミュレータに繋がりません。** `--dart-define=APP_ENV=prod` を指定した場合、`USE_EMULATOR=true` があっても無視します。本番のつもりでエミュレータを見ていた、という取り違えを防ぐためです。

> **エミュレータのデータは消えます。** エミュレータを止めるとリセットされるため、必要なら `./scripts/seed.sh` を再実行してください。

### エミュレータに繋がらないとき

`node scripts/doctor.mjs` を実行したうえで、症状ごとに次を確認してください。

| 症状 | 原因と対処 |
| --- | --- |
| `Failed to load function definition from source` | **Functions がビルドされていません。** `cd functions && npm install && npm run build`。`./scripts/dev-emulators.sh` を使えば自動で行われます |
| `firebase login` を求められる／実プロジェクトに繋ごうとする | `--project demo-musiclist` を付け忘れています。`demo-` で始まる ID だとクラウドに一切アクセスしません |
| `Port taken` / `port is not open` | 前回のエミュレータが残っています。`pkill -f "firebase.*emulators"` で止めてから起動し直してください |
| アプリが `FirebaseNotConfiguredError` で止まる | `--dart-define=USE_EMULATOR=true` を付け忘れています。付けないとクラウドの検証環境に繋ごうとします |
| アプリは起動するがデータが出ない／権限エラー | `./scripts/seed.sh` を実行していないか、エミュレータを再起動してデータが消えています |
| `Unable to parse JSON: ... "denied by ..."` | プロキシが localhost の通信を横取りしています。`export NO_PROXY=127.0.0.1,localhost` を設定してください。`dev-emulators.sh` は自動で設定します |
| `Cannot find module '@firebase/app'` | `cd functions && npm install` をやり直してください |
| Java のエラーで Firestore が起動しない | JDK 11 以上が必要です。`java -version` で確認してください |
| `http://127.0.0.1:4000` が開けない（接続拒否） | **エミュレータを起動したマシンと、ブラウザを開いているマシンが違います。** 上の表を参照してください。同じマシンなら、そもそもエミュレータが起動していません |

上のどれにも当てはまらない場合は、`firebase emulators:start` の出力の**最後の 10 行**を控えてください。原因はたいていそこに出ています。

---

## 3. Firebase プロジェクトの作成（仕様書 12.1 / 12.2）

**本番と検証（ステージング）を別々のプロジェクトとして作成します。** Firestore のデータ・Storage のファイル・認証ユーザーがプロジェクト単位で完全に独立するため、検証作業が本番データを壊す事故を構造的に防げます。

1. [Firebase コンソール](https://console.firebase.google.com/)で 2 つのプロジェクトを作成する。**作成済み。**
   - 本番用：`Music-Storage`
   - 検証用：`Music-Storage-dev`
2. **両方を Blaze プラン（従量課金）に切り替える。** Cloud Functions を使うため Spark プランでは要件を満たせません（仕様書 12.1）。
3. 各プロジェクトで次を有効化する。
   - Authentication（Google／メールとパスワード）
   - Cloud Firestore
   - Cloud Storage
   - Cloud Functions
   - Hosting

### 予算アラートの設定（必須／仕様書 12.1）

**予算超過時の自動停止は実装しない方針**のため、アラートによる検知が唯一の防波堤になります。必ず設定してください。

1. Google Cloud コンソール → お支払い → 予算とアラート
2. **本番・検証の両プロジェクト**に予算を作成する（検証環境の想定額は本番より低く設定）
3. しきい値を **50% / 90% / 100%** の 3 段階で設定
4. 通知先をサイト管理者のメールアドレスにする

---

## 4. 接続設定の生成

`.firebaserc` には次を設定済みです。

```json
{
  "projects": {
    "default": "music-storage-dev",
    "staging": "music-storage-dev",
    "prod": "music-storage-d79b2"
  }
}
```

| 環境 | コンソールの表示名 | プロジェクト ID |
| --- | --- | --- |
| 本番 | `Music-Storage` | `music-storage-d79b2` |
| 検証 | `Music-Storage-dev` | `music-storage-dev` |

> **本番の ID は表示名と一致しません。** Firebase のプロジェクト ID は小文字で、
> 同じ名前が既に使われている場合は末尾にランダムな文字列が付きます。
> 本番はこれに該当し、`music-storage` ではなく `music-storage-d79b2` になっています。
> コマンドで `--project` を指定するときは ID のほうを使ってください。

続いて、Flutter 側の接続設定を生成します。

```sh
# 検証環境
flutterfire configure \
  --project=music-storage-dev \
  --out=lib/env/firebase_options_staging.dart \
  --platforms=web,android,ios

# 本番環境
flutterfire configure \
  --project=music-storage-d79b2 \
  --out=lib/env/firebase_options_prod.dart \
  --platforms=web,android,ios
```

生成された 2 ファイルを `lib/env/firebase_options.dart` から読み込むように書き換えます。現在は起動を止めるためのプレースホルダーが入っており、そのままでは `FirebaseNotConfiguredError` を投げて止まります。

```dart
import 'firebase_options_prod.dart' as prod;
import 'firebase_options_staging.dart' as staging;

static FirebaseOptions get current {
  switch (AppEnvironment.current) {
    case AppEnvironment.production:
      return prod.DefaultFirebaseOptions.currentPlatform;
    case AppEnvironment.staging:
      return staging.DefaultFirebaseOptions.currentPlatform;
  }
}
```

最後に `lib/main.dart` の Firebase 初期化のコメントを外します。

> **補足**：Firebase の Web 設定値（apiKey 等）は公開前提の識別子であり、それ自体は秘密情報ではありません。アクセス制御はセキュリティルールで行います（仕様書 13.5）。

---

## 5. セキュリティルールとインデックスの配置

```sh
cd functions && npm install && cd ..

firebase use staging
firebase deploy --only firestore:rules,firestore:indexes,storage,functions

firebase use prod
firebase deploy --only firestore:rules,firestore:indexes,storage,functions
```

> **Cloud Functions のリージョンは `asia-northeast1`（東京）にしています。**
> Firestore を別のロケーション（`us-central` など）で作成した場合は、
> `functions/src/config.ts` の `REGION` と `lib/env/firebase_emulators.dart` の
> `kFunctionsRegion` を合わせて変更してください。リージョンが違うと、
> トリガーのたびにリージョン間の通信が発生して遅延と費用が増えます。

> **`purgeDeletedFiles` は Cloud Scheduler を使います。** 初回のデプロイ時に
> Cloud Scheduler API の有効化を求められることがあります。Blaze プランなら
> 追加設定なしで使えます（毎日 4:00 JST に実行）。

---

## 6. 最初のサイト管理者を登録（仕様書 4.4）

サイト管理者は Auth の**カスタムクレーム**で判定します（仕様書 13.5）。最初の 1 人だけは、アプリ内から設定する手段がないため手作業で付与します。

1. アプリを起動して、自分のアカウントでサインアップする
2. Firebase コンソール → Authentication で自分の UID を控える
3. サービスアカウント鍵を用意する
   （Firebase コンソール → プロジェクトの設定 → サービスアカウント → 新しい秘密鍵の生成）
4. `scripts/grant-site-admin.js` を実行する

```sh
cd scripts && npm install && cd ..

export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
node scripts/grant-site-admin.js <あなたの UID> --project music-storage-dev
```

このスクリプトは次を行います。

- カスタムクレーム `siteAdmin: true` を付与する（既存のクレームは消さない）
- `siteConfig/global` がなければ初期値で作成する
- すでにサイト管理者なら何もしない（再実行しても安全）

5. **アプリで再ログインする。** カスタムクレームは認証トークンに埋め込まれるため、トークンを取り直すまで反映されません（仕様書 13.5）。

> **サービスアカウント鍵はコミットしないでください。** `.gitignore` で `service-account*.json` と `*-firebase-adminsdk-*.json` を除外していますが、別の名前で保存した場合は注意が必要です。

> 以後、サイト管理者の追加はアプリのサイト管理画面から行えます。**最後の 1 人は降格・退会できません**（仕様書 4.5）。

---

## 7. 開発時の実行

```sh
flutter pub get
flutter run -d chrome                             # 検証環境
flutter run -d chrome --dart-define=APP_ENV=prod  # 本番環境
```

検証環境では画面上部に「検証環境」バナーが出ます。本番を触っていると誤認しないための表示です。

---

## 8. テスト（仕様書 12.6）

### 単体テスト

```sh
flutter test      # 172 件
flutter analyze

cd functions && npm test   # 25 件（サーバー側のドメインロジック）
```

権限判定・容量上限・連番・招待 URL・リダイレクト判定・レスポンシブな外枠を検証します。Firebase に接続せず動くため、数秒で終わります。

> **権限と容量の規則は Dart と TypeScript の両方に持っています。**
> Flutter 側（`lib/domain/`）は画面の出し分けに、Cloud Functions 側
> （`functions/src/domain/`）はサーバー側の判定に使います。
> 同じ内容のテストを両方に置いてあるので、**片方を変えたらもう片方も直してください。**

### セキュリティルールのテスト

エミュレータ上でルールを検証します。本番・検証プロジェクトに一切触れません。エミュレータの起動と終了はスクリプトが面倒を見ます。

```sh
cd rules-test
npm install
npm test          # 75 件（うち 8 件はスキップ。下記参照）
```

Firestore ルールは 70 件すべて検証できます。

> **Storage ルールの一部はエミュレータで検証できません。**
> `storage.rules` はメンバー判定のために Firestore を参照しますが（`firestore.exists()`）、
> **これは本番の Cloud Storage では動くものの、Storage エミュレータでは動きません**。
> エミュレータ上では常に偽と評価され、すべてのアクセスが拒否されます。
>
> そのため「メンバーだから許可される」ことを確認するテストは `describe.skip` にしてあります
> （`rules-test/storage.rules.test.js`）。**下記の手動確認で必ず補ってください。**
>
> なお「拒否される」ことを確認するテストは、エミュレータではすべてが拒否されるため
> 通ってしまいます。合格しても保証にはならないので、これらも手動確認の対象です。

### Cloud Functions の統合テスト

エミュレータ上で実際に関数を呼び出し、Firestore の状態を確かめます（18 件）。

```sh
# ターミナル 1
cd functions && npm run serve

# ターミナル 2
cd functions && npm run test:integration
```

検証する内容：リスト作成の申請と承認、リスト名の重複、招待 URL の発行・受諾・
ワンタイム性、参加申請の承認と役割の付与、メンバー数の集計、
最後のサイト管理者の降格ブロック。

> **実行するとエミュレータの Auth と Firestore を初期化します。** 前回のサイト管理者が
> 残っていると「最後の 1 人」の判定が変わってしまうためです。

### 表示フォントについて

日本語フォント（Noto Sans JP）を**アプリに同梱**しています。Flutter Web は既定では
日本語のグリフを実行時に Google Fonts から取得するため、社内ネットワークなどで
`fonts.gstatic.com` が遮断されていると日本語が表示されなくなるからです。

- ファイル：`assets/fonts/NotoSansJP-400.ttf` / `-700.ttf`（各 2.25MB）
- ライセンス：SIL Open Font License 1.1（`assets/fonts/OFL.txt` を同梱）

**端末側でキャッシュされます。** 初回のみダウンロードし、2 回目以降は取得しません。

| 仕組み | 効果 |
| --- | --- |
| `firebase.json` の `Cache-Control: max-age=31536000, immutable` | ブラウザが 1 年間キャッシュし、再訪問時にサーバーへ問い合わせない |
| Flutter の Service Worker（既定で有効） | オフラインでも表示でき、アプリ更新時は変わったファイルだけ取り直す |

`index.html` と Service Worker 自身は毎回確認させる設定にしています。ここをキャッシュすると
アプリを更新しても古い版が表示され続けるためです。

> 初回の読み込みを軽くしたい場合は、`pubspec.yaml` の `w700` の行を消すと 2.25MB 減ります。
> 太字は CanvasKit が w400 から擬似的に作りますが、見た目は少し劣ります。

### 手動確認

ステージング環境で行います（仕様書 12.6）。

**Storage ルールの確認（必須）** — 上記のとおり自動テストで補えない部分です。

- [ ] Read Only のユーザーが音源をダウンロード・再生できる
- [ ] Read Only のユーザーがアップロードできない
- [ ] Super User・リスト管理者がアップロードできる
- [ ] リストに参加していないユーザーが、そのリストの音源にアクセスできない
- [ ] 同じパスへの上書きができない
- [ ] クライアントからファイルを削除できない

**その他**

- [ ] 画面のレイアウト・レスポンシブ表示（PC／スマートフォン）
- [ ] 認証フロー（Google 連携・メール＋パスワード・パスワード再設定・メール確認）
- [ ] 未ログインで共有 URL を開き、ログイン後に元の URL へ戻る
- [ ] ファイルのアップロード／ダウンロード／外部アプリでの再生
- [ ] 通知の到達
- [ ] 日本語・英語の表示切り替え

---

## 9. デプロイ

```sh
flutter build web --release --dart-define=APP_ENV=prod
firebase use prod
firebase deploy --only hosting
```

検証環境へは `--dart-define` を外し、`firebase use staging` にしてから同じ手順で行います。

---

## 運用上の注意

### バックアップは自動では取られません（仕様書 12.3）

定期自動バックアップは組んでいません。次の操作は**復旧手段がない**ことを前提に扱ってください。

- リストの削除（ファイル・コメントもすべて削除される）
- 猶予期間（初期値 30 日）を過ぎた項目のファイル

必要なときは手動でエクスポートします。

```sh
gcloud firestore export gs://<バケット>/backups/$(date +%Y%m%d)
gsutil -m cp -r gs://<バケット>/lists ./backup/
```

### 削除には猶予期間があります（仕様書 6.3 / 13.4）

項目を削除しても、ファイル本体は 30 日間 Storage に残り、その間はリスト管理者以上が復元できます。**猶予期間中も容量を消費し続ける**ため、上限に近いリストでは削除してもすぐには空きが増えません。
