/// 再生の状態と、ボタンを押したときの移り変わり（仕様書 8 章）
///
/// **音の出力そのものからは切り離してある。** 再生を実際に行うのは
/// `just_audio` だが、「どのボタンを出すか」「押したら何が起きるか」は
/// 端末の音を鳴らさずに確かめられる。ここに置いて回帰テストで固定する。
library;

/// 鳴らせる音源の拡張子。
///
/// **白リストは 1 か所に置く。** ダウンロード機能の対象判定
/// （`download_target.dart` / docs/DOWNLOAD-DESIGN.md 3.3）もここを参照する。
/// 別の集合を書くと、「一覧に再生ボタンが出るのに落とせない曲」ができる。
const Set<String> kPlayableAudioExtensions = {
  'mp3',
  'm4a',
  'wav',
  'flac',
  'ogg',
  'aac',
};

/// ファイル名の拡張子（小文字・ドットなし）。拡張子が無ければ空文字。
String fileExtension(String fileName) =>
    fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';

/// そのファイルを、この画面で鳴らせるか。
///
/// **ファイルの種類は登録時に制限していない（仕様書 7.1）。** 画像や書類も
/// 登録できるため、「ファイルとして登録されたもの」すべてに再生ボタンを
/// 出すと、押しても鳴らないものにボタンが出てしまう。
///
/// 判断はまず `contentType` を見る。登録時に拡張子から決めているが、
/// 分からないものは `application/octet-stream` になる。古い項目で
/// 空になっている場合に備えて、拡張子も見ておく。
bool isPlayableAudio({required String contentType, required String fileName}) {
  if (contentType.toLowerCase().startsWith('audio/')) return true;

  return kPlayableAudioExtensions.contains(fileExtension(fileName));
}

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
  const PlaybackState({
    this.itemId,
    this.status = PlaybackStatus.stopped,
    this.position,
    this.duration,
  });

  /// いま対象にしている項目。何も選んでいなければ null。
  final String? itemId;

  final PlaybackStatus status;

  /// いま鳴っている位置（プログレスバー表示用）。分かるまでは null。
  final Duration? position;

  /// いま鳴らしている曲の長さ。読み込むまでは null。
  final Duration? duration;

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

  PlaybackState copyWith({
    String? itemId,
    PlaybackStatus? status,
    Duration? position,
    Duration? duration,
  }) => PlaybackState(
    itemId: itemId ?? this.itemId,
    status: status ?? this.status,
    position: position ?? this.position,
    duration: duration ?? this.duration,
  );
}

/// 秒数を `分:秒`（例 `1:38`）に整える。プログレスバーの時刻表示用。
///
/// 負値・null は呼び出し側の責務外——`Duration.zero` を渡すこと。
String formatPlaybackDuration(Duration d) {
  final totalSeconds = d.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
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

/// どこから鳴らすか（docs/DOWNLOAD-DESIGN.md 4.3）。
enum PlaybackSource {
  /// 端末に落としてあるファイルから。
  local,

  /// サーバーからのストリーミング。
  remote,

  /// 鳴らせない。オフラインで、猶予も過ぎている。
  blocked,
}

/// 押したときの移り変わりを決める（仕様 5〜7）。
class PlaybackPolicy {
  const PlaybackPolicy._();

  /// どこから鳴らすか（docs/DOWNLOAD-DESIGN.md 4.3）。
  ///
  /// **オフラインの上限（論点 13b）はここで効かせる。** 再生の入口が
  /// 1 か所（`PlaybackController.play`）なので、ここを通せば漏れない。
  ///
  /// - **ダウンロード済みなら、オンラインでもローカルを使う。**
  ///   落としたのに通信するのでは、落とした意味がない。
  /// - **猶予を過ぎたら [local] を返さない。** そのときオンラインなら
  ///   [remote] に落ちる——論点 12 のとおり、**ストリーミング再生は
  ///   これまで通りできる。**
  ///
  /// [localPath] は `index.json` にあり、**実体もある**ときだけ渡すこと。
  /// [isPlayableOffline] は `OfflineAccessPolicy.isPlayableOffline` の結果。
  static PlaybackSource resolve({
    required String? localPath,
    required bool isPlayableOffline,
    required bool isOnline,
  }) {
    if (localPath != null && isPlayableOffline) return PlaybackSource.local;
    if (isOnline) return PlaybackSource.remote;
    return PlaybackSource.blocked;
  }

  /// 再生ボタンを押した。
  ///
  /// - 同じ曲を一時停止していた → **その位置から**続ける
  /// - それ以外（別の曲・止まっている・鳴っている）→ **先頭から**
  ///
  /// 別の曲の再生ボタンを押したときは、鳴っていたほうは自然に止まる。
  /// 2 曲が同時に鳴ると何を聞いているのか分からなくなるため。
  static PlaybackTransition play(PlaybackState current, String itemId) {
    final sameItem = current.itemId == itemId;
    final resumes = sameItem && current.status == PlaybackStatus.paused;

    return PlaybackTransition(
      // **resume は位置・長さをそのまま引き継ぐ。** 止めた位置から
      // 続けるので、プログレスバーもそこから動き出してよい。
      //
      // **先頭から始めるときも、同じ曲なら長さは引き継ぐ**（2026-08-25）。
      // `JustAudioHandle` は同じ URL を読み直さない（`_loaded == url`）ため、
      // `durationStream` が再び流れてくる保証がない。長さをここで null に
      // 戻すと、2 回目以降の再生でバーが二度と出なくなる（依頼者の報告）。
      // 位置だけは 0 に戻す（先頭からのため。null のままだと最初の
      // ティックが届くまでバーの土台自体が出ない＝表示までの遅れになる）。
      //
      // 別の曲に切り替えるときは、どちらも新しい音源のものに
      // 置き換わるまで持ち越さない。
      state: resumes
          ? current.copyWith(status: PlaybackStatus.playing)
          : PlaybackState(
              itemId: itemId,
              status: PlaybackStatus.playing,
              position: Duration.zero,
              duration: sameItem ? current.duration : null,
            ),
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
    // 先頭へ戻すので、プログレスバーの位置も 0 に戻す。
    state: current.copyWith(
      status: PlaybackStatus.stopped,
      position: Duration.zero,
    ),
    command: PlaybackCommand.stop,
  );

  /// 最後まで鳴り終わった。
  ///
  /// 停止を押したときと同じ扱いにする。もう一度押せば先頭から始まる。
  static PlaybackState completed(PlaybackState current) => current.copyWith(
    status: PlaybackStatus.stopped,
    position: Duration.zero,
  );
}
