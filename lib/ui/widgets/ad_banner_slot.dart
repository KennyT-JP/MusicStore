/// バナー広告の**置き場所**。画面はこれを1行置くだけでよい。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/ads.dart';
import '../../providers/app_providers.dart' show isPremiumProvider;
import 'ad_banner_box.dart';

/// バナー広告の置き場所。**出す条件はここ1か所**（`config/ads.dart` の
/// [shouldShowBanner]）: Android / iOS かつ 非プレミアム のときだけ。
/// Web・プレミアム・非対応プラットフォームでは**何も描かない**
/// （`SizedBox.shrink()`）。
///
/// プレミアムの判定は**既存の [isPremiumProvider] に相乗りする**。広告用に別の
/// 判定を作ると、片方だけ直したときに「課金したのに広告が消えない」が起きる。
///
/// **[isPremiumProvider] は `AsyncValue<bool>`。** 「プレミアムでない」と
/// 「まだ分からない」を混ぜないため、`.when` で受ける（`providers/
/// app_providers.dart` の注意書き）。
///
/// - 読み込み中 …… **出さない。** 届く前に広告を出すと、直後にプレミアムだと
///   分かって消える（ちらつき）。
/// - 失敗 …… **出さない（安全側）。** 読めなかった相手を「プレミアムでない」と
///   断定して広告を出すのは、課金済みの人に広告を見せうる。
class AdBannerSlot extends ConsumerWidget {
  const AdBannerSlot({super.key, this.platform});

  /// 判定に使うプラットフォーム。**省略時は実行環境から決める。**
  /// テストが Web / iOS / Android を切り替えて確かめるために開けてある。
  final AdPlatform? platform;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = this.platform ?? currentAdPlatform;
    final show = ref
        .watch(isPremiumProvider)
        .when(
          loading: () => false,
          error: (_, _) => false,
          data: (isPremium) =>
              shouldShowBanner(platform: platform, isPremium: isPremium),
        );
    if (!show) return const SizedBox.shrink();
    return const AdBannerBox();
  }
}
