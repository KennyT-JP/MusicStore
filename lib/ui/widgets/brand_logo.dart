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
  /// 横組み（600×256）。**幅 120px 以上を確保できる場所だけ。**
  horizontal,

  /// 縦組み（520×420）。ログイン画面など、正面に大きく出す場所へ。
  vertical,
}

class BrandLogo extends StatelessWidget {
  /// 横組み。**幅 120px 以上を確保できる場所だけに使う。**
  ///
  /// 元画像は 600×256 なので、幅 120px は高さ 52px に当たる。
  /// 既定をそこに合わせてある。**上部バーには入らない大きさ**なので、
  /// そちらは [BrandLogo.mark] とアプリ名を並べること。
  ///
  /// 下限は brand/README.md の決まり。小さくするとワードマークが読めない。
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
    BrandLogoLayout.horizontal => 600 / 256,
    BrandLogoLayout.vertical => 520 / 420,
  };

  double get _width => height * _aspectRatio;

  @override
  Widget build(BuildContext context) {
    // **背景の明暗で選ぶ。** 暗い配色のときは `-dark`。
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final variant = isDark ? 'dark' : 'light';
    final name = switch (layout) {
      BrandLogoLayout.horizontal => 'logo-horizontal',
      BrandLogoLayout.vertical => 'logo-vertical',
    };

    return Image.asset(
      'assets/brand/$name-$variant.png',
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

/// アイコンだけ（ワードマーク無し）。**16px 以上**（brand/README.md）。
///
/// 上部バーのように**横組みロゴの下限（幅 120px）を確保できない場所**で使う。
/// 決まりを破って横組みを縮めるより、アイコンとアプリ名を並べるほうがよい。
///
/// 明暗で差し替えない。アイコンは角丸のタイルで、どちらの背景でも読める。
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 28});

  /// 一辺の長さ。**16 を下回らないこと。**
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      // 元画像の角丸に合わせて、小さく出しても角が立たないようにする。
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/brand/icon.png',
        height: size,
        width: size,
        fit: BoxFit.contain,
        // ここはアプリ名を隣に出すので、読み上げでは重ねて言わせない。
        excludeFromSemantics: true,
        errorBuilder: (_, _, _) => SizedBox(height: size, width: size),
      ),
    );
  }
}
