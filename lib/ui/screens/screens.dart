/// 画面一覧（仕様書 14.2）
///
/// 実装済みの画面は各ファイルから再エクスポートし、
/// まだのものはプレースホルダーとしてここに置いている。
library;

import 'package:flutter/material.dart';

import 'placeholder_screen.dart';

// 実装済みの画面
export 'auth/reset_password_screen.dart';
export 'auth/sign_in_screen.dart';
export 'auth/sign_up_screen.dart';
export 'auth/verify_email_screen.dart';
export 'home_screen.dart';
export 'item_detail_screen.dart';
export 'item_form_screen.dart';
export 'list_detail_screen.dart';

// ---------------------------------------------------------------------------
// 認証まわり（14.2）
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// 通常利用（14.2）
// ---------------------------------------------------------------------------

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
    title: '通知一覧',
    specReference: '10 / 14.2',
    description:
        'アプリ内通知を新しい順に表示。未読を強調。タップで対象へ遷移。'
        '「すべて既読にする」を置く。初期リリースではプッシュ通知は扱わない。',
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
    title: '設定',
    specReference: '3.4 / 10.3 / 14.2',
    description: '表示名の変更、表示言語（日本語／英語）、通知設定、退会。',
  );
}

class MyRequestsScreen extends StatelessWidget {
  const MyRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
    title: '自分の申請一覧',
    specReference: '5.2.1 / 14.2',
    description:
        '自分が出したリスト作成申請・参加申請の状態（申請中／承認／却下）を表示。'
        '却下されても通知は届かないが、ここで確認して再申請できる。',
  );
}

class RequestListScreen extends StatelessWidget {
  const RequestListScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
    title: 'リスト作成の申請',
    specReference: '5.1',
    description:
        'リスト名（重複チェックあり）、概算の登録曲数、使用者数、作成目的を入力。'
        'サイト管理者が承認すると、申請者がそのリストのリスト管理者になる。',
  );
}

// ---------------------------------------------------------------------------
// 参加・招待（14.2）
// ---------------------------------------------------------------------------

class JoinRequestScreen extends StatelessWidget {
  const JoinRequestScreen({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
    title: 'リスト参加申請',
    specReference: '5.3',
    description:
        'listId: $listId\n\n'
        '共有 URL を開いた未参加者に、リスト名など最低限の情報と'
        '「参加申請」ボタンだけを表示する。中身は承認されるまで見えない。',
  );
}

class AcceptInviteScreen extends StatelessWidget {
  const AcceptInviteScreen({super.key, required this.inviteId});

  final String inviteId;

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
    title: '招待の受諾',
    specReference: '3.3',
    description:
        'inviteId: $inviteId\n\n'
        '有効期限は受諾した時点で判定する。'
        '期限切れ・使用済み・取り消し済みの場合はその旨を表示する。',
  );
}

// ---------------------------------------------------------------------------
// リスト管理（リスト管理者以上／14.2）
// ---------------------------------------------------------------------------

class ListMembersScreen extends StatelessWidget {
  const ListMembersScreen({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
    title: 'メンバー管理',
    specReference: '5.4 / 11.2',
    description:
        'listId: $listId\n\n'
        'メンバー一覧と役割。役割の変更、除外、招待 URL の発行。',
  );
}

class ListJoinRequestsScreen extends StatelessWidget {
  const ListJoinRequestsScreen({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
    title: '参加申請の承認',
    specReference: '5.2 / 11.2',
    description:
        'listId: $listId\n\n'
        '保留中の申請一覧。承認時に役割（Super User／Read Only）を決める。'
        '申請者は役割を選べない。',
  );
}

class ListSettingsScreen extends StatelessWidget {
  const ListSettingsScreen({super.key, required this.listId});

  final String listId;

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
    title: 'リスト設定',
    specReference: '5.5 / 7.4 / 11.2',
    description:
        'listId: $listId\n\n'
        '容量使用量の表示、リスト削除。'
        '削除するとファイル・コメントもすべて削除され、取り消せない。',
  );
}

// ---------------------------------------------------------------------------
// サイト管理（サイト管理者のみ／14.2）
// ---------------------------------------------------------------------------

class SiteAdminHomeScreen extends StatelessWidget {
  const SiteAdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
    title: 'サイト管理',
    specReference: '11.1 / 14.2',
    description:
        'リスト作成申請の承認、リストと容量、ユーザー管理、サイト設定への入口。',
  );
}

class SiteAdminListRequestsScreen extends StatelessWidget {
  const SiteAdminListRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
    title: 'リスト作成申請の承認',
    specReference: '5.1 / 11.1',
    description:
        '保留中の申請一覧と承認・却下。却下時は listNames の予約を解放する。',
  );
}

class SiteAdminListsScreen extends StatelessWidget {
  const SiteAdminListsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
    title: 'リスト一覧・容量',
    specReference: '5.6 / 7.2 / 11.1',
    description:
        '全リストの容量使用量。リストごとの上限設定（初期値 1GB）。'
        '管理者不在リストの抽出とリスト管理者の指名。',
  );
}

class SiteAdminUsersScreen extends StatelessWidget {
  const SiteAdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
    title: 'ユーザー管理',
    specReference: '4.4 / 4.5 / 11.1',
    description:
        'ユーザー一覧、サイト管理者への昇格・降格、権限変更。'
        '最後のサイト管理者は降格できない。',
  );
}

class SiteAdminSettingsScreen extends StatelessWidget {
  const SiteAdminSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(
    title: 'サイト設定',
    specReference: '11.1 / 13.3',
    description:
        '招待 URL の有効期限（初期値 24 時間）、容量上限の初期値（1GB）、'
        '削除ファイルの保持日数（30 日）、孤児ファイルの猶予時間（24 時間）。',
  );
}

// ---------------------------------------------------------------------------
// エラー
// ---------------------------------------------------------------------------

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key, this.location});

  final String? location;

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
    title: 'ページが見つかりません',
    specReference: '—',
    description: location == null ? null : 'パス: $location',
  );
}
