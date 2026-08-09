# セットアップ手順

このリポジトリを動かすまでの手順です。仕様書の該当箇所を併記しています。

**Firebase プロジェクトを作らなくても、ローカルのエミュレータですぐ動かせます。** まずは「2. エミュレータで動かす」を試し、クラウドへの接続はそのあとで構いません。

---

## 1. 開発環境

Windows・macOS・Linux のいずれでも動きます。Windows のコマンドは
「2. エミュレータで動かす」に併記しています。

| 必要なもの | バージョン | 確認コマンド |
| --- | --- | --- |
| Flutter SDK | **3.44 以上**（Dart 3.12.2 以上） | `flutter --version` |
| Node.js | 20 以上 | `node --version` |
| Java | **21 以上**（エミュレータが JVM 上で動く） | `java -version` |
| Firebase CLI | 最新 | `firebase --version` |

> **Java は 21 以上です。17 では動きません**（2026-08-08 に実測）。
> `firebase-tools` 15 以降がそう要求します。17 で起動すると、
> テストが 1 件も走らないまま次のように出て止まります。
>
> ```
> firebase-tools no longer supports Java version before 21.
> Please install a JDK at version 21 or above to get a compatible runtime.
> ```
>
> ```bat
> winget install --id Microsoft.OpenJDK.21
> ```
>
> **17 と 21 が両方入っていても構いません。** `scripts/check.mjs` は
> 版を見て 21 以上のものを選びます。

> **リポジトリの置き場所に、日本語を含めないでください。**
> `flutter analyze` が異常終了します（Flutter 3.44.9 で実測。
> パスに非 ASCII があると解析サーバとのやりとりが壊れる）。
>
> ```
> Unhandled exception: FormatException: Unexpected end of input
> ```
>
> `C:\Codes\MusicStore` のような場所に置いてください。
> `dart analyze` は日本語パスでも動くので、`scripts/check.mjs` は
> そちらを使っています。

```sh
# Firebase CLI
npm install -g firebase-tools

# FlutterFire CLI（クラウドに接続するときに使う）
dart pub global activate flutterfire_cli
```

`firebase login` は、クラウドのプロジェクトを操作するときだけ必要です。エミュレータだけならログイン不要です。

> **Flutter のバージョンが古いと `flutter pub get` が失敗します。**
>
> ```
> The current Dart SDK version is 3.9.2.
> Because music_list_app requires SDK version ^3.12.2, version solving failed.
> ```
>
> これはエラーではなく「Flutter が古い」という意味です。更新してください。
>
> ```sh
> flutter upgrade
> flutter --version   # Dart が 3.12.2 以上になっていることを確認
> ```
>
> `flutter upgrade` が「not on a known channel」などで進まない場合は、
> `flutter channel stable` を実行してから、もう一度 `flutter upgrade` してください。

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

**ウィンドウを 3 つ開いて、1 つずつ実行します。** 1 つ目は起動したまま動き続けるので、
2 つ目・3 つ目は別のウィンドウで実行してください。

**Windows（コマンドプロンプト / PowerShell）**

```bat
rem ウィンドウ 1：エミュレータを起動（Functions のビルドもまとめて行う）
scripts\dev-emulators.cmd

rem ウィンドウ 2：動作確認用のデータを入れる（初回のみ）
scripts\seed.cmd

rem ウィンドウ 3：アプリを起動
flutter pub get
flutter run -d chrome --dart-define=USE_EMULATOR=true
```

**macOS / Linux**

```sh
# ターミナル 1：エミュレータを起動（Functions のビルドもまとめて行う）
./scripts/dev-emulators.sh

# ターミナル 2：動作確認用のデータを入れる（初回のみ）
./scripts/seed.sh

# ターミナル 3：アプリを起動
flutter pub get
flutter run -d chrome --dart-define=USE_EMULATOR=true
```

> **Windows で `.sh` は動きません。** `./scripts/dev-emulators.sh` と打つと
> 「`.` は、内部コマンドまたは外部コマンド…として認識されていません」になります。
> `.sh` は macOS / Linux 用です。Windows では上の `.cmd` を使ってください。
> 中身は同じことをしています。
>
> 上の例で `rem` や `#` で始まる行は説明用のコメントです。**貼り付けなくて構いません**
> （貼り付けると「`#` は…認識されていません」と出ますが、実害はありません）。

**うまく繋がらないときは、まず診断を実行してください。** Windows でもそのまま動きます。

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

### エミュレータでは確認メールが届きません

新規登録すると「確認メールを送信しました」と表示されますが、**エミュレータは実際のメールを
送りません**（外部にメールを出さないのがエミュレータの役目です）。不具合ではありません。

確認用のリンクは、**エミュレータを起動したウィンドウ**に出力されます。

```
i  auth: To verify the email address foo@example.com, follow this link:
   http://127.0.0.1:9099/emulator/action?mode=verifyEmail&oobCode=...&continueUrl=...
```

この URL をブラウザに貼れば、メールのリンクを踏んだのと同じ扱いになります。
アプリの「メール確認待ち」画面で確認を取り直せば先へ進めます。

見逃した場合は、次の URL をブラウザで開くと未使用のリンクが一覧で得られます
（パスワード再設定のリンクも同じ場所に出ます）。

```
http://127.0.0.1:9099/emulator/v1/projects/demo-musiclist/oobCodes
```

**`./scripts/seed.sh`（Windows は `scripts\seed.cmd`）で作られる 4 つのアカウントは
確認済みの状態で作ってあります**（パスワードはすべて `password`）。メール確認を試したい
とき以外は、そちらでログインするのが手早いです。

