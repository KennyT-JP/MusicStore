// Flutter の起動スクリプト（`flutter build web` が生成する既定版の差し替え）。
//
// **差し替える理由は 1 つだけ：描画先を指定するため。**
//
// 既定では body の全面に描くので、広告枠と縦に並べられない。
// CanvasKit は画面を canvas に描くため、**広告の要素をアプリの画面の
// 中には差し込めない**。`index.html` で body を縦並びにし、
// 上に広告枠・下にアプリを置く。その「下」が `#flutter-host`。
//
// **このファイルがあると `flutter build web` は既定版を生成せず、
// これをテンプレートとして使う。** 下の 2 つの二重波かっこは、ビルド時に
// flutter.js 本体とビルド設定へ差し替えられる**必須のトークン**なので
// 消さないこと。
//
// **コメントにトークンをそのまま書かないこと。** 置換は文字列一致で
// 行われるため、説明のつもりで書いた 1 個でも中身に差し替えられる。
// （SessionConcierge では実際にそれでアプリが起動しなくなった）
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: { hostElement: document.getElementById('flutter-host') },
});
