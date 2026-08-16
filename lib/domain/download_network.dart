/// ダウンロードを始めてよい回線か（docs/DOWNLOAD-DESIGN.md 4.6・論点 11b）
///
/// **既定は Wi-Fi のときだけ。設定でモバイル通信も許可できる。**
///
/// ## これは「従量課金を避けられる保証」ではない
///
/// 回線の種別を返す仕組み（`connectivity_plus`）が答えるのは
/// **どの種類の回線に繋がっているか**であって、その回線が従量制かどうかでは
/// ない。ほかの端末のテザリングは **Wi-Fi に見える**し、VPN 経由では
/// 実装によって判定が変わる。
///
/// **画面には「Wi-Fi のときだけダウンロードする」と書き、
/// 「モバイルデータを使いません」とは書かないこと。**
/// 確かめられないことを保証と書かない。
library;

/// 通信条件の判定（4.6）。
class DownloadNetworkPolicy {
  const DownloadNetworkPolicy._();

  /// いまダウンロードを始めてよいか。
  ///
  /// 設定（[allowMobileData]）が入っていれば回線の種別を問わない。
  static bool allows({required bool isWifi, required bool allowMobileData}) =>
      isWifi || allowMobileData;
}
