# オフライン用ダウンロード機能 実装検討（2026-08-16）

**まだ実装していません。** これは「作る前に決めること」を並べ、
決まった範囲の作り方をまとめた文書です。

**この機能は iOS / Android アプリの上に乗ります。** アプリ化そのもの
（Firebase の接続設定、署名、ストア申請、Sign in with Apple、アプリ ID）は
[MOBILE-APP-DESIGN.md](MOBILE-APP-DESIGN.md) が扱うので、ここでは触れません。

---

## 1. これは何か

### 1.1 依頼者の要求（2026-08-16）

- ダウンロード機能を実装する
- ダウンロード機能は**プレミアムユーザー限定**
- ダウンロードした曲は**サンドボックス内にとどめ、ほかのアプリからは見えないようにする**
- **アンインストール時にダウンロードした曲は削除される**

### 1.2 この文書の範囲

| 扱う | 扱わない（[MOBILE-APP-DESIGN.md](MOBILE-APP-DESIGN.md)） |
| --- | --- |
| 端末のどこに何を保存するか | Firebase の android / iOS 向け接続設定 |
| 落とす・消す・同期する動き | 署名鍵、ストア申請、`applicationId` / Bundle ID |
| 権限とプレミアムの確認 | Sign in with Apple、`signInWithPopup` のモバイル対応 |
| ローカルファイル再生への切り替え | `UIBackgroundModes`、`ios/Podfile` の生成 |
| Web からダウンロードを外すこと | apk / ipa を作るビルド経路 |
| 利用規約の新設 | ストアの審査項目全般 |

**利用規約の新設**（論点 14）は両方に関わりますが、
**ダウンロードした音源をどう扱ってよいか**という条項はこの機能に固有なので、
7 節で文面の要件だけ書きます。規約そのものの構成は
[MOBILE-APP-DESIGN.md](MOBILE-APP-DESIGN.md) 側です。

### 1.3 いまの作り（2026-08-16 実測）

| 項目 | 現状 |
| --- | --- |
| ダウンロード | `lib/data/repositories/item_repository.dart:365-366` の `getDownloadURL()` **1 か所のみ**。`launchUrl(..., LaunchMode.externalApplication)` で URL を開くだけ |
| 呼び出し元 | `lib/ui/widgets/item_external_action.dart:39-42`、`lib/ui/screens/item_detail_screen.dart:366-371`、`lib/providers/playback_provider.dart:29-31` |
| 再生 | `just_audio ^0.10.6`。`lib/data/audio_player_handle.dart:51` の `_player.setUrl(url)` = **URL 再生** |
| 権限判定 | **ダウンロードにも再生にも判定が 1 つも無い。** `lib/domain/permissions.dart` に `canDownload` 相当は存在しない |
| プレミアムが左右するもの | ①申請なしのリスト作成 ②容量の自動拡張の **2 つだけ**。ダウンロード・再生には無関係 |
| `path_provider` | **直接依存ではない。** `just_audio` の推移依存として 2.1.6 が入っているだけ（`pubspec.lock:592-599`） |
| ダウンロード用パッケージ | `dio` / `http` / `flutter_downloader` は**無い** |
| 回線種別の判定 | `connectivity_plus` は**無い** |

**プレミアムの基盤は実装済みです。** 期限判定 `isPremiumActive`
（`functions/src/domain/premium.ts:22-28`）、判定 Provider `isPremiumProvider`
（`lib/providers/app_providers.dart:559-563`）、クーポンの発行・引き換えが
すでに動いています。この機能はそこに **3 つ目の用途**を足すことになります。

### 1.4 この設計は初物です（前例がありません）

**同じ作者の `C:\Codes\SessionConcierge`（すでに iOS / Android をストアに
出している Flutter アプリ）を調べましたが、端末にファイルを保存している実装は
ありませんでした。**

| 調べたこと | 結果 |
| --- | --- |
| `lib` 配下の `path_provider` の import | **0 件**（音源創庫と同じく、直接依存に持っていない） |
| `getApplicationDocumentsDirectory` / `getTemporaryDirectory` の呼び出し | **0 件** |
| **`lib` 配下の `dart:io` の import** | **0 件**（`Platform.is*` も 0 件） |
| 端末側の永続化 | `shared_preferences` のキー **2 つだけ**（通知の可否・表示言語） |
| 画像の扱い | `image_picker` で選んで `firebase_storage` へ**直接アップロード**。**中間ファイルを作っていない** |

**つまり、この文書が設計している範囲——保存先の選び方、目録とファイルの整合、
バックアップ除外、ローカルファイル再生——には、社内に一件も前例がありません。**

> **実機で確かめるまで分からないことが多い、という前提で進めてください。**
> 3 節と 4 節の記述は、パッケージの実装（`path_provider` / `firebase_storage` /
> `just_audio` のソースコード）を読んで裏を取ったものですが、
> **「読んで正しい」と「実機で動く」は別です。**
> 8.5 の「端末で確かめること」を、任意の確認ではなく**工程として**扱ってください。

**パッケージにも前例がありません。**

| パッケージ | Session Concierge | この機能での役割 |
| --- | --- | --- |
| **`just_audio`** | **使っていない** | ローカルファイル再生（4.3）。**モバイルでの動作実績ゼロ** |
| **`file_picker`** | **使っていない** | この機能では使いませんが、**モバイルでの動作実績がゼロ**です。アップロードの経路なので確認は [MOBILE-APP-DESIGN.md](MOBILE-APP-DESIGN.md) 側 |
| `firebase_storage` | 使っている（アップロードのみ） | **`writeToFile()` によるダウンロードは前例なし** |

**`just_audio` は Android で ExoPlayer（純 Java/Kotlin）を使うため NDK は不要です。**
ただし**プラグインを 1 つでも NDK が要るものに変えると、
`android/app/build.gradle.kts` に `ndkVersion` の指定が要ります**
（Session Concierge は「Firebase・広告・課金はネイティブビルドを必要としない」として
意図的に指定していません）。

---

## 2. 決めたこと

**2026-08-16 に依頼者へ 1 問ずつ確認した結果です。** 論点番号は
確認時の通し番号で、1・3・14〜16 は
[MOBILE-APP-DESIGN.md](MOBILE-APP-DESIGN.md) 側の論点です。

| # | 論点 | 決定 |
| --- | --- | --- |
| 2 | Web 版のダウンロード | **Web から音源のダウンロードを無くす。** Web はストリーミング再生のみ。音源以外のファイル（楽譜 PDF など）は従来どおり開ける。**既存利用者の機能削減にあたるため、使い方ページと画面での告知を仕様に含める** |
| 4 | ダウンロードの単位 | **曲ごととリスト一括の両方。** 土台は曲ごとで、一括はその繰り返し |
| 5 | 対象ファイル | **音源＋画像。** 画像はアプリ内で表示する（外部アプリへ渡さない＝サンドボックスから出さない）。PDF・zip などは対象外 |
| 6 | 端末側の上限 | **上限を置かない。** 設定に「端末内の使用量」を表示し、曲ごと／一括で手動削除できるようにする |
| 7 | 自動で消える場面 | **2 つだけ**。①権限を失ったとき（脱退・除外・プレミアム失効）②元が削除・差し替えされたとき。**容量都合の自動削除はしない** |
| 8 | オフラインで見える範囲 | **「ダウンロード済み」画面＋コメント。** 曲名・アーティスト・録音日・どのリストのものか・コメントを端末に持つ。**オフライン中のコメント投稿は不可**（読むだけ） |
| 9 | 使える役割 | **メンバーのみ（Read Only を含む）。閲覧者（viewer）は不可。** 共有リンクが回った先の人が端末に音源を残す経路を塞ぐ |
| 10 | 複数端末 | **制限しない。** 契約が「人ごと」なので揃う |
| 11 | 元が削除・差し替えされたとき | **削除→端末からも消す。差し替え→古いのを消して落とし直す** |
| 11b | 通信の条件 | **既定は Wi-Fi のときだけ。** 設定でモバイル通信も許可できる |
| 12 | プレミアム失効時 | **ダウンロード機能が使えなくなり、端末のファイルは削除される。** オンラインのストリーミング再生はこれまで通りできる。復帰したら再ダウンロードが必要 |
| 13 | 脱退・除外後に端末に残った曲 | **起動時にサーバーへ権限を問い合わせ、失われていればその場で削除する** |
| 13b | オフラインの上限 | **最終確認から 30 日で再生を停止する。** ただし**ファイルは消さない**（圏外にいただけの人に再ダウンロードを強いないため）。オンラインで確認が取れれば即座に復活 |

### 2.1 論点 12 の考え方（ここを取り違えると設計が崩れます）

こちらは当初「ダウンロード済みの曲＝資産」と捉え、既存方針 D3
（[PREMIUM-DESIGN.md](PREMIUM-DESIGN.md)）「追加だけ止める・既存は残す」と
矛盾すると考えましたが、**誤りでした**。依頼者による明確化を原文のまま残します。

> **ダウンロードは「機能」であって「資産」ではない。**
> リスト・アップロードしたファイル（資産）は残す。機能は止める。

これで D3 と一貫します。**画面の文言もこの線で書いてください**（6.5）。
「ダウンロードしたファイルが消えました」ではなく、
**「オフラインで聴く機能が止まりました。曲もリストも残っています」**です。

### 2.2 決定から自動的に決まること

| 決定 | そこから決まること |
| --- | --- |
| 9（閲覧者は不可） | 権限確認は「メンバーであること」を**リストごとに**確かめる必要がある。リストごとに脱退・除外が起きるため（4.2） |
| 11（差し替えは落とし直し） | 端末側は `file.storagePath` を覚えておく必要がある。差し替えは必ず別名になる（`item_repository.dart:207`）ので、**パスの一致だけで検出できる**（4.4） |
| 13b（30 日の時計） | **最終確認時刻を端末に持つ**必要がある。そして端末の時計を信用することになる（4.2 の注記） |
| 6（上限なし・手動削除） | 端末の使用量を数える手段が要る。**index を正としてファイルを数える**（3.4） |
| 5（PDF・zip は対象外） | 対象の判定は `isPlayableAudio()`（`lib/domain/playback.dart:17-24`）と `contentType` の `image/` 前方一致で行う。**新しい判定を別に作らないこと** |

