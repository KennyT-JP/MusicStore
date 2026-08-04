# 音楽リスト共有アプリ

メンバーが個々に録音した音源や、YouTube 等で見つけた楽曲を、1 つのリストに集約して共有するアプリです。まず Web 版を開発し、将来的に Android / iOS への展開も見据えています。

- **仕様書**：[docs/MusicListApp_Spec.md](docs/MusicListApp_Spec.md)
- **セットアップ手順**：[docs/SETUP.md](docs/SETUP.md)

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

```sh
# ターミナル 1：エミュレータ
firebase emulators:start --project demo-musiclist

# ターミナル 2：確認用データの投入（初回のみ）
cd scripts && npm install && cd ..
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
node scripts/seed-emulator.js

# ターミナル 3：アプリ
flutter pub get
flutter run -d chrome --dart-define=USE_EMULATOR=true
```

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
    display_name.dart      表示名の解決（3.5 / 5.4）
    local_date.dart        タイムゾーンを持たない日付（6.2）
    concurrent_edit.dart   同時編集の検出（6.3）
  data/
    firestore_paths.dart   Firestore / Storage のパス定義（13.2 / 13.7）
  env/
    app_environment.dart   本番・検証の切り替え（12.2）
    firebase_options.dart  Firebase の接続設定（クラウド分は要差し替え）
    firebase_emulators.dart エミュレータへの接続
  ui/
    routes.dart            画面のパス定義（14.2）
    app_router.dart        画面遷移とリダイレクト判定（14.3）
    shell/                 レスポンシブなアプリ外枠（14.1）
    screens/               各画面（14.2）
  l10n/                    日本語・英語の文言（2 章）

test/                    Flutter の単体テスト
rules-test/              セキュリティルールのテスト（エミュレータ上で実行）
scripts/                 運用スクリプト（サイト管理者の登録・エミュレータへの投入）
firestore.rules          Firestore セキュリティルール（13.5）
storage.rules            Storage セキュリティルール（13.5）
firestore.indexes.json   Firestore のインデックス定義
docs/                    仕様書・セットアップ手順
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
flutter test              # 144 件
cd rules-test && npm test # 71 件（Firestore ルール 66 件を含む）
```

**Storage ルールの一部は自動テストで検証できません。** `storage.rules` はメンバー判定に Firestore を参照しますが、Storage エミュレータがこれに対応していないためです（本番では動きます）。該当箇所はステージング環境での手動確認で補います。確認項目は [docs/SETUP.md](docs/SETUP.md) にチェックリストとしてまとめてあります。

## 現在の状態

仕様は確定済み、プロジェクトの骨格ができた段階です。

- **できていること**：ドメインロジック、ルーティング、レスポンシブな外枠、多言語対応、セキュリティルールとそのテスト、エミュレータでの起動確認
- **これから**：クラウドの Firebase プロジェクト作成と接続、各画面の中身の実装、Cloud Functions の実装

画面は仕様書 14.2 で洗い出した 20 面をルーティングが通る状態で置いてあり、中身が未実装であることを画面上に明示しています。
