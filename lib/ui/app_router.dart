/// 画面遷移（仕様書 14.3）
///
/// go_router を使い、Web の URL がそのまま画面を表すようにする。
/// 共有 URL・招待 URL はここで定義したパスがそのまま外部に渡る。
///
/// 未ログインで共有 URL・招待 URL を開いた場合は、内容を一切表示せずに
/// ログイン画面へ送り、完了後に元の URL へ戻す（3.1.1）。
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/permissions.dart';
import '../domain/role.dart';
import 'routes.dart';
import 'screens/screens.dart';
import 'shell/app_shell.dart';

/// 認証の状態。リダイレクト判定に必要な最小限だけを持つ。
class AuthState {
  const AuthState({
    required this.isSignedIn,
    required this.isEmailVerified,
    required this.isSiteAdmin,
    this.unreadNotificationCount = 0,
  });

  /// 未ログイン。
  const AuthState.signedOut()
    : isSignedIn = false,
      isEmailVerified = false,
      isSiteAdmin = false,
      unreadNotificationCount = 0;

  final bool isSignedIn;

  /// メール確認が済んでいるか（3.1）。
  ///
  /// Google 連携でのログインは常に true として扱う。
  final bool isEmailVerified;

  /// Auth のカスタムクレーム由来（13.5）。
  final bool isSiteAdmin;

  final int unreadNotificationCount;

  /// アプリを普通に使える状態か。
  bool get canUseApp => isSignedIn && isEmailVerified;
}

/// ログインしていなくても開ける画面。
const _publicRoutes = <String>{
  AppRoutes.signIn,
  AppRoutes.signUp,
  AppRoutes.resetPassword,
};

/// [GoRouter] を組み立てる。
///
/// [authListenable] を渡すと、認証状態が変わったときにリダイレクトが
/// 再評価される。
GoRouter buildAppRouter({
  required AuthState Function() readAuthState,
  Listenable? authListenable,
  String initialLocation = AppRoutes.home,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: authListenable,
    redirect: (context, state) =>
        _redirect(readAuthState(), state.matchedLocation, state.uri),
    errorBuilder: (context, state) =>
        NotFoundScreen(location: state.uri.toString()),
    routes: [
      // --- 認証（シェルの外側。ナビゲーションを出さない） ---
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) => SignInScreen(
          redirect: state.uri.queryParameters[AppRoutes.redirectQueryParam],
        ),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        builder: (context, state) => SignUpScreen(
          redirect: state.uri.queryParameters[AppRoutes.redirectQueryParam],
        ),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        builder: (context, state) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        builder: (context, state) => const ResetPasswordScreen(),
      ),

      // 項目の追加・編集は、ナビゲーションを出さない全画面のフォームにする
      // （仕様書 14.4）。上部バーが二重にならないよう ShellRoute の外に置く。
      GoRoute(
        path: AppRoutes.addItemPattern,
        builder: (context, state) =>
            ItemFormScreen(listId: state.pathParameters['listId']!),
      ),
      GoRoute(
        path: AppRoutes.editItemPattern,
        builder: (context, state) => ItemFormScreen(
          listId: state.pathParameters['listId']!,
          itemId: state.pathParameters['itemId']!,
        ),
      ),

      // --- ナビゲーションを備えた画面 ---
      ShellRoute(
        builder: (context, state, child) {
          final auth = readAuthState();
          return AppShell(
            currentRoute: state.matchedLocation,
            onNavigate: (route) => context.go(route),
            isSiteAdmin: auth.isSiteAdmin,
            unreadNotificationCount: auth.unreadNotificationCount,
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: AppRoutes.notifications,
            builder: (context, state) => const NotificationsScreen(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: AppRoutes.myRequests,
            builder: (context, state) => const MyRequestsScreen(),
          ),
          GoRoute(
            path: AppRoutes.requestList,
            builder: (context, state) => const RequestListScreen(),
          ),

          // --- リスト ---
          GoRoute(
            path: AppRoutes.listPattern,
            builder: (context, state) =>
                ListDetailScreen(listId: state.pathParameters['listId']!),
          ),
          GoRoute(
            path: AppRoutes.itemPattern,
            builder: (context, state) => ItemDetailScreen(
              listId: state.pathParameters['listId']!,
              itemId: state.pathParameters['itemId']!,
            ),
          ),

          // --- リスト管理 ---
          GoRoute(
            path: AppRoutes.listMembersPattern,
            builder: (context, state) =>
                ListMembersScreen(listId: state.pathParameters['listId']!),
          ),
          GoRoute(
            path: AppRoutes.listJoinRequestsPattern,
            builder: (context, state) =>
                ListJoinRequestsScreen(listId: state.pathParameters['listId']!),
          ),
          GoRoute(
            path: AppRoutes.listSettingsPattern,
            builder: (context, state) =>
                ListSettingsScreen(listId: state.pathParameters['listId']!),
          ),

          // --- 招待の受諾 ---
          GoRoute(
            path: AppRoutes.shareLinkPattern,
            builder: (context, state) =>
                ShareLinkScreen(linkId: state.pathParameters['linkId']!),
          ),

          // --- サイト管理 ---
          GoRoute(
            path: AppRoutes.siteAdmin,
            builder: (context, state) => const SiteAdminHomeScreen(),
            routes: [
              GoRoute(
                path: 'list-requests',
                builder: (context, state) =>
                    const SiteAdminListRequestsScreen(),
              ),
              GoRoute(
                path: 'lists',
                builder: (context, state) => const SiteAdminListsScreen(),
              ),
              GoRoute(
                path: 'users',
                builder: (context, state) => const SiteAdminUsersScreen(),
              ),
              GoRoute(
                path: 'settings',
                builder: (context, state) => const SiteAdminSettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// リダイレクトの判定（3.1.1 / 14.3）。
///
/// 純粋関数として切り出してあるので、ウィジェットを組まずにテストできる。
String? redirectFor(AuthState auth, String location, Uri uri) =>
    _redirect(auth, location, uri);

String? _redirect(AuthState auth, String location, Uri uri) {
  final isPublic = _publicRoutes.contains(location);

  // 未ログイン：内容を一切見せず、戻り先を持たせてログインへ送る（3.1.1）。
  if (!auth.isSignedIn) {
    if (isPublic) return null;
    return AppRoutes.signInWithRedirect(uri.toString());
  }

  // ログイン済みだがメール未確認：確認画面から出さない（3.1）。
  if (!auth.isEmailVerified) {
    return location == AppRoutes.verifyEmail ? null : AppRoutes.verifyEmail;
  }

  // 確認済みの人が認証画面に留まる理由はないので、戻り先へ送る。
  if (isPublic || location == AppRoutes.verifyEmail) {
    return AppRoutes.resolveRedirect(
      uri.queryParameters[AppRoutes.redirectQueryParam],
    );
  }

  // サイト管理はサイト管理者のみ（14.5）。
  // 画面上の出し分けだけでなく、URL の直接入力も塞ぐ。
  // **判定は domain/permissions.dart を通す。** 以前はここに
  // 直接書いており、テストされている canAccessSiteAdmin は
  // 本番から呼ばれていなかった（監査 S8・第2回）。
  if (location.startsWith(AppRoutes.siteAdmin) &&
      !Permissions.canAccessSiteAdmin(
        ListAccess(isSiteAdmin: auth.isSiteAdmin, role: null),
      )) {
    return AppRoutes.home;
  }

  return null;
}
