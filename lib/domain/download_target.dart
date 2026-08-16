/// 端末に落としてよいファイルか（docs/DOWNLOAD-DESIGN.md 3.3・論点 5）
///
/// **対象は音源と画像だけ。** PDF・zip などは対象外（論点 5）。
/// 画像はアプリ内で表示するだけで、外部アプリへは渡さない。
///
/// **判定を別に作らないこと**（2.3）。音源かどうかは
/// `playback.dart` の [isPlayableAudio] を使い、拡張子の白リストも
/// [kPlayableAudioExtensions] をそのまま使う。ここに別の集合を書くと、
/// 「一覧に再生ボタンが出るのに落とせない曲」ができる。
library;

import 'playback.dart';

/// 端末に持てる画像の拡張子（3.3）。
const Set<String> kDownloadableImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'heic',
};

/// そのファイルをダウンロードの対象にしてよいか（3.3）。
enum DownloadTargetKind {
  /// 音源。`audio-<millis>.<ext>` として持つ。
  audio,

  /// 画像。`image-<millis>.<ext>` として持つ（論点 5）。
  image,

  /// **対象外。** 落として再生も表示もできないものを端末に残さない。
  unsupported,
}

/// このファイルはダウンロードの対象か（3.3・論点 5）。
///
/// **拡張子は白リストを通す。** `contentType` が `audio/` で始まっていても、
/// 拡張子が白リストに無ければ対象外にする——**拡張子は `just_audio` が
/// コンテナ形式を推測する手がかり**なので、扱えない拡張子のまま端末に
/// 置くと、落とせたのに鳴らないものができる。
DownloadTargetKind downloadTargetKind({
  required String contentType,
  required String fileName,
}) {
  final ext = fileExtension(fileName);

  if (isPlayableAudio(contentType: contentType, fileName: fileName)) {
    return kPlayableAudioExtensions.contains(ext)
        ? DownloadTargetKind.audio
        : DownloadTargetKind.unsupported;
  }

  if (contentType.toLowerCase().startsWith('image/')) {
    return kDownloadableImageExtensions.contains(ext)
        ? DownloadTargetKind.image
        : DownloadTargetKind.unsupported;
  }

  return DownloadTargetKind.unsupported;
}
