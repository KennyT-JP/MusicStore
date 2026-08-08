/// 日本語フォントを、最初の描画のあとに読み込む
///
/// **なぜ起動時に読まないのか（2026-08-08）。**
///
/// Flutter Web（CanvasKit）は、`pubspec.yaml` の `fonts:` に書いた
/// フォントを**エンジンの起動中に読み終えるまで、最初の描画を始めない**。
/// このアプリが同梱していた日本語フォントは圧縮後で約 2.5MB あり、
/// 初回に取りに行く量の半分近くを占めていた。
/// 「URL を開いてからログイン画面が出るまで 5 秒ほどかかる」という
/// 指摘の主因がこれだった。
///
/// そこで `assets:` として積み、**画面が出たあとに読み込む**。
///
/// | | 前 | いま |
/// | --- | --- | --- |
/// | 最初の描画までに要るもの | アプリ本体・CanvasKit・日本語フォント | アプリ本体・CanvasKit |
/// | 日本語の見え方 | 最初から Noto Sans JP | 端末のフォント → 読み終えたら Noto Sans JP |
///
/// **文字が出なくなることはない。** 字を絞る手（サブセット化）と違い、
/// グリフは全部持っている。読み込みが終わるまでのあいだ、端末が持って
/// いる日本語フォントで描かれるだけである。読み終えると差し替わる。
///
/// 同梱している理由自体は変えていない。既定のままだと日本語のグリフを
/// 実行時に Google Fonts から取りに行き、それが遮断された環境で
/// 文字が出なくなる（pubspec.yaml 参照）。
library;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// アプリ全体で使う日本語フォントの名前。
///
/// `pubspec.yaml` の `fonts:` には書かない。[japaneseFontProvider] が
/// 実行時に、この名前で登録する。
const String kAppFontFamily = 'NotoSansJP';

/// 同梱している日本語フォント。**太字は持たない**（pubspec.yaml 参照）。
const String _fontAsset = 'assets/fonts/NotoSansJP-400.ttf';

/// 日本語フォントを読み込む。
///
/// 最初に読まれた時点で走り出す。**待つ側は画面を止めない**：
/// 読み終わるまでは端末のフォントで描き、終わったら差し替える
/// （lib/app.dart）。
///
/// 読み込みに失敗しても、例外にせず「未完了」のままにする。
/// フォントが載らないだけで、アプリは端末のフォントで動き続けられる。
/// **ここで落とすと、字が違うというだけで画面が出なくなる。**
final japaneseFontProvider = FutureProvider<bool>((ref) async {
  try {
    final loader = FontLoader(kAppFontFamily)
      ..addFont(rootBundle.load(_fontAsset));
    await loader.load();
    return true;
  } catch (_) {
    return false;
  }
});