---

## 3. 端末に持つもの

### 3.1 保存先

**`path_provider` の `getApplicationSupportDirectory()` を使います。**

| プラットフォーム | 実際の場所 | 根拠 |
| --- | --- | --- |
| iOS | `Library/Application Support`（`NSApplicationSupportDirectory`） | `path_provider_foundation-2.6.0/lib/src/path_provider_foundation_real.dart:45-47` |
| Android | 内部ストレージの `files`（`Context.getFilesDir()` = `/data/data/<applicationId>/files`） | `path_provider_android-2.3.1/lib/src/path_provider_android_real.dart:28-29` |

**この 2 つが、依頼者の要求 3 つを同時に満たす唯一の組み合わせです。**

| 要求 | なぜ満たされるか |
| --- | --- |
| 他アプリから見えない | iOS はアプリごとのコンテナ、Android は内部ストレージ。どちらも OS がプロセス境界で隔離する |
| アンインストールで消える | 両方ともアプリのデータ領域。OS が削除する。**こちらから消す処理を書く必要がない** |
| 利用者にも見えない | `path_provider` の文言が明示している——「Use this for files you don't want exposed to the user」（`path_provider-2.1.6/lib/path_provider.dart:67-68`） |

#### 使ってはいけない場所

| 場所 | なぜ駄目か |
| --- | --- |
| **`getApplicationDocumentsDirectory()`** | iOS では `NSDocumentDirectory`（`path_provider.dart:113`）。`Info.plist` に `UIFileSharingEnabled` を書いた瞬間、**ファイル App から中身が丸見えになります。** 将来だれかが別の目的でその設定を足すと、依頼者の要求が黙って壊れます。「いま立てていないから安全」は、設定 1 行で崩れる安全です |
| **`getExternalStorageDirectory()`**（Android） | 外部ストレージ。ほかのアプリから読めます |
| **`getTemporaryDirectory()`** | iOS では `NSCachesDirectory`（`path_provider.dart:49`）。**OS が容量不足のとき勝手に消します。** 論点 7 の「自動で消える場面は 2 つだけ」に反し、しかも消えたことに気づけません |

### 3.2 バックアップから外す

**再取得できるデータをバックアップに載せてはいけません。** 理由は 2 つあります。

1. **Apple の iOS Data Storage Guidelines**。再ダウンロードできるデータを
   iCloud バックアップに入れると、審査でリジェクトの理由になります
2. **もっと実務的な理由：消したはずのものが復元で戻ります。** 論点 12 で
   「プレミアム失効時に端末のファイルを削除する」と決めた以上、
   バックアップに残っていると、端末を機種変更するだけで復活します。
   **削除の決定が意味を失います**

#### iOS

`Library/Application Support` は**既定でバックアップ対象です。**
`downloads/` ディレクトリに「バックアップから除外」の印を付けます。

```swift
// ios/Runner/AppDelegate.swift へ足す MethodChannel の中身
var url = URL(fileURLWithPath: path)
var values = URLResourceValues()
values.isExcludedFromBackup = true
try url.setResourceValues(&values)
```

- **既存のパッケージにこれを行うものはありません。** `path_provider` にも
  ありません。**MethodChannel を 1 本足します**（`lib/platform/` の
  条件付き import と同じ形。既存の `app_ready.dart` が手本）
- **ディレクトリに 1 回付ければ配下も対象になります**。ただし
  **ディレクトリを作り直すと消えます。** 起動時に毎回、冪等に設定してください
- **確かめる手段が要ります。** 付けたつもりで付いていないのが最悪なので、
  同じ MethodChannel に「いま付いているか」を返す口を用意し、
  設定画面の開発者向け表示か、起動時のログに出します

#### Android

**同じ作者の `SessionConcierge`（すでに iOS / Android をストアに出しているアプリ）に、
そのまま持ち込める実例があります。**

`AndroidManifest.xml` の `<application>` に**2 つとも**書きます。

```xml
android:allowBackup="false"
android:dataExtractionRules="@xml/data_extraction_rules"
```

**なぜ 2 つ要るのか。** `allowBackup="false"` は
**クラウドバックアップ（Auto Backup / Google ドライブ）しか止めません。**
Android 12 以降の**端末間データ移行（device-to-device）は別系統**で、
そちらは `data_extraction_rules.xml` の `<device-transfer>` で塞ぎます。

実ファイルは
`C:\Codes\SessionConcierge\app\android\app\src\main\res\xml\data_extraction_rules.xml`
（コメントを除けば 16 行）。**5 つのドメインを `<cloud-backup>` と `<device-transfer>` の
両方で除外しているだけで、丸ごと持ち込めます。**

```xml
<data-extraction-rules>
    <cloud-backup>
        <exclude domain="root" />
        <exclude domain="file" />
        <exclude domain="database" />
        <exclude domain="sharedpref" />
        <exclude domain="external" />
    </cloud-backup>
    <device-transfer>
        <exclude domain="root" />
        <exclude domain="file" />
        <exclude domain="database" />
        <exclude domain="sharedpref" />
        <exclude domain="external" />
    </device-transfer>
</data-extraction-rules>
```

**`downloads/` だけを `path` で指定するのではなく、ドメインごと除外します。**
`domain="file"` が `getApplicationSupportDirectory()`（＝`Context.getFilesDir()`）に当たるので、
これで `downloads/` は入ります。

##### 実例が全ドメインを除外している理由は、ダウンロードとは別です

**Session Concierge がこれを入れた理由は、ダウンロード機能ではありません。**
実ファイルのコメントにそのまま書かれています。

> Firebase Auth のリフレッシュトークンは SharedPreferences（`sharedpref` ドメイン）に、
> FCM の登録情報は同じくアプリ内の保存領域に置かれる。持ち出されると
> **別端末の復元でログイン状態ごと持ち込まれる。**

**音源創庫にも同じ問題があります**（`firebase_auth` を使っているため）。
つまりこの 1 ファイルは、**ダウンロード機能のためと、認証トークンのためと、
2 つの目的を同時に満たします。**

> **このファイルの所有は [MOBILE-APP-DESIGN.md](MOBILE-APP-DESIGN.md) 側です**（2026-08-16 に決定）。
>
> **同じファイルを両方の文書が「自分が足す」と書くと、片方が先に足したあと、
> もう片方が上書きするか、足されていることに気づかず二重に作ります。**
> そこで所有を 1 つに寄せました。あちらに寄せた理由は 2 つです。
>
> - 主目的が**認証トークンの持ち出し防止**で、これは土台側の関心事
> - **ダウンロード機能より先に要る**（アプリを出した時点で必要になる）
>
> **この文書は「ダウンロードのためにも要る」ことだけを主張し、足しません。**
> ただし**あちらが落としたら、こちらの前提が崩れます**——
> 落ちていないことを 8 節のテストで確かめます。

##### `fullBackupContent` は要りません

当初この文書には「`dataExtractionRules`（API 31 以上）と
`fullBackupContent`（API 30 以下）の**両方**が要る」と書いていましたが、
**実例と突き合わせた結果、誤りでした。**

`android:fullBackupContent` は「Auto Backup は続けるが、一部を除外する」ための指定です。
**`allowBackup="false"` は Auto Backup そのものを止める**ので、
API 30 以下はそれだけで塞がります。`fullBackupContent` の出番がありません。

| API | クラウドバックアップ | 端末間移行 |
| --- | --- | --- |
| 23〜30 | `allowBackup="false"` で止まる | **そもそも仕組みが無い** |
| 31 以上 | `allowBackup="false"` で止まる | **`<device-transfer>` の除外で止まる** |

**アプリ全体のバックアップを止めることになりますが、失うものはありません。**
端末に持っている値は、`shared_preferences` のキー 1 つ
（`showDeletedItems`／`lib/data/local_preferences.dart:21`）と、
ダウンロードしたファイルだけです。前者は
「**消えても困らないもの**だけを置く」と定めた場所です（同 6-7 行）。

### 3.3 ディレクトリ構成

```
<getApplicationSupportDirectory()>/downloads/
  index.json                         ← 何を持っているかの目録
  <listId>/
    <itemId>/
      audio-<millis>.<ext>           ← 音源。<millis> は storagePath 由来
      image-<millis>.<ext>           ← 画像（あれば）
      comments.json                  ← その曲のコメント
      audio-<millis>.<ext>.part      ← 途中のもの（完了時に .part を外す）
```

#### なぜ元のファイル名を使わないか

Storage の保存名は `{millis}-{元のファイル名}` です（`item_repository.dart:207`）。
**元の名前には任意の文字が入ります。**
`:` `/` `\` `?` `*` `"` `<` `>` `|` はファイルシステムで使えないか、
使えても扱いが端末ごとに違います。長さの上限にも当たります。

**`itemId` をディレクトリ名にし、ファイル名はこちらで決めます。**
元の名前は `index.json` に持ちます（画面に出すのはそちら）。

#### なぜ `<millis>` を残すか

**差し替えのときに、新旧を同じディレクトリに並べられるようにするためです。**
古いのを先に消すと、落とし直しに失敗したときに
**聴けるものが 1 つも無い**状態になります。順序は
「新しいのを落とし切る → `index.json` を書き換える → 古いのを消す」です（4.4）。

`storagePath` の `{millis}` は差し替えのたびに必ず変わるので
（`item_repository.dart:207` が `DateTime.now().millisecondsSinceEpoch` を使う）、
新旧が衝突しません。

#### 拡張子

**`file.fileName` から取りますが、そのままは使いません。**
白リストを通します。

- 音源：`mp3` `m4a` `wav` `flac` `ogg` `aac`
  ——**`lib/domain/playback.dart:23` の集合をそのまま使うこと。**
  ここに別の集合を書くと、「一覧に再生ボタンが出るのに落とせない曲」ができます
- 画像：`jpg` `jpeg` `png` `gif` `webp` `heic`
- 白リストに無ければ、その曲は**ダウンロードの対象外**とする
  （落として再生できないものを端末に残さない）

