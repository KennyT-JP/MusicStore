/// 再生の操作（仕様書 8 章）
///
/// 画面はここを見てボタンを出し分け、ここへ操作を頼む。
/// 状態の移り変わりの規則は `lib/domain/playback.dart` にある。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/audio_player_handle.dart';
import '../data/models/list_item.dart';
import '../domain/playback.dart';
import 'app_providers.dart';

/// 音を鳴らす先。テストでは差し替える。
final audioPlayerHandleProvider = Provider<AudioPlayerHandle>((ref) {
  final handle = JustAudioHandle();
  ref.onDispose(handle.dispose);
  return handle;
});

/// Storage のパスから、再生できる URL を取り出す。
///
/// **差し替えられるようにしてある。** ここを直に呼ぶと、
/// 再生の操作を確かめるだけのテストでも Firestore と Storage が要る。
typedef DownloadUrlResolver = Future<String> Function(String storagePath);

final downloadUrlResolverProvider = Provider<DownloadUrlResolver>(
  (ref) => ref.watch(itemRepositoryProvider).downloadUrl,
);

/// いま何を、どういう状況で鳴らしているか。
///
/// **アプリ全体で 1 つ。** リストを移動しても鳴り続けてよいし、
/// 2 曲が同時に鳴ることはない。
final playbackProvider = NotifierProvider<PlaybackController, PlaybackState>(
  PlaybackController.new,
);

class PlaybackController extends Notifier<PlaybackState> {
  StreamSubscription<void>? _completion;

  @override
  PlaybackState build() {
    final handle = ref.watch(audioPlayerHandleProvider);

    // 最後まで鳴り終わったら、停止と同じ状態に戻す。
    // そのままにすると、鳴っていないのに一時停止のボタンが出続ける。
    _completion = handle.onCompleted.listen((_) {
      state = PlaybackPolicy.completed(state);
    });
    ref.onDispose(() => _completion?.cancel());

    return const PlaybackState();
  }

  /// 再生ボタンを押した。
  ///
  /// 同じ曲を一時停止していたならその位置から、それ以外は先頭から。
  Future<void> play(ListItem item) async {
    final file = item.file;
    // ファイルを持たない項目（URL の項目）はここでは扱わない。
    // 外部のページを音として鳴らすことはできないため（8 章）。
    if (file == null) return;

    final transition = PlaybackPolicy.play(state, item.id);
    state = transition.state;

    final handle = ref.read(audioPlayerHandleProvider);
    try {
      if (transition.command == PlaybackCommand.resume) {
        await handle.resume();
        return;
      }
      final url = await ref.read(downloadUrlResolverProvider)(file.storagePath);
      await handle.playFrom(url);
    } catch (_) {
      // 取得や再生に失敗したら、鳴っている表示のままにしない。
      state = PlaybackPolicy.stop(state).state;
      rethrow;
    }
  }

  /// 一時停止。その位置で止める（仕様 7）。
  Future<void> pause() async {
    if (state.status != PlaybackStatus.playing) return;
    final transition = PlaybackPolicy.pause(state);
    state = transition.state;
    await ref.read(audioPlayerHandleProvider).pause();
  }

  /// 停止。先頭へ戻す（仕様 7）。
  Future<void> stop() async {
    if (state.status == PlaybackStatus.stopped) return;
    final transition = PlaybackPolicy.stop(state);
    state = transition.state;
    await ref.read(audioPlayerHandleProvider).stop();
  }
}
