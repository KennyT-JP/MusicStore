/// 通信条件の判定（docs/DOWNLOAD-DESIGN.md 4.6 / 8.1・論点 11b）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/download_network.dart';

void main() {
  group('ダウンロードを始めてよい回線か（4.6）', () {
    test('Wi-Fi なら始められる', () {
      expect(
        DownloadNetworkPolicy.allows(isWifi: true, allowMobileData: false),
        isTrue,
      );
      expect(
        DownloadNetworkPolicy.allows(isWifi: true, allowMobileData: true),
        isTrue,
      );
    });

    test('モバイル通信を許可していれば始められる', () {
      expect(
        DownloadNetworkPolicy.allows(isWifi: false, allowMobileData: true),
        isTrue,
      );
    });

    test('Wi-Fi でなく、許可もしていなければ始めない（既定）', () {
      // **4 通りのうち、false になるのはこの 1 通りだけ**（8.1）。
      expect(
        DownloadNetworkPolicy.allows(isWifi: false, allowMobileData: false),
        isFalse,
      );
    });
  });
}
