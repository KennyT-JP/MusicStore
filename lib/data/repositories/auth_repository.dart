/// 認証（仕様書 3.1 / 3.2 / 3.5）
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/display_name.dart';
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
  Future<void> signInWithGoogle() async {
    final provider = GoogleAuthProvider();
    final credential = await _auth.signInWithPopup(provider);
    await _ensureUserDocument(credential.user);
  }

  /// メールアドレスとパスワードでログインする。
  Future<void> signInWithEmail(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await _ensureUserDocument(credential.user);
  }

  /// メールアドレスとパスワードで登録する。
  ///
  /// 登録後、確認メールを送る。確認が済むまでアプリは使えない（仕様書 3.1）。
  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
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
    await _ensureUserDocument(user, displayName: displayName);
    await user.sendEmailVerification();
  }

  /// 確認メールを再送する（仕様書 3.1）。
  Future<void> resendVerificationEmail() async {
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
  Future<void> sendPasswordResetEmail(String email) async {
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
  Future<void> _ensureUserDocument(User? user, {String? displayName}) async {
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
        fallback: 'ユーザー',
      ),
      email: user.email ?? '',
      photoUrl: user.photoURL,
      locale: 'ja',
      isWithdrawn: false,
      notificationSettings: NotificationSettings.defaults(),
    );
    await ref.set(appUser.toCreateMap());
  }
}
