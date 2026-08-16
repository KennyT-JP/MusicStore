# モバイルアプリ化（iOS / Android）設計（2026-08-16）

**まだ何も着手していません。** これは「作る前に決めること」を並べ、
決まった範囲の作り方と、着手の順序をまとめた文書です。

いま本番で配信しているのは **Web だけ**です。`android/` と `ios/` は
リポジトリに存在しますが、**中身はほぼ Flutter の初期生成のまま**で、
**iOS のビルドは一度も走っていません**。
つまり `android/` `ios/` があることを「動く」と読み替えないでください。
[AUDIT-CHECKLIST.md](AUDIT-CHECKLIST.md) 観点 2「**一度も成功していない経路**」
そのものです。

**この文書は土台側だけを扱います。** ダウンロード（オフライン保存）機能は
[DOWNLOAD-DESIGN.md](DOWNLOAD-DESIGN.md) が扱います。
**ダウンロード機能は、この文書が作る土台の上に乗ります。**

## 前提が変わりました（2026-08-16）

**同じ作者の別プロジェクト `C:\Codes\SessionConcierge` が、
すでに同じことを済ませていました。**

Session Concierge は Flutter アプリで、**Windows だけで App Store と
Google Play に出ています**（2026-08-14 に `session_concierge.ipa` を
App Store Connect へアップロードし、同日提出）。

**この文書は「ゼロから決める」文書ではなく、「動いている前例を、
音源創庫の形に合わせて持ち込む」文書です。**

| 前提 | 改訂前の見立て | **実際** |
| --- | --- | --- |
| macOS | 実機かクラウド Mac が要る | **要りません。** Codemagic の `mac_mini_m2` で完結しています |
| 日程のクリティカルパス | iOS（Apple の審査） | **Android です。** Play の**クローズドテスト 12 人 × 14 日**。App Store にこの要件はありません |
| `Podfile` | 生成が要る | **要りません。** Session Concierge は SPM 運用で `Podfile` を持ちません |
| Android の `INTERNET` 権限 | `main/` に無いと release が通信できない | **誤りでした**（下の取り下げ） |
| `<queries>` | `https` を足さないと `url_launcher` が動かない | **誤りでした**（下の取り下げ） |

### 範囲と日程も決まりました（2026-08-16・依頼者に 1 問ずつ確認）

| 決めたこと | 内容 | 書いてある場所 |
| --- | --- | --- |
| **入口の 3 つ** | Apple Developer・Play Console・Codemagic は**すでに使えます。待ち時間ゼロ** | 1-1 |
| **公開の順番** | **iOS 先行。** 開発は同時、公開だけずらす | 4-0 |
| **Android の一般公開** | **日程未定。** テスター 12 人の見通しが立たないため、**日付を置きません** | 4-0 |
| **共有リンクをアプリで開く** | **今回の範囲に入りました**（App Links / Universal Links・**案 B**） | 5-8-2 |
| **EU への配信** | **先に外して出す。** 体制が整ってから足す | 5-17 |
| **利用規約の著作権** | **「投稿者の責任」と「私的利用の限定」。利用目的は限定しない** | 5-15 |
| **機種変更での移行** | **移行されないことを許容** | 5-9-1 |

### 取り下げる 2 点

**改訂前にこの文書が「危ない」と書いた次の 2 点は、事実に反していました。**

| 取り下げるもの | 根拠 |
| --- | --- |
| **「`INTERNET` が `main/` に無いので release だけ通信できない」** | Session Concierge も `main/AndroidManifest.xml` に `INTERNET` を書いていません。**それで App Store / Play に出て動いています。** プラグイン側の manifest がマージされて入ります。**明示は不要です**（書いても害はありませんが、必要ではありません） |
| **「`<queries>` に `https` の `VIEW` が無いと Android 11+ で `url_launcher` が動かない」** | Session Concierge の `<queries>` はテンプレートの `PROCESS_TEXT` だけで、`LaunchMode.externalApplication` ＋ `https` の外部リンクを **3 箇所**開けています。**`tel:` / `mailto:` / カスタムスキームを開くときだけ**、その分を足す必要が出ます |

> **この 2 件は「調べずに一般論を書いた」失敗です。**
> どちらも「そう言われている」ことをそのまま書き、**同じ構成で動いている
> 実物を確かめませんでした。** 以降、この文書で「無いと動かない」と
> 書いてあるものは、**Session Concierge の実物で確かめたものだけ**です。

> **作業ブランチについて。** 執筆中は `main` に居ましたが、**`dev` へ移して
> コミット済みです**（2026-08-16）。配信は「dev へコミット → 検証環境へ配信
> → 依頼者の確認 → main へマージ → 本番へ配信」の順で、**検証環境と本番へ
> 続けて配信してはいけません。** 着手する人は先に `git branch --show-current`
> を確認してください。

---

## 1. 依頼者しか用意できないもの

**ここが揃うまで、iOS 側は 1 つも進みません。**
ただし **Windows でできることは想像よりずっと多い**ので、
「Mac が無いから何もできない」で止まらないでください。

### 1.1 要るもの

### 1.1 入口の 3 つは、すでに使えます（2026-08-16 に確認）

**Apple Developer Program・Google Play Console・Codemagic は 3 つとも
使える状態です。** Session Concierge がすでに使っています。

> # **入口の待ち時間はゼロです。**
>
> **Apple Developer Program の有効化リードタイム（実績 3 日）は、
> 今回は発生しません。** 「申し込んでから 3 日待つ」を工程に入れないでください。
> **初日から App ID の追加登録も App Store Connect のアプリ登録もできます。**

### 1.2 それでも依頼者にしか用意できないもの

| 要るもの | 費用 | 状況 |
| --- | --- | --- |
| **Android の署名鍵（keystore）** | — | **音源創庫用に新規作成。** Session Concierge の鍵は流用しません（別アプリなので） |
| **App ID / アプリレコードの追加登録** | — | developer.apple.com と App Store Connect、Play Console で**音源創庫のぶんを追加**します。**Sign in with Apple のチェックを App ID 作成時に入れること**（5-6） |
| **App Store Connect の API キー（`.p8`）** | — | **ダウンロードは 1 回きり**。役割は **App Manager 以上**。Session Concierge のものを流用できるかは確認してください（同じ Team なら流用できるはずです） |
| **Codemagic への音源創庫の登録** | **無料枠は未確認** | 下記 |

> **Codemagic の無料枠だけが未確認です。**
> **音源創庫用に別アプリを登録したとき、build minutes を Session Concierge と
> 共有するのか別枠なのかが分かっていません。**
> Session Concierge のどの文書にも料金・無料枠の記述がなく、
> **Codemagic の画面で確認するしかありません。**
>
> **iOS の初回ビルドは 4 回失敗する前提で見積もってください**（8-1）。
> 成功したビルドは 8 分 28 秒でしたが、**失敗したビルドも minutes を消費します。**

### 1.3 macOS は要りません

**Session Concierge は Windows だけで App Store まで出しています。**

| GUI でやると思われている操作 | 実際に使っているコマンド |
| --- | --- |
| Xcode で署名チームを選ぶ | `xcode-project use-profiles` |
| 証明書・プロビジョニングプロファイルの作成 | `app-store-connect fetch-signing-files --create`（**その場で Apple 側に作らせる**） |

Session Concierge の開発ログにこう書かれています。

> iOS 対応を始めたときの見立ては「Mac が無いと何もできない」だった。実際には
> **macOS に縛られているのはコンパイルだけ**で、`ios/` の生成も Bundle ID も
> Info.plist もアイコンも Firebase の登録も Apple サインインの実装も
> **Windows で全部できた。**

**「そこでしか作れない」と「そこでしか動かない」は違います。**
この切り分けをせずに Mac へ移ると往復が増えます。
**そして、手元で潰せる失敗を CI で踏むと、失敗ビルドを浪費します**
（Session Concierge の初回 iOS ビルドは 4 回失敗しました。8-1 参照）。

### 1.4 依頼者が Codemagic の画面で作るもの

**yaml には値を書きません。登録名を指すだけです。**

| 作るもの | 場所 | 名前 |
| --- | --- | --- |
| **App Store Connect の Integration** | Teams → Integrations → App Store Connect | **`codemagic.yaml` の `app_store_connect:` と一字一句一致させること。** 違うと「integration not found」でビルドが始まりません |
| **変数グループ `appstore`** | 環境変数 | 中に `CERTIFICATE_PRIVATE_KEY` を **Secure** で登録 |

**証明書用の秘密鍵は、リポジトリの外に控えます。**
Session Concierge は `C:\Users\mstak\Documents\SessionConcierge-signing\cert_key`
に置いています。

> **毎回同じ鍵を使ってください。** 鍵を変えると証明書が新規発行され、
> **Apple の配布用証明書の保有上限にすぐ達します。**

---

## 2. いまの到達点

**骨格はあるが、中身は初期生成のままです。** 表示名だけ手が入っています。

### 2.1 Session Concierge との対比

**この表が、そのままやることの一覧になります。**

| | Session Concierge（出荷済み） | 音源創庫（いま） |
| --- | --- | --- |
| Flutter プロジェクトの位置 | `app/`（サブディレクトリ） | **リポジトリ直下** |
| `codemagic.yaml` | あり（10KB。ほぼ全部がコメント） | **無し（新規作成）** |
| `applicationId` / `namespace` | **あえて別**（`com.sessionconcierge.app` / `com.sessionconcierge.session_concierge`） | **同一**（`com.musiclist.music_list_app`） |
| 鍵無しの release ビルド | **失敗させる**（`throw GradleException`） | **デバッグ署名にフォールバック**（要修正） |
| Android のフレーバー | `prod` / `dev`（`applicationIdSuffix = ".dev"`） | **無し** |
| `FirebaseInitProvider` | **`tools:node="remove"` で自動初期化を止めている** | 手つかず |
| `allowBackup` | **`false` ＋ `data_extraction_rules.xml`** | 手つかず（＝ Android の既定 `true`） |
| iOS deployment target | **15.0** | **13.0**（Firebase の要求 15.0 に届かない） |
| `Podfile` | **無し**（SPM 運用） | 無し（未生成） |
| `Info.plist` の追加項目 | **5 つ** | **0**（テンプレート既定のみ） |
| `Runner.entitlements` | `applesignin` の 1 項目 | **ファイルごと無し** |
| Google ログイン | `kIsWeb` で分岐・`google_sign_in ^7.2.0` | **`signInWithPopup` のみ（Web 専用）** |
| Sign in with Apple | 実装済み（`sign_in_with_apple ^8.1.0`） | **無し** |
| pubspec version | `1.0.0+6` | **`0.1.0+1`** |
| 端末へのファイル保存 | **無し** | **これから作る（前例なし）** |
| `file_picker` / `just_audio` | **無し** | **あり（＝ Session Concierge に前例が無い）** |

### 2.2 プラットフォーム設定の詳細

| 項目 | 状態 | 場所 |
| --- | --- | --- |
| アプリ表示名 | **手が入っている唯一の箇所** | `android/app/src/main/AndroidManifest.xml:3`、`ios/Runner/Info.plist` |
| Android `applicationId` / `namespace` | どちらも `com.musiclist.music_list_app`。**テンプレートの TODO コメントが残存** | `android/app/build.gradle.kts:34, 44-45` |
| iOS Bundle ID | `com.musiclist.musicListApp` | `ios/Runner.xcodeproj/project.pbxproj:385, 564, 586`（テスト用は `401, 418, 433`） |
| iOS deployment target | **13.0** | `ios/Runner.xcodeproj/project.pbxproj:363, 489, 540` |
| iOS の署名 | `CODE_SIGN_STYLE = Automatic`。**`DEVELOPMENT_TEAM` は未設定** | 同上 |
| `Info.plist` | **テンプレート既定のみ** | `ios/Runner/Info.plist` |
| Android の署名 | 受け口は実装済み。**鍵が無いとデバッグ署名に黙って落ちる**（要修正） | `android/app/build.gradle.kts:22-25, 54-78` |
| `ndkVersion` | **`flutter.ndkVersion` を指定している** | `android/app/build.gradle.kts:36` |

> **`ndkVersion` は、Session Concierge では意図的に指定していません。**
> 「Firebase・広告・課金はネイティブビルドを必要としないため、
> NDK（約 1GB）が不要」という判断です。
> **音源創庫は指定しています。** `just_audio` は Android で ExoPlayer
> （純 Java/Kotlin）なので NDK 不要ですが、**`file_picker` を含めてどれか
> 1 つでも NDK を要求すると必要になります。** いま指定してあるので、
> **外す必要はありません**（ビルドが遅い・容量を食うのが気になったときの
> 選択肢として覚えておいてください）。

