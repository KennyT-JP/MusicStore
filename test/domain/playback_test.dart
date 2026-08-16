/// 再生の状態遷移（仕様書 8 章）
///
/// 停止と一時停止の違いが仕様の要。
///
/// - **停止**：先頭に巻き戻る。次に再生すると頭から
/// - **一時停止**：その位置で止まる。次に再生するとその位置から
///
/// 端末の音を鳴らさずに確かめられるよう、規則だけを切り出してある。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/playback.dart';

const _a = 'item-a';
const _b = 'item-b';

void main() {
  group('再生ボタン', () {
    test('止まっている状態から押すと、先頭から始まる', () {
      final result = PlaybackPolicy.play(const PlaybackState(), _a);

      expect(result.command, PlaybackCommand.startFromBeginning);
      expect(result.state.itemId, _a);
      expect(result.state.status, PlaybackStatus.playing);
    });

    test('一時停止していた同じ曲なら、その位置から続く（仕様 7）', () {
      const paused = PlaybackState(itemId: _a, status: PlaybackStatus.paused);

      final result = PlaybackPolicy.play(paused, _a);

      expect(result.command, PlaybackCommand.resume);
      expect(result.state.status, PlaybackStatus.playing);
    });

    test('停止していた同じ曲は、先頭から始まる（仕様 7）', () {
      const stopped = PlaybackState(itemId: _a, status: PlaybackStatus.stopped);

      final result = PlaybackPolicy.play(stopped, _a);

      expect(result.command, PlaybackCommand.startFromBeginning);
    });

    test('別の曲を押したら、その曲を先頭から', () {
      // 一時停止していたのが別の曲でも、位置は引き継がない。
      const paused = PlaybackState(itemId: _a, status: PlaybackStatus.paused);

      final result = PlaybackPolicy.play(paused, _b);

      expect(result.command, PlaybackCommand.startFromBeginning);
      expect(result.state.itemId, _b);
    });

    test('鳴っている曲をもう一度押したら、先頭に戻して鳴らし直す', () {
      const playing = PlaybackState(itemId: _a, status: PlaybackStatus.playing);

      expect(
        PlaybackPolicy.play(playing, _a).command,
        PlaybackCommand.startFromBeginning,
      );
    });
  });

  group('一時停止と停止', () {
    const playing = PlaybackState(itemId: _a, status: PlaybackStatus.playing);

    test('一時停止はその位置で止める', () {
      final result = PlaybackPolicy.pause(playing);

      expect(result.command, PlaybackCommand.pause);
      expect(result.state.status, PlaybackStatus.paused);
      expect(result.state.itemId, _a, reason: '対象は変わらない');
    });

    test('停止は先頭へ戻す', () {
      final result = PlaybackPolicy.stop(playing);

      expect(result.command, PlaybackCommand.stop);
      expect(result.state.status, PlaybackStatus.stopped);
    });

    test('停止しても対象は残す（行から再生ボタンが消えないように）', () {
      expect(PlaybackPolicy.stop(playing).state.itemId, _a);
    });

    test('一時停止中でも停止できる（頭に戻す手段を残す）', () {
      const paused = PlaybackState(itemId: _a, status: PlaybackStatus.paused);

      final result = PlaybackPolicy.stop(paused);

      expect(result.state.status, PlaybackStatus.stopped);
    });

    test('最後まで鳴り終わったら、停止と同じ状態になる', () {
      final after = PlaybackPolicy.completed(playing);

      expect(after.status, PlaybackStatus.stopped);
      // もう一度押せば先頭から始まる。
      expect(
        PlaybackPolicy.play(after, _a).command,
        PlaybackCommand.startFromBeginning,
      );
    });
  });

  group('再生ボタンを出すファイルかどうか', () {
    // ファイルの種類は登録時に制限していない（仕様 7.1）ので、
    // 画像や書類も登録できる。押しても鳴らないものにボタンを出さない。
    test('音のファイルには出す', () {
      for (final type in [
        'audio/mpeg',
        'audio/mp4',
        'audio/wav',
        'audio/flac',
        'audio/ogg',
        'audio/aac',
      ]) {
        expect(
          isPlayableAudio(contentType: type, fileName: 'take.mp3'),
          isTrue,
          reason: type,
        );
      }
    });

    test('画像や書類には出さない', () {
      expect(
        isPlayableAudio(
          contentType: 'application/octet-stream',
          fileName: '顔写真3.jpg',
        ),
        isFalse,
      );
      expect(
        isPlayableAudio(contentType: 'image/jpeg', fileName: 'a.jpg'),
        isFalse,
      );
      expect(
        isPlayableAudio(contentType: 'application/pdf', fileName: '譜面.pdf'),
        isFalse,
      );
    });

    test('動画にも出さない（音だけを鳴らす作りではない）', () {
      expect(
        isPlayableAudio(contentType: 'video/mp4', fileName: 'live.mp4'),
        isFalse,
      );
    });

    test('種類が空でも、拡張子が音なら出す（古い項目のため）', () {
      expect(isPlayableAudio(contentType: '', fileName: 'take.MP3'), isTrue);
      expect(isPlayableAudio(contentType: '', fileName: 'take.m4a'), isTrue);
      expect(isPlayableAudio(contentType: '', fileName: 'take'), isFalse);
    });
  });

  group('ボタンの出し分け', () {
    test('鳴っている曲だけが「鳴っている」', () {
      const state = PlaybackState(itemId: _a, status: PlaybackStatus.playing);

      expect(state.isPlaying(_a), isTrue);
      expect(state.isPlaying(_b), isFalse);
    });

    test('鳴っている曲と一時停止中の曲に、停止ボタンを出す', () {
      const playing = PlaybackState(itemId: _a, status: PlaybackStatus.playing);
      const paused = PlaybackState(itemId: _a, status: PlaybackStatus.paused);
      const stopped = PlaybackState(itemId: _a, status: PlaybackStatus.stopped);

      expect(playing.isActive(_a), isTrue);
      expect(paused.isActive(_a), isTrue);
      expect(stopped.isActive(_a), isFalse, reason: '止まっていれば要らない');
      expect(playing.isActive(_b), isFalse, reason: '他の行には出さない');
    });

    test('何も選んでいなければ、どの行も対象でない', () {
      const none = PlaybackState();

      expect(none.isPlaying(_a), isFalse);
      expect(none.isActive(_a), isFalse);
    });
  });

  // -----------------------------------------------------------------------
  // どこから鳴らすか（docs/DOWNLOAD-DESIGN.md 4.3 / 8.1）
  // -----------------------------------------------------------------------
  group('再生元の決定（DOWNLOAD-DESIGN 4.3）', () {
    const path = 'L1/I1/audio-1755200000000.wav';

    test('ダウンロード済みで猶予内なら、オンラインでもローカル', () {
      // **落としたのに通信するのでは、落とした意味がない。**
      expect(
        PlaybackPolicy.resolve(
          localPath: path,
          isPlayableOffline: true,
          isOnline: true,
        ),
        PlaybackSource.local,
      );
    });

    test('ダウンロード済みで猶予内、オフラインでもローカル', () {
      expect(
        PlaybackPolicy.resolve(
          localPath: path,
          isPlayableOffline: true,
          isOnline: false,
        ),
        PlaybackSource.local,
      );
    });

    test('猶予を過ぎていて、オンラインなら remote（論点 12）', () {
      // **30 日を超えたら local を返さない。** そのときオンラインなら
      // ストリーミングに落ちる——**論点 12 のとおり、ストリーミング再生は
      // これまで通りできる。** ここを blocked にすると、
      // 「オンラインなのに聴けない」という、仕様に無い止め方になる。
      expect(
        PlaybackPolicy.resolve(
          localPath: path,
          isPlayableOffline: false,
          isOnline: true,
        ),
        PlaybackSource.remote,
      );
    });

    test('猶予を過ぎていて、オフラインなら blocked', () {
      expect(
        PlaybackPolicy.resolve(
          localPath: path,
          isPlayableOffline: false,
          isOnline: false,
        ),
        PlaybackSource.blocked,
      );
    });

    test('落としていなければ、オンラインで remote', () {
      expect(
        PlaybackPolicy.resolve(
          localPath: null,
          isPlayableOffline: true,
          isOnline: true,
        ),
        PlaybackSource.remote,
      );
    });

    test('落としておらず、オフラインなら blocked', () {
      expect(
        PlaybackPolicy.resolve(
          localPath: null,
          isPlayableOffline: true,
          isOnline: false,
        ),
        PlaybackSource.blocked,
      );
    });
  });
}
