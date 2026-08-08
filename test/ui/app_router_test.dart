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

  group('共有リンク /s/ は選択画面を先に出す（3.1.1 の例外／v1.3）', () {
    test('未ログインでも開ける', () {
      // リンクを受け取った人が最初に見るのは選択肢であって、
      // ログインフォームではない。画面はリスト名を出さないので、
      // 見せても漏れるものが無い。
      expect(redirect(signedOut, '/s/abc123'), isNull);
    });

    test('choice クエリが付いていても開ける', () {
      expect(
        redirectFor(signedOut, '/s/abc123', Uri.parse('/s/abc123?choice=join')),
        isNull,
      );
    });

    test('メール未確認でも開ける（求められるのは選んだあと）', () {
      expect(redirect(unverified, '/s/abc123'), isNull);
    });

    test('ログイン済みでも、もちろん開ける', () {
      expect(redirect(member, '/s/abc123'), isNull);
    });

    test('リスト・曲の URL は今までどおりログインを求める', () {
      // 例外は /s/ だけ。/lists/ はリスト名が画面に出るため見せない。
      expect(redirect(signedOut, '/lists/abc123'), isNotNull);
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

    test('戻り先を持っていたら、確認画面にも持ち回す', () {
      // 以前はここで redirect クエリを捨てており、共有リンクから
      // 登録した人が、確認を終えるとホームに置き去りになっていた。
      final result = redirectFor(
        unverified,
        AppRoutes.signIn,
        Uri.parse('/sign-in?redirect=%2Fs%2Fabc%3Fchoice%3Djoin'),
      );
      expect(result, isNotNull);
      expect(result, startsWith(AppRoutes.verifyEmail));
      final query = Uri.parse(result!).queryParameters;
      expect(query[AppRoutes.redirectQueryParam], '/s/abc?choice=join');
    });

    test('確認が済んだら、持ち回した戻り先へ送る', () {
      final result = redirectFor(
        member,
        AppRoutes.verifyEmail,
        Uri.parse('/verify-email?redirect=%2Fs%2Fabc%3Fchoice%3Djoin'),
      );
      expect(result, '/s/abc?choice=join');
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

    test('共有リンクに選んだほうを添えられる', () {
      expect(
        AppRoutes.shareLinkWithChoice('abc', join: true),
        '/s/abc?choice=join',
      );
      expect(
        AppRoutes.shareLinkWithChoice('abc', join: false),
        '/s/abc?choice=view',
      );
    });

    test('確認画面への戻り先つきパス', () {
      expect(AppRoutes.verifyEmailWithRedirect(null), AppRoutes.verifyEmail);
      expect(AppRoutes.verifyEmailWithRedirect(''), AppRoutes.verifyEmail);
      expect(
        AppRoutes.verifyEmailWithRedirect(AppRoutes.home),
        AppRoutes.verifyEmail,
      );
      expect(
        AppRoutes.verifyEmailWithRedirect('/s/abc?choice=join'),
        '/verify-email?redirect=%2Fs%2Fabc%3Fchoice%3Djoin',
      );
    });
  });
}