### 2.3 Firebase の接続設定

| 項目 | 状態 |
| --- | --- |
| 生成済みのプラットフォーム | **Web のみ** |
| `firebase_options_{prod,staging}.dart` | android / iOS で **`UnsupportedError` を投げる**（`lib/env/firebase_options_prod.dart:22-49`） |
| `google-services.json` / `GoogleService-Info.plist` | **どちらも無し** |
| 生成スクリプト | `scripts/configure-firebase.mjs`。**既に `--platforms` を受け付ける**（`:35-38`、`:109`）。既定は `web` |

**Session Concierge は設定ファイルをすべてコミットしています**
（`.gitignore` で除外しているのは `key.properties` だけ）。
「API キーは公開前提の値」という判断で、[SETUP.md](SETUP.md) の
「Firebase の Web 設定値は公開前提の識別子」と同じ立場です。
**音源創庫も同じにしてください**（5-3 で理由を書きます）。

### 2.4 ログイン

```dart
// lib/data/repositories/auth_repository.dart:38-46
/// Web ではポップアップを使う。モバイル版を作るときは
/// google_sign_in パッケージ経由に差し替える必要がある。
Future<void> signInWithGoogle({required String languageCode}) async {
  final provider = GoogleAuthProvider();
  final credential = await _auth.signInWithPopup(provider);   // ← 44-45
  await _ensureUserDocument(credential.user, languageCode: languageCode);
}
```

**`signInWithPopup` は Web 専用です。**
コメントに「モバイル版を作るときは差し替える必要がある」と自分で書いてあり、
**その時が来た**というのがいまの状態です。
**Session Concierge の `auth_controller.dart:186-212` がそのまま手本になります**（5-4）。

### 2.5 `Uri.base` を読んでいる 2 箇所（**モバイルで壊れます**）

**これは改訂前の文書が見落としていた、いちばん実害の大きい箇所です。**

| 場所 | 何をしているか | モバイルでどうなるか |
| --- | --- | --- |
| `lib/ui/share_url.dart:18` | `final origin = base ?? Uri.base;` → `origin.origin` を読む | **例外で落ちます。** ネイティブの `Uri.base` は `file:` 形式で、`origin` を読むと `StateError` |
| `lib/main.dart:42` | `final fragment = Uri.base.fragment;` で起動時のディープリンクを拾う | **常に空**。起動 URL が取れず、`launchLocation` が必ず `/` になります |

> **`share_url.dart:13-15` のコメントが、すでにこの答えを書いています。**
>
> > `Uri.base` はテストでは `file:` 形式になり、`origin` を読むと例外になる。
>
> **テストで起きることは、モバイルでも起きます。**
> だから `base` を差し替えられる形になっているのですが、
> **実際に呼んでいる側は差し替えていません。**

Session Concierge は同じ問題を `app_urls.dart:14` の
**「Web = `Uri.base.origin`、ネイティブ = 固定ドメイン」**で解いています。
**音源創庫も同じ手当てが必ず要ります**（5-8-1）。

**そして、共有リンクを「開く側」も今回の範囲に入りました**（5-8-2）。
**作る側と開く側は対で設計します。**

### 2.6 ビルドと配信

| 項目 | 状態 |
| --- | --- |
| ビルド経路 | `scripts/deploy.mjs:316` の `flutter build web` **のみ** |
| 配信の層 | Firebase の 5 つ（`scripts/deploy.mjs:57`） |
| `android/` `ios/` の変更 | **配信対象レイヤーの判定で読み飛ばされる**（`scripts/deploy.mjs:213-214`） |
| 版番号 | `pubspec.yaml:4` の `version: 0.1.0+1` |

### 2.7 テストとパッケージ

- **モバイル固有の検証はゼロ。** Web 固有のものは 2 本
  （`test/domain/web_startup_test.dart`・`test/domain/hosting_cache_test.dart`）
- **使用中の全パッケージが iOS / Android 双方に対応済み。** Web 専用のものはありません
- `path_provider` は `just_audio` の推移依存としてのみ存在（直接依存に足す必要があります）
- **`google_sign_in` / `sign_in_with_apple` / `crypto` / `flutter_launcher_icons` は無し**

> **フォントの同梱に注意してください。**
> `assets/fonts/NotoSansJP-400.ttf` は **2.36MB** あります
> （`pubspec.yaml:43-54` のとおり、`fonts:` ではなく `assets:` として積み、
> 最初の描画のあとに読み込む作り）。
> **これは CanvasKit（Web）のための同梱で、モバイルでは端末のシステム
> フォントが使えるので本来不要です。** ただし `assets:` は
> **プラットフォーム別に分けられない**ため、モバイルのビルドにも入ります。
> **アプリのサイズが 2.36MB 増えると見込んでください**（Session Concierge も
> 同じ理由で +2.7MB を受け入れています）。

### 2.8 すでに満たしているストア要件

| 要件 | 状態 |
| --- | --- |
| **アプリ内からアカウントを削除できる**（Apple 5.1.1(v)） | **満たしています。** 設定画面の「退会」が `withdrawAccount` を呼びます（`lib/ui/screens/settings_screen.dart:549-601`）。**Session Concierge の調査でも「音源創庫は既に満たしている」と確認されています** |
| 広告 SDK の同梱 | **ありません。** 広告は使い方ページ（`web/help/`）の HTML にだけ置いてあります。**アプリに広告 SDK が無い＝ iOS の ATT（`NSUserTrackingUsageDescription`）は不要**です |
| プライバシーポリシー URL | **あります**（`web/help/{ja,en}/privacy.html`）。**利用規約はありません**（3-4） |

---

## 3. 決めたこと（2026-08-16・依頼者に 1 問ずつ確認）

| # | 論点 | 決定 |
| --- | --- | --- |
| 1 | 出す順番 | **iOS / Android 同時** |
| 15 | Sign in with Apple | **必須** |
| 16 | アプリ ID | **`jp.sessionconcierge.trackcabinet`**（iOS / Android 共通） |
| 14 | 利用規約 | **新設する** |

### 3-1. 論点 1：iOS / Android 同時

**土台の作業は両方に同時に効くもの**が大半なので、分ける利得がありません。

**改訂前は「macOS が無いと Android も出せない」と書きましたが、
これは取り下げます。** macOS は不要です（1-2）。
**代わりに、日程の制約が Android 側にあります**（4 節）。

### 3-2. 論点 15：Sign in with Apple

App Store のガイドライン **4.8** は、第三者のログイン（Google 等）を載せる
アプリに Sign in with Apple を求めます。**無いと審査で弾かれます。**

**ボタンは iOS にだけ出します。** Session Concierge が
`auth_controller.dart:246-247` で**判定を 1 箇所に閉じている**形をそのまま使います。

```dart
static bool get isAppleSignInAvailable =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
```

> **画面側が `Platform.isIOS` を各所で書くと、Web ビルドで `dart:io` が
> 使えず壊れます。** 画面はこの値を見るだけにしてください。

### 3-3. 論点 16：アプリ ID

**`jp.sessionconcierge.trackcabinet`。** 連絡先ドメイン `session-concierge.jp` 由来。

> **Android の `applicationId` はハイフンを使えません。**
> `session-concierge` をそのまま入れると Gradle が受け付けないため、
> **詰めた形（`sessionconcierge`）**にしています。
> **iOS の Bundle ID も同じ文字列に揃えます。**

> # **アプリ ID は、一度ストアに出すと変えられません。**
>
> **いまの `com.musiclist.*`（テンプレートの TODO が残った値）のまま
> 1 回でも提出したら、そこで固定されます。** あとから変えるには
> **別のアプリとして新規登録**するしかなく、既存の利用者は入れ直しになります。

### 3-4. `applicationId` と `namespace` を分ける（**Session Concierge から持ち込む判断**）

**音源創庫はいま両者が同一です**（`com.musiclist.music_list_app`）。
**分けてください。**

| | 値 | 役割 |
| --- | --- | --- |
| `namespace` | **`com.musiclist.music_list_app` のまま据え置く** | **Kotlin / R クラスの置き場。** 変えるとソースの参照が全部ずれます |
| `applicationId` | `jp.sessionconcierge.trackcabinet`（本番）<br>`jp.sessionconcierge.trackcabinet.dev`（検証） | **ストアと端末が見るアプリの同一性。** 公開後は変更不可 |

> **この表は 2026-08-16 に直しました。** 当初は `namespace` も
> `jp.sessionconcierge.trackcabinet` に変えると書いていましたが、
> **それでは両者が同じ値になり、この節の見出し（「分ける」）とも
> 6 節の見張り 3 番（「別であること」）とも矛盾していました。**
> 実装の担当がこの食い違いに気づき、正しい側（据え置き）に倒しています。
>
> **変えるのは `applicationId` だけです。** Session Concierge も
> `namespace = com.sessionconcierge.session_concierge` /
> `applicationId = com.sessionconcierge.app` と別のままにしています。

**理由は Google ログインです。** Session Concierge の
`android/app/build.gradle.kts:91-104` にこう書かれています。

> **Google ログインは「パッケージ名＋署名鍵の SHA-1」の組み合わせで
> OAuth クライアントを作る。この組み合わせは Firebase プロジェクトを
> またいで一意でなければならず**、本番が先に押さえていたため、
> 同じパッケージ名・同じ鍵のままでは dev 側に作れなかった
> （Firebase が `Oauth client already exists in a different project` と返す）。

**音源創庫は本番（`music-storage-d79b2`）と検証（`music-storage-dev`）の
2 プロジェクトを持っています**（[SETUP.md](SETUP.md)）。
**検証環境の Android アプリを作るなら、最初から分けておかないと詰みます。**
あとから分けるには `applicationId` を変えることになり、**公開後はできません。**

**副次的な利点のほうが大きい**とも書かれています。

> 識別子が変わるので、**本番と dev を同じ端末へ並べて入れられる。**
> 以前は入れ替えになり、片方を試すたびにもう片方が消えていた。

> **iOS には dev フレーバーを作りません。**
> Android は `applicationIdSuffix` で分けられますが、iOS は Xcode の
> configuration と scheme を増やす必要があります。
> **Session Concierge は「iOS は本番のみ」と割り切り、確認は Web と
> Android の dev で行っています。** 音源創庫も同じにしてください。

### 3-5. 論点 14：利用規約の新設

**いまはプライバシーポリシーしかなく、著作権への言及がゼロです**
（`docs/manual/legal-{ja,en}.html`）。

1. **ストアが規約の提示を求めます**（利用者が作ったコンテンツを扱うため）
2. **ダウンロード機能が「音源を端末に降ろす」機能だからです。**
   降りたものは取り消せません（[PREMIUM-DESIGN.md](PREMIUM-DESIGN.md) 8 節）。
   **誰の権利のものを、どこまで持ち出してよいか**を、機能を出す前に
   文章で決めておく必要があります

**書く場所と作り方は 5-14 に書きます。手で複製しないこと。**

---

## 4. 日程とクリティカルパス

**いちばん時間がかかるのは Android です。iOS ではありません。**
**この節を読まずに日程を約束しないでください。**

### 4-0. 決めたこと（2026-08-16）

| # | 決定 |
| --- | --- |
| **公開の順番** | **iOS を先に公開します。** 開発は同時に進め、**公開だけずらします** |
| **Android の一般公開** | **日程未定。** クローズドテストのテスター 12 人の見通しが立たないため |

> # **この文書に Android の公開日を書きません。**
>
> **テスターが 12 人揃う見通しが立っていません。**
> 揃った日から 14 日なので、**起点が決まらない限り終点も決まりません。**
> **「たぶん◯月ごろ」と書くと、それが約束として一人歩きします。**
>
> **iOS を先に出し、Android はクローズドテストで配りながら人が揃うのを
> 待つ**——これが決まったやり方です。
> **Android のクローズドテスト版は「出せている」状態**なので、
> 止まっているのは公開だけです。

> **論点 1（iOS / Android 同時）との関係。**
> **「同時」は開発の話です。** 土台の作業は両方に効くので同時に進めますが、
> **公開日は揃いません。** ここを取り違えないでください。

> **Android の一般公開は、ダウンロード機能側の判断の起点にもなっています。**
> 詳細は [DOWNLOAD-DESIGN.md](DOWNLOAD-DESIGN.md) を参照してください。
> **この文書は日付を持ちません。**

### 4-1. Play のクローズドテスト（**最大の制約**）

**AAB を上げただけでは一般公開できません。**
次の 3 つを満たして初めて「本番環境へのアクセスを申請」が押せます。

| 条件 | Session Concierge の達成状況 |
| --- | --- |
| クローズドテスト版リリースを公開する | 達成 |
| **12 人以上のテスターにオプトインしてもらう** | **1 人**（未達） |
| **12 人以上で 14 日以上実施する** | 未達 |

