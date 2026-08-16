/// いまどの回線に繋がっているか（docs/DOWNLOAD-DESIGN.md 4.6・論点 11b）
///
/// **判定そのものは `lib/domain/download_network.dart` にある。**
/// ここは「Wi-Fi か」「そもそも繋がっているか」を答えるだけにする。
///
/// ## これは「従量課金を避けられる保証」ではない（4.6）
///
/// `connectivity_plus` が返すのは**どの種類の回線に繋がっているか**であって、
/// その回線が従量制かどうかではない。
///
/// - ほかの端末のテザリング（Wi-Fi 経由）は **Wi-Fi に見える**
/// - VPN 経由のときは、実装によって判定が変わる
/// - Wi-Fi に繋がっていても、インターネットに出られるとは限らない
///
/// **画面には「Wi-Fi のときだけダウンロードする」と書き、
/// 「モバイルデータを使いません」とは書かないこと。**
/// 確かめられないことを保証と書かない。
library;

import 'package:connectivity_plus/connectivity_plus.dart';

/// 回線の様子を答える口。**テストでは差し替える。**
abstract class NetworkStatus {
  /// Wi-Fi（または有線）に繋がっているか。
  Future<bool> isWifi();

  /// 何かしらの回線に繋がっているか。
  ///
  /// **「オンラインである」の保証ではない**（4.6）。
  /// 4.3 の `PlaybackPolicy.resolve` に渡す `isOnline` はこの値で、
  /// 実際に届かなければ再生の失敗として `onError` に出る。
  Future<bool> isOnline();
}

/// `connectivity_plus` を使う実装。
class ConnectivityNetworkStatus implements NetworkStatus {
  ConnectivityNetworkStatus([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> isWifi() async {
    final results = await _read();
    // **有線（ethernet）も Wi-Fi 扱いにする。** 論点 11b が避けたいのは
    // モバイル回線の従量課金で、有線はそこに当たらない。
    return results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet);
  }

  @override
  Future<bool> isOnline() async {
    final results = await _read();
    return results.any((r) => r != ConnectivityResult.none);
  }

  /// **読めなければ「何も繋がっていない」に倒す。**
  ///
  /// ダウンロードの側は、そのぶん始まらないだけ（利用者は Wi-Fi に
  /// 繋いで押し直せる）。再生の側は `remote` ではなく `blocked` になるが、
  /// **落としてあるものは `local` で鳴る**ので、聴けなくなるのは
  /// もともと通信が要る曲だけ。
  Future<List<ConnectivityResult>> _read() async {
    try {
      return await _connectivity.checkConnectivity();
    } on Exception {
      return const [ConnectivityResult.none];
    }
  }
}
