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
| Java | **11 以上**（Firestore エミュレータが JVM 上で動く） | `java -version` |
| Firebase CLI | 最新 | `firebase --version` |

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

このスクリプトは順に次を行います。

1. `.firebaserc` からデプロイ先のプロジェクト ID を読む
2. `firebase login` 済みか確認する
3. **接続設定が生成済みか確認する**（`REPLACE_ME` が残っていれば、そこで止める）
4. 本番の場合は、プロジェクト ID の入力を求める
5. `flutter build web --release`（本番は `--dart-define=APP_ENV=prod` 付き）
6. `firebase deploy --only firestore:rules,firestore:indexes,storage,functions,hosting`

3 の確認を入れているのは、**設定を忘れたまま配信すると、起動と同時に
`FirebaseNotConfiguredError` で止まるアプリが公開されてしまう**ためです。

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