> **最短でも、12 人が揃った日から 14 日です。**
> **12 人を集める日数は、この 14 日に含まれません。**

**Session Concierge はここで止まっています。**
**音源創庫も、ここが同じ形で止まります。**

> **iOS 側にこの要件はありません**（Google の要件で、Apple には無い）。
> **これが「iOS 先行公開」を決めた理由そのものです。**

### 4-2. テスター集めを独立した工程にする

**これは実装作業ではなく、人を集める作業です。**
実装が終わってから始めると、**そこから 14 日以上が上乗せされます。**

| やること | いつ始めるか |
| --- | --- |
| **12 人のテスターの当て**をつける（音楽仲間・バンドメンバー・知人） | **実装と並行して、いますぐ** |
| テスター用の Google アカウントを集める（オプトインには Google アカウントが要る） | 同上 |
| クローズドテスト版を最初に上げる | 5 節の 10 番が終わった時点。**完成品でなくてよい** |
| 14 日の計測 | **12 人が揃った日から。揃うまで始まりません** |

> **「実装が終わってからテスターを探す」が、いちばんやってはいけない
> 順序です。** クローズドテスト版は動くものでありさえすればよく、
> **完成を待つ理由がありません。**

> **クローズドテストは、すでに「配れている」状態です。**
> テスターに入った人は、その時点から実際にアプリを使えます。
> **12 人という数は一般公開の条件であって、配布の条件ではありません。**
> 少人数でも先に配り始めてください——**使ってもらった人が次のテスターを
> 連れてくる**ほうが、集めきってから配るより現実的です。

### 4-3. その他のリードタイム

| 項目 | 実績・見込み |
| --- | --- |
| Apple Developer Program の有効化 | **0。** 済んでいます（1-1）。**参考：未加入なら実績 3 日**（公称「最大 48 時間」より長い） |
| Play Console のデベロッパー登録 | **0。** 済んでいます（1-1） |
| Codemagic の初回 iOS ビルド | **4 回失敗して成功。** 成功時のビルド時間は **8 分 28 秒**（8-1） |
| Apple のベータ審査（外部テスト） | 初回 1 日ほど。**`submit_to_testflight: false` にしておけば発生しません** |
| App Store の審査 | Session Concierge は 2026-08-14 に提出（結果の記録なし） |
| Play のリリース前レポート | 上げた直後は空。**生成に時間がかかる** |

---

## 5. やること（順序つき）

**上から順に、1 つずつ緑にしてから次へ進んでください。**

**1〜9 は Windows だけでできます。** CI へ行く前に手元で全部潰してください。
**手元で潰せる失敗を CI で踏むと、失敗ビルドを浪費します。**

| # | やること | 手元/CI | なぜその順か |
| --- | --- | --- | --- |
| 1 | **iOS deployment target を 15.0 に上げる** | 手元 | **いちばん先。** 13.0 のままだと Firebase SDK の要求に届かず、CI で必ず落ちます |
| 2 | **アプリ ID を変える**（`applicationId` と `namespace` を分ける） | 手元 | これを後回しにすると、3 の Firebase 登録も 10 の OAuth 登録も全部やり直し |
| 3 | **Firebase の接続設定を android / iOS ぶん生成し、配置する** | 手元 | 2 のあと。ID が確定してから |
| 4 | **`FirebaseInitProvider` の自動初期化を止める** | 手元 | 3 と同時。**入れないと検証環境のビルドが無言で落ちます** |
| 5 | **ログインを作り直す**（`kIsWeb` の分岐・`google_sign_in ^7.2.0`） | 手元 | 3 のあと |
| 6 | **Sign in with Apple を足す**（iOS だけ） | 手元 | 5 と同じ形に乗せる |
| 7 | **`Info.plist` に 4 項目を足す・`Runner.entitlements` を作る** | 手元 | 6 のあと（`applesignin` が要る） |
| 8a | **共有リンクを作る側を直す**（`Uri.base` の始末。ネイティブ用の固定ドメイン） | 手元 | **これを飛ばすと、招待リンクを作った瞬間に例外で落ちます** |
| 8b | **共有リンクを開く側を作る**（App Links / Universal Links） | 手元＋配信 | **8a と対。** 作る側だけ直しても、開いた先がブラウザのままです |
| 9 | **`AndroidManifest` と `build.gradle.kts` を直す**（バックアップ禁止・デバッグ署名フォールバック廃止） | 手元 | 10 の前 |
| 10 | **署名を通す**（keystore・Codemagic の登録） | 依頼者 | 9 のあと。**8b の `assetlinks.json` に鍵の SHA-256 が要るので、ここが終わるまで 8b は完成しません** |
| 11 | **`codemagic.yaml` を新規作成する** | CI | 10 のあと |
| 12 | **アイコンを作る** | 手元 | 13 の前（スクリーンショットに写る） |
| 13 | **スクリーンショットを撮る** | 手元 | 12 のあと |
| 14 | **実機幅でのレイアウト崩れを洗い出す** | **実機** | 13 と同時期。**独立した工程として立てること** |
| 15 | **利用規約を新設する** | 手元 | 17 に要る。**実装と並行して進められる** |
| 16 | **ストア掲載文の正本をリポジトリに置く** | 手元 | 同上 |
| 17 | **ストア提出物を揃える** | 依頼者 | 最後 |

### 5-1. iOS deployment target を 13.0 → 15.0

**`ios/Runner.xcodeproj/project.pbxproj` の `IPHONEOS_DEPLOYMENT_TARGET`
（3 箇所：`363, 489, 540`）を `15.0` にするだけです。**

**理由：`flutter create` の既定 13.0 では、Firebase SDK が要求する 15.0 に
届かずビルドが落ちます。** Session Concierge が実際に踏んでいます。

> **`Podfile` に `platform :ios, '15.0'` を書く手順は要りません。**
> Session Concierge は **SPM（Swift Package Manager）運用**で、
> `Podfile` / `Podfile.lock` / `Pods/` のいずれも持っていません。
> **deployment target は `project.pbxproj` の 1 箇所だけです。**
> 「Podfile が無い＝ iOS の準備ができていない」と読み替えないでください。

**これは Windows で直せます。** CI へ行く前に必ず済ませてください。

### 5-2. アプリ ID の変更

| 直す場所 | いまの値 | 変える値 |
| --- | --- | --- |
| `android/app/build.gradle.kts` `namespace` | `com.musiclist.music_list_app` | **変えない**（3-4 のとおり据え置き） |
| `android/app/build.gradle.kts` `applicationId`（**TODO コメントごと消す**） | `com.musiclist.music_list_app` | `jp.sessionconcierge.trackcabinet` |
| `android/app/build.gradle.kts` に **`prod` / `dev` のフレーバー**を足す | 無し | `dev` は `applicationIdSuffix = ".dev"` |
| `ios/…/project.pbxproj`（Runner の 3 箇所） | `com.musiclist.musicListApp` | `jp.sessionconcierge.trackcabinet` |
| `ios/…/project.pbxproj`（RunnerTests の 3 箇所） | `com.musiclist.musicListApp.RunnerTests` | `jp.sessionconcierge.trackcabinet.RunnerTests` |
| Kotlin のパッケージ階層（`android/app/src/main/kotlin/…`） | `com/musiclist/music_list_app/` | **移動しない**（`namespace` を据え置くので、いまのままで正しい） |

> **`namespace` を据え置くので、Kotlin のディレクトリも動かしません。**
> 当初この表は「`namespace` を変える」前提で書かれており、
> ディレクトリ名の混乱まで心配していましたが、**その心配ごと消えました。**

**フレーバーの形（Session Concierge の実物）:**

| フレーバー | `applicationId` | `google-services.json` の置き場所 |
| --- | --- | --- |
| `prod` | `jp.sessionconcierge.trackcabinet` | `android/app/google-services.json` |
| `dev` | `jp.sessionconcierge.trackcabinet.dev` | `android/app/src/dev/google-services.json` |

> **`flutter create --platforms=ios` を実行しないでください。**
> Session Concierge は **`.metadata` の既存プラットフォーム行を消される**
> 事故を踏んでいます（android と web の記録が消えて手で戻した）。
> **音源創庫は `ios/` と `android/` の両方が既にある**ので、
> 生成し直す場面はありません。**やむを得ず実行したら、`.metadata` の
> 差分を必ず見てください。**

### 5-3. Firebase の設定生成と配置

```sh
scripts\configure-firebase.cmd --platforms=web,android,ios          # 検証環境
scripts\configure-firebase.cmd prod --platforms=web,android,ios     # 本番環境
```

**スクリプトは既に `--platforms` を受け付けます**（`scripts/configure-firebase.mjs:35-38, 109`）。
既定が `web` なので、**指定しないと今までどおり Web だけ**が生成されます。

**設定ファイルはコミットしてください。** Session Concierge がそうしています
（`.gitignore` で除外しているのは `key.properties` だけ）。
[SETUP.md](SETUP.md) の「Firebase の Web 設定値は公開前提の識別子」と同じ立場です。

> **コミットしない運用にすると、6 節のテスト 10 番（設定ファイルの存在）が
> CI で成立しません。** そして **「手元にあるが CI に無い」が、いちばん
> 気づきにくい形で壊れます。**

> **`google-services.json` は、Google ログインを有効化した「あと」に
> 取り直してください。** Session Concierge が踏んでいます。
>
> > Google を有効化する**前に**ダウンロードしたファイルには `oauth_client` が
> > **0 件**で、Android は「serverClientId が無い」で失敗する。
> > **設定を変えたら、その設定から生成したファイルも取り直す。**

### 5-4. `FirebaseInitProvider` の自動初期化を止める

**環境を分けるなら必須です。**

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<provider android:name="com.google.firebase.provider.FirebaseInitProvider"
    android:authorities="${applicationId}.firebaseinitprovider"
    android:exported="false" tools:node="remove" />
