# 音楽リスト共有アプリ

メンバーが個々に録音した音源や、YouTube 等で見つけた楽曲を、1 つのリストに集約して共有するアプリです。まず Web 版を開発し、将来的に Android / iOS への展開も見据えています。

- **仕様書**：[docs/MusicListApp_Spec.md](docs/MusicListApp_Spec.md)
- **セットアップ手順**：[docs/SETUP.md](docs/SETUP.md)
- **開発ログ**：[docs/DEVLOG.md](docs/DEVLOG.md) — つまずいた点と、そう決めた理由

## 技術スタック

| 区分 | 採用技術 |
| --- | --- |
| フロントエンド | Flutter（Web・Android・iOS） |
| バックエンド | Firebase（Blaze プラン） |
| データベース | Cloud Firestore |
| 認証 | Firebase Authentication（Google 連携／メール＋パスワード） |
| ファイル保存 | Cloud Storage for Firebase |
| サーバー処理 | Cloud Functions |
| Web 配信 | Firebase Hosting |
| 状態管理 | Riverpod |
| ルーティング | go_router |

## 開発の始め方

**Firebase プロジェクトを作らなくても、ローカルのエミュレータですぐ動かせます。**

以下は**ご自身のパソコンで**実行してください。エミュレータはコマンドを実行した
マシンの中だけで動くもので、`127.0.0.1` は「いま自分が使っているマシン」を指します。

```sh
git clone https://github.com/KennyT-JP/MusicStore.git
cd MusicStore
```

ウィンドウを 3 つ開いて、1 つずつ実行します。

**Windows**

```bat
scripts\dev-emulators.cmd    :: ウィンドウ 1：エミュレータ
scripts\seed.cmd             :: ウィンドウ 2：確認用データの投入（初回のみ）

flutter pub get              :: ウィンドウ 3：アプリ
flutter run -d chrome --dart-define=USE_EMULATOR=true
```

**macOS / Linux**

```sh
./scripts/dev-emulators.sh   # ターミナル 1：エミュレータ
./scripts/seed.sh            # ターミナル 2：確認用データの投入（初回のみ）

flutter pub get              # ターミナル 3：アプリ
flutter run -d chrome --dart-define=USE_EMULATOR=true
```

`flutter pub get` が `requires SDK version ^3.12.2` で失敗する場合は、Flutter が古いだけです。`flutter upgrade` で更新してください。

エミュレータの管理画面は、**起動したマシンのブラウザ**から <http://127.0.0.1:4000> で開けます。

繋がらないときは `node scripts/doctor.mjs` で原因を切り分けられます。
WSL・Dev Container・SSH 先で起動した場合はポート転送が必要です
（[docs/SETUP.md](docs/SETUP.md) 参照）。

ログインは `site-admin@example.com` / `password` などで行えます（詳細は [docs/SETUP.md](docs/SETUP.md)）。

クラウドの Firebase プロジェクトに繋ぐ手順も [docs/SETUP.md](docs/SETUP.md) にあります。接続設定が未記入のままクラウドに繋ごうとすると、原因が分かる形で例外を投げて止まります。

## 環境の切り替え

本番と検証（ステージング）を**別々の Firebase プロジェクト**に分けています（仕様書 12.2）。検証作業が本番データを壊す事故を構造的に防ぐためです。

```sh
flutter run -d chrome --dart-define=USE_EMULATOR=true  # ローカルのエミュレータ
flutter run -d chrome                                  # 検証環境（既定）
flutter run -d chrome --dart-define=APP_ENV=prod       # 本番環境
```

指定がないときは検証環境に倒します。検証環境では画面上部に「検証環境」のバナーが出ます。**本番環境では `USE_EMULATOR=true` を指定しても無視します**（取り違え防止）。

## ディレクトリ構成

```
lib/
  main.dart              エントリポイント
  app.dart               アプリのルートウィジェット
  domain/                ビジネスロジック（Firebase に依存しない）
    role.dart              役割と権限階層（仕様書 4.1）
    permissions.dart       権限判定（4.2 / 6.3 / 9）
    quota.dart             容量上限の判定（7.2 / 7.3 / 7.5）
    sequence.dart          連番の採番（6.2）
    invite.dart            招待 URL の検証（3.3）
    comment_tree.dart      コメントの入れ子ツリー（9）
    item_query.dart        検索・並び替え（6.4）
    display_name.dart      表示名の解決と初期値の決定（3.4 / 3.5 / 5.4）
    local_date.dart        タイムゾーンを持たない日付（6.2）
    concurrent_edit.dart   同時編集の検出（6.3）
  data/
    firestore_paths.dart   Firestore / Storage のパス定義（13.2 / 13.7）
    models/                Firestore のドキュメントに対応するモデル
    repositories/          Firestore / Storage の読み書き
  providers/
    app_providers.dart     Riverpod のプロバイダ（認証・リスト・項目）
  env/
    app_environment.dart   本番・検証の切り替え（12.2）
    firebase_options.dart  Firebase の接続設定（クラウド分は要差し替え）
    firebase_emulators.dart エミュレータへの接続
  ui/
    routes.dart            画面のパス定義（14.2）
    app_router.dart        画面遷移とリダイレクト判定（14.3）
    shell/                 レスポンシブなアプリ外枠（14.1）
    screens/               各画面（14.2）
    widgets/               画面をまたいで使う部品
  l10n/                    日本語・英語の文言（2 章）

functions/               Cloud Functions（TypeScript／仕様書 13.4）
  src/domain/            権限・容量の規則（Flutter 側と同じ内容）
  src/triggers/          Firestore / Storage のトリガー
  src/callable/          申請の承認・招待・サイト管理者の操作
  src/scheduled/         定期実行（削除ファイルの掃除）

test/                    Flutter の単体テスト
rules-test/              セキュリティルールのテスト（エミュレータ上で実行）
scripts/                 運用スクリプト（サイト管理者の登録・エミュレータへの投入）
firestore.rules          Firestore セキュリティルール（13.5）
storage.rules            Storage セキュリティルール（13.5）
firestore.indexes.json   Firestore のインデックス定義
docs/                    仕様書・セットアップ手順・開発ログ
```

