/// 端末に音源を保存できる場所か（docs/DOWNLOAD-DESIGN.md 6.5 / 7 節）
///
/// **Web には保存先がありません。** `writeToFile()` は `dart:io` の `File` を
/// 取るので、Web では `DownloadFileSystem` の stub が入り、何も落とせません
/// （`lib/data/downloads/download_file_system_factory.dart`）。
/// 画面はそれを**押す前に**知る必要があります——押してから
/// 「できません」と出すのは、壊れているのと見分けが付きません（6.5）。
///
/// **`kIsWeb` を画面のあちこちに散らさないこと**（7.2）。
/// 「Web かどうか」の分岐は `lib/platform/` の条件付き取り込みに揃えます。
/// 手本は `app_ready.dart` で、この 1 つが 2 つ目です。
library;

export 'downloads_supported_stub.dart'
    if (dart.library.js_interop) 'downloads_supported_web.dart';