```

**`<manifest>` に `xmlns:tools="http://schemas.android.com/tools"` を足す
必要があります**（いまの音源創庫には `xmlns:android` しかありません）。

**理由：** Android は `google-services.json` を読んで、起動時に `[DEFAULT]` の
Firebase App を**勝手に作ります**。検証環境のビルドが Dart 側から作り直そうと
すると **`[core/duplicate-app]` で起動時に落ちます**。

> **画面には何も出ず、起動画面のまま止まります。**
> エラーも警告も見えないので、**原因を探す場所がありません。**

止めると、**初期化の向き先が Dart の 1 箇所
（`main()` の `Firebase.initializeApp(options: ...)`）に一本化されます。**

> **`google-services.json` は消さないでください。**
> Google ログインが `serverClientId` をこのファイルから読み、
> Gradle のプラグインもビルド時に参照します。

### 5-5. ログインの作り直し

**分岐の形は `kIsWeb` の実行時分岐です。条件付き import ではありません。**

Session Concierge の使い分け（`lib` 配下で `kIsWeb` を使うファイルは 8 個だけ）:

| 形 | 使いどころ |
| --- | --- |
| **`kIsWeb`（実行時分岐）** | **ロジックの分岐。ほとんどこれ** |
| `defaultTargetPlatform` | Apple ボタンの表示可否、`firebase_options` |
| **条件付き import** | **Web 専用の `import` 文が存在するときだけ**（`dart:js_interop`） |

**音源創庫が `dart:js_interop` を触るのは `lib/platform/app_ready_web.dart`
だけ**なので、**条件付き import を増やす必要はありません。**
改訂前の文書は「条件付き export をもう 1 組作る」と書きましたが、
**過剰です。`kIsWeb` の実行時分岐で足ります。**

**Session Concierge の実装**（`auth_controller.dart:186-212`）:

```dart
if (kIsWeb) {
  final provider = GoogleAuthProvider();
  result = await _auth.signInWithPopup(provider);
} else {
  final cred = await _googleCredential();      // google_sign_in から資格情報だけ取る
  if (cred == null) return const AuthFailure('canceled');
  result = await _auth.signInWithCredential(cred);
}
```

ネイティブ側（`auth_controller.dart:226-238`）:

```dart
final signIn = GoogleSignIn.instance;
await signIn.initialize();
try {
  final account = await signIn.authenticate();
  return GoogleAuthProvider.credential(idToken: account.authentication.idToken);
} on GoogleSignInException catch (e) {
  if (e.code == GoogleSignInExceptionCode.canceled) return null;  // 「やめた」は失敗にしない
  rethrow;
}
```

**必ず押さえること:**

| 項目 | 内容 |
| --- | --- |
| **パッケージの版** | **`google_sign_in: ^7.2.0`。v6 と v7 で API が完全に別物です**（v6 は `GoogleSignIn().signIn()`）。**版を合わせないと丸ごと動きません。** ネットで見つかる古い記事はほぼ v6 です |
| `authentication` が返すもの | **v7 は `idToken` しか返しません**（`accessToken` は別経路） |
| **キャンセルを失敗扱いにしない** | 利用者がシートを閉じただけで**赤いメッセージが出る**のを防ぎます |
| `signInWithProvider` は使わない | Session Concierge は使っていません。**前例のある道を選んでください** |

> **改訂前の文書は `signInWithProvider` を選択肢 B として挙げましたが、
> 取り下げます。** 実績があるのは `google_sign_in ^7.2.0` の側だけです。

> **iOS では `Info.plist` に `CFBundleURLTypes`（`REVERSED_CLIENT_ID`）と
> `GIDClientID` が要ります**（5-7）。**無いと認証は済むのにアプリへ
> 戻れません。** 利用者からは「固まった」ように見えます。

> **ログインボタンにタイムアウトを入れることを検討してください。**
> Session Concierge は `login_screen.dart:331-338` で **90 秒**を入れています。
> ポップアップの完了検知が返ってこないと `_busy` が true のまま残り、
> **ログイン画面のボタンが全部押せなくなります**（2026-08-12 に実際に発生）。

### 5-6. Sign in with Apple

| 要るもの | 内容 |
| --- | --- |
| パッケージ | **`sign_in_with_apple: ^8.1.0`** と **`crypto: ^3.0.7`**（nonce のハッシュ用） |
| iOS の設定 | **`ios/Runner/Runner.entitlements`**（新規）に `com.apple.developer.applesignin` = `[Default]`。**この記述が無いと、実装しても呼んだ瞬間に失敗します**。**同じファイルに 5-8-2 の `com.apple.developer.associated-domains` も入ります**——**ファイルを作るのはここ 1 回だけです** |
| Apple 側 | developer.apple.com の App ID 作成時に **`Sign in with Apple` にチェック**（**人の作業**） |
| Firebase 側 | Apple プロバイダを有効化 |
| 表示の判定 | **`isAppleSignInAvailable` を 1 箇所に閉じる**（3-2） |

**nonce の扱いが要点です。間違えると `invalid-credential` になります。**

| 渡す先 | 渡すもの |
| --- | --- |
| **Apple** | **`sha256.convert(utf8.encode(rawNonce)).toString()`（SHA-256 したもの）** |
| **Firebase** | **`rawNonce`（生のもの）** |

`rawNonce` は 32 文字を `Random.secure()` で作ります。
**逆にすると Firebase が検証に失敗します。** 横取りされた ID トークンを
弾くための仕組みなので、省略できません。

**表示名は初回だけしか渡ってきません。**

> **2 回目以降は必ず空で返ります。** `user.displayName` を当てにできません。
> **初回に受け取ったものを、そのまま名前確認の画面へ渡してください。**
> 取り逃すと、名前欄が空のまま利用者に考えさせることになります。

> **リレーアドレス（`@privaterelay.appleid.com`）について。**
> Session Concierge はこれを**普通のメールアドレスとして通しています**
> （コード・Functions・文書のどこにも特別扱いがありません）。
> メール確認を **`providerIds.contains('password')` のときだけ**要求する
> 設計なので、Apple / Google のユーザーはメール確認フローに入らず、
> **リレーアドレスへ送る経路そのものがありません。**
>
> **音源創庫の `auth_repository.dart:36` も同じ立場です**
> （「Google 連携でのログインは Google 側で確認済みのため、常に true」）。
> **同じ扱いでよいはずですが、実機で `emailVerified` を確かめてください。**

> **`aps-environment` を entitlements に書かないでください。**
> **書いたまま APNs 鍵が無いと署名が失敗します**（App ID 側で
> Push Notifications を有効にしていないと「プロビジョニングプロファイルに
> `aps-environment` が含まれていない」でビルドが止まる）。
> **書かなければ通知が届かないだけで済みます。** 通知は今回やりません（7 節）。

### 5-7. `Info.plist` に足す 4 項目

**Session Concierge がテンプレートから足しているのは 5 項目
（うち Google ログイン関連が 2 つ）です。音源創庫に要るのは 4 種類。**

| キー | 値 | 無いとどうなるか |
| --- | --- | --- |
| **`CFBundleLocalizations`** | `[ja, en]` | **日本語端末でも英語で起動します。** Android では起きない形の落とし穴です。**Flutter の `supportedLocales`（`lib/l10n/app_localizations.dart:95`）は OS の判断に効きません** |
| **`ITSAppUsesNonExemptEncryption`** | `<false/>` | **アップロードのたびに輸出コンプライアンスの質問が出ます。** 入れておけば提出時に**不要**になります（Session Concierge の実績） |
| **`CFBundleURLTypes`** | `GoogleService-Info.plist` の `REVERSED_CLIENT_ID` を 1 つ | **認証は済むのにアプリへ戻れません。** 利用者からは「固まった」ように見えます。**一字一句同じにすること** |
| **`GIDClientID`** | `GoogleService-Info.plist` の `CLIENT_ID` と同じ | `google_sign_in` が読みます |

**意図的に書かないもの（Session Concierge が明示的に外しているもの）:**

| 書かないもの | 理由 |
| --- | --- |
| **`UIBackgroundModes`** | 「使わない背景動作を宣言したまま出すと、審査で用途の説明を求められる」。**今回バックグラウンド再生はやりません**（7 節） |
| **`NSCameraUsageDescription`** | 「使わない権限を書くと審査で用途の説明を求められる」 |
| `NSPhotoLibraryUsageDescription` | Session Concierge は `image_picker` のために書いていますが、**音源創庫は写真を選びません。** `file_picker` は UIDocumentPicker を使い、権限宣言が不要です |
| `NSMicrophoneUsageDescription` / `NSUserTrackingUsageDescription` / `NSAppTransportSecurity` / `LSApplicationQueriesSchemes` | Session Concierge はいずれも無し |

> **写真の利用理由が無いと、選択画面を出した瞬間に落ちます。
> 逆に、使わない権限を書くと用途の説明を求められます。**
> **「念のため書いておく」がいちばん悪い選択です。**

### 5-8. 共有リンク（**作る側と開く側は、対で設計します**）

**招待リンクには 2 つの側があります。片方だけ直すと、もう片方で壊れます。**

| 側 | いまの状態 | やること |
| --- | --- | --- |
| **作る側**（URL を組み立てる） | `lib/ui/share_url.dart:18`。**モバイルで例外を投げます** | 5-8-1 |
| **開く側**（URL を受け取る） | 何もない。**ブラウザで開くだけ** | 5-8-2 |

> **作る側だけ直すと、「リンクは作れるが、押した人はブラウザに落ちる」に
> なります。開く側だけ作ると、「開く仕掛けはあるが、そもそもリンクが
> 作れない」になります。** 順に 8a → 8b で進めてください。

---

#### 5-8-1. 作る側：`Uri.base` の始末

**2-5 のとおり、`lib/ui/share_url.dart:18` はモバイルで例外を投げます。**

```dart
// lib/ui/share_url.dart:17-19
String buildShareUrl(String path, {Uri? base}) {
  final origin = base ?? Uri.base;
  return '${origin.origin}${origin.path}#$path';   // ← ネイティブで StateError
}
```

**ネイティブの `Uri.base` は `file:` 形式**（実行時のカレントディレクトリ）
**で、`.origin` を読むと `StateError` を投げます。**
**招待リンクを作った瞬間に落ちます。**

> **`share_url.dart:13-15` のコメントが、すでにこの答えを書いています。**
>
> > `Uri.base` はテストでは `file:` 形式になり、`origin` を読むと例外になる。
>
> **テストで起きることは、モバイルでも起きます。**
> だから `base` を差し替えられる形になっているのですが、
> **実際に呼んでいる側は差し替えていません。**

**Session Concierge の解き方**（`app_urls.dart:14`）:

| プラットフォーム | 使う値 |
| --- | --- |
| Web | `Uri.base.origin` |
| **ネイティブ** | **固定ドメインの定数** |

**「QR・共有リンク・ガイド URL・規約リンクが全部これを通る」**と
書かれています。**音源創庫も同じです。**

| 直すもの | 場所 |
| --- | --- |
| **ネイティブ用の固定ドメイン定数を 1 箇所に集約する** | `lib/env/app_environment.dart`（`--dart-define` で本番／検証が切り替わる場所） |
| `buildShareUrl` の `base ?? Uri.base` | `lib/ui/share_url.dart:18` |
| 起動時のディープリンク取得 | `lib/main.dart:42`。**ネイティブでは常に空になります。** 5-8-2 で受け取り口を作るので、**そちらと繋ぎます** |

> **本番と検証で URL が違います**（本番は独自ドメイン、検証は `*.web.app`）。
> ここを間違えると、**検証環境のアプリが本番の招待 URL を配ります。**
> **配られた人は本番のリストに入ろうとして、入れません。**

---

#### 5-8-2. 開く側：App Links / Universal Links（**今回の範囲・社内に前例なし**）

**共有リンクを押したら、アプリが入っている端末ではアプリが開きます。**

##### 採った案と、採らなかった案

音源創庫の共有リンクは **`https://<host>/#/invite/abc123`** の形です
（`buildShareUrl` が `#` を挟む。go_router のハッシュ方式）。

> # **App Links / Universal Links は、OS が「パス」で照合します。**
> # **`#` から後ろは使いません。**
>
> **このリンクのパスは `/` だけです。**
> **OS から見ると、サイトのトップページと区別が付きません。**

| 案 | 内容 | 判定 |
| --- | --- | --- |
| **A** | URL をパス方式へ変える（`/invite/abc123`） | **採らない。** **アプリ全体の URL が変わり、Web 側の検証を一通りやり直すことになります。** すでに配ったリンクも動かし続ける必要があります |
| **B** | **パス `/` を丸ごとアプリに渡す** | **採用。** **すでに配ったリンクがそのまま動きます** |

**代償を明示します。**

> **サイトのトップ（`/`）を開こうとした人も、アプリに飛びます。**
> 「音源創庫のサイトを見よう」と思って URL を叩いた人が、アプリに入ります。
>
> **使い方ページ（`/help/...`）は別パスなので影響しません。**
> AdSense の対象である読み物ページは、**ブラウザで開いたままです**
> （ナレッジベース S-7 の構成を壊しません）。

##### 要るもの

| プラットフォーム | 要るもの |
| --- | --- |
| **Android** | `/.well-known/assetlinks.json`（**手元の鍵と Play アプリ署名鍵の両方の SHA-256**）＋ `AndroidManifest` に `<intent-filter android:autoVerify="true">`（ホストと `android:path="/"`） |
| **iOS** | `/.well-known/apple-app-site-association`（**拡張子なし**）＋ Associated Domains の entitlement（`applinks:<host>`） |

**`Runner.entitlements` は 5-6 で作るので、そこに `com.apple.developer.associated-domains`
を足します**（`applesignin` と同じファイル）。

##### 配信面（**ここが事故の多いところ**）

| 注意 | 内容 |
| --- | --- |
| **rewrite より先に返ること** | `firebase.json` の `rewrites` は `**` → `/index.html` の catch-all です。**`.well-known/` は実ファイルなので、rewrite より先に返ります**（`ads.txt` が 200 で返ることを実測済み）。**ただし下の `ignore` を先に確認してください** |
| **`apple-app-site-association` の `Content-Type`** | **拡張子が無いので、Hosting は `Content-Type` を推測できません。** `firebase.json` の `headers` に **`application/json` を明示**しないと **Apple 側に弾かれます** |
| **環境ごとに中身が違う** | 署名鍵もドメインも `applicationId` も違います。`sitemap.xml` と同じく、**`scripts/deploy.mjs` で配信物の側だけ**差し替えます（`scripts/deploy.mjs:334-352` の仕組みに乗せる） |
| **フラグメントはアプリに渡る** | **OS の照合には使われませんが、アプリには `#/invite/abc123` まで渡ってきます。** 受け取り口（`lib/main.dart:42` の隣）で読んでください |

> # **`firebase.json` の `ignore` を必ず確認してください。**
>
> いまの `firebase.json` の `hosting.ignore` に **`"**/.*"`** が入っています
> （Firebase の既定）。**これはドット始まりを除外する指定です。**
> **`.well-known/` もドット始まりです。**
>
> **「配信したのにファイルが無い」という形で失敗する可能性があります。**
> **配信したら、必ず外から実測してください。**
>
> ```
> curl -i https://<host>/.well-known/assetlinks.json
> curl -i https://<host>/.well-known/apple-app-site-association
> ```
>
> **確かめるのは状態コードだけでは足りません**（ナレッジベース S-7 の
> 「SPA の catch-all rewrite に注意」と同じ形）。
> **catch-all があるので、ファイルが無くても 404 ではなく 200 でアプリの
> HTML が返ります。** **`Content-Type` と中身まで見てください。**
> 除外されていたら `ignore` から `.well-known` を外す手当てが要ります。

