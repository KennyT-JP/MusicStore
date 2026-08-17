/// AdMob（アプリ内広告）の設定。**広告に関する判断は全部ここに集める。**
///
/// **Web の AdSense とは別物。** Web 側（`web/index.html`・`web/help/`）の
/// 広告は AdSense で、**アプリの画面には置かない**という決定がある
/// （canvas 描画の画面には読めるテキストが無く、そこへ広告を出すのは
/// ポリシー違反。`test/domain/ads_placement_test.dart` が見張る）。
/// ここで扱うのは **Android / iOS アプリの中に出すバナー**だけ。
///
/// **なぜ1か所に集めるか。** 広告 ID・出す条件・広告要求の作り方が散ると、
/// 「片方だけ本番 ID」「片方だけパーソナライズ」のような事故が起きる。
/// 表示の判定は [shouldShowBanner]、広告要求は
/// `ui/widgets/ad_banner_box_mobile.dart` の1か所だけが作る。
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../env/app_environment.dart';

// ---------------------------------------------------------------------------
// 広告 ID
//
// **アプリ ID（`~` 区切り）と広告ユニット ID（`/` 区切り）は別物。**
// アプリ ID は AndroidManifest / Info.plist に書く（ここの値と一致していることを
// `test/domain/ad_banner_test.dart` が見張る）。広告ユニット ID は広告を
// 読み込むときに使う。
// ---------------------------------------------------------------------------

/// Android のアプリ ID（AndroidManifest の
/// `com.google.android.gms.ads.APPLICATION_ID` と同じ値であること）。
///
/// **`android/app/src/main/AndroidManifest.xml` と対。** 片方だけ直すと、
/// Android は起動時に SDK が落ちるか広告が出ない（どちらもエラーが画面に
/// 出ない）。`test/domain/ad_banner_test.dart` の「一致している」で止まる。
const kAndroidAdMobAppId = 'ca-app-pub-3984824596223175~4349292169';

/// iOS のアプリ ID（Info.plist の `GADApplicationIdentifier` と同じ値）。
///
/// **`ios/Runner/Info.plist` の `GADApplicationIdentifier` と対。**
/// この宣言が Info.plist に無い／食い違うと、**iOS は起動直後に落ちる**
/// （AdMob SDK が起動時に読みに行く）。片方だけ直す事故は
/// `test/domain/ad_banner_test.dart` の「一致している」で止まる。
const kIosAdMobAppId = 'ca-app-pub-3984824596223175~4636232623';

/// Android のバナー広告ユニット ID（本番）。
const kAndroidBannerAdUnitId = 'ca-app-pub-3984824596223175/1132101886';

/// iOS のバナー広告ユニット ID（本番）。
const kIosBannerAdUnitId = 'ca-app-pub-3984824596223175/2343598436';

/// Google 公式のテスト用バナー広告ユニット ID（Android）。
///
/// **本番以外（検証・デバッグ）は必ずこちらを使う。** 本番の広告ユニットを
/// 自分で叩くと、Google からは「無効なトラフィック」に見え、**アカウントごと
/// 止まりうる**。切り替えは [bannerAdUnitId]（本番環境のときだけ本番 ID）。
const kTestAndroidBannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

/// Google 公式のテスト用バナー広告ユニット ID（iOS）。
const kTestIosBannerAdUnitId = 'ca-app-pub-3940256099942544/2934735716';

/// Google がサンプル／テスト用に公開している ID のパブリッシャ部分。
///
/// アプリ ID も広告ユニット ID も、テスト用は全部この発行者になる。
/// **本物かどうかの判定はこの文字列で行う**（個々の ID を並べると、
/// 別のテスト ID を使ったときに見張りから漏れる）。
const kGoogleSampleAdPublisher = 'pub-3940256099942544';

/// [id] が Google のテスト用 ID か。
bool isGoogleSampleAdId(String id) => id.contains(kGoogleSampleAdPublisher);

// ---------------------------------------------------------------------------
// 表示の条件
// ---------------------------------------------------------------------------

/// 広告を出す対象のプラットフォーム。
///
/// `kIsWeb` と `defaultTargetPlatform` を1つの値に畳む。**Web の判定を
/// 忘れると、Web でも `defaultTargetPlatform` が android を返す**ので
/// （ブラウザの UA によっては）Web に広告が出てしまう。
enum AdPlatform { web, android, ios, other }

/// いま動いている環境の [AdPlatform]。
AdPlatform get currentAdPlatform {
  if (kIsWeb) return AdPlatform.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => AdPlatform.android,
    TargetPlatform.iOS => AdPlatform.ios,
    _ => AdPlatform.other,
  };
}

/// **いま広告を出してよいプラットフォームか。**
///
/// - **Android と iOS の両方**。どちらも本物のアプリ ID を入れてある。
/// - **Web は出さない。** canvas 描画のアプリ画面に広告を置くのは
///   AdSense のポリシーに反する（読めるテキストが無い）。しかも
///   `google_mobile_ads` は `dart:io` を使うので Web ではそもそも動かない。
/// - デスクトップ等は AdMob 自体が対応していない。
bool adsSupportedOn(AdPlatform platform) =>
    platform == AdPlatform.android || platform == AdPlatform.ios;

/// **バナーを出すか。** 画面側（[AdBannerSlot]）はこの1本だけを見る。
///
/// [isPremium] は既存の `isPremiumProvider` の確定値（`AsyncValue<bool>` を
/// 解決したもの）を渡す。**新しいプレミアム判定を作らない**——判定が2つあると、
/// 片方だけ直したときに「課金したのに広告が消えない」が起きる。
///
/// **「まだ分からない（読み込み中）」を渡してはいけない。** その扱いは
/// 画面側の責任（`.when` で読み込み中・失敗は「出さない」に倒す）。ここへは
/// 「プレミアムである／でない」の確定値だけが来る。
bool shouldShowBanner({required AdPlatform platform, required bool isPremium}) {
  if (isPremium) return false; // プレミアムの特典「広告の非表示」
  return adsSupportedOn(platform);
}

// ---------------------------------------------------------------------------
// 広告ユニット ID の切り替え
// ---------------------------------------------------------------------------

/// 実際に読み込むバナー広告ユニット ID。
///
/// **本番環境のときだけ本番の広告ユニット。** 検証（staging）・デバッグでは
/// 必ず Google のテスト用 ID を使う。開発中に本番の広告ユニットを表示・
/// タップすると無効なトラフィックとして扱われる（Google のポリシー。
/// アカウント停止まである）。
///
/// **アプリ ID（マニフェスト／plist）はこの切り替えの対象ではない。**
/// あちらは常に本番の実値を書く（テスト用 ID にすると本番の広告が出ない）。
///
/// [production] を省略すると `AppEnvironment.current.isProduction` を見る。
/// 引数で受けるのは、テストから両方の分岐を確かめられるようにするため。
String bannerAdUnitId({required AdPlatform platform, bool? production}) {
  final isProd = production ?? AppEnvironment.current.isProduction;
  return switch (platform) {
    AdPlatform.android =>
      isProd ? kAndroidBannerAdUnitId : kTestAndroidBannerAdUnitId,
    AdPlatform.ios => isProd ? kIosBannerAdUnitId : kTestIosBannerAdUnitId,
    // Web・非対応プラットフォームでは広告を読み込まない（[adsSupportedOn]）。
    // ここに来るのは呼び出し側の間違い。
    AdPlatform.web || AdPlatform.other => throw StateError(
      '広告非対応のプラットフォーム（$platform）でバナーの ID を求めた',
    ),
  };
}