拡張子を残すのは、`just_audio` がコンテナ形式を推測するときの手がかりになるためです。

### 3.4 メタデータをどこに持つか

#### `shared_preferences` は不向きです

`shared_preferences ^2.5.5` はすでに直接依存にあり、
`lib/data/local_preferences.dart` が使っています。**ですが、ここには使いません。**
理由は 4 つで、いずれも致命的です。

| 理由 | 中身 |
| --- | --- |
| **既存のコメントが禁じている** | `local_preferences.dart:6-7`——「ここに置くのは**消えても困らないもの**だけにすること」。目録は消えると困ります。**消えるとファイルだけが残り、数えることも消すこともできない孤児になります**（10 節の 1） |
| **バックアップから外せない** | iOS の `NSUserDefaults` は `Library/Preferences` に置かれ、**項目単位でバックアップから除外できません。** 3.2 で `downloads/` を除外しても、目録だけがバックアップに残ります。復元した端末では「持っているはずのファイルが無い」状態になります |
| **部分更新ができない** | キーと値の store なので、1 曲の状態を変えるには**目録全体を読んで書き直す**ことになります。一括ダウンロードで複数の曲が同時に完了すると、**あとから書いたほうが前の更新を消します**（lost update） |
| **起動時に全部メモリへ載る** | `NSUserDefaults` も Android の実装も、初期化時に全体を読みます。曲数に比例して起動が遅くなります |

#### 採るのは `index.json`（ダウンロード先と同じディレクトリ）

```
<downloads>/index.json
```

**目録とファイルを同じディレクトリに置くことが要点です。**

- **3.2 のバックアップ除外が、目録にもそのまま効きます**
- **アンインストールで一緒に消えます。** 片方だけ残ることがありません
- **利用者が「アプリのデータを消去」しても一緒に消えます**（Android）。
  目録だけ残ると、実体の無い曲が一覧に並びます

書き込みは**必ず別名へ書いてから rename** します。

```
index.json.tmp へ全体を書く → flush → rename('index.json')
```

`rename` は同一ファイルシステム内では POSIX が原子性を保証しており、
iOS / Android はどちらも POSIX です。**途中で電源が落ちても、
古い目録か新しい目録のどちらかが残り、壊れた目録は残りません。**

#### 規模の見積り

1 件あたりのおおよその大きさ：
`itemId` 20 + `listId` 20 + `storagePath` 約 120 + `fileName` 約 80 +
`title` / `artist` 約 60 + 数値・時刻 約 100 = **約 400 バイト**。

| 曲数 | `index.json` の大きさ |
| --- | --- |
| 100 | 約 40 KB |
| 1,000 | 約 400 KB |
| 10,000 | 約 4 MB |

**1,000 件（400 KB）までは、起動時に読み込んで問題ありません。**
これを超えるようなら `sqflite` へ移してください。**いま入れないのは、
プラグインを 1 つ増やす代償に見合う規模ではないからです**
（このアプリのリストは 3 件・作った人 2 人という規模です／
[PREMIUM-DESIGN.md](PREMIUM-DESIGN.md) の移行記録）。

**コメントは `index.json` に入れません。** 別ファイル
（`<listId>/<itemId>/comments.json`）にします。コメントは曲より
はるかに件数が多く、しかも曲ごとに独立して更新されます。
目録に混ぜると、コメント 1 件の同期のたびに目録全体を書き直すことになります。

### 3.5 持つ項目

#### `index.json`

```jsonc
{
  "version": 1,                        // 形を変えたときの移行用
  "lastVerifiedAt": 1755300000000,     // サーバーが返した最終確認時刻（4.2）
  "allowMobileData": false,            // 通信条件（4.6）。既定は Wi-Fi のみ
  "items": [
    {
      "listId": "...",
      "listName": "バンド練習 2026",     // オフラインで「どのリストか」を出す（論点 8）
      "itemId": "...",
      "seq": 42,                        // 連番。一覧の並び順に使う
      "date": "2026-08-01",             // 録音日（論点 8）
      "title": "...",
      "artist": "...",
      "storagePath": "lists/…/items/…/1755200000000-take3.wav",  // 差し替え検出（4.4）
      "fileName": "take3.wav",          // 画面に出す名前
      "contentType": "audio/wav",
      "sizeBytes": 41234567,            // サーバー側の大きさ
      "localAudio": "…/audio-1755200000000.wav",   // downloads からの相対パス
      "localImage": null,
      "localBytes": 41234567,           // 端末上の実測。使用量の表示に使う（6.4）
      "downloadedAt": 1755290000000,
      "commentsSyncedAt": 1755290000000
    }
  ]
}
```

**`sizeBytes` と `localBytes` を分けて持ちます。** 使用量の表示に
サーバー側の値を使うと、途中で終わったファイルや落とし損ねたぶんが
数字に出ません。**設定画面が示す「端末内の使用量」は、端末の実測でなければ
意味がありません**（6.4）。

**`localAudio` は相対パスで持ちます。** iOS はアプリを更新すると
コンテナの絶対パスが変わることがあります。絶対パスを保存すると、
更新の翌日に全部「ファイルが無い」ことになります。

#### `comments.json`

```jsonc
{
  "itemId": "...",
  "syncedAt": 1755290000000,
  "comments": [
    { "id": "...", "body": "...", "authorName": "...",
      "parentId": null, "path": [], "depth": 0,
      "status": "active", "createdAt": 1755280000000 }
  ]
}
```

`path` / `depth` / `parentId` をそのまま持つと、
**`lib/domain/comment_tree.dart` のツリー組み立てをオフラインでも
そのまま使えます。** 別の組み立て方を作らないでください。

**`authorName` を解決済みで持ちます。** 表示名は `users/{uid}` にあり、
オフラインでは引けません。同期のときに解決して埋めます。
名前が変わっても端末側は古いまま出ますが、
**「名前が古い」と「名前が出ない」なら前者のほうがましです。**

---

## 4. 動きの設計

### 4.1 ダウンロード

#### 取得方法：2 案の比較

| | A: `getDownloadURL()` + HTTP | B: `writeToFile()` |
| --- | --- | --- |
| いまの経路との関係 | **同じ**（`item_repository.dart:365-366`） | 新規 |
| 端末に残るもの | **無期限・認証不要の URL**（`?alt=media&token=…`） | **バイト列だけ** |
| 監査 L-9 への影響 | **広げる。** 端末の目録が「無期限の鍵束」になる | **広げない** |
| 毎回の権限確認 | **効かない。** URL を持っていれば誰でも取れる | **効く。** SDK が Auth トークンを付け、`storage.rules` の `canRead()` が毎回評価される |
| 進捗の取得 | HTTP パッケージ次第。`http` か `dio` を足す | `DownloadTask.snapshotEvents`（`firebase_storage-13.4.6/lib/src/task.dart:26-29`） |
| 中断・再開 | 自前 | `pause()` / `resume()` / `cancel()`（`task.dart:40-52`） |
| 追加パッケージ | **`http` または `dio` が要る** | **不要**（`firebase_storage ^13.4.6` は既に直接依存） |
| Web で動くか | 動く | **動かない**（`dart:io` の `File` を取る） |

**推奨は B（`writeToFile()`）です。**

決め手は 2 つです。

1. **監査 L-9 を広げないこと。** `getDownloadURL()` が返す URL は
   **無期限・認証不要**で、これは 2026-08-06 の監査で指摘され、
   **いまも未対応**です。ダウンロード機能を A で作ると、
   **利用者の端末に、そのリストの全曲ぶんの無期限 URL が並んだファイルが
   できます。** いまは「メンバーが自分でコピーしたら」という限定的な露出でしたが、
   A にすると露出の量が曲数ぶんに増えます。**未対応の問題を、
   別の機能を作るついでに拡大してはいけません**
   （[AUDIT-CHECKLIST.md](AUDIT-CHECKLIST.md) 観点 4）
2. **権限確認がもう一枚増えること。** B なら、脱退・除外された人が
   ダウンロードを始めた時点で `storage.rules` の `canRead()` に落ちて失敗します。
   起動時の権限確認（4.2）とは独立した守りになります。
   A の URL には権限の概念がないので、この守りが 1 枚も無くなります。

**`getData()` は採りません。** 既定の上限が 10 MB
（`firebase_storage-13.4.6/lib/src/reference.dart:99-101`）で、
音源はこれを普通に超えます。上限を上げても、
**ファイル全体が端末のメモリに載ります。** 100 MB の WAV を
一括ダウンロードで 10 曲並べれば、端末が落ちます。

#### B の代償（承知のうえで採ります）

| 代償 | どうするか |
| --- | --- |
| **Web で動かない** | 論点 2 で Web からダウンロードを外すので、機能としては影響なし。ただし**共通コードに `dart:io` を書くと `flutter build web` が落ちます**（いま `lib/` に `dart:io` はゼロ）。`lib/platform/app_ready.dart:16` と同じ条件付き import の形で分けます |
| **アプリを閉じると止まる** | `DownloadTask` はアプリのプロセスと寿命を共にします。バックグラウンド継続は OS 側の仕組み（iOS の background `URLSession`、Android の `WorkManager`）が要り、`firebase_storage` は提供していません。**今回やりません**（9 節）。画面に「アプリを開いたままにしてください」と出します |
| **再開が「途中から」にならない** | 上と同じ理由で、次回起動時は**最初から取り直し**になります。`.part` は消して落とし直します。**「再開」と書かないこと。** できないことを言葉で約束しない |

#### 曲ごとのダウンロード

```
ボタンを押す
  ↓
1. 権限を確かめる（端末側）
     プレミアムか（isPremiumProvider）
     メンバーか（ListAccess.hasAtLeast(readOnly)）
     → どちらか欠ければボタンを出していないはずだが、念のため
  ↓
2. 通信条件を確かめる（4.6）
     Wi-Fi でない かつ allowMobileData が false → 「Wi-Fi で接続してください」
  ↓
3. .part へ writeToFile()
     snapshotEvents で進捗（bytesTransferred / totalBytes）
     画面には「%」ではなく「12.3 MB / 41.2 MB」も併記する
     （曲は大きく、% だけだと止まって見える）
  ↓
4. 画像があれば同じ手順で（論点 5）
  ↓
5. コメントを取って comments.json へ（論点 8）
  ↓
6. .part を外す（rename）
  ↓
7. index.json に 1 件足す（3.4 の tmp + rename）
```

