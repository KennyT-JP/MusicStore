/// Web での [notifyAppReady]
///
/// `web/index.html` が用意している `window.appReady()` を呼び、
/// ロゴ入りの読み込み画面を消してもらいます。
///
/// **呼べなくても落とさない。** 合図の相手が居ないのは
/// 「読み込み画面がもう消えている」か「古い index.html が配信されている」
/// だけで、アプリ自体は動き続けられます。
/// ここで例外を投げると、**画面が出ない**という重い壊れ方になります。
library;

import 'dart:js_interop';

@JS('appReady')
external JSFunction? get _appReady;

/// HTML 側の読み込み画面を消してもらう。
void notifyAppReady() {
  final ready = _appReady;
  if (ready == null) return;
  ready.callAsFunction();
}
