/// ダウンロードの対象になるファイルか（docs/DOWNLOAD-DESIGN.md 3.3・論点 5）
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/download_target.dart';
import 'package:music_list_app/domain/playback.dart';

DownloadTargetKind _kind(String contentType, String fileName) =>
    downloadTargetKind(contentType: contentType, fileName: fileName);

void main() {
  test('音源の白リストは playback.dart の 1 か所（3.3・8.4）', () {
    // **ここに別の集合を書かないこと。** 書くと「一覧に再生ボタンが
    // 出るのに落とせない曲」ができる。
    expect(kPlayableAudioExtensions, {
      'mp3',
      'm4a',
      'wav',
      'flac',
      'ogg',
      'aac',
    });
  });

  group('音源（3.3）', () {
    test('白リストの拡張子は対象', () {
      for (final ext in kPlayableAudioExtensions) {
        expect(
          _kind('audio/mpeg', 'take.$ext'),
          DownloadTargetKind.audio,
          reason: '$ext が落とせない',
        );
      }
    });

    test('大文字の拡張子も対象', () {
      expect(_kind('', 'take.WAV'), DownloadTargetKind.audio);
    });

    test('種類が空でも、拡張子が白リストなら対象（古い項目のため）', () {
      expect(_kind('', 'take.m4a'), DownloadTargetKind.audio);
    });

    test('audio/ でも白リストに無い拡張子は対象外', () {
      // 拡張子は just_audio がコンテナ形式を推測する手がかり。
      // **落として鳴らないものを端末に残さない。**
      expect(
        _kind('audio/x-aiff', 'take.aiff'),
        DownloadTargetKind.unsupported,
      );
    });

    test('拡張子が無いものは対象外', () {
      expect(_kind('audio/mpeg', 'take'), DownloadTargetKind.unsupported);
    });
  });

  group('画像（論点 5）', () {
    test('白リストの拡張子は対象', () {
      for (final ext in kDownloadableImageExtensions) {
        expect(
          _kind('image/jpeg', 'cover.$ext'),
          DownloadTargetKind.image,
          reason: '$ext が落とせない',
        );
      }
    });

    test('image/ でも白リストに無い拡張子は対象外', () {
      expect(_kind('image/tiff', 'cover.tiff'), DownloadTargetKind.unsupported);
    });

    test('拡張子だけが画像で、種類が空なら対象外', () {
      // 画像は contentType の image/ 前方一致で判定する（2.3）。
      // 音源と違い、拡張子だけを頼りにしない。
      expect(_kind('', 'cover.png'), DownloadTargetKind.unsupported);
    });
  });

  group('対象外（論点 5）', () {
    test('PDF は対象外', () {
      // **端末に置くと外部アプリで開きたくなり、それはサンドボックスから
      // 出すことになる**（9 節）。
      expect(
        _kind('application/pdf', 'score.pdf'),
        DownloadTargetKind.unsupported,
      );
    });

    test('zip は対象外', () {
      expect(
        _kind('application/zip', 'set.zip'),
        DownloadTargetKind.unsupported,
      );
    });

    test('動画は対象外', () {
      expect(_kind('video/mp4', 'live.mp4'), DownloadTargetKind.unsupported);
    });
  });
}