**順序が要点です。** `index.json` に書くのは**最後**です。
先に書くと、途中で失敗したときに「持っていることになっているが実体が無い曲」が
一覧に並びます。

#### 途中で失敗したとき

| 失敗 | 扱い |
| --- | --- |
| 通信が切れた | `.part` を消す。`index.json` は触らない。画面に「もう一度お試しください」 |
| 権限が無い（`storage.rules` に落ちた） | `.part` を消す。**その場で権限確認（4.2）を走らせる。** メンバーでなくなっていた可能性が高い |
| 端末の容量不足 | `.part` を消す。**端末の空き容量を出す。** 論点 6 で上限を置かないと決めた以上、足りなくなるのは利用者の端末の話であり、こちらで先回りして止めることはしません |
| アプリを閉じた | 次回起動時に `.part` を掃除する（4.7） |

#### リスト一括

**曲ごとの繰り返しです**（論点 4）。並列にはしません。

- **同時に 1 つずつ。** 並列にすると、端末の回線を占有し、
  途中で止めたときにどこまで済んだのか分からなくなります
- 進捗は「12 曲中 5 曲目」と「その曲の中の進捗」の 2 段
- **1 曲失敗しても止めません。** 続けて、最後に「3 曲落とせませんでした」と出します。
  1 曲の失敗で 50 曲が止まるのは割に合いません
- 途中で止めるボタンを必ず置く。押したら**いま落としている曲の `.part` だけ捨て、
  済んだぶんは残す**

### 4.2 権限確認

**アプリの起動ごとに 1 回、サーバーへ問い合わせます。**

```
アプリ起動 → オンライン → verifyDownloadAccess を呼ぶ（5 節）
   ├─ メンバーであり、プレミアムが有効 → lastVerifiedAt を更新（30 日の時計をリセット）
   ├─ プレミアムが切れている           → downloads/ を丸ごと削除（論点 12）
   └─ 特定のリストのメンバーでなくなった → そのリストのぶんだけ削除（論点 13）

アプリ起動 → オフライン
   ├─ 最終確認から 30 日以内 → そのまま聴ける
   └─ 30 日を超えた          → 再生を止める（ファイルは消さない／論点 13b）
                               オンラインで確認が取れれば即座に復活
```

#### 「メンバーであること」と「プレミアム」を両方見る理由

**別々に失われるからです。**

- プレミアムが切れても、リストのメンバーではあり続ける
- リストを脱退・除外されても、プレミアムは有効なまま

片方だけ見ると、もう片方が抜けたことに気づけません。
**そして結果が違います**——プレミアム失効は**全部削除**、
脱退・除外は**そのリストだけ削除**です。

#### 30 日の判定は純関数に置く

**`lib/domain/offline_access.dart` を新設します。**
`playback.dart` / `permissions.dart` と同じ流儀で、通信も端末の音も要らない
形にして回帰テストで固定します。

```dart
/// オフラインで再生してよいか（論点 13b）。
///
/// **ちょうど 30 日は「切れている」側に倒す。** functions/src/domain/premium.ts の
/// isPremiumActive が `untilMs > nowMs`（ちょうどは含まない）としており、
/// 境界の扱いがファイルごとに違うと、どちらが正しいかを読む側が毎回調べ直す。
static bool isPlayableOffline({
  required DateTime? lastVerifiedAt,
  required DateTime now,
  Duration grace = const Duration(days: 30),
}) {
  if (lastVerifiedAt == null) return false;   // 一度も確認できていない → 不可
  return now.difference(lastVerifiedAt) < grace;
}
```

- **30 日 = 2,592,000,000 ミリ秒。** 依頼者の決定（論点 13b）そのままの数字です。
  `siteConfig.itemPurgeGraceDays` の既定 30 日（`functions/src/config.ts:154`）と
  **たまたま同じ値ですが、別のものです。混ぜないこと**——
  片方を変えたときにもう片方まで動きます
- **`lastVerifiedAt` が null なら不可。** ダウンロードは権限確認を通った
  あとにしか始まらないので、実際には起きないはずですが、
  **既定は安全側に倒します**（`ListRole.tryParse` が未知の値に役割を与えないのと同じ考え）

#### 端末の時計は信用できません（正直に書きます）

**この設計は端末の時計に依存しています。** 端末の日付を戻せば、
30 日の時計は伸びます。

- **塞ぐには「時刻をサーバーからしか取らない」しかなく、それは
  オフライン再生と両立しません。** オフラインで聴けることが要求である以上、
  ここは開きます
- **これは「保証」ではなく「歯止め」です。** 意図せず圏外にいた人が
  聴けなくなるのを防ぐための猶予であって、悪意ある人を止める仕組みではありません。
  画面にも規約にもそう書いてください
- 同じ理由で、`index.json` を書き換えて `lastVerifiedAt` を伸ばすこともできます。
  暗号化しても復号鍵を端末に置く以上、結論は変わりません（9 節）

### 4.3 再生

#### いまの作り

`lib/data/audio_player_handle.dart:49-58` の `playFrom(String url)` が
`_player.setUrl(url)` を呼んでいます。`_loaded` に「いま読み込んである URL」を
覚えて、同じ曲の繰り返しで読み直しを避けています。

#### 変えるところ

**`just_audio 0.10.6` には `setFilePath(String filePath, ...)` があります**
（`just_audio-0.10.6/lib/just_audio.dart:798`）。
`setAudioSource(AudioSource.uri(Uri.file(filePath)))` と等価です。

`AudioPlayerHandle` に口を 1 つ足します。

```dart
abstract class AudioPlayerHandle {
  Future<void> playFrom(String url);        // 既存。URL 再生
  Future<void> playFile(String filePath);   // 追加。ローカルファイル再生
  // 以下は既存のまま
}
```

`JustAudioHandle` 側：

```dart
@override
Future<void> playFile(String filePath) async {
  if (_loaded != 'file:$filePath') {
    await _player.setFilePath(filePath);
    _loaded = 'file:$filePath';
  } else {
    await _player.seek(Duration.zero);
  }
  _start();
}
```

**`_loaded` に接頭辞を付けます。** URL とファイルパスを同じキー空間に
混ぜると、たまたま同じ文字列になったときに読み直しを飛ばします。
`playFrom` 側も `'url:$url'` にしてください。

#### どちらを使うか（純ロジック）

**`lib/domain/playback.dart` に足します。**

```dart
enum PlaybackSource { local, remote, blocked }

/// どこから鳴らすか。
///
/// **オフラインの上限（論点 13b）はここで効かせる。** 再生の入口が
/// 1 か所（PlaybackController.play）なので、ここを通せば漏れない。
static PlaybackSource resolve({
  required String? localPath,       // index.json にあり、実体もある
  required bool isPlayableOffline,  // OfflineAccessPolicy の結果
  required bool isOnline,
}) {
  if (localPath != null && isPlayableOffline) return PlaybackSource.local;
  if (isOnline) return PlaybackSource.remote;
  return PlaybackSource.blocked;
}
```

**ダウンロード済みなら、オンラインでもローカルを使います。**
落としたのに通信するのでは、落とした意味がありません。

**30 日を超えたら `local` を返しません。** そのときオンラインなら
`remote`（ストリーミング）に落ちます——**論点 12 のとおり、
ストリーミング再生はこれまで通りできる**ので、これで正しい動きになります。
オフラインかつ 30 日超なら `blocked` で、画面に
「オフラインで聴ける期間が過ぎました。一度オンラインにしてください」と出します。

`PlaybackController.play`（`lib/providers/playback_provider.dart:96-127`）は
この結果で分岐します。**`_urls` のキャッシュは `remote` のときだけ使います。**

#### 途中でファイルが消えていたら

`localPath` が `index.json` にあっても、実体が無いことがあります
（利用者が OS の設定から消した、など）。**`setFilePath` は失敗し、
`onError` に流れます**（`audio_player_handle.dart:71-77` の作りがそのまま効きます）。
そのとき `index.json` からその 1 件を落とし、`remote` で鳴らし直します。

### 4.4 同期（元の削除・差し替え）

#### いつ確かめるか

**4.2 の権限確認と同じタイミング（起動時）です。** 別のタイミングを増やしません。

加えて、**そのリストを画面で開いているあいだは Firestore の購読が動いている**ので、
そこで変化に気づいたらその場で処置します。

#### 全件は読みません

`index.json` に「そのリストを最後に同期した時刻」を持ち、
`updatedAt` がそれより新しい項目だけを読みます。

```
lists/{listId}/items
  .where('updatedAt', isGreaterThan: lastSyncedAt)
```

> **`firestore.indexes.json` への宣言を忘れないこと。**
> **エミュレータは索引を強制しないので、統合テストは緑のまま本番だけ落ちます**
> （2026-08-10 に索引の宣言漏れでユーザー削除が本番で必ず失敗した件と同じ形。
> [PREMIUM-DESIGN.md](PREMIUM-DESIGN.md) 9 節の注記）。

#### 何を見て判断するか（純関数）

**`lib/domain/download_sync.dart` を新設します。**

```dart
enum SyncAction { keep, remove, replace }

static SyncAction decide({
  required String? serverStatus,      // 'active' | 'deleted' | null（ドキュメントが無い）
  required String? serverStoragePath,
  required String localStoragePath,
}) {
  if (serverStatus == null) return SyncAction.remove;       // 消えた
  if (serverStatus == 'deleted') return SyncAction.remove;  // ソフト削除（論点 11）
  if (serverStoragePath == null) return SyncAction.remove;  // URL 項目に変わった
  if (serverStoragePath != localStoragePath) return SyncAction.replace;
  return SyncAction.keep;
}
```