##### 環境ごとの中身

| | 本番 | 検証 |
| --- | --- | --- |
| ホスト | 本番のドメイン | `music-storage-dev.web.app` |
| `assetlinks.json` の `package_name` | `jp.sessionconcierge.trackcabinet` | **`jp.sessionconcierge.trackcabinet.dev`**（3-4 でフレーバーを分けたため） |
| `assetlinks.json` の SHA-256 | **手元のアップロード鍵＋Play アプリ署名鍵の 2 つ** | **手元の鍵だけ**（Play に出さないため） |
| `apple-app-site-association` | 要る | **要りません。** **iOS に dev フレーバーを作らない**と決めています（3-4） |

> **`assetlinks.json` に Play アプリ署名鍵の SHA-256 を入れ忘れると、
> ストアから入れた人だけリンクが開きません。**
> **8-2 の Google ログインとまったく同じ形の事故です。**
> **Play が AAB を署名し直すので、端末に届くアプリの署名は手元の鍵では
> ありません。** 開発端末では動くので気づけません。
> **鍵の場所は 8-2 に書いてあります。**

> **`autoVerify="true"` の照合は、インストール時に OS が行います。**
> **`assetlinks.json` を後から直しても、すでに入っている端末では
> 自動で再照合されません。** 入れ直すか、
> Android の「デフォルトで開く」設定から手動で有効にする必要があります。
> **配信を先に、インストールを後にしてください。**

##### 社内に前例がありません

**Session Concierge はディープリンクを実装していません**
（`<intent-filter>` は LAUNCHER の 1 つだけ。`VIEW` / `BROWSABLE` /
`autoVerify` の宣言なし）。**QR・共有 URL はブラウザで開かせる設計です。**

**つまり、ここだけは「動いている前例を持ち込む」ができません**（9 節）。
**実機で確かめる以外の方法がありません。**

### 5-9. `AndroidManifest` と `build.gradle.kts`

#### 5-9-1. バックアップを止める（**Session Concierge のファイルを丸ごと持ち込めます**）

```xml
<application
    android:allowBackup="false"
    android:dataExtractionRules="@xml/data_extraction_rules"
    ... >
```

**理由：**

> **Firebase Auth のリフレッシュトークンは SharedPreferences に入っています。**
> 指定しないと Android の既定は `allowBackup=true` で、アプリの保存領域が
> まるごと Auto Backup の対象になり、**利用者の Google ドライブへ複製され、
> 別端末の復元でログイン状態ごと持ち込まれます。**

**`allowBackup=false` はクラウドバックアップしか止めません。**
Android 12 以降の**端末間データ移行**は別系統で、
`android/app/src/main/res/xml/data_extraction_rules.xml`（新規）の
`<device-transfer>` 側で除外します。

**Session Concierge のファイルは、5 ドメイン（`root` / `file` / `database` /
`sharedpref` / `external`）を `<cloud-backup>` と `<device-transfer>` の
両方で `exclude` するだけの短いファイルで、丸ごとコピーできます。**

> **このファイルは、この文書が所有します**（2026-08-16 に決定）。
>
> `data_extraction_rules.xml` は**認証トークンの持ち出し防止**と
> **ダウンロード済み音源の移行防止**という 2 つの目的を同時に満たすため、
> [DOWNLOAD-DESIGN.md](DOWNLOAD-DESIGN.md) も同じファイルを必要とします。
> **両方が「自分が足す」と書くと、二重に作るか、片方が上書きします。**
> 所有をこちらに寄せた理由は、主目的が土台側の関心事であることと、
> **ダウンロード機能より先に要る**ことです。
> あちらは「要る」ことだけを主張し、足しません。

> **ダウンロード機能への波及があります。**
> 全ドメインを除外する以上、**端末に置いたダウンロード済み音源は
> 機種変更で移行されません（新しい端末では落とし直しになります）。**
> **この代償は依頼者が許容しました**（2026-08-16）
> （[DOWNLOAD-DESIGN.md](DOWNLOAD-DESIGN.md) 11 節の F と同じ論点です）。
> **利用規約にも書きます**（5-15）。

#### 5-9-2. デバッグ署名フォールバックを廃止する

**音源創庫の `android/app/build.gradle.kts:72-76` は、まさに Session Concierge が
危険だと判断して廃止した分岐を持っています。**

```kotlin
// いまの音源創庫（build.gradle.kts:72-76）
signingConfig = if (keystoreProperties.getProperty("storeFile") != null) {
    signingConfigs.getByName("release")
} else {
    signingConfigs.getByName("debug")     // ← ここ
}
```

Session Concierge の記録:

> 以前は鍵が無いとデバッグ署名に落としていたが、そのせいで `key.properties` の
> 無い環境の `assembleRelease` が**エラーも警告も出さずにデバッグ鍵で
> 署名された APK を出していた**。**Play は debug 署名を弾くが、
> APK を直接配る経路ではそれが本番として流通しうる。**

**直し方（Session Concierge の実物）:**

```kotlin
// **判定を buildTypes の中に書いてはいけない。**
val wantsReleaseBuild =
    gradle.startParameter.taskNames.any { it.contains("Release") }
if (wantsReleaseBuild && !keystorePropertiesFile.exists()) {
    throw GradleException("release ビルドに必要な android/key.properties が見つかりません。…")
}
```

> **なぜ `buildTypes` の中に書いてはいけないか。**
> **`buildTypes` ブロックは debug ビルドでも設定段階で必ず評価されます。**
> そこで `throw` すると、**鍵を持たない開発機で `flutter run`（debug）まで
> 落ちます。** 実行しようとしているタスク名を見て、
> **release を作ろうとしたときだけ止めてください。**

**ビルド後の確認方法**（Session Concierge の実績）:

```
keytool -printcert -jarfile <出力した AAB/APK>
```

**`CN=Android Debug` と出たら失敗です。**

#### 5-9-3. `<queries>` と `INTERNET` は触りません

**前提が変わりましたの節のとおり、どちらも現状のままで動きます。**
`tel:` / `mailto:` / カスタムスキームを開く機能を足したときだけ、
その分を `<queries>` に足してください。

#### 5-9-4. `<intent-filter>` は 5-8-2 で足します

**App Links の `<intent-filter android:autoVerify="true">` は
5-8-2 の担当です。ここでは足しません。**

> **同じファイルを 2 箇所から直す形になります。**
> `AndroidManifest.xml` に手を入れるのは
> **5-4（`FirebaseInitProvider`）・5-9-1（バックアップ）・5-8-2（App Links）**
> の 3 つです。**別々の日に触ると、あとから来た変更が前のものを消します。**
> **まとめて 1 回で書くか、順序を守ってください。**

### 5-10. 署名

| 側 | やること | 誰が |
| --- | --- | --- |
| Android | keystore を作り、`android/key.properties` を書く | **依頼者** |
| iOS | Codemagic の Integration と変数グループ `appstore` を作る | **依頼者**（1-3） |
| iOS | 証明書とプロファイルの発行 | **CI**（`fetch-signing-files --create`） |

**Android の keystore（Session Concierge の実務メモがそのまま使えます）:**

| 項目 | 内容 |
| --- | --- |
| `keytool` の場所 | **PATH に無い。** `C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe` |
| パスワード | **いまの `keytool` は PKCS12 形式で作るため、鍵のパスワード＝キーストアのパスワード。** `key.properties` の `keyPassword` と `storePassword` には**同じ値**を書く |
| 置き場所 | **リポジトリの外。** 別名（alias）は `upload` |
| `storeFile` の書き方 | **スラッシュ区切り** |
| CI に渡すか | **渡しません。** Session Concierge は手元 Windows でのみ Android の release ビルドをしています |

**`android/app/build.gradle.kts:9-21` に作り方のコマンドがコメントで
書いてあります。そこに書いてある「鍵を失くすと、同じアプリとして
更新できなくなる」を読んでから作ってください**（8-5）。

### 5-11. `codemagic.yaml` の新規作成

**音源創庫には `codemagic.yaml` がありません。新規作成です。**
**Session Concierge のものを土台にできますが、そのままでは動きません。**

#### 5-11-1. 最大の落とし穴：`working_directory: app` の 5 行

> **Session Concierge の Flutter プロジェクトは `app/` の下です。
> 音源創庫はリポジトリ直下です。**

| 直すもの | Session Concierge | **音源創庫** |
| --- | --- | --- |
| `working_directory: app`（**5 箇所すべて**） | あり | **全部削る** |
| `working_directory: app/ios` | CocoaPods のステップ | **削る**（そもそもこのステップ自体が不要。下記） |
| `artifacts` | `app/build/ios/ipa/*.ipa` | **`build/ios/ipa/*.ipa`** |
| `xcode-project build-ipa --workspace` | `ios/Runner.xcworkspace`（`working_directory: app` からの相対） | **`ios/Runner.xcworkspace`**（リポジトリ直下からの相対。**文字列は同じだが意味が違う**） |

> **直し忘れると「pubspec が見つかりません」で全ステップが落ちます。**
> **1 つでも残っていると、そのステップだけが落ちます。**

#### 5-11-2. 版の固定（**意図的な非対称**）

```yaml
flutter: 3.44.9      # ← 固定する
xcode: latest        # ← 固定しない
cocoapods: default
```

| | 扱い | 理由 |
| --- | --- | --- |
| **Flutter** | **固定する** | `stable` にすると「**こちらが何も変えていないのにビルドの中身が変わる**」。Session Concierge は 2026-08-09 に**手元の SDK が 3.41.9 → 3.44.9 に自動で上がっていた**のを踏んでいます（気づいたのはテストではなく警告）。**これが版を固定している直接の理由です** |
| **Xcode** | **固定しない（`latest`）** | Apple は「**この版以降の SDK でビルドしたもの**」しか受け付けず、**その下限が定期的に上がります。** 固定すると**ある日突然アップロードを拒否されます** |

> **`flutter: 3.44.9` をそのまま持ってこないでください。**
> **音源創庫側で `flutter test` と `dart analyze` を通した版**に合わせます。
> Session Concierge の 3.44.9 は「手元で 532 件のテストと analyze を通した版」
> という根拠つきの数字で、**音源創庫の根拠ではありません。**

#### 5-11-3. 署名の 3 経路

| 何を | どこから |
| --- | --- |
| App Store Connect API キー（Issuer ID / Key ID / `.p8`） | **Codemagic の Integrations**。`integrations: app_store_connect: <登録名>` と**登録名を指すだけ**。値は yaml に書かない |
| 証明書用の秘密鍵 | **Codemagic の変数グループ（Secure）** `appstore` の `CERTIFICATE_PRIVATE_KEY`。`--certificate-key=@env:CERTIFICATE_PRIVATE_KEY` で渡す |
| 証明書・プロファイル本体 | **その場で Apple 側に作る**（`fetch-signing-files --create`） |

> # **`environment.ios_signing:` を使ってはいけません。**
>
> Session Concierge の yaml にこう書かれています。
>
> > **`ios_signing:` は置かない。** あれは「Apple 側にある署名ファイルを
> > **取ってくる**」設定で、**無いものを作りはしない**。まだ 1 つも作って
> > いない段階で使うと、環境の準備中に
> > `No matching profiles found for bundle identifier ... "app_store"`
> > で止まる（2026-08-14・初回ビルドで実際に踏んだ）。
>
> **代わりに `fetch-signing-files` に `--create` を付けます。**
> 2 回目以降は既にあるものを拾うので、毎回作られるわけではありません。

#### 5-11-4. ステップの並び

| # | 名前 | 内容 |
| --- | --- | --- |
| 1 | 依存を取得する | `flutter pub get` |
| 2 | **自動テストを流す** | `flutter test`。**ビルドの前に置くこと**（下記） |
| 3 | ~~CocoaPods を入れる~~ | **音源創庫では不要。** Session Concierge も「実質何もしていない」と書いています（SPM 運用で `Podfile` が無い） |
| 4 | 署名ファイルを用意する | `keychain initialize` → `fetch-signing-files --create` → `keychain add-certificates` → `xcode-project use-profiles` |
| 5 | ipa を作る | `flutter build ios --release --no-codesign` → `xcode-project build-ipa` |

> **テストはビルドの前に置いてください。**
> 「送信してから気づくと、版番号を上げ直して出し直すことになる
> （**App Store は同じ番号を受け取らない**）」

