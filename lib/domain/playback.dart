/// 再生の状態と、ボタンを押したときの移り変わり（仕様書 8 章）
///
/// **音の出力そのものからは切り離してある。** 再生を実際に行うのは
/// `just_audio` だが、「どのボタンを出すか」「押したら何が起きるか」は
/// 端末の音を鳴らさずに確かめられる。ここに置いて回帰テストで固定する。
library;

/// いまの再生の状況。
enum PlaybackStatus {
  /// 止まっている。次に再生すると**先頭から**始まる。
  stopped,

  /// 鳴っている。
  playing,

  /// その位置で止めてある。次に再生すると**その位置から**続く（仕様 7）。
  paused,
}

/// どの曲を、どういう状況で持っているか。
class PlaybackState {
  const PlaybackState({this.itemId, this.status = PlaybackStatus.stopped});

  /// いま対象にしている項目。何も選んでいなければ null。
  final String? itemId;

  final PlaybackStatus status;

  /// その項目が、いま鳴っているか。
  bool isPlaying(String id) =>
      itemId == id && status == PlaybackStatus.playing;

  /// その項目が、一時停止で止まっているか。
  bool isPaused(String id) => itemId == id && status == PlaybackStatus.paused;

  /// その項目に対して、停止・一時停止のボタンを出すべきか。
  ///
  /// 鳴っているときと、一時停止しているときの両方で出す。
  /// 一時停止中に停止（先頭へ戻す）を選べないと、
  /// 途中で止めたものを頭に戻す手段がなくなる。
  bool isActive(String id) => itemId == id && status != PlaybackStatus.stopped;

  PlaybackState copyWith({String? itemId, PlaybackStatus? status}) =>
      PlaybackState(
        itemId: itemId ?? this.itemId,
        status: status ?? this.status,
      );
}

/// 再生ボタンを押したときに、音の側へ何を頼むか。
enum PlaybackCommand {
  /// 先頭から流し始める（別の曲に切り替えるとき、止まっているとき）。
  startFromBeginning,

  /// 止めた位置から続ける（一時停止していたとき）。
  resume,

  /// その位置で止める。
  pause,

  /// 止めて先頭へ戻す。
  stop,
}

/// ボタンを押した結果。
class PlaybackTransition {
  const PlaybackTransition({required this.state, required this.command});

  final PlaybackState state;
  final PlaybackCommand command;
}

/// 押したときの移り変わりを決める（仕様 5〜7）。
class PlaybackPolicy {
  const PlaybackPolicy._();

  /// 再生ボタンを押した。
  ///
  /// - 同じ曲を一時停止していた → **その位置から**続ける
  /// - それ以外（別の曲・止まっている・鳴っている）→ **先頭から**
  ///
  /// 別の曲の再生ボタンを押したときは、鳴っていたほうは自然に止まる。
  /// 2 曲が同時に鳴ると何を聞いているのか分からなくなるため。
  static PlaybackTransition play(PlaybackState current, String itemId) {
    final resumes = current.itemId == itemId &&
        current.status == PlaybackStatus.paused;

    return PlaybackTransition(
      state: PlaybackState(itemId: itemId, status: PlaybackStatus.playing),
      command: resumes
          ? PlaybackCommand.resume
          : PlaybackCommand.startFromBeginning,
    );
  }

  /// 一時停止を押した。その位置で止める（仕様 7）。
  static PlaybackTransition pause(PlaybackState current) =>
      PlaybackTransition(
        state: current.copyWith(status: PlaybackStatus.paused),
        command: PlaybackCommand.pause,
      );

  /// 停止を押した。先頭へ戻す（仕様 7）。
  ///
  /// **対象は残す。** 残しておかないと、停止した直後にその行から
  /// 再生ボタンが消えてしまう。
  static PlaybackTransition stop(PlaybackState current) => PlaybackTransition(
    state: current.copyWith(status: PlaybackStatus.stopped),
    command: PlaybackCommand.stop,
  );

  /// 最後まで鳴り終わった。
  ///
  /// 停止を押したときと同じ扱いにする。もう一度押せば先頭から始まる。
  static PlaybackState completed(PlaybackState current) =>
      current.copyWith(status: PlaybackStatus.stopped);
}
