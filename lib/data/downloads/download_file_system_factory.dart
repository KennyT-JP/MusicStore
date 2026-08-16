/// 端末に合わせて [DownloadFileSystem] を選ぶ
///
/// **`lib/platform/app_ready.dart` と同じ形の条件付き取り込み。**
/// `dart:io` を共通コードに書くと `flutter build web` が落ち、
/// `scripts/deploy.mjs` の配信が止まる（docs/DOWNLOAD-DESIGN.md 10 節の 5）。
///
/// 既定（Web）は何もできない実装で、`dart:io` がある環境
/// （iOS / Android、テストの Dart VM）だけが本物になる。
library;

export 'download_file_system_stub.dart'
    if (dart.library.io) 'download_file_system_io.dart';
