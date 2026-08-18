# セキュリティレビュー報告（2026-08-18）

## 対象範囲

レビュー用ブランチ `claude/security-review-3bcx8x` は `origin/main` と同一で
差分が無かったため、**前回の監査対応コミット（`bc1054c` 監査ラウンド 5 の
グループ B・C 対応）以降の 5 コミット（`bc1054c..ffe1fb3`）** を対象とした。

対象コミット:

| コミット | 内容 |
| --- | --- |
| `f2d80b9` | モバイルアプリへの AdMob バナー広告の追加（プレミアムは非表示） |
| `a8b2caa` | Android / iOS のランチャーアイコン設定 |
| `84a15d9` | Android versionCode を 2 に更新 |
| `cb390fa` | プライバシーポリシーへの AdMob 記載追加 |
| `ffe1fb3` | iOS の利用目的文言（写真・カメラ・位置情報）の追加 |

## 結論

**悪用可能性の高い脆弱性は検出されなかった（確信度 0.7 以上の指摘 0 件）。**

脆弱性の洗い出しを行ったうえで、確信度の基準（0.7 以上）を満たす指摘が
無かったため、偽陽性の絞り込み工程は実施不要だった。

## 確認した箇所と判断根拠

| 対象 | 判断 |
| --- | --- |
| `android/app/src/main/AndroidManifest.xml` | 追加は AdMob の `APPLICATION_ID` メタデータ（設計上公開の識別子）と通常保護レベルの `INTERNET` 権限のみ。`usesCleartextTraffic` の追加、`exported` なコンポーネント、新規インテントフィルタ、危険権限は無し |
| `lib/config/ads.dart`、`lib/ui/widgets/ad_banner_*.dart` | 広告ユニット ID は秘密情報ではなく公開識別子。リクエストは `AdRequest(nonPersonalizedAds: true)` 固定で PII を渡していない。クライアント側のプレミアム判定は広告の表示のみを制御し、保護データへのアクセスは制御していない。読み込み失敗時は広告を出さない側に倒れる。Web ビルドは条件付き import で SDK を除外 |
| `scripts/build-android.mjs`、`codemagic.yaml` | 静的な引数配列に固定文字列 `--dart-define=APP_ENV=prod` を追加するだけ。信頼できない入力がシェルに到達しない |
| `ios/Runner/Info.plist` | 公開識別子 `GADApplicationIdentifier` と静的な利用目的文言 3 件の追加のみ。ATS 例外、URL スキーム、バックグラウンドモードの追加は無し |
| `web/app-ads.txt`、プライバシー・法務系 HTML | 静的で公開前提の内容。スクリプト、イベントハンドラ、動的コンテンツは無く XSS の余地なし |
| `pubspec.yaml` / `pubspec.lock` | `google_mobile_ads` 9.1.0 とアイコン生成用の dev 依存のみ。全て pub.dev からハッシュつきで固定。git / path 依存や typosquat の疑いのあるパッケージは無し |
| アイコン画像、リソース、テスト、設計文書 | バイナリ・静的資産とリポジトリ内テストのみで、実行される攻撃面が無い |

## 意図的に指摘から除外したもの（判定基準による）

- ソースにコミットされた AdMob のアプリ ID・広告ユニット ID
  — 設計上公開される識別子であり秘密情報ではない
- クライアント側の `isPremiumProvider` による広告表示の制御
  — 最悪でも収益上の問題であり、認可境界ではない
- 現状のアプリが行わない挙動を記述している iOS の位置情報の利用目的文言
  — App Store 対応上の文言の問題であり、脆弱性ではない
