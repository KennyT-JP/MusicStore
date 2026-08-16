/// 端末へ持たせるコメントの `authorName`（docs/DOWNLOAD-DESIGN.md 3.5）
///
/// **表示名は `users/{uid}` にあり、オフラインでは引けない。**
/// だから落とすときに解決して埋める。名前が変わっても端末側は古いまま
/// 出るが、**「名前が古い」と「名前が出ない」なら前者のほうがまし**（3.5）。
///
/// ここで守るのは 2 つ。
///
/// 1. **埋まること。** 空のまま落とすと、オフラインで開いたときに
///    投稿者が誰も分からない。しかも**気づくのは圏外に出てから**で、
///    そのときはもう直せない
/// 2. **退会・除外の扱いが画面と同じであること。**
///    `DisplayNameResolver.resolveInList`（`domain/display_name.dart`）を
///    通すこと。**同じ判定を 2 か所に書くと**、画面では「退会したユーザー」
///    なのに端末の写しには本名が残る、という食い違いが出る
///
/// 「退会したユーザー」に倒す条件は 3 つある（仕様書 13.3 / 3.5 / 5.4）。
/// **どれも本名を出さないほうへ倒す**ので、3 つとも確かめる。
///
/// | 相手 | 期待 |
/// | --- | --- |
/// | いまもメンバー | その人の表示名 |
/// | アカウントを退会した（`isWithdrawn`） | 「退会したユーザー」 |
/// | **メンバーから外れた**（除外・自分で脱退） | 「退会したユーザー」 |
/// | ユーザー文書が引けない | 「退会したユーザー」 |
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:music_list_app/data/models/app_user.dart';
import 'package:music_list_app/data/models/list_item.dart';
import 'package:music_list_app/data/models/music_list.dart';
import 'package:music_list_app/data/repositories/item_repository.dart';
import 'package:music_list_app/data/repositories/list_repository.dart';
import 'package:music_list_app/domain/download_index.dart';
import 'package:music_list_app/domain/role.dart';
import 'package:music_list_app/providers/app_providers.dart';
import 'package:music_list_app/ui/downloads/download_jobs.dart';

class _FakeItemRepository extends Mock implements ItemRepository {}

class _FakeListRepository extends Mock implements ListRepository {}

const _listId = 'list-1';
const _itemId = 'item-1';
const _withdrawn = '退会したユーザー';

ItemComment _comment({
  required String id,
  required String createdBy,
  String? parentId,
  List<String> path = const [],
  ContentStatus status = ContentStatus.active,
}) => ItemComment(
  id: id,
  parentId: parentId,
  path: path,
  createdAt: DateTime.fromMillisecondsSinceEpoch(1755280000000),
  body: '$id の本文',
  createdBy: createdBy,
  status: status,
);

ListMember _member(String uid) => ListMember(uid: uid, role: ListRole.readOnly);

