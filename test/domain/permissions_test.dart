/// 権限判定のテスト（仕様書 4.2 / 6.3 / 9 / 4.5）
///
/// 12.6 で「間違えると影響が大きい」として自動テスト必須にした領域。
/// 見えてはいけない情報が見えてしまう事故を防ぐ。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/permissions.dart';
import 'package:music_list_app/domain/role.dart';

void main() {
  const readOnly = ListAccess(isSiteAdmin: false, role: ListRole.readOnly);
  const superUser = ListAccess(isSiteAdmin: false, role: ListRole.superUser);
  const listAdmin = ListAccess(isSiteAdmin: false, role: ListRole.listAdmin);
  const siteAdmin = ListAccess.siteAdmin();
  const outsider = ListAccess.none();

  group('役割の階層（4.1）', () {
    test('上位は下位を包含する', () {
      expect(ListRole.listAdmin.isAtLeast(ListRole.superUser), isTrue);
      expect(ListRole.listAdmin.isAtLeast(ListRole.readOnly), isTrue);
      expect(ListRole.superUser.isAtLeast(ListRole.readOnly), isTrue);
    });

    test('下位は上位を包含しない', () {
      expect(ListRole.readOnly.isAtLeast(ListRole.superUser), isFalse);
      expect(ListRole.superUser.isAtLeast(ListRole.listAdmin), isFalse);
    });

    test('サイト管理者は全リストでリスト管理者と同等（4.2）', () {
      expect(siteAdmin.effectiveRole, ListRole.listAdmin);
      expect(siteAdmin.hasAtLeast(ListRole.listAdmin), isTrue);
    });

    test('未知の役割文字列は復元しない', () {
      // 不明な値を強い権限として扱うと権限昇格になるため、必ず null を返す。
      expect(ListRole.tryParse('owner'), isNull);
      expect(ListRole.tryParse(''), isNull);
      expect(ListRole.tryParse(null), isNull);
      expect(ListRole.tryParse('superUser'), ListRole.superUser);
    });
  });

  group('リストの閲覧（5.3）', () {
    test('メンバーは閲覧できる', () {
      expect(Permissions.canViewList(readOnly), isTrue);
      expect(Permissions.canViewList(superUser), isTrue);
    });

    test('未参加者は閲覧できない', () {
      expect(Permissions.canViewList(outsider), isFalse);
    });

    test('閲覧者は中身を見られる（3.3）', () {
      // 共有リンクで「メンバーにならずに見る」を選んだ人。
      // **ここを落とすと、見る権利があるのに参加申請の画面へ送られる**
      // （2026-08-08 の指摘）。
      const viewer = ListAccess(
        isSiteAdmin: false,
        role: null,
        isViewer: true,
      );
      expect(Permissions.canViewList(viewer), isTrue);
    });

    test('閲覧者は、見られるだけで何も書けない（3.3）', () {
      // **見られることと書けることは別。** 役割を持たせて済ませると、
      // 書ける判定まで通ってしまう。
      const viewer = ListAccess(
        isSiteAdmin: false,
        role: null,
        isViewer: true,
      );
      expect(Permissions.canAddItem(viewer), isFalse);
      expect(Permissions.canPostComment(viewer), isFalse);
      expect(Permissions.canManageMembers(viewer), isFalse);
      expect(Permissions.canCreateShareLink(viewer), isFalse);
      expect(Permissions.canAccessSiteAdmin(viewer), isFalse);
      // メンバーではないので「離脱」もしない。
      expect(Permissions.canLeaveList(viewer), isFalse);
      // **代わりに「閲覧をやめる」が出る**（3.3・2026-08-15）。
      // 出口がまったく無いと、共有リンクで一度見た人は
      // リスト管理者に頼むしか外れる手段が無い。
      expect(Permissions.canStopViewing(viewer), isTrue);
      expect(viewer.effectiveRole, isNull);
    });

    test('メンバーには「閲覧をやめる」を出さない', () {
      // メンバーは「このリストから抜ける」で外れる。両方出すと、
      // 同じ画面に似た操作が 2 つ並んで迷う。
      expect(Permissions.canStopViewing(readOnly), isFalse);
      expect(Permissions.canStopViewing(listAdmin), isFalse);
      expect(Permissions.canStopViewing(siteAdmin), isFalse);
    });

    test('サイト管理者はメンバー登録がなくても閲覧できる', () {
      expect(Permissions.canViewList(siteAdmin), isTrue);
    });
  });

  group('項目の追加（4.2）', () {
    test('Super User 以上は追加できる', () {
      expect(Permissions.canAddItem(superUser), isTrue);
      expect(Permissions.canAddItem(listAdmin), isTrue);
      expect(Permissions.canAddItem(siteAdmin), isTrue);
    });

    test('Read Only は追加できない', () {
      expect(Permissions.canAddItem(readOnly), isFalse);
    });

    test('未参加者は追加できない', () {
      expect(Permissions.canAddItem(outsider), isFalse);
    });
  });

  group('項目の編集・削除（6.3）', () {
    bool canEdit(ListAccess access, {required String creator}) =>
        Permissions.canEditItem(
          access,
          viewerUid: 'me',
          itemCreatedBy: creator,
          itemIsDeleted: false,
        );

    test('登録した本人は編集できる', () {
      expect(canEdit(superUser, creator: 'me'), isTrue);
    });

    test('他人の項目は Super User でも編集できない', () {
      expect(canEdit(superUser, creator: 'someone-else'), isFalse);
    });

    test('リスト管理者は他人の項目も編集できる', () {
      expect(canEdit(listAdmin, creator: 'someone-else'), isTrue);
    });

    test('サイト管理者は他人の項目も編集できる', () {
      expect(canEdit(siteAdmin, creator: 'someone-else'), isTrue);
    });

    test('Read Only は自分の項目でも編集できない', () {
      // Read Only はそもそも項目を作れないが、役割を降格された場合に
      // 過去の投稿を編集できてしまわないことを確認する。
      expect(canEdit(readOnly, creator: 'me'), isFalse);
    });

    test('削除済みの項目は誰も編集できない', () {
      expect(
        Permissions.canEditItem(
          siteAdmin,
          viewerUid: 'me',
          itemCreatedBy: 'me',
          itemIsDeleted: true,
        ),
        isFalse,
      );
    });

    test('削除の可否は編集と同じ条件', () {
      expect(
        Permissions.canDeleteItem(
          superUser,
          viewerUid: 'me',
          itemCreatedBy: 'someone-else',
          itemIsDeleted: false,
        ),
        isFalse,
      );
      expect(
        Permissions.canDeleteItem(
          listAdmin,
          viewerUid: 'me',
          itemCreatedBy: 'someone-else',
          itemIsDeleted: false,
        ),
        isTrue,
      );
    });
  });

  group('削除済み項目の復元（6.3 / 13.4）', () {
    test('猶予期間中はリスト管理者以上が復元できる', () {
      expect(
        Permissions.canRestoreItem(
          listAdmin,
          itemIsDeleted: true,
          withinGracePeriod: true,
        ),
        isTrue,
      );
    });

    test('Super User は復元できない', () {
      expect(
        Permissions.canRestoreItem(
          superUser,
          itemIsDeleted: true,
          withinGracePeriod: true,
        ),
        isFalse,
      );
    });

    test('猶予期間を過ぎたら復元できない', () {
      expect(
        Permissions.canRestoreItem(
          siteAdmin,
          itemIsDeleted: true,
          withinGracePeriod: false,
        ),
        isFalse,
      );
    });

    test('削除されていない項目は復元対象にならない', () {
      expect(
        Permissions.canRestoreItem(
          listAdmin,
          itemIsDeleted: false,
          withinGracePeriod: true,
        ),
        isFalse,
      );
    });
  });

  group('コメント（9）', () {
    test('Read Only はコメントも返信も一切できない', () {
      expect(Permissions.canPostComment(readOnly), isFalse);
    });

    test('Super User 以上は書ける', () {
      expect(Permissions.canPostComment(superUser), isTrue);
      expect(Permissions.canPostComment(listAdmin), isTrue);
      expect(Permissions.canPostComment(siteAdmin), isTrue);
    });

    test('自分のコメントは本人が編集・削除できる', () {
      expect(
        Permissions.canEditComment(
          superUser,
          viewerUid: 'me',
          commentCreatedBy: 'me',
          commentIsDeleted: false,
        ),
        isTrue,
      );
    });

    test('リスト管理者は自リスト内のどのコメントでも編集・削除できる', () {
      expect(
        Permissions.canDeleteComment(
          listAdmin,
          viewerUid: 'me',
          commentCreatedBy: 'someone-else',
          commentIsDeleted: false,
        ),
        isTrue,
      );
    });
  });

  group('リスト管理（5.4 / 5.5 / 7.4）', () {
    test('メンバー管理・リスト削除・容量把握はリスト管理者以上', () {
      for (final access in [listAdmin, siteAdmin]) {
        expect(Permissions.canManageMembers(access), isTrue);
        expect(Permissions.canDeleteList(access), isTrue);
        expect(Permissions.canViewQuota(access), isTrue);
        expect(Permissions.canCreateShareLink(access), isTrue);
      }
      for (final access in [readOnly, superUser, outsider]) {
        expect(Permissions.canManageMembers(access), isFalse);
        expect(Permissions.canDeleteList(access), isFalse);
        expect(Permissions.canViewQuota(access), isFalse);
        expect(Permissions.canCreateShareLink(access), isFalse);
      }
    });

    test('自分自身は「除外」できない（離脱で抜ける）', () {
      expect(
        Permissions.canRemoveMember(
          listAdmin,
          viewerUid: 'me',
          targetUid: 'me',
        ),
        isFalse,
      );
      expect(
        Permissions.canRemoveMember(
          listAdmin,
          viewerUid: 'me',
          targetUid: 'other',
        ),
        isTrue,
      );
    });

    test('メンバーは自分から抜けられる', () {
      expect(Permissions.canLeaveList(readOnly), isTrue);
      expect(Permissions.canLeaveList(listAdmin), isTrue);
    });

    test('メンバー登録のないサイト管理者に離脱の概念はない', () {
      expect(Permissions.canLeaveList(siteAdmin), isFalse);
    });
  });

  group('サイト管理者が 0 人になることの防止（4.5）', () {
    test('最後の 1 人は降格・退会できない', () {
      expect(
        Permissions.canStepDownAsSiteAdmin(
          isSiteAdmin: true,
          siteAdminCount: 1,
        ),
        isFalse,
      );
    });

    test('2 人以上いれば降格・退会できる', () {
      expect(
        Permissions.canStepDownAsSiteAdmin(
          isSiteAdmin: true,
          siteAdminCount: 2,
        ),
        isTrue,
      );
    });

    test('サイト管理者でない人は制限を受けない', () {
      expect(
        Permissions.canStepDownAsSiteAdmin(
          isSiteAdmin: false,
          siteAdminCount: 1,
        ),
        isTrue,
      );
    });
  });

  group('サイト管理画面（14.5）', () {
    test('サイト管理者のみ入れる', () {
      expect(Permissions.canAccessSiteAdmin(siteAdmin), isTrue);
      expect(Permissions.canAccessSiteAdmin(listAdmin), isFalse);
      expect(Permissions.canAccessSiteAdmin(outsider), isFalse);
    });
  });

  // -----------------------------------------------------------------------
  // オフライン用ダウンロード（docs/DOWNLOAD-DESIGN.md 5.2 / 8.1）
  // -----------------------------------------------------------------------
  group('ダウンロードの可否（DOWNLOAD-DESIGN 5.2・論点 9 / 12・仕様書 4.1）', () {
    const viewer = ListAccess(isSiteAdmin: false, role: null, isViewer: true);

    // **サイト管理者でメンバーでもある人。** 役割を持つのでメンバーとして通る。
    // 「サイト管理者は不可」と読んで `!isSiteAdmin && …` と書くと、この人が
    // 落ちる。**外すのは例外であって、その人ではない。**
    const siteAdminMember = ListAccess(
      isSiteAdmin: true,
      role: ListRole.readOnly,
    );

    // `canDownload` は純関数で、受け取る `isPremium` は呼び出し側
    // （`canDownloadProvider`）が渡す**実効プレミアム**（プレミアム or
    // サイト管理者／仕様書 4.1）。ここで固定するのは「メンバー軸」と
    // 「渡された実効プレミアム」の 2 つで決まること。

    test('Read Only のメンバーはダウンロードできる（論点 9）', () {
      // 「メンバーのみ（Read Only を含む）」。ここを
      // `hasAtLeast(superUser)` にすると、Read Only が落ちる。
      expect(Permissions.canDownload(readOnly, isPremium: true), isTrue);
    });

    test('Super User・リスト管理者もできる', () {
      expect(Permissions.canDownload(superUser, isPremium: true), isTrue);
      expect(Permissions.canDownload(listAdmin, isPremium: true), isTrue);
    });

    test('閲覧者はできない（論点 9）', () {
      // **共有リンクが回った先の人が端末に音源を残す経路を塞ぐ**のが
      // 論点 9 の狙い。`access.canView` で判定すると、
      // `canView` は `effectiveRole != null || isViewer` なので閲覧者が通る。
      expect(viewer.canView, isTrue, reason: '前提：閲覧者は中身を見られる');
      expect(Permissions.canDownload(viewer, isPremium: true), isFalse);
    });

    test('メンバーでもなんでもない人はできない', () {
      expect(Permissions.canDownload(outsider, isPremium: true), isFalse);
    });

    test('サイト管理者はメンバーでなくてもできる（全リスト／仕様書 4.2）', () {
      // **サイト管理者は「全リストの項目を扱える」（4.2）ので、メンバーで
      // なくてもダウンロードできる。** メンバー軸も `|| access.isSiteAdmin` で
      // 例外にした（サーバーの verifyDownloadAccess も全リストを `member` で
      // 返す）。前提としてサイト管理者は effectiveRole が listAdmin。
      expect(
        siteAdmin.hasAtLeast(ListRole.readOnly),
        isTrue,
        reason: '前提：サイト管理者は effectiveRole が listAdmin になる',
      );
      expect(Permissions.canDownload(siteAdmin, isPremium: true), isTrue);
    });

    test('サイト管理者でメンバーでもある人はできる（仕様書 4.1）', () {
      // 役割を持っているのでメンバーとして通る。
      // **行きすぎた修正（`!access.isSiteAdmin && …`）でこの行が落ちる。**
      expect(Permissions.canDownload(siteAdminMember, isPremium: true), isTrue);
    });

    test('canDownload は isSiteAdmin からプレミアムを導き出さない（実効値は上流で合成）', () {
      // **仕様書 4.1・旧・論点 18 を上書き。** サイト管理者は実効プレミアム
      // 扱いになったが、その合成は 1 か所（`isPremiumOrAdminProvider`）に置く。
      // **`canDownload` 自身は渡された `isPremium` を素直に使う**——ここで
      // `|| access.isSiteAdmin` を足すと、プレミアムの判定が 2 か所になる。
      // だから「サイト管理者メンバーでも、渡された実効値が false なら false」を
      // 固定して、二重化を弾く。実際の運用では上流が true を渡すので落とせる。
      expect(
        Permissions.canDownload(siteAdminMember, isPremium: false),
        isFalse,
      );
    });

    test('実効プレミアムでなければ、メンバーでも落とせない（論点 12）', () {
      // **「ダウンロードは機能であって資産ではない」**（2.1）。
      // 実効プレミアム（プレミアム or サイト管理者）が無ければ機能は止まる。
      // 曲もリストも残る。一般メンバーは契約が切れれば false が渡る。
      expect(Permissions.canDownload(readOnly, isPremium: false), isFalse);
      expect(Permissions.canDownload(superUser, isPremium: false), isFalse);
      expect(Permissions.canDownload(listAdmin, isPremium: false), isFalse);
      expect(Permissions.canDownload(viewer, isPremium: false), isFalse);
    });
  });
}
