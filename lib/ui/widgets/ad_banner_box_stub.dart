/// バナー広告の実体（**Web 用＝何も描かない**）。
///
/// Web では広告を出さないので、ここは常に空。**それでも「空を返す実装」を
/// 置くのは、`ad_banner_box.dart` の条件つき import が Web で選ぶ先を
/// 必要とするため**（無いと Web ビルドが `google_mobile_ads` を読み込み、
/// `dart:io` が無くてコンパイルできない）。
///
/// 型と鍵は `ad_banner_box_mobile.dart` と**同じ名前**にしておく
/// （画面側はどちらが選ばれたかを知らずに書けるようにする）。
library;

import 'package:flutter/widgets.dart';

/// バナー広告の実体（Web 用）。
class AdBannerBox extends StatelessWidget {
  const AdBannerBox({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
