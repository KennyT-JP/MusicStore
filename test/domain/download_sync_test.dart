/// 元の削除・差し替えの判定（docs/DOWNLOAD-DESIGN.md 4.4 / 8.1）
///
/// **判定を間違えると、端末のファイルが消えるか、古いものを聴き続けることになる。**
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/download_sync.dart';

const _local = 'lists/L1/items/I1/1755200000000-take3.wav';

SyncAction _decide({required String? status, required String? path}) =>
    DownloadSyncPolicy.decide(
      serverStatus: status,
      serverStoragePath: path,
      localStoragePath: _local,
    );

void main() {
  group('同期の判定（4.4・8.1 の表）', () {
    test('active で storagePath が同じ → keep', () {
      // **同じパスへの上書きは storage.rules が禁じている**ので、
      // パスが同じなら中身も同じ。落とし直す必要はない。
      expect(_decide(status: 'active', path: _local), SyncAction.keep);
    });

    test('active で storagePath が違う → replace（論点 11）', () {
      // 差し替えは必ず別名でアップロードされる（item_repository.dart:204-212）。
      // **パスの一致だけで検出できる。**
      expect(
        _decide(
          status: 'active',
          path: 'lists/L1/items/I1/1755300000000-take4.wav',
        ),
        SyncAction.replace,
      );
    });

    test('deleted → remove（論点 11）', () {
      // ソフト削除。端末からも消す。
      expect(_decide(status: 'deleted', path: _local), SyncAction.remove);
    });

    test('ドキュメントが無い（null）→ remove', () {
      expect(_decide(status: null, path: _local), SyncAction.remove);
    });

    test('ドキュメントが無ければ、パスも見ずに remove', () {
      // 消えた項目の storagePath は当てにならない。
      expect(_decide(status: null, path: null), SyncAction.remove);
    });

    test('URL の項目に変わった（file が null）→ remove', () {
      expect(_decide(status: 'active', path: null), SyncAction.remove);
    });

    test('知らない status は active と同じ扱い（keep）', () {
      // **これは既存の作りに合わせた結果。** ContentStatus.tryParse
      // （lib/data/models/list_item.dart:36-37）が `'deleted'` 以外を
      // すべて active として復元するので、ここだけ「未知は消す」に倒すと、
      // **画面には出ているのに端末からは消える**という食い違いになる。
      // 削除の判定は 'deleted' の 1 つだけにそろえてある。
      expect(_decide(status: 'archived', path: _local), SyncAction.keep);
    });
  });
}
