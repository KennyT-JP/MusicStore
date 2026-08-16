/// ダウンロード機能の画面テストで使う差し替え（docs/DOWNLOAD-DESIGN.md 6 節）
///
/// **端末のファイルにも Firebase にも触らずに、画面だけを確かめる。**
/// `DownloadsController.build` は既定で `DownloadRepository` を呼ぶので、
/// そこだけを差し替える。
library;

import 'dart:async';

import 'package:music_list_app/data/audio_player_handle.dart';
import 'package:music_list_app/data/models/list_item.dart';
import 'package:music_list_app/domain/download_index.dart';
import 'package:music_list_app/domain/local_date.dart';
import 'package:music_list_app/providers/download_provider.dart';

/// 何を頼まれたかだけを覚える、音の側の差し替え
/// （`test/ui/playback_ui_test.dart` と同じ考え）。
class FakeAudioHandle implements AudioPlayerHandle {
  final calls = <String>[];
  final _errors = StreamController<Object>.broadcast();

  @override
  Future<void> playFrom(String url) async => calls.add('playFrom:$url');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Stream<void> get onCompleted => const Stream.empty();

  @override
  Stream<Object> get onError => _errors.stream;

  @override
  Future<void> dispose() async => _errors.close();
}

/// 目録を直接与える [DownloadsController]。
///
/// **[build] だけを差し替える。** 判定（帯・残り日数・見積もり）は
/// 本物のまま動かす——差し替えてしまうと、画面が判定を通っているかを
/// 確かめられなくなる。
class FakeDownloadsController extends DownloadsController {
  FakeDownloadsController([this.index = const DownloadIndex()]);

  final DownloadIndex index;

  /// 端末から消してほしいと言われた曲。
  final removed = <String>[];

  @override
  Future<DownloadIndex> build() async => index;

  @override
  Future<void> removeItem({
    required String listId,
    required String itemId,
  }) async {
    removed.add('$listId/$itemId');
  }

  @override
  Future<void> removeAll() async => removed.add('*');
}

/// 目録の 1 件。既定は「41.2 MB の wav が 1 本」。
DownloadedItem downloadedItem({
  required String itemId,
  String listId = 'list-1',
  String listName = '練習音源',
  int seq = 1,
  String? title = '練習 1 本目',
  String? artist,
  String date = '2026-08-01',
  int localBytes = 41234567,
}) => DownloadedItem(
  listId: listId,
  listName: listName,
  itemId: itemId,
  seq: seq,
  date: LocalDate.tryParse(date)!,
  storagePath: 'lists/$listId/items/$itemId/1755200000000-take3.wav',
  fileName: 'take3.wav',
  contentType: 'audio/wav',
  sizeBytes: localBytes,
  localAudio: '$listId/$itemId/audio-1755200000000.wav',
  localBytes: localBytes,
  downloadedAt: DateTime.utc(2026, 8, 15),
  title: title,
  artist: artist,
);

/// 一覧に並べる音源の項目。
ListItem audioItem({
  required String id,
  required int seq,
  String listId = 'list-1',
  int sizeBytes = 41234567,
  String? title,
}) => ListItem(
  id: id,
  seq: seq,
  itemDate: LocalDate.tryParse('2026-08-01')!,
  kind: ItemKind.file,
  file: ItemFile(
    storagePath: 'lists/$listId/items/$id/1755200000000-take$seq.wav',
    fileName: 'take$seq.wav',
    sizeBytes: sizeBytes,
    contentType: 'audio/wav',
  ),
  title: title ?? '練習 $seq 本目',
  createdBy: 'u1',
  registrantDisplayName: '山田',
  status: ContentStatus.active,
);