> **`flutter build ipa` は使いません。**
> あれは署名まで自分でやろうとし、その前段で「**開発用**証明書が鍵束にあるか」
> を確かめます。**配布用のビルドに開発用証明書は要らないのに、無いと
> `No valid code signing certificates were found` で止まります**
> （Session Concierge の 2 回目のビルドで実際に発生）。**2 段に分けます。**

#### 5-11-5. ストアへの自動提出は繋がない

```yaml
publishing:
  app_store_connect:
    auth: integration
    submit_to_testflight: false
    submit_to_app_store: false
```

> **`submit_to_testflight: true` は「外部テストへの提出」を意味します。**
> フィードバック用メール・審査連絡先（氏名・電話・メール）の登録と、
> **Apple のベータ審査**（初回 1 日ほど）を要求し、未登録だと
> **ビルドの処理が終わった「後」に**落ちます
> （Session Concierge が初回で踏みました。**バイナリは無事**でした）。

**`false` でも TestFlight にビルドは出ます。**
内部テスター（最大 100 人）はそのまま入れられます。

**失敗通知のメール宛先を必ず書いてください。**
「ビルドは非同期なので、**画面を見ていないと落ちたことに気づきません**」。

#### 5-11-6. Android は CI 化しません

**Session Concierge は Android を CI 化していません。**
手元 Windows で `flutter build appbundle --release --flavor prod` を実行し、
Play Console へ手動アップロードしています。
**keystore を CI に渡さずに済む**という利点があります。**同じにしてください。**

### 5-12. アイコン

**`flutter_launcher_icons` を dev 依存に足して生成します。**
**手で mipmap を並べないでください**（解像度ごとの置き換え漏れが起きます）。

| 設定 | 値 | 理由 |
| --- | --- | --- |
| **`remove_alpha_ios: true`** ＋ `background_color_ios` | 必須 | **iOS のアイコンは透過を持てず、持ったまま出すと App Store Connect がアップロードそのものを拒否します。ビルドは通るので気づくのが遅れます** |
| `adaptive_icon_background` / `adaptive_icon_foreground` | Android の適応アイコン | |

**Play のフィーチャーグラフィック（1024×500・透過不可）も要ります。**
Session Concierge は `brand/make_feature_graphic.py` で生成しています。

> **手で画像編集ソフトを開かないこと。**
> 「同じ絵を作り直せないと、掲載情報の更新のたびに品質がぶれる」

### 5-13. スクリーンショット

**Windows では iOS シミュレータが動きません。**
Session Concierge は `app/test/store_screenshots.dart` で、
**ウィジェットを直接描いて、Apple が求めるピクセル数ちょうどで PNG に
書き出しています。**

| 押さえること | 内容 |
| --- | --- |
| ファイル名 | **`_test.dart` で終わらせない。** `flutter test` に拾われないようにし、撮るときだけ名指しで実行する |
| フォント | **同梱フォントと Material アイコンを明示的に流し込まないと、文字もアイコンも豆腐（□）になります** |
| **撮影用の架空データ** | **別に用意します。** Session Concierge は `tool/seed_demo_for_screenshots.mjs` で投入・撤去（`--remove`）し、**ID をすべて `demo-` で始めています。本番へ流すには明示指定が要る**作りです |

> **実在の音源名・利用者名を写さないでください。**
> スクリーンショットは**世界中に公開されます。** リストの中身も、
> メンバーの表示名も、そのまま出ます。

**必要なサイズ:**

| ストア | 規定 |
| --- | --- |
| App Store | **6.7 インチと 6.5 インチが必須。** ただし Session Concierge の実際の提出は 6.5 インチ・13 インチ 各 4 枚で、**記述に揺れがあります。提出直前に App Store Connect の画面で確認してください** |
| Play | **最低 2 枚**、16:9 か 9:16 |
| Play アプリアイコン | 512×512 PNG |
| Play フィーチャーグラフィック | 1024×500 PNG/JPG・**透過不可** |

### 5-14. 実機幅でのレイアウト崩れの洗い出し（**独立した工程**）

**これは「ついでに確かめる」ではなく、独立した工程として立ててください。**

Session Concierge の記録（2026-08-04）:

> **Play Console 用のスクリーンショットを実機で撮ろうとして、初めて
> レイアウト崩れが見つかった。Web では一度も出ておらず、ブラウザの幅を
> 狭めても再現しなかった**（実機の論理幅 411dp − 余白 = 379px と、
> 開発中に見ていた幅が違った）。原因は**列幅を定数で持っていたこと**。

**音源創庫はこの症状を丸ごと未経験です。**

| 使える手段 | 内容 |
| --- | --- |
| **実機** | いちばん確実。**ブラウザを狭めても再現しません** |
| **Play のリリース前レポート** | 「テストとリリース → テスト → リリース前レポート」。**Google が実機（Android 15 以降を含む）でアプリを自動起動しスクリーンショットを撮ります。持っていない世代の端末の見た目を確かめる手段**になります。**上げた直後は空で、生成に時間がかかります** |

**探すもの:** 幅を定数で持っている箇所。
音源創庫には `test/ui/layout_widths_test.dart` があるので、
**そこに実機の論理幅（例：379px）を足すことを検討してください。**

### 5-15. 利用規約の新設

**法務ページは `scripts/build-manual.mjs` が生成します。手で複製しないこと。**

| | 場所 |
| --- | --- |
| 原本（既存） | `docs/manual/legal-{ja,en}.html`（本文だけの断片） |
| 生成物（既存） | `web/help/{ja,en}/privacy.html`（`scripts/build-manual.mjs:186, 322, 385-393`） |
| スラッグ（既存） | `PRIVACY_SLUG = 'privacy'`（`scripts/build-manual.mjs:123`） |
| 見張り | `test/domain/help_links_test.dart` |

**同じ形で規約を足します。**

| 作るもの | 置き場所 |
| --- | --- |
| 原本 | `docs/manual/terms-{ja,en}.html` |
| 生成 | `scripts/build-manual.mjs` に `TERMS_SLUG = 'terms'` を足し、`web/help/{ja,en}/terms.html` を出す |
| 導線 | ページ下部の並び（`scripts/build-manual.mjs:279`）に規約を足す |
| sitemap | 同スクリプトが作ります。**新しいページを載せ忘れないこと** |

> **`web/help/` に直接ファイルを置かないでください。**
> `scripts/build-manual.mjs` は生成前に出力先を掃除します。
> **手で置いたファイルは次の生成で黙って消えます。**

**著作権の扱いは 2 本立てで書くと決まりました**（2026-08-16）。

| 決めた柱 | 内容 |
| --- | --- |
| **投稿者の責任** | **投稿する人が、その音源について必要な権利を持っていること** |
| **私的利用の限定** | **ダウンロードしたものを、共有の範囲を超えて配布しないこと** |

> # **利用目的は限定しません。**
>
> 「バンド練習に限る」のような**用途の縛りは書きません。**
> **自分の演奏の保管、教室での共有など、想定していない正当な使い方まで
> 塞いでしまう**からです。
>
> **縛るのは「権利を持っているか」と「外へ配らないか」の 2 点だけです。**
> **踏み込みすぎないこと。**

**規約に書くこと（項目の一覧）:**

| 項目 | なぜ |
| --- | --- |
| **投稿者が必要な権利を持っていること** | **決めた柱その 1。** いま著作権への言及がゼロ |
| **共有の範囲を超えて配布しないこと** | **決めた柱その 2** |
| **問題が起きたときの削除・停止の根拠** | **これが無いと、権利者から連絡が来ても消せません。** 規約を作る実務上の目的の半分はここ |
| **運営者の免責** | 上の 3 つと対 |
| **権限を失うと端末のファイルが消えること** | 論点 12・13。**先に書いておかないと「勝手に消された」になります** |
| **機種変更で移行されないこと** | 5-9-1 の `data_extraction_rules.xml` の帰結 |
| 禁止事項・アカウント停止の条件 | ストアが求めます |
| 運営者と連絡先 | **F's Factory / support@session-concierge.jp**（正本は `scripts/build-manual.mjs` の `OPERATOR`。**別に書かない**） |
| 準拠法・裁判管轄 | 規約として要ります |

> **条文の起草はこちら側で行い、依頼者が確認します。**
> 上は「何を書くか」の一覧であって、条文案ではありません。

**Play は「アカウント削除用 URL」も求めます**（アプリをインストール
せずに削除を依頼できる Web ページ）。**アプリ内の退会とは別に要ります。**

### 5-16. ストア掲載文の正本をリポジトリに置く

**Session Concierge が `SessionConcierge_ストア掲載文.md` を作った理由が、
そのまま教訓です。**

> Android 配布手順には「案を提示済み」とだけ書いてあり、
> **本文がどこにも残っていなかった。会話の中だけにあるものは、
> 次に触るときに再現できない。**

**`docs/STORE-LISTING.md`（仮）を作ってください。**

| 項目 | 上限 | 使う場所 |
| --- | --- | --- |
| プロモーション用テキスト | **170 字** | App Store のみ。**審査なしで差し替えられる** |
| 概要（詳しい説明） | **4000 字** | 両ストア共通 |
| 短い説明 | **80 字** | Google Play のみ |

**文章上の注意（そのまま流用できます）:**

- **審査用アカウントには有料機能を付けておく**（「機能にたどり着けない」は差し戻しの典型）
- **「ベータ」「テスト中」と書かない**
- **他のプラットフォームの名前を書かない**（App Store の説明に Android など）
- **価格・無料期間を本文に書かない**（設定項目と食い違う）

### 5-17. ストア提出物

| 提出物 | Apple | Google | 備考 |
| --- | --- | --- | --- |
| プライバシーポリシー URL | 必須 | 必須 | **あります** |
| 利用規約 URL | 必須 | 必須 | **5-15 で新設** |
| **アカウント削除用 URL** | — | **必須** | **Web ページが要ります**（5-15） |
| 収集データの申告 | App Privacy | データセーフティ | Session Concierge は**メールアドレス・表示名・プロフィール画像・利用状況**を申告。音源創庫は `users/{uid}/private/state` の中身（メール・表示言語・通知設定・プレミアム・容量。[PREMIUM-DESIGN.md](PREMIUM-DESIGN.md) 7.1）を漏れなく書く |
| スクリーンショット | 6.7 / 6.5 インチ | 最低 2 枚 | 5-13 |
| **審査用テストアカウント** | **必須** | 必須 | 下記 |
| 年齢区分 / コンテンツレーティング | 必須 | 必須 | **利用者同士のコメント機能がある**ことを反映 |
| 輸出コンプライアンス | **不要** | — | `ITSAppUsesNonExemptEncryption=false` を入れてあるため（5-7） |
| アカウント削除の導線 | **必須（5.1.1(v)）** | 必須 | **満たしています**（2-8） |

**審査用テストアカウントの作り方:**

**このアプリは主要機能がすべてログイン必須**なので、無いと審査担当が
何も試せません。**次の 3 つを満たしたアカウントを用意してください。**

1. メール確認済み
2. リストのメンバーに入っている（曲が見える状態）
3. **プレミアムが有効**（クーポンで付与。[PREMIUM-DESIGN.md](PREMIUM-DESIGN.md) 5 節）

> **プレミアムの期限を長く取ってください。**
> Session Concierge は**審査用アカウントのプレミアム期限が 17 日後に
> 切れる設定だったことに提出直前で気づき、2029/01/01 まで延長**しています。
> **放置していれば審査中に主要機能が試せなくなっていました。**
> 審査は再提出のたびに走ります。

> **App Review のメモに「アプリ内課金は提供していない」を英語で明記
> してください。** 概要にプレミアムの記載があると、審査側が IAP を探します。
> Session Concierge が実際にそうしています。

**EU への配信：先に外して出します**（2026-08-16 決定）

> **EU のトレーダーステータスを届け出ると、名称・住所・電話・メールが
> EU の App Store 製品ページに公開されます。**
> **先に EU を外して出し、体制が整ってから足す**という順序を採りました。
> あとから足せるので、**出せなくなるわけではありません。**

> # **「ヨーロッパ（42）」を一括で外さないでください。**
>
> App Store Connect の地域区分「ヨーロッパ（42）」は
> **EU 27 か国＋非 EU 15 か国**です。
> **まとめて外すと、イギリス・スイス・ノルウェー等の非 EU 15 か国も
> 一緒に落ちます。**
>
> **外すのは EU 27 か国だけ。個別に外してください。**
> **数を数えてから作業すること**——「ヨーロッパを外す」という言葉のまま
> 操作すると、**42 か国が落ちたことに気づきません。**

---

## 6. テストで守るもの

