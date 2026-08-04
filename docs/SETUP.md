# セットアップ手順

このリポジトリを動かすまでの手順です。仕様書の該当箇所を併記しています。

---

## 1. 開発環境

| 必要なもの | バージョン | 確認コマンド |
| --- | --- | --- |
| Flutter SDK | 3.44 以上 | `flutter --version` |
| Node.js | 20 以上（Cloud Functions・Firebase CLI 用） | `node --version` |
| Firebase CLI | 最新 | `firebase --version` |

```sh
# Firebase CLI
npm install -g firebase-tools
firebase login

# FlutterFire CLI（Firebase の接続設定を生成する）
dart pub global activate flutterfire_cli
```

---

## 2. Firebase プロジェクトの作成（仕様書 12.1 / 12.2）

**本番と検証（ステージング）を別々のプロジェクトとして作成します。** Firestore のデータ・Storage のファイル・認証ユーザーがプロジェクト単位で完全に独立するため、検証作業が本番データを壊す事故を構造的に防げます。

1. [Firebase コンソール](https://console.firebase.google.com/)で 2 つのプロジェクトを作成する。
   - 本番用（例：`musiclist-prod`）
   - 検証用（例：`musiclist-staging`）
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

## 3. 接続設定の生成

`.firebaserc` のプロジェクト ID を、作成した実際の ID に差し替えます。

```json
{
  "projects": {
    "default": "musiclist-staging",
    "staging": "musiclist-staging",
    "prod": "musiclist-prod"
  }
}
```

続いて、Flutter 側の接続設定を生成します。

```sh
# 検証環境
flutterfire configure \
  --project=musiclist-staging \
  --out=lib/env/firebase_options_staging.dart \
  --platforms=web,android,ios

# 本番環境
flutterfire configure \
  --project=musiclist-prod \
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

## 4. セキュリティルールとインデックスの配置

```sh
firebase use staging
firebase deploy --only firestore:rules,firestore:indexes,storage

firebase use prod
firebase deploy --only firestore:rules,firestore:indexes,storage
```

---

## 5. 最初のサイト管理者を登録（仕様書 4.4）

サイト管理者は Auth の**カスタムクレーム**で判定します（仕様書 13.5）。最初の 1 人だけは、アプリ内から設定する手段がないため手作業で付与します。

1. アプリを起動して、自分のアカウントでサインアップする
2. Firebase コンソール → Authentication で自分の UID を控える
3. 次のスクリプトを実行する（サービスアカウント鍵が必要）

```js
// scripts/grant-site-admin.js
const admin = require('firebase-admin');
admin.initializeApp({ credential: admin.credential.applicationDefault() });

const uid = process.argv[2];
admin.auth().setCustomUserClaims(uid, { siteAdmin: true })
  .then(() => console.log(`granted siteAdmin to ${uid}`))
  .then(() => process.exit(0));
```

```sh
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
node scripts/grant-site-admin.js <あなたの UID>
```

4. **アプリで再ログインする。** カスタムクレームは認証トークンに埋め込まれるため、トークンを取り直すまで反映されません（仕様書 13.5）。

あわせて `siteConfig/global` を作成します。

```json
{
  "inviteExpiryHours": 24,
  "defaultQuotaBytes": 1073741824,
  "itemPurgeGraceDays": 30,
  "orphanFileGraceHours": 24,
  "siteAdminCount": 1
}
```

> 以後、サイト管理者の追加はアプリのサイト管理画面から行えます。**最後の 1 人は降格・退会できません**（仕様書 4.5）。

---

## 6. 開発時の実行

```sh
flutter pub get
flutter run -d chrome                             # 検証環境
flutter run -d chrome --dart-define=APP_ENV=prod  # 本番環境
```

検証環境では画面上部に「検証環境」バナーが出ます。本番を触っていると誤認しないための表示です。

---

## 7. テスト（仕様書 12.6）

### 単体テスト

```sh
flutter test
flutter analyze
```

権限判定・容量上限・連番・招待 URL・リダイレクト判定を検証します。Firebase に接続せず動くため、数秒で終わります。

### セキュリティルールのテスト

エミュレータ上でルールを検証します。本番・検証プロジェクトに一切触れません。

```sh
firebase emulators:start --only firestore,auth,storage
```

> **未実装**：ルールのテストコードはまだ書いていません。`@firebase/rules-unit-testing` を使ったテストを別途用意します。ルール本体（`firestore.rules` / `storage.rules`）は作成済みです。

### 手動確認

次はステージング環境で手動確認します（仕様書 12.6）。

- 画面のレイアウト・レスポンシブ表示（PC／スマートフォン）
- 認証フロー（Google 連携・メール＋パスワード・パスワード再設定・メール確認）
- ファイルのアップロード／ダウンロード／外部アプリでの再生
- 通知の到達
- 日本語・英語の表示切り替え

---

## 8. デプロイ

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