**`storagePath` の一致だけで差し替えを検出できます。**
差し替えは必ず別名でアップロードされ（`item_repository.dart:204-212` の
「必ず別の場所へ置く」）、`replaceItemFile`
（`functions/src/callable/items.ts:41-125`）が `file` を差し替えます。
**同じパスへの上書きは `storage.rules:91,100` が禁じている**ので、
パスが同じなら中身も同じです。

**`previousFiles` は見ません。** サーバー専用の項目で
Dart モデルにも無く、いまの `file` を見れば足ります。
**見る必要のないものを読むと、それも守る対象になります。**

#### `replace` の順序

```
1. 新しい storagePath を audio-<新 millis>.<ext>.part へ落とす
2. .part を外す
3. index.json の storagePath と localAudio を書き換える（tmp + rename）
4. 古い audio-<旧 millis>.<ext> を消す
```

**古いのを先に消しません。** 途中で失敗したら、聴けるものが 1 つも無くなります。
3 と 4 のあいだで落ちても、次回起動の掃除（4.7）が拾います。

#### `remove` のとき

ディレクトリごと消し、`index.json` から落とします。
**画面に何が起きたかを出します**——黙って消えると、
利用者は「アプリが勝手に消した」と受け取ります。

「〇〇（曲名）は元が削除されたため、端末からも削除しました」

### 4.5 プレミアム失効

```
verifyDownloadAccess が premiumActive: false を返した
  ↓
downloads/ を丸ごと削除（index.json も含む）
  ↓
画面に知らせる
```

**丸ごと消します。** リストごとに残す判断はしません。
論点 12 は「ダウンロード機能が使えなくなり、端末のファイルは削除される」です。

#### 文言（2.1 の考え方に沿って）

**書いてはいけない文言：**

> ダウンロードしたファイルを削除しました。

**書く文言：**

> プレミアムの期間が終わりました。
> **オフラインで聴く機能が止まり、端末に保存していた音源を削除しました。**
> **曲もリストも、アップロードしたファイルも、すべて残っています。**
> これまでどおり、オンラインで再生できます。
> プレミアムに戻ると、また端末に保存できるようになります（もう一度ダウンロードが必要です）。

**「残っているもの」を先に、具体的に書きます。**
[PREMIUM-DESIGN.md](PREMIUM-DESIGN.md) の容量の節で
「『容量が減りました』とだけ出すと、ファイルが消されたと誤解されます」と
書いたのと同じ間違いを、ここで繰り返さないでください。

### 4.6 通信条件

**既定は Wi-Fi のときだけ。設定で解除できます**（論点 11b）。

#### 判定

`connectivity_plus` を足します（いま無し）。純ロジックは分けます。

```dart
// lib/domain/download_network.dart
static bool allows({required bool isWifi, required bool allowMobileData}) =>
    isWifi || allowMobileData;
```

#### これは「従量課金を避けられる保証」ではありません

`connectivity_plus` が返すのは**どの種類の回線に繋がっているか**であって、
その回線が従量制かどうかではありません。

- ほかの端末のテザリング（Wi-Fi 経由）は **Wi-Fi に見えます**
- VPN 経由のときは、実装によって判定が変わります
- Wi-Fi に繋がっていても、インターネットに出られるとは限りません

**画面には「Wi-Fi のときだけダウンロードする」と書き、
「モバイルデータを使いません」とは書かないでください。**
確かめられないことを保証と書かない、という決まりです。

Android では `<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />` が
要ります。**いま `AndroidManifest.xml` に `<uses-permission>` は 1 つもありません。**

### 4.7 起動時の掃除

**4.2 の権限確認より先に、1 回だけ走らせます。**

| 掃除するもの | なぜ |
| --- | --- |
| `.part` が残っているファイル | 前回のダウンロードが途中で終わった。再開はできない（4.1）ので捨てる |
| `index.json` に載っていないディレクトリ | 目録を書く前に落ちた、または `replace` の途中で落ちた。**孤児**（10 節の 1） |
| `index.json` に載っているが実体が無い項目 | 逆向きの食い違い。目録から落とす |

**この掃除が無いと、孤児が永久に容量を食い続けます。**
利用者から見ると「設定の使用量が実際より小さい」または
「アプリのストレージ使用量だけが増え続ける」形で出ます。

---

## 5. サーバー側に足すもの

### 5.1 `verifyDownloadAccess`（新規）

**置き場所は `functions/src/callable/downloads.ts`。**
`functions/src/index.ts` に export を足します。

```
入力  { listIds: string[] }              // 端末が持っているリストの一覧
出力  { premiumActive: boolean,
        verifiedAt: number,              // サーバーの時刻（ミリ秒）
        lists: { [listId: string]: 'member' | 'notMember' } }
```

#### 中で確かめること（順序も含めて、すべてサーバー側）

| 確かめること | 満たさないとき |
| --- | --- |
| ログイン済み・メール確認済み | `signInRequired` / `emailNotVerified`（`requireUid` がそのまま投げる） |
| `listIds` が配列で、要素が文字列 | `missingField` |
| `listIds` の件数が上限以内（**50 件**） | `tooManyLists`（新設） |

**それ以外は例外を投げません。**

#### なぜ `premiumRequired` を投げないか

**これが 5 節でいちばん大事な点です。**

`createListDirectly`（`functions/src/callable/list_requests.ts`）は
プレミアムでない人に `premiumRequired` を投げます。**この関数では投げません。**

例外にすると、**呼び出し側は「呼び出しが失敗した」と
「プレミアムでない」を区別できません。** 圏外・タイムアウト・
Functions のコールドスタート失敗も、同じ「失敗」として届きます。

そして**この関数の失敗は、端末のファイル削除を引き起こします。**
電波の悪い場所で 1 回失敗しただけで全曲消える、という事故になります。

**「プレミアムでない」は正常な答えです。** 正常応答で返し、
呼び出し側は「答えが返った」ことと「その中身」を分けて扱います。

```
呼び出しが失敗した        → 何もしない。オフラインとして扱う（30 日の時計は動かさない）
premiumActive: false      → 削除する
lists[X] == 'notMember'   → X のぶんだけ削除する
```

#### 実装の骨格

```ts
export const verifyDownloadAccess = onCall({ region: REGION }, async (request) => {
  const uid = requireUid(request);                    // callable/access.ts:19-28
  const isSiteAdmin = isSiteAdminRequest(request);    // callable/access.ts:35-40
  const listIds = requireListIds(request.data);       // 上限 50
  const nowMs = Date.now();

  const db = getFirestore();

  // プレミアムは本人だけの場所から読む（config.ts:81 の userPrivate）。
  const priv = await db.doc(paths.userPrivate(uid)).get();
  const until = priv.data()?.premium?.until;
  const premiumActive = isPremiumActive(                // domain/premium.ts:22-28
    until instanceof Timestamp ? until.toMillis() : null,
    nowMs
  );

  // メンバーかどうかはリストごとに見る。
  const lists: Record<string, 'member' | 'notMember'> = {};
  if (listIds.length > 0) {
    const snaps = await db.getAll(
      ...listIds.map((id) => db.doc(paths.listMember(id, uid)))
    );
    listIds.forEach((id, i) => {
      // **サイト管理者は members ドキュメントを持たない**（domain/roles.ts:46-49）。
      // 存在だけで判定すると、サイト管理者の端末から全部消える。
      lists[id] = isSiteAdmin || snaps[i].exists ? 'member' : 'notMember';
    });
  }

  return { premiumActive, verifiedAt: nowMs, lists };
});
```

#### 既存の作りに合わせるところ

| 合わせるもの | どこに合わせるか |
| --- | --- |
| ログイン・メール確認 | `requireUid`（`functions/src/callable/access.ts:19-28`）。**自前で書かない** |
| サイト管理者の判定 | `isSiteAdminRequest`（同 35-40） |
| プレミアムの期限判定 | `isPremiumActive`（`functions/src/domain/premium.ts:22-28`）。**`until > now` の境界をここで変えない** |
| プレミアムの置き場所 | `paths.userPrivate(uid)`（`functions/src/config.ts:81`）。`users/{uid}` ではない |
| メンバーの置き場所 | `paths.listMember(listId, uid)`（同 89） |
| エラー | `fail(status, code)`（`functions/src/errors.ts:136-142`）。**日本語の文をそのまま投げない** |
| リージョン | `onCall({ region: REGION }, …)` |

#### `functions/src/errors.ts` に足す符号

```ts
// --- オフライン用ダウンロード（docs/DOWNLOAD-DESIGN.md） ---
'tooManyLists',
```

`FALLBACK` にも文を足します。
**`lib/l10n` の `functionError…` も対で足すこと**——
対応を確かめるテストが `functions/test/domain.test.ts` にあります
（`errors.ts:24-25` の注記）。

#### なぜ Firestore を直接読まずに Functions を通すか

`users/{uid}/private/state` は**本人が読めます**し、
`lists/{listId}/members/{uid}` も読めます。技術的にはクライアントだけでできます。
それでも呼び出し可能関数にする理由は 3 つです。

1. **サーバーの時刻が返る。** `lastVerifiedAt` を端末の時計で決めると、
   時計を進めるだけで確認を偽装できます。サーバー時刻なら
   **その瞬間に確認が取れたことだけ**は本当になります
   （その後の経過時間は端末の時計なので、4.2 の注記のとおり完全には塞げません）
2. **1 往復で済む。** リスト 10 個なら、クライアント直読みは
   `private/state` 1 回 + `members` 10 回 = 11 往復。
   Functions なら 1 往復で、サーバー内では `getAll` の 1 回です
3. **判定の場所が 1 つになる。** 「メンバーか」「プレミアムか」を
   クライアントで組み合わせると、規則がクライアントにだけ存在します

### 5.2 `lib/domain/permissions.dart` に足すもの

```dart
/// ダウンロードできるか（docs/DOWNLOAD-DESIGN.md 論点 9・12）。
///
/// **メンバーのみ。Read Only は可、閲覧者（viewer）は不可。**
/// 閲覧者は共有リンクで「メンバーにならずに見る」を選んだ人で、
/// 役割を持たない（role.dart:89-92）。hasAtLeast は常に false を返すので、
/// readOnly を求めるだけで閲覧者は落ちる。
///
/// **プレミアムが要る（論点 12）。** 切れたら false になり、
/// 端末のファイルは 4.5 の流れで削除される。
static bool canDownload(ListAccess access, {required bool isPremium}) {
  if (!isPremium) return false;
  return access.hasAtLeast(ListRole.readOnly);
}
```