`domain/` は Firebase に依存させていません。通信なしでテストでき、権限や容量の判定を確実に検証できるようにするためです（仕様書 12.6）。

## テスト方針

壊れると影響が大きいロジックは自動テストで守り、画面操作はステージング環境での手動確認でカバーします（仕様書 12.6）。

自動テストの対象：

| 対象 | 理由 |
| --- | --- |
| 権限判定（`domain/permissions.dart`） | 間違えると見えてはいけない情報が見える |
| 容量上限（`domain/quota.dart`） | 80%／90% の通知境界、上限超過時のブロック |
| 連番（`domain/sequence.dart`） | 振り直しなし・欠番維持が崩れると復旧できない |
| 招待 URL（`domain/invite.dart`） | ワンタイム性・有効期限 |
| リダイレクト判定（`ui/app_router.dart`） | 未ログインで内容が漏れないこと |
| Firestore セキュリティルール | クライアントを信用しない最後の防波堤 |

```sh
flutter test                        # 181 件
cd rules-test && npm test           # 71 件（Firestore ルール 66 件を含む）
cd functions && npm test            # 29 件（サーバー側のドメインロジック・通知）
cd functions && npm run test:integration  # 18 件（要エミュレータ）
```

**権限と容量の規則は Dart と TypeScript の両方にあります。** 画面の出し分けは Flutter 側、
サーバー側の判定は Functions 側が使います。同じ内容のテストを両方に置いてあるので、
片方を変えたらもう片方も直してください。

**Storage ルールの一部は自動テストで検証できません。** `storage.rules` はメンバー判定に Firestore を参照しますが、Storage エミュレータがこれに対応していないためです（本番では動きます）。該当箇所はステージング環境での手動確認で補います。確認項目は [docs/SETUP.md](docs/SETUP.md) にチェックリストとしてまとめてあります。

## 現在の状態

仕様は確定済み、**検証環境（<https://music-storage-dev.web.app>）への配信まで完了**しています。

### 画面（20 / 20 実装済み）

| 画面 | 内容 |
| --- | --- |
| ログイン | Google 連携／メール＋パスワード |
| サインアップ | 登録と確認メールの送信 |
| メール確認待ち | 再送・確認の取り直し |
| パスワード再設定 | リセットリンクの送信 |
| ホーム（参加リスト一覧） | リスト名・項目数・自分の役割。管理者には容量 |
| リスト詳細（項目一覧） | 並び替え・検索・削除済みの表示切替 |
| 項目詳細 | ファイル／URL の再生・ダウンロード、コメントスレッド |
| 項目の追加・編集 | ファイル／URL のタブ切替、進捗表示、容量チェック |
| 通知一覧 | 未読の強調、対象への遷移、すべて既読 |
| 設定 | 表示名・表示言語・通知設定・退会 |
| 自分の申請一覧 | 申請中／承認／却下の確認と再申請 |
| リスト作成の申請 | 4 項目の入力。名前の重複はサーバー側で判定 |
| リスト参加申請 | 共有 URL を開いた未参加者向け |
| 招待の受諾 | 期限切れ・使用済みなど理由別の表示 |
| メンバー管理 | 役割変更・除外・離脱・招待 URL の発行 |
| 参加申請の承認 | 承認時に役割を決定 |
| リスト設定 | 容量表示・共有 URL・リスト削除 |
| サイト管理（4 画面） | 申請承認・リストと容量・ユーザー管理・サイト設定 |

### 実装済みの Cloud Functions（仕様書 13.4）

| 契機 | 処理 |
| --- | --- |
| Storage への保存・削除 | 使用容量の加減算と 80%／90% 通知 |
| 項目の作成 | リスト管理者・サイト管理者へ通知 |
| コメントの作成 | 管理者＋親コメント／項目の投稿者へ通知 |
| メンバーの増減 | memberCount / adminCount の更新 |
| リストの削除 | 配下のデータ・ファイル・名前予約の削除 |
| リスト作成申請 | 申請・承認・却下 |
| 参加申請 | 申請・承認・却下 |
| 招待 URL | 発行・受諾（ワンタイム）・取消 |
| サイト管理者 | 昇格・降格（最後の 1 人はブロック） |
| 退会 | 投稿を残して isWithdrawn を立てる |
| 定期実行（毎日 4:00 JST） | 猶予期間切れファイルと孤児ファイルの削除 |

### そのほか残っていること

- 本番環境の構築 — Firestore と Cloud Storage の**ロケーションは作成後に変更できません**。決めきってから作ってください（仕様書 12.1 / 12.2）
- 予算アラートの設定（仕様書 12.1）— 自動停止を実装しない方針のため、唯一の歯止めです
- 項目編集時のファイル差し替え（旧ファイルの猶予期間つき削除が必要なため、Functions と合わせて実装）
- Storage ルールの手動確認（[docs/SETUP.md](docs/SETUP.md) のチェックリスト）