なおクラウドの検証環境・本番環境では、Firebase Authentication が実際にメールを送ります。

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
| `'.' は、内部コマンドまたは外部コマンド…として認識されていません` | **Windows で `.sh` を実行しようとしています。** `scripts\dev-emulators.cmd` / `scripts\seed.cmd` を使ってください |
| `'#' は、内部コマンドまたは外部コマンド…として認識されていません` | 手順書のコメント行（`#` や `rem` で始まる説明文）を貼り付けています。無視して構いません |
| `'firebase' は、内部コマンドまたは外部コマンド…として認識されていません` | Firebase CLI が入っていないか、PATH に反映されていません。`npm install -g firebase-tools` を実行し、**コマンドプロンプトを開き直して**ください |
| `'flutterfire' は、内部コマンドまたは外部コマンド…として認識されていません` | `dart pub global activate` の入れ先（`%LOCALAPPDATA%\Pub\Cache\bin`）が PATH に入っていません。**PATH を直す必要はありません。** `scripts\configure-firebase.cmd` を使ってください（PATH に依存しない方法で起動します） |
| メッセージが `繧ｨ繝ｩ繝ｼ` のように文字化けする | 古い版のスクリプトです。`git pull` で更新してください。現在の `.cmd` は英数字だけで書かれており、日本語は Node 側から出力しています |
| `Because music_list_app requires SDK version ^3.12.2, version solving failed.` | **Flutter が古いだけです。** `flutter upgrade` を実行してください（「1. 開発環境」参照） |
| `Failed to load function definition from source` | **Functions がビルドされていません。** `cd functions && npm install && npm run build`。`./scripts/dev-emulators.sh`（Windows は `scripts\dev-emulators.cmd`）を使えば自動で行われます |
| `firebase login` を求められる／実プロジェクトに繋ごうとする | `--project demo-musiclist` を付け忘れています。`demo-` で始まる ID だとクラウドに一切アクセスしません |
| `Port taken` / `port is not open` | 前回のエミュレータが残っています。macOS / Linux は `pkill -f "firebase.*emulators"`、Windows は `taskkill /F /IM java.exe` と `taskkill /F /IM node.exe` で止めてから起動し直してください |
| アプリが `FirebaseNotConfiguredError` で止まる | `--dart-define=USE_EMULATOR=true` を付け忘れています。付けないとクラウドの検証環境に繋ごうとします |
| デプロイが `We failed to modify the IAM policy for the project` で失敗する | 下の「IAM ポリシーの変更に失敗するとき」を参照してください |
| 初回デプロイが `Permission denied while using the Eventarc Service Agent` で失敗する | **数分待ってもう一度実行してください。** 第 2 世代の関数は初回に裏でサービスアカウントが作られ、権限が行き渡るまで少し時間がかかります。設定の誤りではありません |
| デプロイが `<何とか> API has not been used in project ... before or it is disabled` で失敗する | 出力に表示される URL を開いて API を有効化し、もう一度実行してください。`purgeDeletedFiles` が使う Cloud Scheduler API が該当することがあります |
| デプロイが `cannot listen to a bucket in region ...` で失敗する | 関数とバケットのリージョンが違います。`functions/.env.<プロジェクト ID>` に `STORAGE_REGION=<バケットのリージョン>` を書いてください（5 章「リージョンについて」参照） |
| デプロイが `cannot listen to a database in region ...` で失敗する | 同様に `FUNCTIONS_REGION=<Firestore のロケーション>` を指定してください |
| 新規登録したのに確認メールが届かない | **正常です。** エミュレータはメールを送りません。リンクはエミュレータの出力に表示されます（上の「エミュレータでは確認メールが届きません」参照） |
| アプリは起動するがデータが出ない／権限エラー | `./scripts/seed.sh` を実行していないか、エミュレータを再起動してデータが消えています |
| `Unable to parse JSON: ... "denied by ..."` | プロキシが localhost の通信を横取りしています。macOS / Linux は `export NO_PROXY=127.0.0.1,localhost`、Windows は `set NO_PROXY=127.0.0.1,localhost`。起動スクリプトは自動で設定します |
| `Cannot find module '@firebase/app'` | `cd functions && npm install` をやり直してください |
| Java のエラーで Firestore が起動しない | JDK 11 以上が必要です。`java -version` が `1.8.0_xxx` のように **`1.` で始まる場合は Java 8** で、古すぎます。Windows は `winget install EclipseAdoptium.Temurin.21.JDK`、そのほかは <https://adoptium.net/> から JDK 21 を入れてください |
| JDK を入れたのに `java -version` が古いまま | 古い Java のほうが PATH の先に残っています。Windows は「システム環境変数の編集」→ PATH から古い Java の行を消すか、新しい JDK の `bin` を上に移動してください。`where java` で優先順が見えます |
| `http://127.0.0.1:4000` が開けない（接続拒否） | **エミュレータを起動したマシンと、ブラウザを開いているマシンが違います。** 上の表を参照してください。同じマシンなら、そもそもエミュレータが起動していません |

上のどれにも当てはまらない場合は、`firebase emulators:start` の出力の**最後の 10 行**を控えてください。原因はたいていそこに出ています。

### 呼び出し可能関数が `internal` で失敗するとき

アプリから申請などを行うと `internal` とだけ表示され、Cloud Functions のログに
次が出ている場合。

```
W submitlistrequest: The request was not authenticated.
Either allow unauthenticated invocations or set the proper Authorization header.
Empty Authorization header value.
```

**関数のコードは動いていません。** 手前の Cloud Run が呼び出しを門前払いしています。

呼び出し可能関数（`onCall`）は、Cloud Run の側では**誰でも呼べる状態にしておく必要があります。**
Firebase のログイン情報は `Authorization` ヘッダに載りますが、それは Google の
アクセストークンではないため Cloud Run には読めません。**利用者の確認は関数の中で
`request.auth` を見て行います**（未ログインなら `unauthenticated` を返す）。

Firebase CLI は関数を**新規作成したとき**にこの設定を入れますが、初回デプロイが
Cloud Build の失敗などで途中まで進んだ場合、作成後の設定だけが飛ばされることがあります。
その場合、あとから `firebase deploy` を繰り返しても更新扱いになるため直りません。

