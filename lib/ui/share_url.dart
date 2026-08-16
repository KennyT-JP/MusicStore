/// 共有・招待の URL を組み立てる（仕様書 3.3 / 5.3 / 5-8-1）
///
/// **画面から独立させてある。** 以前は list_admin_screens.dart の中にあり、
/// ホーム画面から使おうとすると管理画面を読み込むことになっていた。
library;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../env/app_environment.dart';

/// [buildShareUrl] が既定で使う土台の URL。
///
/// | プラットフォーム | 使う値 |
/// | --- | --- |
/// | Web | `Uri.base`（表示中のドメインに追従する） |
/// | ネイティブ（iOS / Android） | 環境ごとの固定ドメイン |
///
/// **Web で `Uri.base` を見るのは、検証環境で検証環境の URL が出るため。**
/// サブディレクトリ配信でも path が残るので、そのまま使う。
///
/// **ネイティブでは `Uri.base` を見てはいけない。** 実行時のカレント
/// ディレクトリを指す `file:` 形式になり、`origin` を読むと **`StateError`
/// を投げる**（テストで `file:` 形式になるのと同じ理由。**テストで起きる
/// ことは、本番のモバイルでも起きる**）。素通しにすると、モバイルでは
/// **招待リンクを 1 本も作れない。**
///
/// 末尾に `/` を足すのは、`https://<host>/#/invite/abc` の形にそろえるため
/// （`Uri.parse('https://example.test')` の path は空文字になる）。
Uri get defaultShareBase =>
    kIsWeb ? Uri.base : Uri.parse('${AppEnvironment.current.shareOrigin}/');

/// アプリ内のパスから、人に渡せる URL を作る。
///
/// go_router のハッシュ方式に合わせて `#` を挟む
/// （`https://<host>/#/invite/abc123`）。
///
/// **[base] を差し替えられるようにしてある。** 渡せないと**招待 URL の
/// 組み立てを一度も確かめられない。** ここが壊れると誰もリストに参加
/// できなくなるので、確かめられる形にしておく。
String buildShareUrl(String path, {Uri? base}) {
  final origin = base ?? defaultShareBase;
  return '${origin.origin}${origin.path}#$path';
}
