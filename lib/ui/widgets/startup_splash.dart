/// 起動直後（ログイン状態の復元中）に出す画面
///
/// **ここは HTML の読み込み画面と地続きに見せる。**
/// `web/index.html` はロゴ＋回転表示を出しており、アプリが引き継いだ
/// 瞬間にロゴが消えると、**利用者には「白くなった」と見えます**
/// （2026-08-14 の依頼者の報告「白い画面のまま数秒」）。
///
/// 以前はここが `Center(child: CircularProgressIndicator())` だけで、
/// ロゴがありませんでした。
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'brand_logo.dart';

class StartupSplash extends StatelessWidget {
  const StartupSplash({super.key});

  @override
  Widget build(BuildContext context) {
    // **ロゴは正面に大きく出す組み方**（縦組み）。
    // HTML 側も横組み 2 段を大きく出しているので、印象を揃える。
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandLogo.vertical(
              height: 120,
              semanticLabel: AppL10n.of(context).appTitle,
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
