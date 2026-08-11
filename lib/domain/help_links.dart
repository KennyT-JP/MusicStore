/// 画面から、使い方の該当箇所へ飛ぶための対応表（仕様書 14.2）
///
/// **リンク先は Web で公開しているマニュアル**（`web/help/{言語}/`）。
/// 開く言語は**アプリの表示言語に従う**（依頼者の指示・2026-08-11）。
/// 端末やブラウザの言語ではない——設定画面で日本語を選んでいる人には
/// 日本語を出す。
///
/// **対応表をここに置く理由。** 画面側に URL を直接書くと、節の名前を
/// 変えたときに拾い漏れる。ここに集めておけば、
/// `test/domain/help_links_test.dart` が**実際のマニュアルを読んで**、
/// リンク先の節が存在することを確かめられる。
library;

/// 使い方の節（マニュアルの見出し ID と一対一）。
enum HelpTopic {
  gettingStarted('getting-started'),
  account('account'),
  signIn('sign-in'),
  home('home'),
  listRequest('list-request'),
  myRequests('my-requests'),
  list('list'),
  item('item'),
  itemForm('item-form'),
  playback('playback'),
  shareLink('share-link'),
  joinRequest('join-request'),
  members('members'),
  listSettings('list-settings'),
  roles('roles'),
  storage('storage'),
  notifications('notifications'),
  settings('settings'),
  siteAdmin('site-admin');

  const HelpTopic(this.anchor);

  /// マニュアル側の見出し ID（`<h2 id="...">`）。
  final String anchor;
}

/// 使い方のページを組み立てる。
///
/// [languageCode] は `Localizations.localeOf(context).languageCode`。
/// 日本語以外は英語に倒す（用意しているのは 2 言語だけ）。
String helpUrlFor(HelpTopic topic, String languageCode) {
  final language = languageCode == 'ja' ? 'ja' : 'en';
  return '/help/$language/#${topic.anchor}';
}

/// いま出ている画面に対応する節を返す。
///
/// **画面ごとに違う節へ飛ばす。** 目次の先頭に落とすだけでは、
/// 困っている人が自分で探すことになる（それなら押す意味が薄い）。
///
/// [route] は go_router の `state.matchedLocation`。
/// パラメータを含む形（`/lists/abc/items/1`）で渡ってくるので、
/// **長いものから順に**判定する。
HelpTopic helpTopicForRoute(String route) {
  // 認証まわり。
  if (route.startsWith('/sign-in') || route.startsWith('/reset-password')) {
    return HelpTopic.signIn;
  }
  if (route.startsWith('/sign-up') || route.startsWith('/verify-email')) {
    return HelpTopic.account;
  }

  // 共有リンクを開いた人は、受け取る側の説明へ。
  if (route.startsWith('/s/')) return HelpTopic.shareLink;

  // サイト管理は、下位の画面もまとめて 1 節にまとめてある。
  if (route.startsWith('/admin')) return HelpTopic.siteAdmin;

  // リストの中の画面。**長いパスから先に見る。**
  if (route.startsWith('/lists/')) {
    if (route.endsWith('/members')) return HelpTopic.members;
    if (route.endsWith('/join-requests')) return HelpTopic.joinRequest;
    if (route.endsWith('/settings')) return HelpTopic.listSettings;
    if (route.endsWith('/add') || route.endsWith('/edit')) {
      return HelpTopic.itemForm;
    }
    if (route.contains('/items/')) return HelpTopic.item;
    return HelpTopic.list;
  }

  return switch (route) {
    '/' => HelpTopic.home,
    '/notifications' => HelpTopic.notifications,
    '/settings' => HelpTopic.settings,
    '/my-requests' => HelpTopic.myRequests,
    '/request-list' => HelpTopic.listRequest,
    // 知らない画面でも、押せば使い方の先頭へは行ける。
    _ => HelpTopic.gettingStarted,
  };
}
