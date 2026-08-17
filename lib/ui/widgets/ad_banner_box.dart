/// バナー広告の**実体**。プラットフォームごとに実装を切り替える入口。
///
/// **Web には `google_mobile_ads` を読み込ませない。** あのパッケージの
/// Dart コードは `dart:io` を使うので、Web ビルドに含めると**コンパイルが
/// 通らない**（実行時に Web を判定して分岐しても、import した時点で駄目）。
/// そのため実装ファイルを分け、条件つき import で選ぶ。
///
/// - 既定（Web）… `ad_banner_box_stub.dart`（何も描かない）
/// - `dart:io` があるとき（Android / iOS / テストの Dart VM）…
///   `ad_banner_box_mobile.dart`
///
/// **出すか出さないかの判断はここではしない。** それは
/// `ui/widgets/ad_banner_slot.dart` と `config/ads.dart` の仕事で、この入口は
/// 「出すと決まったときに何を描くか」だけを持つ。
///
/// **切り替えの向きは `lib/platform/downloads_supported.dart` と対になっている。**
/// あちらは既定が「保存先あり（非 Web）」で Web だけ stub、こちらは既定が
/// 「広告なし（Web）」で `dart:io` があるときだけ実体。どちらも
/// **Web に `dart:io` を持ち込まない**という同じ狙い。
library;

export 'ad_banner_box_stub.dart'
    if (dart.library.io) 'ad_banner_box_mobile.dart';
