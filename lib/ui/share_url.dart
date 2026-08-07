/// 共有・招待の URL を組み立てる（仕様書 3.3 / 5.3）
///
/// **画面から独立させてある。** 以前は list_admin_screens.dart の中にあり、
/// ホーム画面から使おうとすると管理画面を読み込むことになっていた。
library;

/// アプリ内のパスから、人に渡せる URL を作る。
///
/// go_router のハッシュ方式に合わせて `#` を挟む。
/// 既定では `Uri.base` を見るので、検証環境なら検証環境の、
/// 本番なら本番の URL になる。
///
/// **[base] を差し替えられるようにしてある。** `Uri.base` はテストでは
/// `file:` 形式になり、`origin` を読むと例外になる。渡せないと
/// **招待 URL の組み立てを一度も確かめられない。** ここが壊れると
/// 誰もリストに参加できなくなるので、確かめられる形にしておく。
String buildShareUrl(String path, {Uri? base}) {
  final origin = base ?? Uri.base;
  return '${origin.origin}${origin.path}#$path';
}
