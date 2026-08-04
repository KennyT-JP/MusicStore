/// 画面のパス定義（仕様書 14.2 / 14.3）
///
/// Web 版では URL がそのまま画面を表すため、共有 URL・招待 URL の形も
/// ここで決まる。
library;

/// アプリ内のパス。
class AppRoutes {
  const AppRoutes._();

  // --- 認証（14.2） ---

  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';

  /// メール確認待ち（3.1）。確認が済むまでここから進めない。
  static const String verifyEmail = '/verify-email';
  static const String resetPassword = '/reset-password';

  // --- 通常利用（14.2） ---

  /// ホーム＝参加リスト一覧（14.2）。
  static const String home = '/';

  static const String notifications = '/notifications';
  static const String settings = '/settings';

  /// 自分が出した申請の状態一覧（5.2.1）。
  static const String myRequests = '/my-requests';

  /// リスト作成の申請（5.1）。
  static const String requestList = '/request-list';

  // --- リスト（14.2） ---

  /// リスト詳細（項目一覧）。**共有 URL はこの形**（5.3）。
  static String list(String listId) => '/lists/$listId';

  static String item(String listId, String itemId) =>
      '/lists/$listId/items/$itemId';

  static String addItem(String listId) => '/lists/$listId/add';

  static String editItem(String listId, String itemId) =>
      '/lists/$listId/items/$itemId/edit';

  // --- リスト管理（14.2） ---

  static String listMembers(String listId) => '/lists/$listId/members';

  static String listJoinRequests(String listId) =>
      '/lists/$listId/join-requests';

  static String listSettings(String listId) => '/lists/$listId/settings';

  // --- 参加・招待（14.2） ---

  /// 招待 URL。ID は推測できないランダム文字列（13.3）。
  static String invite(String inviteId) => '/invite/$inviteId';

  // --- サイト管理（14.2） ---

  static const String siteAdmin = '/admin';
  static const String siteAdminListRequests = '/admin/list-requests';
  static const String siteAdminLists = '/admin/lists';
  static const String siteAdminUsers = '/admin/users';
  static const String siteAdminSettings = '/admin/settings';

  // --- パスのパターン（go_router 用） ---

  static const String listPattern = '/lists/:listId';
  static const String itemPattern = '/lists/:listId/items/:itemId';
  static const String addItemPattern = '/lists/:listId/add';
  static const String editItemPattern = '/lists/:listId/items/:itemId/edit';
  static const String listMembersPattern = '/lists/:listId/members';
  static const String listJoinRequestsPattern = '/lists/:listId/join-requests';
  static const String listSettingsPattern = '/lists/:listId/settings';
  static const String invitePattern = '/invite/:inviteId';

  /// ログイン後に戻る先を保持するクエリパラメータ（3.1.1）。
  ///
  /// 未ログインで共有 URL・招待 URL を開いた場合、まずログイン画面を出し、
  /// 完了後にここへ戻す。
  static const String redirectQueryParam = 'redirect';

  /// ログイン画面へ、戻り先つきで遷移するパスを組み立てる。
  static String signInWithRedirect(String destination) {
    if (destination.isEmpty || destination == home) return signIn;
    final encoded = Uri.encodeQueryComponent(destination);
    return '$signIn?$redirectQueryParam=$encoded';
  }

  /// ログイン後に戻るべきパスを取り出す。
  ///
  /// 外部サイトへ飛ばされないよう、**アプリ内の相対パスだけ**を受け入れる。
  /// `//example.com` のようなスキーム相対 URL も拒否する。
  static String resolveRedirect(String? raw) {
    if (raw == null || raw.isEmpty) return home;
    if (!raw.startsWith('/')) return home;
    if (raw.startsWith('//')) return home;
    return raw;
  }
}
