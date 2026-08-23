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
  JustAudioHandle() {
    _wireCompletion();
  }

  /// いま使っている再生器。**曲を切り替えるたびに作り直す**（下の注記）。
  AudioPlayer _player = AudioPlayer();

  final _errors = StreamController<Object>.broadcast();

  /// [onCompleted] は呼び出し側が 1 度だけ購読する（`PlaybackController.build`）。
  /// **`_player` を作り直しても購読先が変わらないよう**、自前の
  /// コントローラーを間に挟み、いまの `_player` からの「鳴り終わった」を
  /// こちらへ中継する（[_wireCompletion]）。
  final _completed = StreamController<void>.broadcast();
  StreamSubscription<ProcessingState>? _completionSub;

  /// いま読み込んである URL。同じ曲を繰り返すときに読み直さない。
  String? _loaded;

  /// 操作の世代。**呼ぶたびに増やす。**
  ///
  /// [playFrom] は `setUrl` の完了を**待ってから** `_start()` を呼ぶため、
  /// その待っているあいだに別の操作（停止・別の曲の再生）が割り込むことが
  /// ある。**`await` のあとで世代を確かめてから鳴らす。** 古い世代なら、
  /// `_start()` を呼ばずに終わる。
  int _generation = 0;

  void _wireCompletion() {
    _completionSub?.cancel();
    _completionSub = _player.processingStateStream
        .where((state) => state == ProcessingState.completed)
        .listen((_) {
          if (!_completed.isClosed) _completed.add(null);
        });
  }

  @override
  Future<void> playFrom(String url) async {
    final generation = ++_generation;
    if (_loaded != url) {
      // **別の曲へ切り替えるときは、`AudioPlayer` を作り直す。**
      //
      // just_audio_web（0.4.16）は 1 つの `<audio>` 要素を使い回し、
      // 曲ごとの「直前の再生位置」を内部で覚えておいて `play()` のたびに
      // その位置へ seek し直す作りになっている
      // （`UriAudioSourcePlayer._resumePos`）。この内部状態は
      // `AudioPlayerHandle` からは触れず、`pause`/`seek` の呼び出し順や
      // タイミングによっては、**止めたはずの前の曲の位置や再生要求が、
      // 新しい曲の読み込みに混ざる**（パッケージ内部の作りに起因。
      // 依頼者の報告「1 曲目を再生→停止→別の曲を再生すると 1 曲目の
      // 途中から再生される」で判明。世代カウンタだけでは塞げなかった）。
      //
      // **作り直せば、この内部状態を一切引き継がない。** 前の再生器は
      // 使い終わったら破棄する（`<audio>` 要素ごと消える）。
      final old = _player;
      _player = AudioPlayer();
      _wireCompletion();
      unawaited(old.dispose());

      await _player.setUrl(url);
      _loaded = url;
    } else {
      // 同じ曲を先頭から。読み直さずに位置だけ戻す。
      await _player.seek(Duration.zero);
    }
    // 待っているあいだに、あとから来た操作に割り込まれていないか。
    if (generation != _generation) return;
    _start();
  }

  @override
  Future<void> resume() async {
    // 待っているあいだに割り込まれる経路はここには無いが、進行中の
    // playFrom（読み込み待ち）をこの操作で上書きしたことにする。
    _generation++;
    _start();
  }

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
  Future<void> pause() {
    // 進行中の playFrom（読み込み待ち）があれば、この操作で上書きする。
    _generation++;
    return _player.pause();
  }

  @override
  Future<void> stop() async {
    // 同上。**ここを増やさないと、読み込み中に押した停止が無効になる**
    // （このクラスの `_generation` のコメント参照）。
    _generation++;
    await _player.pause();
    // **止めるだけでなく先頭へ戻す（仕様 7）。**
    // just_audio の stop() は読み込みごと解放してしまい、次の再生で
    // 読み直しが要る。位置を戻すだけにして、すぐ鳴らせる状態を保つ。
    await _player.seek(Duration.zero);
  }

  @override
  Stream<void> get onCompleted => _completed.stream;

  @override
  Stream<Object> get onError => _errors.stream;

  @override
  Future<void> dispose() async {
    await _completionSub?.cancel();
    await _errors.close();
    await _completed.close();
    await _player.dispose();
  }
}
