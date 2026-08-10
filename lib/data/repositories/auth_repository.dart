/// 認証（仕様書 3.1 / 3.2 / 3.5）
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/display_name.dart';
import '../../domain/signup_locale.dart';
import '../firestore_paths.dart';
import '../models/app_user.dart';

/// 認証まわりの操作。
class AuthRepository {
  AuthRepository(this._auth, this._db);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  User? get currentUser => _auth.currentUser;

  Stream<User?> authStateChanges() => _auth.userChanges();

  /// サイト管理者かどうか（仕様書 13.5）。
  ///
  /// Auth のカスタムクレームで判定する。変更はトークンを取り直すまで
  /// 反映されないため、[refresh] を true にすると強制的に更新する。
  Future<bool> isSiteAdmin({bool refresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final token = await user.getIdTokenResult(refresh);
    return token.claims?['siteAdmin'] == true;
  }

  /// メール確認が済んでいるか（仕様書 3.1）。
  ///
  /// Google 連携でのログインは Google 側で確認済みのため、常に true になる。
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// Google アカウントでログインする。
  ///
  /// Web ではポップアップを使う。モバイル版を作るときは
  /// google_sign_in パッケージ経由に差し替える必要がある。
  Future<void> signInWithGoogle({required String languageCode}) async {
    final provider = GoogleAuthProvider();
    final credential = await _auth.signInWithPopup(provider);
    await _ensureUserDocument(credential.user, languageCode: languageCode);
  }

  /// メールアドレスとパスワードでログインする。
  Future<void> signInWithEmail(
    String email,
    String password, {
    required String languageCode,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await _ensureUserDocument(credential.user, languageCode: languageCode);
  }

  /// メールアドレスとパスワードで登録する。
  ///
  /// 登録後、確認メールを送る。確認が済むまでアプリは使えない（仕様書 3.1）。
  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
    required String languageCode,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user;
    if (user == null) return;
    if (displayName.trim().isNotEmpty) {
      await user.updateDisplayName(displayName.trim());
    }
    // **入力された名前をそのまま渡す。**
    // updateDisplayName はサーバー側を更新するだけで、手元の User の
    // displayName は reload するまで空のまま。渡さずに user から読むと、
    // 「まだ空」と判断してメールアドレスの @ より前を採用してしまう。
    await _ensureUserDocument(
      user,
      displayName: displayName,
      languageCode: languageCode,
    );

    // **メールの言語は送る直前に指定する（仕様書 2 章）。**
    // 指定しないと Firebase の既定（英語）で届く。画面が日本語なのに
    // 英語のメールが来るのは分かりにくい。判断は「いま画面に出ている
    // 言語」で行う。登録時点ではまだ利用者の設定が無いため。
    await _applyLanguage(languageCode);
    await user.sendEmailVerification();
  }

  /// 送信するメールの言語を Firebase Auth に伝える（仕様書 2 章）。
  ///
  /// 対応していない言語コードを渡すと例外になるため、扱う言語に絞る。
  /// それ以外は英語に倒す（画面の表示言語と同じ規則）。
  Future<void> _applyLanguage(String languageCode) async {
    await _auth.setLanguageCode(SignupLocalePolicy.localeFor(languageCode));
  }

  /// 確認メールを再送する（仕様書 3.1）。
  Future<void> resendVerificationEmail({required String languageCode}) async {
    await _applyLanguage(languageCode);
    await _auth.currentUser?.sendEmailVerification();
  }

  /// メール確認が済んだかを取り直す。
  Future<bool> reloadEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  /// パスワード再設定のリンクを送る（仕様書 3.1）。
  Future<void> sendPasswordResetEmail(
    String email, {
    required String languageCode,
  }) async {
    await _applyLanguage(languageCode);
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() => _auth.signOut();

  // 退会できるかの判定はサーバー側にある（仕様書 4.5）。
  //
  // 以前はここにも同じ確認があったが、退会画面は withdrawAccount を
  // 直接呼んでサーバーのエラーで判断しており、**本番からは一度も
  // 呼ばれていなかった**（監査 第2回）。
  // 「最後のサイト管理者は退会できない」は
  // functions/src/callable/site_admin.ts が守っている。

  /// users ドキュメントがなければ作る。
  ///
  /// Cloud Functions でも作成するが、Functions を用意する前でも動くように
  /// クライアント側でも用意する。すでにあれば何もしない。
  /// [displayName] は登録画面で入力された名前。
  /// 指定がなければ Auth 側の表示名を使う（Google 連携のとき）。
  Future<void> _ensureUserDocument(
    User? user, {
    String? displayName,
    required String languageCode,
  }) async {
    if (user == null) return;
    final ref = _db.doc(FirestorePaths.user(user.uid));
    final snapshot = await ref.get();
    if (snapshot.exists) return;

    final appUser = AppUser(
      uid: user.uid,
      // 優先順位は domain 側に置いてある（仕様書 3.4）。回帰テストで守る。
      displayName: DisplayNameResolver.initial(
        entered: displayName,
        authDisplayName: user.displayName,
        email: user.email,
        // 名前もメールアドレスも無いときの最後の受け皿。
        // 画面に出る文字ではなく、この人の**表示名として保存される**値。
        // 英語で使っている人に日本語の名前が付くのを避ける。
        fallback: languageCode == 'ja' ? 'ユーザー' : 'User',
      ),
      email: user.email ?? '',
      photoUrl: user.photoURL,
      // **表示言語は、いま使っている言語で作る（仕様書 2 章）。**
      // ここを 'ja' 固定にしていたため、英語で登録した人も
      // 登録し終えた瞬間に日本語へ切り替わっていた（監査 第3回）。
      // 確認メールだけは使っている言語で送っていたので、
      // メールは英語・画面は日本語という食い違いになっていた。
      // 規則は domain/signup_locale.dart に置き、回帰テストが本物を見る。
      locale: SignupLocalePolicy.localeFor(languageCode),
      isWithdrawn: false,
      notificationSettings: NotificationSettings.defaults(),
    );
    await ref.set(appUser.toCreateMap());
  }
}
