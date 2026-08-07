/// 音を鳴らす部分（仕様書 8 章）
///
/// **差し替えられる形にしてある。** テストで端末の音を鳴らすわけには
/// いかないため、「どう鳴らすか」をここに閉じ込め、画面と状態の移り変わりは
/// これを介して確かめられるようにする。
library;

import 'dart:async';

import 'package:just_audio/just_audio.dart';

/// 再生を頼む先。
abstract class AudioPlayerHandle {
  /// この URL を先頭から鳴らす。
  Future<void> playFrom(String url);

  /// 止めた位置から続ける。
  Future<void> resume();

  /// その位置で止める。
  Future<void> pause();

  /// 止めて先頭へ戻す。
  Future<void> stop();

  /// 最後まで鳴り終わったことを知らせる。
  Stream<void> get onCompleted;

  /// 鳴らし始められなかったことを知らせる。
  ///
  /// **再生の開始は待てない**（`JustAudioHandle._start` 参照）ので、
  /// 失敗はこちらへ流す。
  Stream<Object> get onError;

  Future<void> dispose();
}

/// just_audio を使う実装。
class JustAudioHandle implements AudioPlayerHandle {
  JustAudioHandle([AudioPlayer? player]) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  final _errors = StreamController<Object>.broadcast();

  /// いま読み込んである URL。同じ曲を繰り返すときに読み直さない。
  String? _loaded;

  @override
  Future<void> playFrom(String url) async {
    if (_loaded != url) {
      await _player.setUrl(url);
      _loaded = url;
    } else {
      // 同じ曲を先頭から。読み直さずに位置だけ戻す。
      await _player.seek(Duration.zero);
    }
    _start();
  }

  @override
  Future<void> resume() async => _start();

  /// 鳴らし始める。
  ///
  /// **`play()` を待ってはいけない。** just_audio の `play()` が返す Future は
  /// 「再生を始めた」ではなく「**再生が終わった／止まった**」ときに完了する。
  /// 待つと、曲の長さのあいだ呼び出し側が止まったままになる。
  ///
  /// 待たない代わりに、鳴らし始められなかったときだけ `onError` へ流す。
  /// ブラウザが自動再生を拒む（NotAllowedError）のがここに出る。
  void _start() {
    unawaited(
      _player.play().catchError((Object error) {
        if (!_errors.isClosed) _errors.add(error);
      }),
    );
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.pause();
    // **止めるだけでなく先頭へ戻す（仕様 7）。**
    // just_audio の stop() は読み込みごと解放してしまい、次の再生で
    // 読み直しが要る。位置を戻すだけにして、すぐ鳴らせる状態を保つ。
    await _player.seek(Duration.zero);
  }

  @override
  Stream<void> get onCompleted => _player.processingStateStream
      .where((state) => state == ProcessingState.completed);

  @override
  Stream<Object> get onError => _errors.stream;

  @override
  Future<void> dispose() async {
    await _errors.close();
    await _player.dispose();
  }
}