**いまモバイル固有のテストはゼロです。**
**ゼロは「守られていない」ではなく「守られていないことに気づけない」**です
（[AUDIT-CHECKLIST.md](AUDIT-CHECKLIST.md) 観点 4）。

**下は全部、Windows の `flutter test` だけで動きます。**
実機も macOS も要りません。`test/domain/firebase_launchers_test.dart` と同じ作りです。

| # | 見張るもの | どう見るか | 破れたときに起きること |
| --- | --- | --- | --- |
| 1 | **アプリ ID が全箇所で一致している** | `build.gradle.kts` の `applicationId` と `project.pbxproj` の `PRODUCT_BUNDLE_IDENTIFIER` を**代入の形**で読む | 片方だけ変えると Firebase の設定が届かない。**出したあとは取り返しがつかない** |
| 2 | **`applicationId` にハイフンが無い** | 正規表現 | Gradle が受け付けない |
| 3 | **`namespace` と `applicationId` が別であること** | 同上 | 検証環境の Android アプリが作れなくなる（3-4） |
| 4 | **iOS deployment target が 15.0 以上** | `project.pbxproj` の 3 箇所すべて | **CI で落ちる**（手元で潰せる失敗を CI で踏む） |
| 5 | **`Info.plist` に `CFBundleLocalizations` があり、`ja` と `en` を含む** | plist を読む | **日本語端末でも英語起動** |
| 6 | **`CFBundleLocalizations` が `lib/l10n/` の言語と一致する** | `AppL10n.supportedLocales`（`lib/l10n/app_localizations.dart:95`）と突き合わせる | **同じことを決める場所が 2 つある**（ナレッジベース S-5） |
| 7 | **`Info.plist` に `ITSAppUsesNonExemptEncryption = false` がある** | plist を読む | 提出のたびに輸出コンプライアンスの質問 |
| 8 | **`Info.plist` に `CFBundleURLTypes` と `GIDClientID` がある** | plist を読む | **Google ログインからアプリへ戻れない**（「固まった」に見える） |
| 9 | **`Runner.entitlements` に `applesignin` があり、`aps-environment` が無い** | ファイルを読む | 前者が無いと Apple ログインが呼んだ瞬間に失敗。**後者があると鍵が無いので署名が失敗** |
| 10 | **`AndroidManifest` に `allowBackup="false"` と `dataExtractionRules` がある** | 文字列 | **Firebase Auth のトークンがバックアップで別端末へ渡る** |
| 11 | **`AndroidManifest` に `FirebaseInitProvider` の `tools:node="remove"` がある** | 文字列 | 検証環境のビルドが **`[core/duplicate-app]` で無言に落ちる** |
| 12 | **`build.gradle.kts` にデバッグ署名フォールバックが無い** | `signingConfigs.getByName("debug")` を探す | **デバッグ鍵の release が黙って出る** |
| 13 | **Firebase の接続設定が android / iOS で `UnsupportedError` を投げない** | `lib/env/firebase_options_*.dart` を読む | 起動即クラッシュ。**`REPLACE_ME` の見張り（`deploy.mjs:307-312`）と同じ発想** |
| 14 | **`google-services.json` / `GoogleService-Info.plist` が置いてある** | ファイルの存在 | 同上（**5-3 でコミットする方針にしたので成立します**） |
| 15 | **`buildShareUrl` が `Uri.base` に直接依存していない** | `lib/ui/share_url.dart` を読む | **モバイルで招待リンクを作った瞬間に例外**（5-8-1） |
| 15b | **`assetlinks.json` に SHA-256 が 2 つ以上ある**（本番向け） | JSON を読み、`sha256_cert_fingerprints` の要素数を数える | **手元の鍵だけだと、ストアから入れた人のリンクが開かない**（5-8-2・8-2 と同じ形） |
| 15c | **`assetlinks.json` の `package_name` が `applicationId` と一致する** | `build.gradle.kts` と突き合わせる | **照合が通らず、リンクが黙ってブラウザで開く。** エラーは出ません |
| 15d | **`apple-app-site-association` に `Content-Type` の指定がある** | `firebase.json` の `headers` を読む | **Apple に弾かれる**（拡張子が無く推測できないため） |
| 15e | **`firebase.json` の `ignore` が `.well-known` を除外していない** | `hosting.ignore` を読む | **配信したのにファイルが無い。** catch-all rewrite があるので **404 ではなく 200 でアプリの HTML が返り、「あるように見えて無い」** |
| 16 | **`AuthRepository` に `signInWithPopup` が `kIsWeb` の外で書かれていない** | `lib/data/repositories/` を走査 | **モバイルが起動時に落ちる** |
| 17 | **Apple ログインのボタンが iOS でだけ出る（両方向）** | ウィジェットテストでプラットフォームを差し替える | **iOS に出ないと審査で落ち、他に出すと押しても動かないボタンになる**（ナレッジベース S-1） |
| 18 | **`Platform.is*` / `dart:io` が `lib/` に無い** | `lib/` を走査 | **Web ビルドが壊れます。** Session Concierge も `dart:io` の import は `lib` 配下に 0 件 |
| 19 | **`google_sign_in` の版が `^7` 系** | `pubspec.yaml` を読む | **v6 と v7 で API が別物。** うっかり下げると丸ごと動かない |
| 20 | **利用規約のページが生成されている** | `scripts/build-manual.mjs --check` | 提出物が欠ける。既存の `test/domain/help_links_test.dart` に相乗りできる |

> **ファイルのパスを文字列で比べるときは `test/support/repo_files.dart` の
> `posixPath()` を必ず通してください。**
> Windows では区切りが `\` になり、`'android/app/'` と比べても一致しません。
> **2026-08-07 に、これで 2 本のテストが「常に通る」状態になっていました**
> （[AUDIT-CHECKLIST.md](AUDIT-CHECKLIST.md) 観点 4）。**赤にならず、
> 何も守らないまま緑になります。**

> **見張りを足したら、わざと壊して落ちることを確かめてください。**
> `test/domain/firebase_launchers_test.dart:19-24` に、**その見張り自身が
> 一度空振りした**記録があります。「名前がファイルのどこかに出てくるか」で
> 見ていたため、**設定を消してもエラー案内の文に名前が残っていて通りました。**

**機械で見張れないもの（＝人が確かめるもの）:**

| 確かめること | いつ |
| --- | --- |
| アイコンに透過が無い | アイコン差し替え時。**ビルドは通る** |
| **AAB がデバッグ鍵で署名されていない** | `keytool -printcert -jarfile`。**`CN=Android Debug` と出たら失敗** |
| Google ログインが実機で戻ってくる | 内部テスト / TestFlight で 1 回 |
| Apple のリレーアドレスで `emailVerified` がどうなるか | 同上 |
| **ストア経由で入れたアプリでログインできる** | **8-2。ここが最大の落とし穴です** |
| **`.well-known/` の 2 ファイルが外から取れる** | 配信のたび。**`curl -i` で状態コード・`Content-Type`・中身まで**（5-8-2） |
| **ストア経由で入れたアプリで共有リンクが開く** | **8-2 と同じ形。** 手元の APK では動くので気づけません |
| **サイトのトップを開いた人がアプリに飛ぶ**（＝案 B の代償が想定どおりか） | ディープリンクを入れたあと 1 回 |
| **実機幅でレイアウトが崩れない** | 5-14 |
| **`file_picker` と `just_audio` がモバイルで動く** | **前例がありません**（9 節） |

---

## 7. 今回やらないこと

| やらないこと | 理由 |
| --- | --- |
| **ダウンロード（オフライン保存）機能** | [DOWNLOAD-DESIGN.md](DOWNLOAD-DESIGN.md) の担当。**この土台の上に乗ります** |
| **プッシュ通知（APNs / FCM）** | **`aps-environment` を entitlements に書いたまま鍵が無いと署名が失敗する**ので、やらない間は書きません。いまの通知はアプリ内の通知画面で完結しています。**足すときは Session Concierge の `default_notification_icon` / `_color` / `_channel_id` の 3 つを忘れないこと**（無いとアイコンが白い塊・色が灰色・チャンネル名が「その他」になり、**エラーにも警告にもなりません**） |
| **バックグラウンド再生** | `UIBackgroundModes` を書くと審査で用途説明を求められます |
| **アプリ内課金（IAP）** | プレミアムは**クーポンで配る**と決まっています。**アプリ内で金銭を受け取らない限り発生しません。** ただし**アプリ内から外部の決済ページへ誘導すると規約違反**なので、そういう導線も作りません |
| **共有リンクの URL 方式を変えること**（`#` を使わないパス方式へ） | **案 A を採りませんでした**（5-8-2）。アプリ全体の URL が変わり、**Web 側の検証を一通りやり直すことになります。** すでに配ったリンクも動かし続ける必要があります |
| **`/help/...` をアプリで開くこと** | 読み物ページは**ブラウザで開いたまま**にします。AdSense の構成（ナレッジベース S-7）を壊さないため |
| **Android の CI 化** | Session Concierge も手元 Windows でビルドしています。**keystore を CI に渡さずに済む**利点があります |
| **CI での自動採番** | Session Concierge も手動運用です（**意図的な設計判断というより、単に手動のまま**と読めます） |
| **Sign in with Apple を Web / Android にも出す** | Apple 側に Services ID と戻り先 URL（ドメイン検証つき）の登録が別途必要。**iOS の審査要件を満たすのに要りません** |
| **macOS / Windows / Linux デスクトップ版** | 要求は iOS / Android のみ |
| **`getDownloadURL()` の露出（監査 L-9）の是正** | **未対応のまま残ります。** ダウンロード機能の作り方でこの露出の扱いが変わるため、[DOWNLOAD-DESIGN.md](DOWNLOAD-DESIGN.md) 側で判断します |

---

## 8. 危ないところ

**着手する人へ。事故の起きやすい順です。**

### 8-1. 署名ステップが「緑なのに何も作っていない」（**AP-71**）

**Session Concierge の初回 iOS クラウドビルドは 4 回失敗しました**（2026-08-14）。

| 回 | エラー | 実際の原因 |
| --- | --- | --- |
| 1 | `No matching profiles found for bundle identifier ... "app_store"` | **`environment.ios_signing:` は「取ってくる」設定で、無いものを作らない** |
| 2 | `No valid code signing certificates were found` | `flutter build ipa` が前段で**開発用**証明書を確かめる。**配布用ビルドに開発用証明書は要らないのに落ちる** |
| 3 | `"Runner" requires a provisioning profile with the Sign In with Apple feature` | **これを「capability が足りない」と読んだのが誤り。App ID 側の設定は最初から正しかった** |
| 4 | （成功。**8 分 28 秒**） | 真因は **`--certificate-key` の指定漏れ** |

**真因の性質が厄介です。**

> `app-store-connect fetch-signing-files` は、秘密鍵を渡さないと証明書を
> 作れません。**しかもログに 1 行出すだけで、ステップは成功扱いで終わります。**
>
> ```
> Cannot save Signing Certificates without certificate private key
> ```
>
> **2 回目・3 回目の署名ステップは緑になっていたのに、何も作っていませんでした。**
> **4 秒で成功して見えました。**

**見分け方:**

> 決め手はログ本文で、最後の 3 行（`Provisioning Profiles` / `Signing Certificate` /
> `Team Id`）が**すべて空**であることが証拠でした。**成功しているときはここが埋まります。**

**共有ドキュメントの 2 つのアンチパターンに昇格しています。**

| # | 内容 |
| --- | --- |
| **AP-71** | **緑になったステップを、成功したことにする** |
| **AP-72** | **エラーメッセージが挙げた条件を、原因だと読む**。回避策：**「無い」と言われたら、まず対象が存在するかを数える。0 件なら、条件の話は始まっていない** |

> **無害な警告:** 鍵束への取り込みで
> `security: SecKeychainItemImport: Unable to decode the provided data.`
> が出ますが、直後に `1 key imported. / 1 certificate imported.` と続いて
> いれば問題ありません。

### 8-2. Play アプリ署名鍵の指紋を、**2 か所**に登録し忘れる

> **AAB を Play へ上げると、Google が署名し直します。**
> 端末に届くアプリの署名は手元の鍵ではなく **Play の鍵**になります。

**この 1 つの事実が、2 つの機能を同時に壊します。**

| 登録先 | 何の指紋 | 忘れるとどうなるか |
| --- | --- | --- |
| **Firebase / Google Cloud**（OAuth クライアント） | **SHA-1** | **ストアから入れた人だけ Google ログインが失敗します** |
| **`/.well-known/assetlinks.json`**（App Links） | **SHA-256** | **ストアから入れた人だけ共有リンクがアプリで開きません**（ブラウザに落ちます） |