> **2026-08-07 に本番で実際に起きました。** 初回の本番配信で 20 件が
> 「Failed to create」となり、再実行したところ「update」で成功しました。
> **関数はできたが、呼び出しの許可だけが入らない**状態です。
> 配信ログの `create` / `update` を見れば予測できます。
> 失敗した直後の再実行が `update` になっていたら、この症状を疑ってください。

**対象は `onCall` の 19 件だけです。** トリガー（`onFileUploaded` など）と
定期実行は利用者が直接呼ばないので、呼び出しの許可とは無関係です。
消す必要はありません。

#### 直し方 1：許可だけ与える（推奨・作り直さない）

[Cloud Shell](https://console.cloud.google.com/) を開いて実行します
（`gcloud` が最初から入っています）。**関数は消えず、止まりません。**

```sh
PROJECT=music-storage-d79b2      # 検証環境なら music-storage-dev
REGION=asia-northeast1

for f in submitListRequest approveListRequest rejectListRequest \
         submitJoinRequest approveJoinRequest rejectJoinRequest \
         createShareLink acceptShareLink revokeShareLink \
         grantSiteAdmin revokeSiteAdmin withdrawAccount \
         listSiteUsers setListQuota assignListAdmin \
         createSiteUser disableSiteUser enableSiteUser deleteSiteUser; do
  gcloud functions add-invoker-policy-binding "$f" \
    --region="$REGION" --member=allUsers --project="$PROJECT"
done
```

すでに許可が入っているものは、そのまま通ります（何度実行しても安全です）。

#### 直し方 2：作り直す

`gcloud` が使えない場合です。**消えている間、その操作はエラーになります。**

```sh
firebase functions:delete submitListRequest approveListRequest rejectListRequest \
  submitJoinRequest approveJoinRequest rejectJoinRequest \
  createShareLink acceptShareLink revokeShareLink \
  grantSiteAdmin revokeSiteAdmin withdrawAccount \
  listSiteUsers setListQuota assignListAdmin \
  createSiteUser disableSiteUser enableSiteUser deleteSiteUser \
  --region asia-northeast1 --project music-storage-d79b2 --force

./scripts/deploy.sh prod --no-build --only=functions
```

削除してから作り直すと、Firebase CLI が呼び出しの許可を含めて設定し直します。
データ（Firestore・Storage）には影響しません。

#### どちらの場合も、直ったことの確かめ方

アプリからリスト作成を申請し、`internal` が出なくなることを確認します。
ログにこれが**出ていなければ**直っています。

```
The request was not authenticated. ... Empty Authorization header value.
```

> **`internal` は「関数の中で想定外の例外が出た」ときにも出ます。**
> ログに上の行が無い場合は別の原因です。ログの本文を読んでください。


### 監査対応を配信するとき（既存データの手当て）

この版には**既存データの手当てが要る変更**が含まれます。
**配信の直後に**次を実行してください。何度実行しても安全です。

> **第 2 回の監査対応（2026-08-06）で手当てが 2 つ増えました。**
> 以前に実行済みの環境でも、**もう一度実行してください。**

```sh
node scripts/backfill.mjs --project music-storage-dev --key /path/to/service-account.json --dry-run
node scripts/backfill.mjs --project music-storage-dev --key /path/to/service-account.json
```

| 何を直すか | 直さないとどうなるか |
| --- | --- |
| `members` に `uid` を足す | 退会してもリストのメンバーから外れない（監査 S14） |
| `stats` に `itemCount` を入れる | ホーム画面の項目数が 0 と表示される（監査 S6） |
| **`joinRequests` に `uid` を足す** | 自分が出した参加申請が申請一覧に出ない。**アプリの中に復旧手段がありません**（監査 第2回） |
| **`stats` が無いリストに作る** | そのリストに**曲を 1 曲も追加できません**（追加のトランザクションが失敗する／監査 第2回） |

> `--dry-run` の出力に「stats を作成」が並んだら、そのリストは
> **これまで曲を 1 曲も追加できなかった**ものです。

> **第 2 回の監査で、新規登録が失敗する不具合が見つかりました（この版で修正済み）。**
> メール確認をサーバー側で強制する対応（監査 S3）が、**新規登録そのものを壊していました。**
> 登録処理は「読んで、無ければ作る」順なのに、読みだけが禁じられていたためです。
> **この版より前の検証環境では、メール＋パスワードでの新規登録ができません。**

> **あわせて、メール確認が済んでいないアカウントは使えなくなります。**
> 仕様 3.1 の「確認が済むまでアプリは使えない」を、画面のリダイレクトだけでなく
> セキュリティルールと Cloud Functions でも担保するようにしたためです（監査 S3）。
> 配信後にログインできなくなった場合は、確認メールのリンクを開いてください。
> Firebase コンソールの Authentication から手動で確認済みにすることもできます。

### 一部の関数だけ Cloud Build で失敗するとき

```
Build failed with status: FAILURE and message: An unexpected error occurred.
```

**初回デプロイでよく起きます。** 23 個の関数のコンテナが一斉に組み立てられる一方で、
置き場所（Artifact Registry のリポジトリ）はその最中に作られます。用意が整う前に
始まった分が巻き添えで失敗するため、一部だけ成功して残りが落ちる、という形になります。

**まずそのまま再実行してください。** 置き場所はもうできているので、次は通ることが多いです。
成功済みの関数は更新されるだけで、二重に作られることはありません。

```sh
./scripts/deploy.sh --no-build --only=functions
```

Windows は `scripts\deploy.cmd --no-build --only=functions` です。
`--only=functions` を付けると、成功済みのルールや Web の配信を省いて関数だけやり直せます。

2 回試しても同じ関数が失敗する場合は、エラーに出ている
`https://console.cloud.google.com/cloud-build/builds;region=.../<ID>` を開いて、
**ビルドログの最後の 30 行**を確認してください。Firebase CLI の
「An unexpected error occurred」より具体的な原因が出ています。

### IAM ポリシーの変更に失敗するとき

```
Error: We failed to modify the IAM policy for the project.
```

第 2 世代の Cloud Functions は、Storage や Pub/Sub の裏方（サービスエージェント）に
権限を与えないと動きません。Firebase CLI がそれを自動で設定しようとして拒否された状態です。

エラーの**少し上**に、必要な権限が `gcloud` のコマンドとして並んでいます。控えておいてください。

原因は主に 3 つあります。**上から順に確認するのが早いです。**

**1. Compute Engine API が未有効（新しいプロジェクトで最も多い）**

付与先の 1 つ `<プロジェクト番号>-compute@developer.gserviceaccount.com` は、
Compute Engine API を一度も有効にしていないプロジェクトには**存在しません**。
存在しない相手に権限は付けられないため、まとめて失敗します。

<https://console.cloud.google.com/apis/library/compute.googleapis.com> を開き、
対象プロジェクトを選んで有効化してください。数分待ってから再実行します。

```sh
./scripts/deploy.sh --no-build      # Windows は scripts\deploy.cmd --no-build
```

`--no-build` を付けると Web の再ビルドを省けます。

**2. ログイン中のアカウントがオーナーでない**

```sh
firebase login:list
```

プロジェクトを作成したアカウントと同じか確認し、違えば `firebase login --reauth` で入り直します。
Google Cloud コンソールの IAM で、そのアカウントに**オーナー**が付いているかも確認してください
（編集者だけでは権限設定を変えられません）。

**3. 組織のポリシーで拒否されている**

勤務先の Google Workspace 組織に属するプロジェクトだと、組織のポリシーで
外部サービスアカウントの追加が禁止されていることがあります。この場合は自分では解除できません。
管理者に依頼するか、個人アカウントで作ったプロジェクトを使ってください。

**手動で付与する**

上のどれでも直らない場合は、[Cloud Shell](https://console.cloud.google.com/) を開いて、
エラーの上に出ていた `gcloud projects add-iam-policy-binding ...` をそのまま実行します
（Cloud Shell には `gcloud` が入っています）。そこで出るエラーメッセージのほうが、
Firebase CLI の要約より原因を具体的に示してくれます。

真の原因を知りたい場合は詳細ログ付きで実行してください。

```sh
./scripts/deploy.sh --debug --no-build
```

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
./scripts/configure-firebase.sh          # 検証環境
./scripts/configure-firebase.sh prod     # 本番環境
```

Windows は `scripts\configure-firebase.cmd` / `scripts\configure-firebase.cmd prod` です。

> **`flutterfire` を直接呼ばずにスクリプト越しにしている理由。**
> `dart pub global activate flutterfire_cli` は実行ファイルを pub のキャッシュ
> （Windows なら `%LOCALAPPDATA%\Pub\Cache\bin`）に置きますが、**このフォルダは
> PATH に入っていないことが多く**、`flutterfire` と打っても
> 「認識されていません」になります。スクリプトは PATH に依存しない
> `dart pub global run` 経由で起動し、未導入なら導入も行います。

既定では **Web だけ**を設定します。Android / iOS も要るようになったら、あとから足せます
（何度実行しても安全です）。

```sh
./scripts/configure-firebase.sh --platforms=web,android,ios
```

**手で書き換える必要はありません。** 出力先の 2 ファイルはリポジトリに用意してあり、
`lib/env/firebase_options.dart` から読み込むよう配線済みです。上のコマンドが中身を
実際の値で上書きします。

生成前は `REPLACE_ME` が入っており、そのままクラウドに繋ごうとすると
`FirebaseNotConfiguredError` を投げて止まります（設定忘れに気づけるように）。

> **生成後は `git status` に「modified」として残り続けます。これが正常です。**
>
> ```
> modified:   lib/env/firebase_options_staging.dart
> ```
>
> リポジトリ側は `REPLACE_ME` のまま置き、手元だけ実際の値にする作りだからです。
> **この変更を `git checkout` で捨てないでください。** 捨てると `REPLACE_ME` に戻り、
> 配信も検証環境への接続もできなくなります。
>
> `git pull` が
> `Your local changes to the following files would be overwritten by merge` で
> 止まったときは、**まず `git diff <ファイル名>` で中身を確かめてください。**
> 上の 2 ファイルなら残す、それ以外（`firebase.json` など）なら
> `git checkout -- <ファイル名>` で捨てる、が基本です。

> **`flutterfire configure` は `firebase login` 済みであることが前提です。** まだの場合は
> 先に `firebase login` を実行してください。ブラウザが開き、Google アカウントでの許可を求められます。

> **補足**：Firebase の Web 設定値（apiKey 等）は公開前提の識別子であり、それ自体は秘密情報ではありません。アクセス制御はセキュリティルールで行います（仕様書 13.5）。

---

## 5. デプロイ

セキュリティルール・インデックス・Cloud Functions・Web アプリをまとめて配信します。

```sh
./scripts/deploy.sh          # 検証環境（music-storage-dev）
./scripts/deploy.sh prod     # 本番環境（music-storage-d79b2）
```

Windows は `scripts\deploy.cmd` / `scripts\deploy.cmd prod` です。

**どの枝から出すかが決まっています**（2026-08-08 の指示）。

| 環境 | 配信元の枝 |
| --- | --- |
| 検証（staging） | `dev`（`main` からも可） |
| **本番** | **`main` のみ** |

このスクリプトは順に次を行います（2026-08-08 に作り直しました）。

1. `.firebaserc` からデプロイ先のプロジェクト ID を読む
2. `firebase login` 済みか確認する
3. **枝と作業ツリーを確認する**（上の表のとおりか。未コミットの変更が無いか）
4. **このコミットが検証済みか確認する。** `scripts/check.mjs` が全部緑だった
   コミットの ID（`.last-check.json`）と HEAD を突き合わせ、
   違えば**その場で検証を実行**してから進む
5. **変更のあった層だけを選ぶ。** 前回配信したコミット（git タグ
   `deploy/staging` / `deploy/prod`）からの差分で、ルール・索引・関数・
   Hosting のどれを出すか決める。**関数だけの変更なら Web ビルド（約 5 分）は
   走りません。** 変更が無ければ何もせず終わります
6. Hosting を出すときだけ `flutter build web --release`
   （本番は `--dart-define=APP_ENV=prod` 付き。接続設定が `REPLACE_ME` のままなら
   ここで止まります）
7. `firebase deploy --only <選んだ層>`
8. **配信後の確認。** 新規 callable への呼び出し許可の自動付与、
   callable 全件と Hosting への実際の疎通確認。異常があれば失敗として止まる

| 引数 | 意味 |
| --- | --- |
| `prod` | 本番へ。付けなければ検証環境 |
| `--all` | 差分に関係なく全層を配信 |
| `--only=functions` など | 層を手で指定（配信済みの記録は動かしません） |
| `--no-build` | ビルドを飛ばす。失敗直後のやり直し専用 |
| `--skip-tests` | 検証を飛ばす。**依頼者が明示したときだけ** |

> **接続設定の 2 ファイル**（`lib/env/firebase_options_staging.dart` と
> `_prod.dart`）は、**変更されているのが正常**なので未コミット扱いにしません
> （4 章）。それ以外に未コミットの変更があると止まります。

> **「どこまで配信済みか」は git タグ（ローカル）で覚えています。**
> 別のマシンから初めて配信するときはタグが無いので、全層が配信されます。
> 危険側ではなく安全側（出しすぎる側）に倒れる作りです。

完了すると `https://<プロジェクト ID>.web.app` で開けます。

> **初回は Google Cloud 側の API 有効化を求められることがあります。** 出力に表示された
> URL を開いて有効化し、もう一度実行してください。`purgeDeletedFiles` が使う
> Cloud Scheduler API が該当します。

> **Firestore と Cloud Storage は、先に Firebase コンソールで作成しておく必要があります。**
> 未作成のままだとルールの配信で失敗します（3 章参照）。

個別に配信したい場合は、従来どおり CLI を直接使えます。

```sh
firebase deploy --project music-storage-dev --only firestore:rules
```

### 配信したのに、画面が古いまま／アイコンが出ないとき

**まずブラウザのキャッシュを疑ってください。** 強制リロード（Ctrl + Shift + R）
だけでは足りない場合があります。

過去に一度、**アイコンの場所だけ空いていて絵柄が出ない**という形で出ました。
原因は `firebase.json` のキャッシュ指定です。

Flutter はアイコン用の `MaterialIcons-Regular.otf` を、**そのビルドで使っている
アイコンだけに削り込んで作り直します。** 名前は変わらないのに中身がビルドごとに
変わるファイルです。ここを `immutable`（取り直さない）にしていたため、
**新しい画面が古いフォントで描かれ**、増やしたアイコンだけが出ませんでした。

`firebase.json` は `must-revalidate` に直してあり、
`test/domain/hosting_cache_test.dart` で戻らないよう固定しています。
ただし**すでにブラウザに残っている分は消えません。** 一度だけ手で消してください。

1. F12 で開発者ツールを開く
2. **Application** タブ →左の **Storage** → **Clear site data**
3. ページを開き直す

シークレット ウィンドウで開いて直るなら、原因はキャッシュだと切り分けられます。

### 配信が `Cannot determine backend specification` で止まるとき

**再実行しても直りません。** firebase は配信の前に、関数のコードを一度
読み込んで「どんな関数があるか」を聞き出します。その待ち時間が
既定で **10 秒**しかなく、そこを超えると出ます。

`scripts/deploy.cmd` は `FUNCTIONS_DISCOVERY_TIMEOUT` を 120 秒にして
起動します。**エミュレータの起動（`npm run serve`）にも同じ制限があります。**

それでも超える場合は、まず単体で読めるか確かめてください。

```sh
cd functions
npm run build
node -e "require('./lib/index.js'); console.log('読み込めました')"
```

読めるのに配信で超えるなら、Node の版が `functions/package.json` の指定
（22）と違うことが多いです。配信のログに次の 1 行が出ていないか見てください。

```
!  functions: Your requested "node" version "22" doesn't match your global version "24".
```

### 統合テストが「submitListRequest が見つかりません」で止まるとき

**エミュレータを起動したウィンドウの出力を見てください。** 原因は 2 通りあり、
片方に決めつけると調査が無駄になります（2026-08-07 に実際に遠回りしました）。

| ウィンドウに出ているもの | 原因 | 対処 |
| --- | --- | --- |
| `Failed to load function definition from source: ... Timeout after 10000` | **関数が 1 つも読み込まれていない** | `npm run serve` を使う（待ち時間を 120 秒に延ばしてあります） |
| URL に `music-storage-dev` が入っている | プロジェクト ID が違う | `npm run serve` を使う（`--project demo-musiclist` が入っています） |

> **読み込みに失敗しても `All emulators ready!` は出ます。**
> 表の枠が出たから起動できた、とは限りません。
> その少し上に `!!` で始まる行が無いか確かめてください。

読み込みが制限時間を超えるのは、`package.json` の `engines`（Node 22）と
手元の Node の版が違うときに起きやすいです。`npm run serve` は
`FUNCTIONS_DISCOVERY_TIMEOUT` を 120 秒にして起動します。

それでも出る場合は、まず単体でビルドが通るか確かめてください。

```sh
cd functions
npm run build
node -e "require('./lib/index.js'); console.log('読み込めました')"
```

### 一覧の再生ボタンで鳴らないとき

「再生できませんでした」と出たら、**その通知の「詳細」を開いてください。**
技術的な内容がそのまま出ます。原因ごとに対処が違います。

| 詳細に出る内容 | 原因 | 対処 |
| --- | --- | --- |
| `MissingPluginException(No implementation found for method init on channel com.ryanheise.just_audio.methods)` | **`just_audio` の Web 版が組み込まれないままビルドされています。**アプリのコードの問題ではありません | `flutter clean` → `flutter pub get` → 配信し直す（下の囲みを参照） |
| `NotAllowedError: play() failed because the user didn't interact...` | ブラウザが自動再生を止めています。画面に一度も触れていない状態とみなされました | **もう一度再生ボタンを押してください。** 2 度目は URL を取り直さないぶん速く、通ることが多いです |
| `[firebase_storage/object-not-found]` | Storage にファイルがありません。猶予期間の掃除で消えたか、登録が途中で失敗しています | 項目を登録し直してください |
| `[firebase_storage/unauthorized]` | そのリストのメンバーとして読む権限がありません | メンバーに入っているか、メール確認が済んでいるかを確かめてください |
| `PlatformException(4, Failed to load URL...)` | ブラウザがその音を読めません。形式が対応外か、通信が途中で切れています | 別の端末・別のブラウザで試し、mp3 で登録し直してください |

> **`MissingPluginException` は、足した部品が組み込まれなかったという意味です。**
>
> 前に作った生成物が残っていると、**古い部品一覧がそのまま使われる**ことがあります。
> ビルドも配信も成功し、画面も動くのに、**その部品を使う操作だけが失敗します。**
> 気づきにくいので、`scripts/deploy.mjs` に手当てを入れてあります。
> 部品の顔ぶれが前回のビルドと変わっていたら、自動で `flutter clean` します。
>
> 手で直すときは次のとおりです。
>
> ```sh
> flutter clean
> flutter pub get
> scripts\deploy.cmd
> ```

> **再生ボタンが出るのは、音として鳴らせるファイルだけです**（仕様 8.1）。
> ファイルの種類は登録時に制限していない（7.1）ので、画像や書類も登録できますが、
> それらには再生ボタンを出しません。ボタン自体が出ない場合は、
> `contentType` が `audio/` で始まっていないか、URL の項目です。

### 本番へ配信する前の確認（初回のみ）

**本番は取り違えても戻せません。** 検証環境の初回配信は 6 回失敗しました。
同じところで止まらないよう、順に確かめてください。

#### 1. 検証環境で動作を確認したか

**本番に出す版は、検証環境で一度動かしたものにしてください。**
自動テストは「壊れていないこと」を見ますが、実際にメールが届くか、
通知が届くかまでは見ていません（仕様 12.6 の手動確認）。

#### 2. 予算アラートを設定したか（仕様 12.1）

**自動停止は実装しない方針なので、これが唯一の歯止めです。**
本番プロジェクトに未設定なら、配信より先に設定してください（3 章）。

費用を決めるのは保存量ではなく**ダウンロード量**です。音源を配るアプリなので、
利用者が増えたときに効いてくるのはこちらです。

#### 3. 接続設定を生成したか

```bat
scripts\configure-firebase.cmd prod
```

`lib/env/firebase_options_prod.dart` が `REPLACE_ME` のままだと、
`deploy.cmd prod` が事前検査で止めます。

#### 4. **Storage バケットのリージョンを確かめたか**

**検証環境の初回配信が最初に失敗したのがここです。**

```
A function in region asia-northeast1 cannot listen to a bucket in region us-east1
```

Storage のトリガーは、バケットと同じリージョンでしか動かせません。
**バケットのリージョンは作成後に変更できません。**

Firebase コンソール → Storage を開き、バケットのロケーションを確認してください。

| バケットのロケーション | 対応 |
| --- | --- |
| `asia-northeast1` | 何もしなくてよい（`functions/.env` の既定と同じ） |
| それ以外（`us-east1` など） | `functions/.env.music-storage-d79b2` を作り、下記を書く |

```
STORAGE_REGION=us-east1
```

Firestore のロケーションも同様に確認し、`asia-northeast1` でなければ
同じファイルに `FUNCTIONS_REGION=<Firestore のロケーション>` を足してください。

> **このファイルはリポジトリに入れて構いません**（リージョン名だけで秘密ではありません）。
> むしろ入れておかないと、次に配信する人が同じところで止まります。

#### 5. Authentication のログイン方法を有効にしたか

Firebase コンソール → Authentication → Sign-in method で、
**メール／パスワード**と **Google** を有効にしてください。
検証環境で有効でも、本番は別プロジェクトなので個別に設定が要ります。

あわせて「承認済みドメイン」に `<プロジェクト ID>.web.app` が入っていることを
確認してください（通常は自動で入ります）。

#### 6. 初回配信で起きうること（検証環境で実際に起きたもの）

| 症状 | 対処 |
| --- | --- |
| `<何とか> API has not been used in project ...` | 出力の URL を開いて有効化し、再実行。`purgeDeletedFiles` が使う Cloud Scheduler API が該当します |
| `We failed to modify the IAM policy for the project` | API の有効化と同時に走ったため。**数分待って再実行**すれば通ります |
| Cloud Build が大量に失敗する（1 個だけ成功する） | コンテナの置き場所が同じ配信の中で作られるため。**そのまま再実行**すれば通ります |
| 呼び出すと `internal` とだけ出る | Cloud Run の呼び出し許可が設定されていません。下記参照 |

**`internal` が出たときは、関数のコードは 1 行も動いていません。**
`onCall` の関数は Cloud Run のレベルで誰でも呼べる状態が要りますが、
この設定は**新規作成のときにしか行われません**。上の Cloud Build 失敗で
作成が途中終了すると、設定だけが飛ばされます。再実行は更新扱いなので直りません。

**その関数を削除してから配信し直してください**（この章の「呼び出し可能関数が
`internal` で失敗するとき」を参照）。

#### 6.5 2 回目の配信で `update` と出た呼び出し可能関数に注意

初回の配信が途中で失敗し、再実行で通ったときは、出力をよく見てください。

```
+  functions[submitJoinRequest(asia-northeast1)] Successful update operation.
+  functions[onItemCreated(asia-northeast1)]     Successful create operation.
```

**`onCall` の関数が `update` になっていたら、器だけが前回作られていたということです。**
Cloud Run の「誰でも呼べる」設定は**新規作成のときにしか行われない**ため、
更新扱いになった関数はその設定が飛ばされている可能性があります。

そのまま呼ぶと `internal` とだけ返ります（**関数のコードは 1 行も動いていません**）。
削除してから配信し直すと、新規作成として扱われて直ります。

```bat
firebase functions:delete <対象の関数を並べる> ^
  --region asia-northeast1 --project music-storage-d79b2 --force

scripts\deploy.cmd prod --no-build --only=functions
```

削除してもデータは消えません（関数の定義だけです）。

**トリガー（`onItemCreated` など）は対象外です。** 呼び出し許可の設定を持たないためです。

#### 7. 配信

```bat
scripts\deploy.cmd prod
```

本番のプロジェクト ID（`music-storage-d79b2`）の入力を求められます。
取り違え防止のためなので、そのまま入力してください。

#### 8. 最初のサイト管理者を登録

**本番は誰もサイト管理者ではない状態から始まります。**
6 章の手順を、本番のサービスアカウント鍵で実行してください。

```bat
node scripts\grant-site-admin.js --key <本番の鍵.json> --email <あなたのメール>
```

登録後、**アプリからログインし直してください**（カスタムクレームは
トークンを取り直すまで反映されません）。

#### 9. 既存データの手当て

新しく作った本番プロジェクトにデータが無ければ不要です。
すでに利用を始めている場合は、検証環境と同じ手当てを実行してください。

```bat
node scripts\backfill.mjs --project music-storage-d79b2 --key <本番の鍵.json> --dry-run
node scripts\backfill.mjs --project music-storage-d79b2 --key <本番の鍵.json>
```

### リージョンについて

Cloud Functions は既定で `asia-northeast1`（東京）で動かします。主な利用者が日本にいる想定です。

**プロジェクトのロケーションが東京でない場合、デプロイが失敗します。**

```
Error: A function in region asia-northeast1 cannot listen to a bucket in region us-east1
```

トリガーは対象と同じリージョンでしか動かせないためです。しかも **Cloud Storage の
バケットは作成後にリージョンを変更できません。** そこでコードを直さずに、
`functions/.env.<プロジェクト ID>` で上書きできるようにしてあります。

| 変数 | 対象 | 既定 |
| --- | --- | --- |
| `FUNCTIONS_REGION` | 全体（呼び出し可能関数・定期実行・Firestore トリガー） | `asia-northeast1` |
| `STORAGE_REGION` | Storage のトリガーだけ | `FUNCTIONS_REGION` と同じ |

検証環境はバケットが `us-east1` にあるため、`functions/.env.music-storage-dev` で
`STORAGE_REGION=us-east1` を指定済みです。

> **この値は `defineString`（パラメータ）として受け取っています**（`functions/src/config.ts`）。
> `process.env` では受け取れません。Firebase CLI は「どの関数をどこに配置するか」を決める
> 解析の段階で、子プロセスに `HOME` / `PATH` など一部の環境変数しか渡さないためです。
> `.env` の中身が渡るのはその後なので、`process.env` 経由だと指定しても無視されます。

現在のロケーションは次で確認できます。

```sh
firebase firestore:databases:list --project music-storage-dev
```

Firestore も東京以外にある場合は、同じファイルに `FUNCTIONS_REGION` を追記してください。
あわせて `lib/env/firebase_emulators.dart` の `kFunctionsRegion` も揃えます。

> **本番プロジェクトは `asia-northeast1` で作成してください。** Firestore・Cloud Storage
> ともにロケーションはあとから変更できず、直すにはプロジェクトの作り直しが必要になります。

> **`functions/.env.*` に秘密情報を書かないでください。** リポジトリに入るファイルです。
> 鍵やトークンは `firebase functions:secrets:set` で Secret Manager に置きます。

> **`purgeDeletedFiles` は Cloud Scheduler を使います。** 初回のデプロイ時に
> Cloud Scheduler API の有効化を求められることがあります。Blaze プランなら
> 追加設定なしで使えます（毎日 4:00 JST に実行）。

---

## 6. 最初のサイト管理者を登録（仕様書 4.4）

サイト管理者は Auth の**カスタムクレーム**で判定します（仕様書 13.5）。最初の 1 人だけは、アプリ内から設定する手段がないため手作業で付与します。

1. アプリを起動して、自分のアカウントでサインアップする
2. サービスアカウント鍵を用意する
   （Firebase コンソール → プロジェクトの設定 → サービスアカウント → 新しい秘密鍵の生成）
3. `scripts/grant-site-admin.js` を**メールアドレス指定で**実行する

```sh
cd scripts && npm install && cd ..

node scripts/grant-site-admin.js \
  --email you@example.com \
  --project music-storage-dev \
  --key /path/to/service-account.json
```

Windows は 1 行で書きます（`\` での改行は使えません）。

```
cd scripts && npm install && cd ..
node scripts\grant-site-admin.js --email you@example.com --project music-storage-dev --key C:\path\to\service-account.json
```

> **UID を調べる必要はありません。** メールアドレスから引きます。
> Firebase コンソールを開くと、ブラウザが別の Google アカウントでサインインしている場合に
> 「プロジェクトが存在しないか、…権限がありません」と出て詰まりがちなので、
> そこを通らずに済むようにしています。

誰が登録済みか分からないときは一覧を出せます。

```sh
node scripts/grant-site-admin.js --list --project music-storage-dev --key /path/to/service-account.json
```

```
UID                           メールアドレス
00hzFMGtVt6wDYVy7yG4pv2GnfQp  site-admin@example.com [サイト管理者]
UZVRD2u3uqP42SwGajslvSIyiHJ0  super-user@example.com
```

UID を直接指定することもできます（`--email` の代わりに UID を置く）。

> 環境変数 `GOOGLE_APPLICATION_CREDENTIALS` でも鍵を指定できますが、Windows では
> `export` が使えず間違えやすいため、`--key` で渡せるようにしています。

> 何度実行しても安全です。すでにサイト管理者ならその旨を表示して何もしません。

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

> **ふだんは 1 つのコマンドで足ります。**
>
> ```bat
> scripts\check.cmd
> ```
>
> 4 本を並列に走らせ、エミュレータの起動・後片付けまで行います
> （約 3 分・別窓なし）。**配信の前にこれを通してください。**
> 以下は、個別に動かしたいときの説明です。

### 単体テスト

```sh
flutter test      # 314 件
dart analyze --fatal-infos   # 指摘 0 件が基準

cd functions && npm test   # 85 件（サーバー側のドメインロジック・通知）
```

権限判定・容量上限・連番・共有リンク・リダイレクト判定・レスポンシブな外枠を検証します。Firebase に接続せず動くため、数秒で終わります。

> **権限と容量の規則は Dart と TypeScript の両方に持っています。**
> Flutter 側（`lib/domain/`）は画面の出し分けに、Cloud Functions 側
> （`functions/src/domain/`）はサーバー側の判定に使います。
> 同じ内容のテストを両方に置いてあるので、**片方を変えたらもう片方も直してください。**

### セキュリティルールのテスト

エミュレータ上でルールを検証します。本番・検証プロジェクトに一切触れません。エミュレータの起動と終了はスクリプトが面倒を見ます。

```sh
cd rules-test
npm install
npm test          # 127 件（Firestore 111 件・Storage 13 件・書き方の見張り 3 件。スキップなし）
```

Firestore ルールは全件エミュレータで検証できます。

> **かつてここには「Storage ルールの一部はエミュレータで検証できない」と書いていました。**
> `storage.rules` がメンバー判定に使う `firestore.exists()` に Storage エミュレータが
> 対応していない、という理由で 8 件を `describe.skip` にしていたのです。
>
> **これは誤りでした。** 2026-08-06 のゼロベース監査で実際に skip を外して実行したところ、
> 8 件すべてが期待どおりに動きました。誤った前提がこの文書・README・DEVLOG・
> テストファイルのコメントの 4 箇所に転記され、増幅していました。
>
> 現在はスキップなしで 13 件すべてを検証しています。

> **メンバー判定が働いていないときは、その場で止まります。**
>
> ```
> メンバー判定（storage.rules の firestore.exists()）が働いていません。
> この状態では否定側のテストが「拒否された」ことだけを見て緑になり、
> ルールの後退を見逃します。以降の結果は信用できません。
> ```
>
> `storage.rules` は Firestore を参照してメンバーかどうかを判定します。
> この参照が失敗すると**全員が拒否される**ため、
> 「Read Only はアップロードできない」「未参加者は読めない」といった
> **否定側の 4 件がすべて緑になります**。土台が壊れているほど緑が増える、
> いちばん質の悪い出方です。
>
> 第 2 回の監査で、ルールをわざと壊す対照実験によりこれを実証しました。
> そのため、否定側を動かす前に前提を確かめ、崩れていれば理由を出して止めます。
> **「〜できない」と書かれた箇所こそ、まず試してください。**

> **エミュレータは 5 種類（Auth / Firestore / Storage / Functions / Pub/Sub）を起動します。**
> Pub/Sub が無いと、定期実行の `purgeDeletedFiles` が読み込み時に無視され、
> **エミュレータ上で一度も起動できません。** ログには
> `function ignored because the pubsub emulator does not exist` としか出ないため
> 気づきにくく、第 2 回の監査まで見落としていました。

### Cloud Functions の統合テスト

エミュレータ上で実際に関数を呼び出し、Firestore の状態を確かめます（75 件）。

```sh
cd functions && npm run test:integration
```

**ウィンドウは 1 つで済みます。** エミュレータの起動・後片付けまで
`functions/run-integration.mjs` が行います。すでに別のウィンドウで
エミュレータが動いていれば、そちらへ繋いでテストだけを走らせます。

> **以前は「1 枚目で `npm run serve`、2 枚目でテスト」という手順でした。**
> その形では**一度も実行されず**、期待値が古いまま赤くなっていたことに
> 気づけず、**そのまま本番へ配信されていました**（2026-08-08 に判明）。
> 人が窓を 2 つ並べる前提の手順は、書いてあっても実行されません。

> **Pub/Sub エミュレータは起動しません。** 統合テストは定期実行の関数を
> 呼ばないうえ、**Pub/Sub エミュレータだけが別の窓を開く**ためです
> （Windows で実測）。手で触るときの `npm run serve` には残してあります。

検証する内容：リスト作成の申請・承認・却下（名前予約の解放を含む）、
共有リンクの発行・受け取り（参加／閲覧）・何度でも使えること・取消、
**リンクが役割を持たないこと**、参加申請の承認・却下・連打の抑止、
メンバー数の集計、サイト管理者の昇格・降格と「最後の 1 人」のブロック、
容量上限の変更、リスト管理者の指名、退会（メンバーからの除去を含む）、
曲が追加されたときの通知先、メール確認が済むまで呼べないこと。

> **エミュレータは必ず `demo-musiclist`（架空のプロジェクト）で起動します。**
> `.firebaserc` の既定は検証環境の `music-storage-dev` なので、
> `--project demo-musiclist` を付け忘れると実在のプロジェクト ID で立ち上がり、
> 関数の URL もカスタムクレームの付与先も噛み合いません。`npm run serve` には
> このオプションが入っています。**素の `firebase emulators:start` は使わないでください。**
>
> 噛み合っていないときは、テストの冒頭で理由を出して止まります。
> 以前は 24 件が FAIL する一方で、**何も起きていないだけの確認が PASS** になり、
> 結果を読み違えかねない状態でした。

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

**Storage ルールは自動テストで検証済みになりました**（上記の経緯を参照）。
本番の Cloud Storage とエミュレータで挙動が違う可能性は残るため、
初回の配信時に一度だけ次を確かめておくと安心です。

- [ ] Read Only のユーザーが音源をダウンロード・再生できる
- [ ] Read Only のユーザーがアップロードできない
- [ ] リストに参加していないユーザーが、そのリストの音源にアクセスできない
- [ ] **同じパスへの上書きができない**（監査 S4 で一度破れていた箇所）

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