**`hasAtLeast(ListRole.readOnly)` で閲覧者が落ちることが要点です。**
`ListAccess.effectiveRole`（`lib/domain/role.dart:89-92`）は
閲覧者に役割を与えないので、`hasAtLeast` は必ず false になります。
`canView` を使うと**閲覧者が通ってしまいます**——
`canView` は `effectiveRole != null || isViewer` です（同 99）。

`isPremium` は `isPremiumProvider`（`lib/providers/app_providers.dart:559-563`）
から取ります。**`AsyncValue` のまま扱ってください**——
届く前に false を確定させると、プレミアムの人に一瞬
「ダウンロードできません」が見えます（同 552-555 の注記）。

### 5.3 `storage.rules` は変えません（そして、変えても塞げません）

**ダウンロードと再生は、Storage から見ると同じ `read` です。**

`storage.rules:82` の `allow read: if canRead(listId)` は
メンバーと閲覧者の両方に開いています。**閲覧者を外すことはできません**——
同 80-81 のコメントのとおり、**閲覧者もストリーミング再生できる必要がある**からです。

つまり：

| 塞げるもの | 塞げないもの |
| --- | --- |
| 正規のアプリから、閲覧者や非プレミアムがダウンロードすること | 改造したクライアントから、閲覧者や非プレミアムが音源を取ること |

**論点 9 の狙い（共有リンクが回った先の人が端末に音源を残す経路を塞ぐ）は、
正規の経路を塞げば実務上は達成されます。** リンクを受け取った人が
アプリを改造する話は、共有リンクの設計とは別の層の問題です。

**ただし「ルールで守られている」と書かないこと。** 守っているのは
`canDownload`（クライアント）と `verifyDownloadAccess`（サーバー）の 2 つで、
`storage.rules` はここには効いていません。

---

## 6. 画面

### 6.1 ダウンロード済み一覧

**新しい画面を 1 つ足します。** `lib/ui/app_router.dart` の `ShellRoute` の中、
`AppRoutes.settings`（`app_router.dart:147-150`）の並びです。

```dart
GoRoute(
  path: AppRoutes.downloads,          // '/downloads'
  builder: (context, state) => const DownloadsScreen(),
),
```

| 項目 | 中身 |
| --- | --- |
| 並び | **リストごとにまとめる**（論点 8 の「どのリストのものか」）。リスト内は `seq` 順 |
| 1 行に出すもの | 曲名・アーティスト・録音日・大きさ。すべて `index.json` から（3.5） |
| 行を押したら | オフライン用の詳細（曲の情報＋コメント）。**コメントは読むだけ。投稿欄を出さない**（論点 8） |
| 再生 | ローカルファイルから（4.3） |
| 削除 | 行のスワイプか、選択して一括 |
| **オフラインで開けること** | この画面は Firestore を一切読まないこと。読むと、圏外で真っ白になります |

**30 日を超えているときは、画面の上に帯を出します。**

> オフラインで聴ける期間（30 日）が過ぎました。
> 一度インターネットに接続すると、また聴けるようになります。
> **端末のファイルは残っています。**

### 6.2 曲ごとのボタン

置き場所は 2 か所です。

| 場所 | いまの状態 |
| --- | --- |
| 一覧（`lib/ui/screens/list_detail_screen.dart:609-650` の行） | 再生ボタンと `ItemExternalAction` がある |
| 詳細（`lib/ui/screens/item_detail_screen.dart:359-381` の `_MediaAction`） | ファイル行にダウンロードのアイコン |

**ボタンの状態は 4 つです。**

| 状態 | 見え方 |
| --- | --- |
| 未ダウンロード | ダウンロードのアイコン |
| ダウンロード中 | 進捗の輪＋押すと中止 |
| ダウンロード済み | チェックの付いたアイコン。押すと「端末から削除しますか」 |
| 使えない | **6.5 のとおり** |

**アイコンを流用しないでください。** いまの `Icons.download_outlined`
（`item_external_action.dart:28`）は「URL を開く」の意味で使われています。
Web からその機能を外す（7 節）ので混乱は減りますが、
**同じ絵で違う動きをさせない**ことは守ってください。

### 6.3 リスト一括

リスト詳細の上部メニューに「このリストを端末に保存」を置きます。

- 押したら**確認を出します**——「12 曲・約 480 MB をダウンロードします」。
  **曲数と合計サイズを必ず出すこと。** 大きさを知らせずに 500 MB を
  落とし始めるのは、端末の容量にも通信量にも失礼です
- 進行中は画面の下に帯（「5 / 12 曲目 · 中止」）
- **すでに落としてあるぶんは数に入れません。** 「12 曲中 8 曲は保存済み。
  残り 4 曲・約 160 MB」

### 6.4 設定

`lib/ui/screens/settings_screen.dart` に節を 1 つ足します
（クーポン入力が同 207-330 にあるので、その並び）。

| 出すもの | 中身 |
| --- | --- |
| **端末内の使用量** | **`localBytes` の合計**（3.5）。「1.2 GB（42 曲）」。**サーバー側の `sizeBytes` を使わないこと**——落とし損ねたぶんが数字に出ません |
| リストごとの内訳 | 「バンド練習 2026 — 820 MB（28 曲）」 |
| **すべて削除** | 確認ダイアログ。**「曲とリストは消えません」を必ず書く**（2.1） |
| **モバイル通信でもダウンロードする** | 既定 off（論点 11b）。説明は「オフのときは Wi-Fi に接続しているあいだだけダウンロードします」。**「モバイルデータを使いません」とは書かない**（4.6） |
| 端末の空き容量 | 参考として。論点 6 で上限を置かないので、判断材料は利用者に渡す |

### 6.5 プレミアムでない人・閲覧者への見せ方

| 相手 | 見せ方 |
| --- | --- |
| **プレミアムでない人** | ボタンは**出します**（薄く）。押すと「オフライン保存はプレミアムの機能です」＋設定のクーポン入力への導線。**隠さない**——存在を知らせないと、契約する理由も伝わりません |
| **閲覧者（viewer）** | ボタンを**出しません。** プレミアムを契約しても使えないので、押せるものを見せると「契約したのに使えない」になります |
| **判定が届く前** | **どちらも出しません**（`app_providers.dart:552-555`）。読み込み中に「使えない」を確定表示すると、プレミアムの人に一瞬それが見えます |
| **Web で開いている人** | ボタンを出しません。7 節の告知に置き換えます |

---

## 7. Web からダウンロードを外す

**論点 2。既存利用者の機能削減にあたります**
（[AUDIT-CHECKLIST.md](AUDIT-CHECKLIST.md) 観点 6「既存利用者が使えなくなる変更は無いか」）。

### 7.1 何を外し、何を残すか

| | 外す | 残す |
| --- | --- | --- |
| **音源ファイル**（`isPlayableAudio()` が true） | ダウンロードのボタン | **ストリーミング再生**（`list_detail_screen.dart:609-650`） |
| **音源以外のファイル**（PDF・zip など） | — | **従来どおり開ける**（論点 2） |
| **URL の項目**（`kind == 'url'`） | — | 従来どおり外部サイトへ |

**判定は `isPlayableAudio(contentType:, fileName:)`
（`lib/domain/playback.dart:17-24`）を使います。**
「音源かどうか」の規則がすでにここにあり、
再生ボタンの出し分けもこれで行っています。**新しい判定を別に作らないこと**——
2 つあると、「再生ボタンは出るのにダウンロードもできる曲」ができます。

### 7.2 手を入れる場所

| 場所 | 変更 |
| --- | --- |
| `lib/ui/widgets/item_external_action.dart:25-33` | `isFile` だけで分けているのを、**`isFile && isPlayableAudio(...)` のときは Web でボタンを出さない**に変える |
| `lib/ui/screens/item_detail_screen.dart:359-381` | 同上。`trailing` と `onTap` を条件で出し分ける |
| `lib/ui/screens/item_detail_screen.dart:331-334` のコメント | 「アプリ内蔵のプレーヤーは作らない」は**すでに事実と違います**（一覧に再生ボタンがある）。この機会に直す |
| `lib/data/repositories/item_repository.dart:365-366` | **残します。** ストリーミング再生（`playback_provider.dart:29-31`）と、音源以外のファイルが使っています |

**「Web かどうか」の分岐は `lib/platform/` の形に揃えます。**
条件付き import は `lib/platform/app_ready.dart:16` の 1 箇所だけなので、
同じ形を 1 つ増やします。`kIsWeb` を画面のあちこちに散らさないこと。

### 7.3 告知

**外す順序が要点です。**

| 順 | やること | なぜ |
| --- | --- | --- |
| 1 | **使い方ページと画面に告知を出す。ボタンはまだ外さない** | 代わりが無いまま消すと、その日から困る人がいます |
| 2 | **アプリを iOS / Android の両方に配信する** | 代わりが用意できた |
| 3 | **Web からボタンを外す** | ここで初めて外す |

**3 を 2 より先にやってはいけません。** 「アプリでできます」と書いた
そのアプリがまだ無い、という期間を作らないでください。

**1 と 3 のあいだを何日空けるかは、依頼者に決めてもらう項目です**（11 節）。

#### 告知の場所と文面

| 場所 | 内容 |
| --- | --- |
| **使い方ページ**（`web/help/{ja,en}/`） | **`scripts/build-manual.mjs` が `docs/manual/{ja,en}.html` から生成します。`web/help/` を手で触らないこと**（決定事項 4.12） |
| **ダウンロードボタンがあった場所** | 空白にしない。「オフラインで聴くには、アプリをお使いください」＋ストアへの導線 |
| **リスト詳細の上部**（告知期間中のみ） | 帯で 1 回だけ。閉じられるようにする |

文面の要件：

