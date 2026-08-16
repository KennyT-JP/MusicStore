/// 端末に持つコメントが、本当に持てているか（docs/DOWNLOAD-DESIGN.md 論点 8）
///
/// **回帰テスト。2026-08-16 に実際に踏んだ。**
///
/// コメントの取り出しを、画面用のプロバイダ経由で書いていた。
///
/// ```dart
/// await ref.read(itemCommentsProvider(args).future)
/// ```
///
/// これらは **autoDispose** である（`app_providers.dart` の「リストや項目
/// ごとに作られるプロバイダは autoDispose にすること」／監査 S7）。
/// `ref.read(….future)` は**購読を作らない**ので、**その曲のコメントを
/// 誰も見ていないと、値が届く前に破棄される。**
///
/// ```
/// Bad state: The provider StreamProvider<List<ItemComment>>… was disposed
/// during loading state, yet no value could be emitted.
/// ```
///
/// そして `DownloadJobsController` の catch がそれを握りつぶし、
/// **コメント 0 件のまま保存される。**
///
/// | 落とし方 | 結果 |
/// | --- | --- |
/// | 項目詳細から | 動く（その画面が購読しているため） |
/// | **一覧から 1 曲** | **静かに 0 件** |
/// | **リスト一括** | **静かに 0 件** |
///
/// **「一括で落としたときだけ、オフラインでコメントが読めない」**という形。
/// 論点 8 は端末にコメントを持つことを決定事項にしているので、仕様違反である。
///
/// **握りつぶす側は残す**（コメントが取れなくても音源は落とす）ので、
/// 失敗は例外にならない。だから**中身を数える見張りが要る。**
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:music_list_app/data/models/app_user.dart';
import 'package:music_list_app/data/models/list_item.dart';
import 'package:music_list_app/data/models/music_list.dart';
import 'package:music_list_app/data/downloads/download_file_system.dart';
import 'package:music_list_app/data/repositories/item_repository.dart';
import 'package:music_list_app/data/repositories/list_repository.dart';
import 'package:music_list_app/domain/download_index.dart';
import 'package:music_list_app/domain/role.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/providers/download_provider.dart';
import 'package:music_list_app/ui/downloads/download_jobs.dart';

import 'support/downloads_harness.dart';

class _MockItemRepository extends Mock implements ItemRepository {}

class _MockListRepository extends Mock implements ListRepository {}

/// **本物の Firestore と同じで、値は非同期に届く。**
///
/// ここを `Stream.value(...)`（同期に届く）にすると、破棄されるより先に
/// 値が入ってしまい、**この見張りは何も守らなくなる**
/// （docs/AUDIT-CHECKLIST.md 観点 4「前提が崩れると自動的に通る」）。
Stream<T> _lateStream<T>(T value) => Stream.fromFuture(
  Future.delayed(const Duration(milliseconds: 20), () => value),
);

final _comment = ItemComment(
  id: 'c1',
  parentId: null,
  path: const [],
  createdAt: DateTime.utc(2026, 8, 1),
  body: 'ここのテンポ、少し速い',
  createdBy: 'u1',
  status: ContentStatus.active,
);

/// 何を渡されたかだけを覚える [DownloadsController]。
class _CapturingDownloads extends DownloadsController {
  final commentsPerItem = <String, List<OfflineComment>>{};

  @override
  Future<DownloadIndex> build() async => const DownloadIndex();

  @override
  Future<void> downloadItem({
    required String listId,
    required String listName,
    required ListItem item,
    List<OfflineComment> comments = const [],
    DownloadProgress? onProgress,
    void Function(DownloadHandle handle)? onStarted,
  }) async {
    commentsPerItem[item.id] = comments;
  }
}

ProviderContainer _container(_CapturingDownloads downloads) {
  final items = _MockItemRepository();
  final lists = _MockListRepository();

  when(
    () => items.watchComments(any(), any()),
  ).thenAnswer((_) => _lateStream([_comment]));
  when(() => lists.fetchUsers(any())).thenAnswer(
    (_) async => {
      'u1': const AppUser(uid: 'u1', displayName: '鈴木', isWithdrawn: false),
    },
  );
  when(() => lists.watchMembers(any())).thenAnswer(
    (_) => _lateStream(const [ListMember(uid: 'u1', role: ListRole.readOnly)]),
  );

  final container = ProviderContainer(
    overrides: [
      itemRepositoryProvider.overrideWithValue(items),
      listRepositoryProvider.overrideWithValue(lists),
      downloadsProvider.overrideWith(() => downloads),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('誰も画面で購読していない曲でも、コメントを取れる（論点 8）', () async {
    final container = _container(_CapturingDownloads());

    final comments = await container.read(offlineCommentsLoaderProvider)(
      listId: 'list-1',
      itemId: 'item-1',
      withdrawnLabel: '退会したユーザー',
    );

    expect(
      comments,
      hasLength(1),
      reason:
          'autoDispose のプロバイダ経由で読むと、購読が無いあいだに破棄され、'
          'コメント 0 件のまま保存されます。リポジトリを直に呼んでください。',
    );
    expect(comments.first.body, 'ここのテンポ、少し速い');
    // **`authorName` は解決済みで持つ**（3.5）。オフラインでは引けない。
    expect(comments.first.authorName, '鈴木');
  });

  test('一括ダウンロードでも、コメントが 0 件にならない（論点 8）', () async {
    // **ここが本題。** 一括は誰もその曲のコメントを購読していない状態で走る。
    final downloads = _CapturingDownloads();
    final container = _container(downloads);

    await container
        .read(downloadJobsProvider.notifier)
        .downloadList(
          listId: 'list-1',
          listName: '練習音源',
          items: [
            audioItem(id: 'item-1', seq: 1),
            audioItem(id: 'item-2', seq: 2),
          ],
          withdrawnLabel: '退会したユーザー',
        );

    expect(downloads.commentsPerItem.keys, {'item-1', 'item-2'});
    for (final entry in downloads.commentsPerItem.entries) {
      expect(
        entry.value,
        hasLength(1),
        reason:
            '${entry.key} のコメントが端末に渡っていません。'
            'オフラインで「コメントが 1 件も無い曲」になります（論点 8）。',
      );
    }
  });

  test('単曲ダウンロードでも同じ（一覧の行から押した場合）', () async {
    final downloads = _CapturingDownloads();
    final container = _container(downloads);

    await container
        .read(downloadJobsProvider.notifier)
        .downloadItem(
          listId: 'list-1',
          listName: '練習音源',
          item: audioItem(id: 'item-9', seq: 9),
          withdrawnLabel: '退会したユーザー',
        );

    expect(downloads.commentsPerItem['item-9'], hasLength(1));
  });

  test('見張りが効いていること（値が非同期に届く作りになっている）', () async {
    // **この見張り自身を試す**（監査 第4回：6 つの見張り全部に抜け道があった）。
    // 同期に届くストリームにしてしまうと、破棄より先に値が入って
    // 何も守らなくなる。
    final started = DateTime.now();
    await _lateStream(1).first;
    expect(
      DateTime.now().difference(started),
      greaterThanOrEqualTo(const Duration(milliseconds: 10)),
      reason: 'テストの前提（値が非同期に届くこと）が崩れています',
    );
  });
}
