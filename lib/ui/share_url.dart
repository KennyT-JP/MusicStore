/// 共有・招待の URL を組み立てる（仕様書 3.3 / 5.3）
///
/// **画面から独立させてある。** 以前は list_admin_screens.dart の中にあり、
/// ホーム画面から使おうとすると管理画面を読み込むことになっていた。
library;

/// アプリ内のパスから、人に渡せる URL を作る。
///
/// go_router のハッシュ方式に合わせて `#` を挟む。
/// `Uri.base` を使うので、検証環境なら検証環境の、本番なら本番の URL になる。
String buildShareUrl(String path) {
  final base = Uri.base;
  return '${base.origin}${base.path}#$path';
}
