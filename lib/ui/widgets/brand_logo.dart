/// ブランドのロゴ（brand/README.md）
///
/// **明暗で差し替える。** 明るい背景には `-light`、暗い背景には `-dark`。
/// 逆に置くと文字が背景に沈む。判断は画面の明暗（`Brightness`）で行い、
/// 呼ぶ側に選ばせない。**選ばせると、いつか取り違える。**
///
/// ## 決まりごと（brand/README.md「使い方のルール」）
///
/// - **縦横比を変えない。** ここでは高さだけを受け取り、幅は元の比率で決める
/// - **横組みは幅 120px 以上。** 下回ると読めなくなるので、
///   [BrandLogo.horizontal] は高さの下限をそこから逆算してある
/// - 周囲にはアイコンの高さの 1/4 以上の余白を空ける（置く側の責任）
library;

import 'package:flutter/material.dart';

/// ロゴの組み方。
enum BrandLogoLayout {
  /// 横一列のロックアップ（362×39）。**上部バー向け。**
  ///
  /// 「アイコン → 音源創庫 → TRACK CABINET」を 1 行に並べたもの。
  /// **高さ 28px 以上**（brand/README.md）。上部バーに収まる。
  inline,

  /// 横組み 2 段（600×256）。**幅 120px 以上を確保できる場所だけ。**
  horizontal,

  /// 縦組み（520×420）。ログイン画面など、正面に大きく出す場所へ。
  vertical,
}

class BrandLogo extends StatelessWidget {
  /// 横一列のロックアップ。**上部バーはこれを使う。**
  ///
  /// 既定の 30 は、上部バー（既定 56px）に余白ごと収まり、かつ
  /// 下限の 28px を上回る大きさ。**28 を下回らないこと**——
  /// それ以下では英字が潰れる（brand/README.md）。
  const BrandLogo.inline({super.key, this.height = 30})
    : layout = BrandLogoLayout.inline;

  /// 横組み 2 段。**幅 120px 以上を確保できる場所だけに使う。**
  ///
  /// 元画像は 600×256 なので、幅 120px は高さ 52px に当たる。
  /// 既定をそこに合わせてある。**上部バーには入らない大きさ**なので、
  /// そちらは [BrandLogo.inline] を使うこと。
  const BrandLogo.horizontal({super.key, this.height = 52})
    : layout = BrandLogoLayout.horizontal;

  /// ログイン画面など、正面に大きく出す場所へ置く。
  const BrandLogo.vertical({super.key, this.height = 120})
    : layout = BrandLogoLayout.vertical;

  final BrandLogoLayout layout;

  /// 表示する高さ。幅は元の比率から決まる（縦横比は変えない）。
  final double height;

  /// 元画像の縦横比。**ここを間違えるとロゴが歪む。**
  double get _aspectRatio => switch (layout) {
    // 明暗で幅がわずかに違う（362 と 372）。**広いほうで場所を取る。**
    // 狭いほうに合わせると、切り替わったときに収まらなくなる。
    BrandLogoLayout.inline => 372 / 39,
    BrandLogoLayout.horizontal => 600 / 256,
    BrandLogoLayout.vertical => 520 / 420,
  };

  double get _width => height * _aspectRatio;

  @override
  Widget build(BuildContext context) {
    // **背景の明暗で選ぶ。** 暗い配色のときは `-dark`。
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final asset = switch (layout) {
      // 横一列だけは、暗い側に **タイルなし**（`-notile`）を使う。
      // アイコンの角丸タイルは濃紺で、暗い地色だと背景に溶けて
      // 四角い影のように見える（brand/README.md）。
      BrandLogoLayout.inline => isDark
          ? 'logo-inline-dark-notile'
          : 'logo-inline-light',
      BrandLogoLayout.horizontal => isDark
          ? 'logo-horizontal-dark'
          : 'logo-horizontal-light',
      BrandLogoLayout.vertical => isDark
          ? 'logo-vertical-dark'
          : 'logo-vertical-light',
    };

    return Image.asset(
      'assets/brand/$asset.png',
      height: height,
      width: _width,
      // 縦横比を保ったまま収める。切り取らない。
      fit: BoxFit.contain,
      // 読み上げには文字で伝える。ロゴ自体は装飾ではなくアプリ名なので、
      // 空のラベルにはしない。
      semanticLabel: '音源創庫',
      // **読み込めなくても画面を壊さない。** 画像が欠けたときは
      // 何も描かずに場所だけ空ける（アプリ名は別途どこかに出ている）。
      errorBuilder: (_, _, _) => SizedBox(height: height, width: _width),
    );
  }
}