**開発端末では動きます。手元の APK を直接入れても動きます。だから気づけません。**

> **後者はエラーすら出ません。** 照合に失敗すると、Android は黙って
> ブラウザで開くだけです。**「動いている」と「アプリで開いている」を
> 見分けるには、実際に押して確かめるしかありません。**

**画面の場所**（Session Concierge が 2026-08-11 に実物で確認。
**2 度案内を間違えた**と記録あり）:

> 左メニュー「**Google Play による保護**」→「Google Play ストアの保護」→
> 「**アプリの署名**」。**「テストとリリース」の下ではありません。**

| 注意 | 内容 |
| --- | --- |
| 同じ画面に 2 つ並ぶ | 「**アップロード鍵の証明書**」と「**アプリ署名鍵の証明書**」。**取り違えないこと** |
| どの指紋を見るか | 「ポスト量子暗号鍵」ではなく**従来の鍵**。**同じ画面に SHA-1 と SHA-256 が両方出ます**（OAuth は SHA-1、`assetlinks.json` は SHA-256） |
| **両方登録する** | 手元のアップロード鍵 **と** Play アプリ署名鍵。**OAuth も `assetlinks.json` も、どちらも 2 つずつ** |

**確かめ方は 1 つだけです。内部テストのリンクからインストールして、
実際にログインし、実際に共有リンクを押してください。**

### 8-3. 環境を 1 つ増やしたら、「登録する場所」を数える

**Session Concierge は同じ形の抜けを 1 日に 3 つ続けて踏んでいます**（2026-08-11）。

| 症状 | 原因 |
| --- | --- |
| 本番の Web で Google ログインが失敗 | **独自ドメインが Auth の承認済みドメインに無い**（既定は `*.web.app` だけ） |
| dev の Android で Google ログインが作れない | **パッケージ名＋SHA-1 の組み合わせを本番が押さえている**（3-4） |
| ストア配信版だけ失敗（未然に防いだ） | **Play が署名し直す**（8-2） |

> **どれも「最初に作ったときは正しかった」。**
> 環境が増えるたびに登録先が増えているのに、**増やす作業が手順のどこにも
> 書かれていなかった。使い始めるまで症状が出ない。**

**音源創庫は本番と検証の 2 プロジェクトを持ちます。**
**Android の本番／検証・iOS の本番で、登録先が最低 3 組できます。**
**チェックリストを作ってください。**

### 8-4. `versionCode` は再利用できない

**版番号の正本は `pubspec.yaml:4` の `version: 0.1.0+1` の 1 か所だけ**です。
そこから Gradle（`versionCode` / `versionName`）にも Xcode
（`CURRENT_PROJECT_VERSION`）にも流れます。
**プラットフォーム側に直接書かないでください。**

| ルール | 内容 |
| --- | --- |
| **一度使った番号は、そのリリースを削除しても二度と使えない** | Play も App Store も |
| **番号は飛んでもよく、上がってさえいればよい** | **「出していないはず」と決めつけて同じ番号を使い直すと弾かれます**（Session Concierge が 2026-08-05 に実際に踏んだ）。**迷ったら上げる** |
| Android と iOS で番号を共有する | Session Concierge がそうしています |
| **`pubspec.yaml` のコメントを採番台帳にする** | Session Concierge は使用済み番号の履歴をコメントに書いています。**そのまま真似してください** |

> **`pubspec.yaml` を直しても、ビルドし直さなければ AAB は古いままです。**
> 確認方法（Session Concierge の実績）:
> ```
> grep -m1 "versionCode" build/app/intermediates/merged_manifest/prodRelease/*/AndroidManifest.xml
> ```

**音源創庫は `0.1.0+1`。Play に上げた瞬間から `+1` は永久に使えなくなります。**

### 8-5. 署名鍵を失くすと、同じアプリとして更新できない

`android/app/build.gradle.kts:19-21` に既に書いてあります。

> **鍵を失くすと、同じアプリとして更新できなくなる。** 手元だけでなく
> 安全な場所へ控えを取ること（Play アプリ署名を使う場合も、
> アップロード鍵は必要）。

**Play アプリ署名を使っていれば、アップロード鍵は Google に再発行を
依頼できます。使っていなければ、そこで終わりです。**

**iOS 側:** 証明書とプロファイルは再発行できますが、
**Apple Developer Program の契約が切れると配信が止まります。**
**証明書用の秘密鍵は毎回同じものを使ってください**（変えると証明書が増え、
**Apple の配布用証明書の保有上限にすぐ達します**）。

### 8-6. 検証環境の設定でストアに出す

`scripts/deploy.mjs` は Web について、接続設定が `REPLACE_ME` のままなら
止めます（`:307-312`）。**モバイルのビルドには同じ見張りがありません。**

**Session Concierge は `lib/src/config/flavor.dart` で
「既定を prod に倒す」**という手当てをしています
（**指定忘れのビルドが dev データを本番配信する事故を避けるため**）。

**音源創庫の `lib/env/app_environment.dart` も同じ立場か、確かめてください。**
**検証環境向けのビルドをストアに出すと、利用者のデータが見えず、
検証用のデータが利用者に見えます。**

### 8-7. 「ビルドが緑」を「出せる」と読み替える

| 事象 | ビルド | 実際 |
| --- | --- | --- |
| アイコンに透過がある | 通る | **アップロードで拒否** |
| debug 鍵で署名された AAB | 通る | **Play で拒否**（`CN=Android Debug`） |
| 署名ステップで `--certificate-key` を忘れた | **緑（4 秒）** | **何も作っていない**（8-1） |
| 通知の 3 つの `meta-data` を書き忘れた | 通る | **通知は届くが、白い塊で灰色で「その他」**（**エラーにも警告にもならない**） |

**2026-08-07 の `just_audio` の件**（[AUDIT-CHECKLIST.md](AUDIT-CHECKLIST.md)
観点 2・6）も同じ形でした。**ビルドは成功し、配信も成功し、画面も普通に
開き、その部品を使う操作だけが失敗しました。**

**モバイル化では部品を複数足します。同じ事故の条件が揃っています。**

### 8-8. 「アプリだけ古いまま」

**Web（Hosting）だけを更新した日に、ストアから入れたアプリは古いままです。**
モバイルを足した瞬間から、この非対称が発生します。

**Session Concierge はこれを事故ではなく「受容」として扱っています**
（2026-08-12。「次にアプリ側の変更が出たときにまとめて上げる」）。

**音源創庫も同じ立場でよいはずですが、次の 2 点に注意してください。**

| 注意 | 内容 |
| --- | --- |
| **サーバー側の変更は両方に効く** | Firestore ルール・Functions を変えると、**古いアプリにも即座に効きます。** 古いアプリが壊れる変更をしないこと |
| **「Web で直したから直った」と言わない** | 利用者がアプリを使っているなら、**Web の配信は届いていません** |

### 8-9. Play Console の警告の「場所」は当てにならない

Session Concierge の記録:

> 非推奨 API の警告が示した呼び出し元は、難読化の対応表（`mapping.txt`）で
> 引くと**無関係な Firebase Storage のラムダ**だった。真の呼び出し元は
> **Flutter 本体**。**難読化された名前は、対応表で実名に戻してから読む。**

### 8-10. 「出ない」を「無い」と読み替える

Session Concierge が通知チャンネルの調査で踏んだ形です。

> `dumpsys notification_manager` にチャンネルが出ないので「作られていない」と
> 判断しかけたが、**この dump にはそもそもチャンネルが載らない。**
> **「出ない」を「無い」と読み替える前に、その道具がそもそも出すものなのかを
> 確かめる。**

**AP-41「指定しなければ何も起きないと思う（実際は既定が選ばれる）」**
にも昇格しています。**Android は、指定しないと既定が選ばれます。何も
起きないのではありません。**

---

## 9. Session Concierge から学べないところ

**ここだけは前例がありません。「動いている前例がある」と思い込まないでください。**

| 項目 | 状況 |
| --- | --- |
| **`file_picker` のモバイル対応** | **Session Concierge は使っていません。** 画像は `image_picker` で選んで Storage に直接アップロードしています。**音源創庫のファイル選択が iOS / Android で動くかは、実機で確かめるまで分かりません** |
| **`just_audio` のモバイル対応** | **同じく前例なし。** Android は ExoPlayer、iOS は AVFoundation を使うため、**Web の `setUrl` とは別の実装が動きます**（`lib/data/audio_player_handle.dart:51`） |
| **端末へのファイル保存** | **Session Concierge には実装が 1 つもありません**（`path_provider` の import 0 件、`getApplicationDocumentsDirectory` 0 件、`dart:io` の import 0 件）。**キャッシュ設計・保存先ディレクトリの選び方について、学べるものはありません。** [DOWNLOAD-DESIGN.md](DOWNLOAD-DESIGN.md) は完全に新規設計です |
| **ディープリンク（App Links / Universal Links）** | **今回の範囲に入りましたが、前例がありません**（5-8-2）。Session Concierge の `<intent-filter>` は LAUNCHER の 1 つだけで、`VIEW` / `BROWSABLE` / `autoVerify` の宣言はありません。**QR・共有 URL はブラウザで開かせる設計です。** `.well-known/` の配信も、entitlement も、`assetlinks.json` も、**すべて音源創庫が最初です** |
| **フォントの同梱量** | Session Concierge は 1.35MB × 2、音源創庫は 2.36MB × 1。**同じ問題ですが数字が違います** |
| **Codemagic の料金・無料枠** | **どの文書にも記述がありません。画面で確認が要ります**（1-2） |

> **ディープリンクだけは、8 節の「危ないところ」に頼れません。**
> ほかの項目は Session Concierge が実際に踏んだ事故を並べたものですが、
> **ディープリンクには踏んだ人がいません。**
> 5-8-2 に書いた注意は、**AdSense 対応（`ads.txt` の実測）と
> Play の再署名（8-2）という、形の似た別件からの類推**です。
> **類推であることを承知したうえで、実測で確かめてください。**

> **移植できる考え方**（ダウンロード機能へ）:
> `data_extraction_rules.xml` で全ドメインを除外する以上、
> **端末に置いたものは端末間移行で持ち出されません。**
> **ダウンロード済み音源は機種変更で移行されず、新しい端末では落とし直しに
> なります。この代償は依頼者が許容しました**（2026-08-16）。

---

## 10. 参照

| 文書 | 何が書いてあるか |
| --- | --- |
| [DOWNLOAD-DESIGN.md](DOWNLOAD-DESIGN.md) | ダウンロード（オフライン保存）機能。**この土台の上に乗ります** |
| [PREMIUM-DESIGN.md](PREMIUM-DESIGN.md) | プレミアムの決定事項。**冒頭の「まだ実装していません」は古く、実装済みです**（要修正） |
| [SETUP.md](SETUP.md) | Firebase プロジェクトの作成、`configure-firebase` の使い方、デプロイ |
| [AUDIT-CHECKLIST.md](AUDIT-CHECKLIST.md) | 監査の観点。観点 2（一度も成功していない経路）・観点 4（自動的に通るテスト）・観点 6（配信後にしか出ない問題） |
| `C:\Codes\SessionConcierge\codemagic.yaml` | **iOS の CI 設定の実物。ほぼ全部がコメントで、理由が本文より長い** |
| `C:\Codes\SessionConcierge\app\android\app\build.gradle.kts` | **署名の停止判定・フレーバー・`applicationId` を分ける理由** |
| `C:\Codes\SessionConcierge\app\android\app\src\main\AndroidManifest.xml` | **`allowBackup=false`・`FirebaseInitProvider` の削除** |
| `C:\Codes\SessionConcierge\app\android\app\src\main\res\xml\data_extraction_rules.xml` | **丸ごとコピーできます** |
| `C:\Codes\SessionConcierge\app\lib\src\features\auth\auth_controller.dart` | **Google / Apple ログインのプラットフォーム分岐** |
| `C:\Codes\SessionConcierge\SessionConcierge_iOS配布手順.md` | **§1a が現行の正**（§2・§3 は「手元に Mac がある場合」として残してあるだけ） |
| `C:\Codes\SessionConcierge\SessionConcierge_Android配布手順.md` | keystore の作り方・Play Console の実務 |
| `C:\Codes\共有ドキュメント\ナレッジベース.md` S-6 | ストア審査（Apple / Google） |
| `C:\Codes\共有ドキュメント\ナレッジベース.md` S-1 | 認証の設計。**Apple サインインは iOS だけに出す** |
| `C:\Codes\共有ドキュメント\アンチパターン集.md` AP-71 / AP-72 / AP-41 / AP-42 | **緑を成功と読む・条件を原因と読む・既定が選ばれる・別プラットフォームへそのまま持ち込む** |
