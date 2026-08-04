/// ルーティングのリダイレクト判定のテスト（仕様書 3.1 / 3.1.1 / 14.5）
///
/// 未ログインで共有 URL を開いたときに内容が漏れないこと、
/// サイト管理画面に URL 直打ちで入れないことを検証する。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/ui/app_router.dart';
import 'package:music_list_app/ui/routes.dart';

void main() {
  const signedOut = AuthState.signedOut();
  const unverified = AuthState(
    isSignedIn: true,
    isEmailVerified: false,
    isSiteAdmin: false,
  );
  const member = AuthState(
    isSignedIn: true,
    isEmailVerified: true,
    isSiteAdmin: false,
  );
  const siteAdmin = AuthState(
    isSignedIn: true,
    isEmailVerified: true,
    isSiteAdmin: true,
  );

  String? redirect(AuthState auth, String location) =>
      redirectFor(auth, location, Uri.parse(location));

  group('未ログイン（3.1.1）', () {
    test('共有 URL を開いたらログインへ送り、戻り先を持たせる', () {
      final result = redirect(signedOut, '/lists/abc123');
      expect(result, isNotNull);
      expect(result, startsWith(AppRoutes.signIn));

      final query = Uri.parse(result!).queryParameters;
      expect(query[AppRoutes.redirectQueryParam], '/lists/abc123');
    });

    test('招待 URL でも同じ扱い', () {
      final result = redirect(signedOut, '/invite/xyz');
      final query = Uri.parse(result!).queryParameters;
      expect(query[AppRoutes.redirectQueryParam], '/invite/xyz');
    });

    test('ログイン画面自体はそのまま開ける', () {
      expect(redirect(signedOut, AppRoutes.signIn), isNull);
      expect(redirect(signedOut, AppRoutes.signUp), isNull);
      expect(redirect(signedOut, AppRoutes.resetPassword), isNull);
    });

    test('ホームもログインを求める', () {
      // リスト名すら見せない（3.1.1）。
      expect(redirect(signedOut, AppRoutes.home), AppRoutes.signIn);
    });
  });

  group('メール未確認（3.1）', () {
    test('確認画面から出られない', () {
      expect(redirect(unverified, AppRoutes.home), AppRoutes.verifyEmail);
      expect(redirect(unverified, '/lists/abc'), AppRoutes.verifyEmail);
      expect(redirect(unverified, AppRoutes.settings), AppRoutes.verifyEmail);
    });

    test('確認画面自体はとどまれる', () {
      expect(redirect(unverified, AppRoutes.verifyEmail), isNull);
    });
  });

  group('ログイン後の戻り先（3.1.1）', () {
    test('戻り先が指定されていればそこへ送る', () {
      final result = redirectFor(
        member,
        AppRoutes.signIn,
        Uri.parse('/sign-in?redirect=%2Flists%2Fabc123'),
      );
      expect(result, '/lists/abc123');
    });

    test('戻り先がなければホームへ', () {
      expect(redirect(member, AppRoutes.signIn), AppRoutes.home);
    });

    test('外部サイトへは飛ばさない', () {
      // オープンリダイレクトを塞ぐ。
      expect(AppRoutes.resolveRedirect('https://example.com'), AppRoutes.home);
      expect(AppRoutes.resolveRedirect('//example.com'), AppRoutes.home);
      expect(AppRoutes.resolveRedirect('/lists/abc'), '/lists/abc');
    });
  });

  group('サイト管理（14.5）', () {
    test('サイト管理者でなければ URL 直打ちでも入れない', () {
      expect(redirect(member, AppRoutes.siteAdmin), AppRoutes.home);
      expect(redirect(member, AppRoutes.siteAdminUsers), AppRoutes.home);
    });

    test('サイト管理者は入れる', () {
      expect(redirect(siteAdmin, AppRoutes.siteAdmin), isNull);
      expect(redirect(siteAdmin, AppRoutes.siteAdminUsers), isNull);
    });
  });

  group('通常の画面', () {
    test('メンバーはそのまま開ける', () {
      expect(redirect(member, AppRoutes.home), isNull);
      expect(redirect(member, '/lists/abc123'), isNull);
      expect(redirect(member, AppRoutes.settings), isNull);
      expect(redirect(member, AppRoutes.myRequests), isNull);
    });
  });

  group('パスの組み立て', () {
    test('リストと項目のパス', () {
      expect(AppRoutes.list('abc'), '/lists/abc');
      expect(AppRoutes.item('abc', 'i1'), '/lists/abc/items/i1');
      expect(AppRoutes.editItem('abc', 'i1'), '/lists/abc/items/i1/edit');
      expect(AppRoutes.addItem('abc'), '/lists/abc/add');
    });

    test('ホームへの戻り先はクエリを付けない', () {
      expect(AppRoutes.signInWithRedirect(AppRoutes.home), AppRoutes.signIn);
      expect(AppRoutes.signInWithRedirect(''), AppRoutes.signIn);
    });
  });
}