> **Web ブラウザからの音源のダウンロードを終了します。**（2026-XX-XX 予定）
> これまでどおり、**ブラウザでそのまま再生できます。**
> **楽譜やその他のファイルは、これまでどおりダウンロードできます。**
> 端末に保存してオフラインで聴く機能は、**iOS / Android アプリ**でご利用いただけます
> （プレミアムの機能です）。

- **「終了します」を先に、「できること」をすぐ後ろに書きます。** 順序が逆だと、
  何が変わるのか読み取れません
- **「楽譜やその他のファイルは従来どおり」を必ず書きます**（論点 2）。
  これを書かないと、全部落とせなくなったと受け取られます
- **日英の両方**（`lib/l10n/` と `docs/manual/{ja,en}.html`）

### 7.4 利用規約

**利用規約は存在しません**（論点 14。あるのはプライバシーポリシーのみで、
**著作権への言及がゼロ**です）。規約の全体は
[MOBILE-APP-DESIGN.md](MOBILE-APP-DESIGN.md) 側ですが、
**この機能に固有の条項が 2 つ**必要です。

| 条項 | なぜ |
| --- | --- |
| **端末に保存した音源の扱い** | 私的な範囲での利用にとどめること。第三者への提供・再配布をしないこと。**ダウンロードできることは、権利が移ることを意味しない** |
| **保存したものが消える場面** | ①プレミアムの期間が終わったとき ②リストから抜けた・外されたとき ③元が削除・差し替えされたとき ④30 日以上オンラインにならなかったとき（**このときは再生が止まるだけで、ファイルは残る**）。**先に書いておかないと、消えた時点で「勝手に消された」になります** |

---

## 8. テストで守るもの

**このリポジトリの流儀に従い、通信も端末の音も要らない純関数に切り出してから
確かめます**（`lib/domain/playback.dart:1-6` の考え方）。

### 8.1 純ロジック（`test/domain/`）

#### `OfflineAccessPolicy`（4.2）— **境界を必ず確かめる**

| 入力 | 期待 |
| --- | --- |
| 最終確認から **29 日 23 時間 59 分 59 秒** | **再生できる** |
| 最終確認から **30 日ちょうど**（2,592,000,000 ms） | **再生できない** |
| 最終確認から **30 日 + 1 ミリ秒** | 再生できない |
| 最終確認から **30 日 − 1 ミリ秒** | 再生できる |
| `lastVerifiedAt` が null | **再生できない**（安全側） |
| `now` が `lastVerifiedAt` より前（端末の時計が戻っている） | **再生できる。** これは仕様（4.2 の注記）。**テストに書いて固定しておくこと**——後から見た人が「バグだ」と直してしまわないように |

#### `Permissions.canDownload`（5.2）

| 相手 | `isPremium` | 期待 |
| --- | --- | --- |
| Read Only のメンバー | true | **できる**（論点 9） |
| Super User | true | できる |
| リスト管理者 | true | できる |
| サイト管理者（`ListAccess.siteAdmin()`） | true | できる |
| **閲覧者**（`isViewer: true, role: null`） | true | **できない**（論点 9） |
| メンバーでもなんでもない（`ListAccess.none()`） | true | できない |
| Read Only のメンバー | **false** | **できない**（論点 12） |
| 閲覧者 | false | できない |

#### `DownloadSyncPolicy.decide`（4.4）

| サーバー側 | 期待 |
| --- | --- |
| `status: 'active'`、`storagePath` が同じ | `keep` |
| `status: 'active'`、`storagePath` が違う | **`replace`**（論点 11） |
| `status: 'deleted'` | **`remove`**（論点 11） |
| ドキュメントが無い | `remove` |
| `kind` が `url` に変わった（`file` が null） | `remove` |

#### `PlaybackPolicy.resolve`（4.3）

| ローカル | 30 日以内 | オンライン | 期待 |
| --- | --- | --- | --- |
| あり | はい | はい | `local`（**落としたのに通信しない**） |
| あり | はい | いいえ | `local` |
| あり | **いいえ** | はい | **`remote`**（論点 12：ストリーミングはこれまで通り） |
| あり | いいえ | いいえ | `blocked` |
| なし | — | はい | `remote` |
| なし | — | いいえ | `blocked` |

#### `DownloadNetworkPolicy.allows`（4.6）

Wi-Fi × 設定 の 4 通り。`isWifi: false, allowMobileData: false` だけが false。

### 8.2 サーバー側（`functions/test/`）

- **閲覧者が `verifyDownloadAccess` を呼ぶと `notMember` が返ること。**
  `viewers/{uid}` があっても `members/{uid}` は無いので `notMember` になる
- **プレミアムでない人が呼んでも例外にならないこと。**
  **符号まで確かめる**——`premiumRequired` が投げられていないこと、
  `{ premiumActive: false }` が正常応答で返ること（5.1）
- **未ログインは `signInRequired`、メール未確認は `emailNotVerified`。**
  **符号まで確かめる**（`permissionDenied` ではなく、それぞれの符号であること）
- **サイト管理者は `members` が無くても `member` が返ること**（5.1 の注記）
- `listIds` が 51 件で `tooManyLists`、50 件で通ること（**境界**）
- `verifiedAt` がサーバーの時刻であること（呼び出し前後の時刻に挟まれる）
- 期限の境界：`until` がちょうど `now` のとき `premiumActive: false`
  （`isPremiumActive` が `>` であることに揃う／`domain/premium.ts:27`）

### 8.3 ファイルを実際に触るテスト（`Directory.systemTemp` を使う）

- **差し替えで古いものが残らないこと。**
  `audio-1000.wav` を持っている状態で `audio-2000.wav` に差し替え、
  **`audio-1000.wav` がディレクトリに存在しないこと**を確かめる
- **差し替えの途中で落ちても、聴けるものが残ること。**
  手順 2（`.part` を外す）の直後に止めたとき、
  `audio-1000.wav` と `audio-2000.wav` の両方があり、
  次回起動の掃除で `index.json` に載っていないほうが消えること
- **`index.json` の原子性。**
  `index.json.tmp` を残したまま止めても、`index.json` が壊れていないこと
- **孤児の掃除**（4.7）。`index.json` に無いディレクトリが消えること、
  逆に `index.json` にあって実体が無い項目が目録から落ちること
- **プレミアム失効で `downloads/` が空になること**（論点 12）
- **リスト A から抜けたとき、A のぶんだけ消えて B が残ること**（論点 13）

### 8.4 静的な見張り

| 確かめること | なぜ |
| --- | --- |
| **`lib/` に `getApplicationDocumentsDirectory` と `getExternalStorageDirectory` が出てこないこと** | 保存先を間違えると、依頼者の要求が黙って壊れます（10 節の 3）。**実行時に気づく手段がありません** |
| **`lib/` の共通コード（`lib/platform/` 以外）に `dart:io` が出てこないこと** | いま `lib/` に `dart:io` はゼロです。入れると `flutter build web` が落ちます |
| **`flutter build web` が通ること** | `scripts/deploy.mjs:316` が本番でこれを実行します。既存の `test/web_startup_test.dart` の隣 |
| 白リストが 1 か所であること | 3.3 の拡張子の集合が `playback.dart:23` を参照していること |

### 8.5 端末で確かめること（自動化できないもの）

**書き出しておかないと、誰も確かめません。**
**そして 1.4 のとおり、ここには社内の前例がありません。**
**「前例なし」と印を付けた行は、誰も一度も確かめたことがない動きです。**

| 確かめること | 手順 |
| --- | --- |
| **バックアップから外れていること（iOS）** | ダウンロード後、Finder / iTunes でバックアップを取り、`Library/Application Support/downloads` が含まれないこと。もしくは MethodChannel の読み取り口で `isExcludedFromBackup == true` |
| **アンインストールで消えること** | 落とした状態でアプリを削除 → 再インストール → 何も残っていないこと（**iOS / Android の両方**） |
| **ほかのアプリから見えないこと（iOS）** | ファイル App にアプリのフォルダが出ないこと |
| **ほかのアプリから見えないこと（Android）** | ファイルマネージャから `/data/data/<applicationId>/files` に到達できないこと |
| 機種変更で復元しても戻らないこと | バックアップ除外が効いていることの、いちばん実務的な確認。**11 節 F の判断がここに出ます** |
| **【前例なし】ローカルファイル再生が iOS で鳴ること** | `just_audio` の `setFilePath`（4.3）。**`SessionConcierge` は `just_audio` 自体を使っていません**（1.4）。iOS は AVPlayer、Android は ExoPlayer と**実装が別**なので、片方で鳴っても他方の証拠になりません |
| **【前例なし】ローカルファイル再生が Android で鳴ること** | 同上 |
| **【前例なし】拡張子ごとに鳴ること** | 3.3 の白リスト（`mp3` `m4a` `wav` `flac` `ogg` `aac`）を**1 つずつ実機で**。**`flac` と `ogg` は iOS で扱いが違います。** ブラウザで鳴ったことは、iOS で鳴る証拠になりません |
| **【前例なし】`writeToFile()` が大きなファイルで完走すること** | 100 MB 級の WAV。**進捗（`snapshotEvents`）が最後まで流れること**と、途中でアプリを背面に回したときに何が起きるか（4.1 の「アプリを閉じると止まる」が実際にどう見えるか） |
| **【前例なし】ダウンロード中に画面を回転・離脱しても壊れないこと** | `.part` の掃除（4.7）が効くこと |
| **【前例なし】`file_picker` のアップロードがモバイルで動くこと** | **この機能の範囲外**ですが、`SessionConcierge` に前例がありません（1.4）。確認は [MOBILE-APP-DESIGN.md](MOBILE-APP-DESIGN.md) 側で |

> **実機の幅は、ブラウザを狭めた幅とは違います。**
> `SessionConcierge` は Play Console 用のスクリーンショットを実機で撮って
> 初めてレイアウト崩れを見つけました（Web では一度も出ず、
> ブラウザの幅を狭めても再現しなかった）。
> **6 節の画面——特に進捗の帯と使用量の表示——は、実機幅で確かめてください。**

---

## 9. 今回やらないこと

**書かないと、あとで「なぜ無いのか」を調べ直すことになります。**