void main() {
  late _FakeItemRepository items;
  late _FakeListRepository lists;
  late ProviderContainer container;

  /// そのリストのメンバーと、`users` から引ける人を決めて器を組む。
  void arrange({
    required List<ItemComment> comments,
    required List<String> memberUids,
    required Map<String, AppUser> users,
  }) {
    items = _FakeItemRepository();
    lists = _FakeListRepository();

    when(
      () => items.watchComments(_listId, _itemId),
    ).thenAnswer((_) => Stream.value(comments));
    when(
      () => lists.watchMembers(_listId),
    ).thenAnswer((_) => Stream.value(memberUids.map(_member).toList()));
    when(
      () => lists.fetchUsers(any()),
    ).thenAnswer((_) async => users);

    container = ProviderContainer.test(
      overrides: [
        itemRepositoryProvider.overrideWithValue(items),
        listRepositoryProvider.overrideWithValue(lists),
      ],
    );

    // **購読を張ってから読む。**
    //
    // `offlineCommentsLoaderProvider` は `ref.read(…​.future)` で
    // `itemCommentsProvider` / `listMembersProvider` を読む。どちらも
    // `autoDispose` なので、**ほかに誰も見ていないと、最初の値が届く前に
    // 捨てられる**（`The provider … was disposed during loading state`）。
    //
    // 画面（項目詳細）はコメントもメンバーも購読しているので、そこから
    // 落とすかぎり値は届く。ここではその状態を作っている。
    // **購読していない場所から落としたときの挙動は、この機能の持ち主へ
    // 申し送り済み**（一括ダウンロードがそれに当たる）。
    container.listen(
      itemCommentsProvider((listId: _listId, itemId: _itemId)),
      (_, _) {},
    );
    container.listen(listMembersProvider(_listId), (_, _) {});
  }

  Future<List<OfflineComment>> load() => container.read(
    offlineCommentsLoaderProvider,
  )(listId: _listId, itemId: _itemId, withdrawnLabel: _withdrawn);

  test('いまもメンバーなら、その人の表示名が入る', () async {
    arrange(
      comments: [_comment(id: 'c1', createdBy: 'u1')],
      memberUids: const ['u1'],
      users: const {
        'u1': AppUser(uid: 'u1', displayName: '山田', isWithdrawn: false),
      },
    );

    final comments = await load();

    expect(
      comments.single.authorName,
      '山田',
      reason:
          '空のまま落とすと、オフラインで開いたときに投稿者が分からない。'
          'そして気づくのは圏外に出てからで、そのときはもう直せない。',
    );
  });

  test('アカウントを退会した人は「退会したユーザー」', () async {
    arrange(
      comments: [_comment(id: 'c1', createdBy: 'u1')],
      memberUids: const ['u1'],
      users: const {
        'u1': AppUser(uid: 'u1', displayName: '鈴木', isWithdrawn: true),
      },
    );

    final comments = await load();

    expect(comments.single.authorName, _withdrawn);
    expect(
      comments.single.authorName,
      isNot(contains('鈴木')),
      reason: '退会した人の名前を端末へ持ち出さない（仕様書 3.5）',
    );
  });

  test('メンバーから外れた人は「退会したユーザー」（除外・脱退）', () async {
    arrange(
      comments: [_comment(id: 'c1', createdBy: 'u1')],
      // users には残っているが、もうこのリストのメンバーではない。
      memberUids: const ['u2'],
      users: const {
        'u1': AppUser(uid: 'u1', displayName: '佐藤', isWithdrawn: false),
      },
    );

    final comments = await load();

    expect(
      comments.single.authorName,
      _withdrawn,
      reason:
          '「退会したユーザー」と出す条件は 2 つある（仕様書 13.3）。'
          '退会フラグだけを見ると、除外された人の名前が端末に残る。',
    );
  });

  test('ユーザー文書が引けない人も「退会したユーザー」', () async {
    arrange(
      comments: [_comment(id: 'c1', createdBy: 'u1')],
      memberUids: const ['u1'],
      users: const {},
    );

    final comments = await load();

    expect(comments.single.authorName, _withdrawn);
  });

  test('削除済みのコメントも、返信の親子関係ごと持って帰る', () async {
    arrange(
      comments: [
        _comment(id: 'c1', createdBy: 'u1', status: ContentStatus.deleted),
        _comment(id: 'c2', createdBy: 'u1', parentId: 'c1', path: const ['c1']),
      ],
      memberUids: const ['u1'],
      users: const {
        'u1': AppUser(uid: 'u1', displayName: '山田', isWithdrawn: false),
      },
    );

    final comments = await load();

    final parent = comments.firstWhere((c) => c.id == 'c1');
    final reply = comments.firstWhere((c) => c.id == 'c2');

    expect(
      parent.status,
      'deleted',
      reason: '削除済みも持つ（ツリーの親になるため／3.5）',
    );
    expect(reply.parentId, 'c1');
    expect(reply.path, const ['c1']);
    expect(
      reply.depth,
      1,
      reason:
          'path をそのまま持てば comment_tree.dart の組み立てを'
          'オフラインでもそのまま使える（3.5）。別の組み立て方を作らないこと。',
    );
  });

  test('コメントが 1 件も無ければ空', () async {
    arrange(comments: const [], memberUids: const ['u1'], users: const {});

    expect(await load(), isEmpty);
  });
}