| やらないこと | 理由 |
| --- | --- |
| **バックグラウンドでのダウンロード継続** | `firebase_storage` の `DownloadTask` はアプリのプロセスと寿命を共にします。続けるには iOS の background `URLSession` と Android の `WorkManager` を別々に書くことになり、**取得方法を A（URL + HTTP）に戻す必要が出ます**——L-9 を広げないという 4.1 の判断と衝突します |
| **途中からの再開** | 上と同じ理由。`.part` は捨てて最初から取り直します。**「再開」という言葉を画面に出さないこと** |
| **端末をまたぐ「ダウンロード済み」の同期** | 論点 10 で複数端末を制限しないと決めました。**どの端末に何が入っているかをサーバーが持たない**ぶん、持ち物の管理も要りません。持たせると、端末を捨てたときに掃除する仕組みが要ります |
| **容量都合の自動削除** | 論点 7。自動で消える場面は 2 つだけです。**端末の容量が足りないのは利用者の端末の話**で、こちらが勝手に消すと「聴こうと思った曲が無い」が起きます |
| **オフラインでのコメント投稿** | 論点 8。投稿を溜めて後から送ると、**送った順と表示される順が食い違い**、返信の親子関係（`comment_tree.dart` の `path` / `depth`）が壊れます。読むだけにします |
| **PDF・zip のダウンロード** | 論点 5。**音源と画像だけ**です。PDF を端末に置くと、外部アプリで開きたくなり、それはサンドボックスから出すことになります |
| **音源の暗号化** | **復号鍵を端末に置く以上、端末を触れる人には開けられます。** 実装と不具合が増える代償に対して、守れる範囲が変わりません。**「保証」と書けないものを作らない**という決まりに沿った判断です。依頼者の要求「サンドボックス内にとどめる」は、OS の隔離で満たします（3.1） |
| **監査 L-9 そのものの解消** | この機能は **L-9 を広げないだけ**です。ストリーミング再生（`playback_provider.dart:29-31`）と Web の音源以外のファイルは、いまも `getDownloadURL()` を使い続けます。**直すのは別件**で、期限付き URL か、認証付き取得への全面移行が要ります |
| **プレミアムでない人への試用** | 論点 12 に無いので入れません。「1 曲だけ落とせる」といった例外を作ると、**削除の判断（4.5）に例外が要る**ようになります |

---

## 10. 危ないところ

**着手する人へ。事故の起きやすい順です。**

> **前提：この設計には社内に前例がありません**（1.4）。
> `SessionConcierge` は端末にファイルを一切保存しておらず、`lib` 配下に
> `dart:io` の import が 0 件です。**下の 9 つは、コードとパッケージの実装を
> 読んで挙げたものであって、「実際に踏んだ」記録ではありません。**
> **踏んだ記録が無いということは、ここに挙がっていない罠があるということです。**
> 8.5 の実機確認を、任意の確認ではなく工程として扱ってください。

### 1. `index.json` と実ファイルの食い違い（孤児）

**いちばん起きます。** 落としたが目録に書く前に落ちた、
差し替えの途中で落ちた、目録を書いたがファイルを消す前に落ちた——
どれも普通に起こります。

- **書く順序を 1 か所に閉じ込めること。** 4.1 と 4.4 の順序を、
  リポジトリのクラス 1 つの中だけで完結させます。画面から呼ばない
- **起動時の掃除（4.7）を必ず作ること。** これが無いと、
  孤児が永久に容量を食い、設定の使用量は実際より小さく出ます。
  利用者から見ると「アプリのストレージだけが増え続ける」形で出ます
- 差し替えは**新しいのを落とし切ってから古いのを消す**（4.4）

### 2. 保存先を間違える

`getApplicationDocumentsDirectory()` にすると、iOS で
`UIFileSharingEnabled` を立てた瞬間に**ファイル App から丸見えになります。**
依頼者の要求「ほかのアプリからは見えないようにする」に直接反します。

**厄介なのは、間違えても動くことです。** テストは通り、
ダウンロードも再生もできます。**気づくのは、誰かが別の目的で
`Info.plist` に 1 行足したときです。** 8.4 の静的な見張りを必ず入れてください。

### 3. バックアップ除外を忘れる

**プレミアム失効で消したファイルが、機種変更で戻ります。**
4.5 の削除が意味を失います。

- **iOS と Android で、やることが全く違います**（3.2）。片方だけやりがちです
- Android は **`allowBackup="false"` と `dataExtractionRules` の両方**が要ります。
  前者は**クラウドバックアップしか止めず**、Android 12 以降の端末間移行は
  `<device-transfer>` 側で塞ぐ必要があります。**片方だけだと、機種変更で戻ります**
- **`SessionConcierge` の実ファイルをそのまま持ち込めます**（3.2）。書き起こさないこと
- **「付けたつもり」を検出する手段を作ること**（3.2 の読み取り口）

### 4. プレミアム失効の判定を例外で表す

`verifyDownloadAccess` が `premiumRequired` を投げる作りにすると、
**通信の失敗と区別できなくなります**（5.1）。
そして**この判定の結果は端末のファイル削除です。**

**電波の悪い場所で 1 回失敗しただけで、全曲が消えます。**
正常応答で状態を返す形を崩さないでください。

### 5. Web を壊す

`writeToFile` は `dart:io` の `File` を取ります。共通コードに書くと
**`flutter build web` が落ち、`scripts/deploy.mjs:316` の配信が止まります。**

いま `lib/` に `dart:io` の使用はゼロです。
`lib/platform/app_ready.dart:16` と同じ条件付き import の形で分けてください。

### 6. Web からボタンを外す時期

**アプリが両ストアに出る前に外すと、代わりの無い期間ができます**（7.3）。
[AUDIT-CHECKLIST.md](AUDIT-CHECKLIST.md) 観点 6 に真正面から当たります。

順序は「告知 → アプリ配信 → 外す」です。**逆にしないこと。**

### 7. 同期クエリの索引宣言漏れ

4.4 の `where('updatedAt', isGreaterThan: …)` には索引が要ります。

> **エミュレータは索引を強制しないので、統合テストは緑のまま本番だけ落ちます。**
> 2026-08-10 に索引の宣言漏れでユーザー削除が本番で必ず失敗しました。
> `firestore.indexes.json` への宣言を忘れないこと。

### 8. サイト管理者を消してしまう

サイト管理者は `lists/{listId}/members/{uid}` を持ちません
（`functions/src/domain/roles.ts:46-49`）。
`members` の存在だけで判定すると、**サイト管理者の端末から全部消えます。**
5.1 の `isSiteAdmin ||` を落とさないこと。

### 9. 「30 日」を `itemPurgeGraceDays` と混ぜる

どちらも既定 30 日ですが、**別のものです。**

| | 何の日数か | 置き場所 |
| --- | --- | --- |
| オフラインの猶予 | 最終確認から再生を止めるまで（論点 13b） | この機能の中（4.2） |
| `itemPurgeGraceDays` | 削除した項目の実体を消すまで | `siteConfig`（`functions/src/config.ts:154`） |

**片方を `siteConfig` から読むようにすると、サイト管理者が削除の猶予を
15 日に変えた瞬間に、オフラインで聴ける期間も 15 日になります。**

---

## 11. 依頼者の判断がまだ要るところ

**着手前に決めてください。** 決めずに進むと、あとから作り直しになります。

| # | 決めること | なぜ要るか |
| --- | --- | --- |
| A | **Web の告知から機能を外すまで、何日空けるか** | 7.3 の順序は決まっていますが、日数が決まっていません。既存利用者への影響の大きさを決める数字です |
| B | **サイト管理者もプレミアムが要るか** | 論点 12 に例外の記述がありません。いまの設計（5.1）では**サイト管理者もプレミアムが無ければ使えません。** これでよいか |
| C | **プレミアムでない人にボタンを見せるか** | 6.5 では「薄く出して、押すと案内」としました。まったく出さない選択もあります |
| D | **一括ダウンロードの上限** | 論点 6 で端末側の上限は置かないと決めましたが、**1 回の一括で 500 曲・20 GB**のような操作を止めるかどうかは別の話です |
| E | **「オフラインで聴けなくなりました」を通知で送るか** | 30 日が近づいたとき（例：残り 3 日）に知らせるか。既存の通知の仕組み（`users/{uid}/notifications`）に乗せられます |
| F | **機種変更でダウンロード済み音源が移行されないことを許容するか** | 下の 11.1 |

### 11.1 F の中身

3.2 で Android のバックアップ除外を入れると、
`data_extraction_rules.xml` が `<device-transfer>` でも全ドメインを除外するため、

> **ダウンロード済みの音源は機種変更で新しい端末へ移行されません。
> 新しい端末では、もう一度ダウンロードすることになります。**

**こちらの見立ては「許容する」です。** 理由は 3 つあります。

1. **設計と整合します。** 4.2 の権限確認は、新しい端末でも起動時に走ります。
   移行してきたファイルがあっても、そこで確認が取れなければ結局消えます
2. **再取得できるデータです。** iOS 側で「再取得できるデータをバックアップから
   除外する」（3.2）と決めた理由と同じ理由が、Android にもそのまま当てはまります
3. **論点 10 で複数端末を制限しないと決めています。** 新しい端末で
   落とし直すことは、もともと想定されている使い方です

**それでも依頼者に確かめる理由は、代償が利用者に直接見えるからです。**
20 GB を落としている人が機種変更すると、**新しい端末で 20 GB を落とし直します。**
Wi-Fi のみが既定（論点 11b）なので通信費はかかりませんが、時間はかかります。

**「移行する」を選ぶ場合**は、`<device-transfer>` から `domain="file"` の除外を外し、
`<cloud-backup>` 側だけ全ドメインを除外することになります。**ただしそのとき、
`sharedpref` に入っている Firebase Auth のリフレッシュトークンも一緒に移行するかを
別に決める必要が出ます**（3.2 の注記）。**「音源だけ移行する」は
`data_extraction_rules.xml` の粒度では書き分けが要ります**（`domain="file"` に
`path="downloads/"` を付けた `<include>` を使う形）。**単純に片方を外さないこと。**
