/// 認証（仕様書 3.1 / 3.2 / 3.5）
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../domain/apple_sign_in.dart';
import '../../domain/display_name.dart';
import '../../domain/signup_locale.dart';
import '../firestore_paths.dart';
import '../models/app_user.dart';

/// 認証まわりの操作。
class AuthRepository {
  AuthRepository(this._auth, this._db);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  /// `GoogleSignIn.instance.initialize()` を覚えておく場所。
  ///
  /// **v7 の `initialize()` は「ちょうど 1 回だけ呼ぶこと」と決まっている**
  /// （2 回以上呼んだときの動きは規定されていない）。実際、呼ぶたびに
  /// プラグイン側の認証イベントを購読し直す作りなので、**ログインを
  /// やめて押し直すだけで購読が積み上がる。**
  ///
  /// このリポジトリはアプリに 1 つしか作らない（authRepositoryProvider）ので、
  /// ここに持っておけば実質アプリで 1 回になる。
  Future<void>? _googleInitialized;

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
  /// Google / Apple 連携でのログインは向こう側で確認済みのため、
  /// 常に true になる。**Apple のリレーアドレス
  /// （`@privaterelay.appleid.com`）も特別扱いしない**——この経路は
  /// そもそもメール確認の流れに入らないので、リレー宛に送ることがない
  /// （docs/MOBILE-APP-DESIGN.md 5-6）。
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// 「Apple でサインイン」を出してよい環境か
  /// （docs/MOBILE-APP-DESIGN.md 5-6）。
  ///
  /// **画面はこれだけを見ること。** 各画面が `Platform.isIOS` を書くと
  /// `dart:io` が共通コードへ漏れ、`flutter build web` が落ちる。
  /// 判定そのものは [AppleSignInPolicy] にあり、テストが本物を見る。
  static bool get isAppleSignInAvailable => AppleSignInPolicy.isAvailable(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
  );

  /// Google アカウントでログインする（docs/MOBILE-APP-DESIGN.md 5-5）。
  ///
  /// **Web とネイティブで、呼ぶ API そのものが違う。**
  ///
  /// | 環境 | 呼ぶもの |
  /// | --- | --- |
  /// | Web | `signInWithPopup`（**Web 専用 API**） |
  /// | iOS / Android | `google_sign_in` で資格情報を取り、`signInWithCredential` |
  ///
  /// 分岐は `kIsWeb` の実行時分岐にしてある。条件付き import は
  /// **Web 専用の `import` 文が要るときだけ**の手段で、ここでは要らない。
  ///
  /// **利用者が選択をやめたときは、何もせずに戻る。** 例外にすると
  /// シートを閉じただけで画面に赤いメッセージが出る——「やめた」は
  /// 誤りではない。
  Future<void> signInWithGoogle({required String languageCode}) async {
    final UserCredential credential;
    if (kIsWeb) {
      // **Web の経路は 2026-08-16 以前のまま。** ここを触ると、
      // いま動いている Web のログインを巻き添えにする。
      credential = await _auth.signInWithPopup(GoogleAuthProvider());
    } else {
      final googleCredential = await _googleCredential();
      if (googleCredential == null) return; // やめた
      credential = await _auth.signInWithCredential(googleCredential);
    }
    await _ensureUserDocument(credential.user, languageCode: languageCode);
  }

  /// ネイティブで Google の資格情報を取る（Web はポップアップ側で完結する）。
  ///
  /// 利用者が選択をやめたときは null を返す。**失敗として扱わない。**
  ///
  /// **`google_sign_in` は v7 系。** v6 とは API が完全に別物で、
  /// v6 の `GoogleSignIn().signIn()` はここでは存在しない。
  /// v7 の `authentication` が返すのは `idToken` だけ
  /// （`accessToken` は別経路）。Firebase の資格情報には idToken で足りる。
  Future<AuthCredential?> _googleCredential() async {
    final signIn = GoogleSignIn.instance;
    await _initializeGoogle(signIn);
    try {
      final account = await signIn.authenticate();
      return GoogleAuthProvider.credential(
        idToken: account.authentication.idToken,
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  /// `google_sign_in` の初期化を、**アプリで 1 回だけ**行う。
  ///
  /// 何を読むかは端末側の設定にある——iOS は `Info.plist` の `GIDClientID`、
  /// Android は `google-services.json`。だから引数は要らない。
  ///
  /// **失敗したら覚えない。** 覚えたままにすると、たまたま通信が悪かった
  /// 1 回のせいで、**以後ずっと Google ログインが使えなくなる。**
  Future<void> _initializeGoogle(GoogleSignIn signIn) async {
    final pending = _googleInitialized ??= signIn.initialize();
    try {
      await pending;
    } catch (_) {
      _googleInitialized = null;
      rethrow;
    }
  }

  /// Apple アカウントでログインする（docs/MOBILE-APP-DESIGN.md 5-6）。
  ///
  /// **呼ぶのは iOS だけ**（[isAppleSignInAvailable]）。
  ///
  /// **Apple が名前を渡すのは初回だけ。** 2 回目以降は必ず空で返るので、
  /// `user.displayName` を当てにできない。ここで受け取った名前を
  /// そのまま [_ensureUserDocument] に渡す——users ドキュメントを作るのは
  /// 初回の 1 回だけなので、**名前が来る回と、名前を保存する回が一致する。**
  ///
  /// 利用者がやめたときは、Google と同じく何もせずに戻る。
  Future<void> signInWithApple({required String languageCode}) async {
    final apple = await _appleCredential();
    if (apple == null) return; // やめた
    final credential = await _auth.signInWithCredential(apple.credential);
    await _ensureUserDocument(
      credential.user,
      displayName: apple.name,
      languageCode: languageCode,
    );
  }

  /// Apple の資格情報と、**初回だけ渡ってくる名前**を取る。
  ///
  /// 利用者がやめたときは null（Google と同じく失敗にしない）。
  Future<({AuthCredential credential, String name})?> _appleCredential() async {
    // **nonce は「生のまま Firebase へ、SHA-256 を Apple へ」渡す。**
    // 逆にすると Firebase の検証が失敗して `invalid-credential` になる。
    // 規則は lib/domain/apple_sign_in.dart にあり、テストが本物を見る。
    final rawNonce = AppleNonce.random();
    final AuthorizationCredentialAppleID apple;
    try {
      apple = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: AppleNonce.hashed(rawNonce),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      rethrow;
    }

    final name = [apple.givenName, apple.familyName]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' ');
    return (
      credential: OAuthProvider('apple.com').credential(
        idToken: apple.identityToken,
        rawNonce: rawNonce,
      ),
      name: name,
    );
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
  /// [displayName] は登録画面で入力された名前、または
  /// **Apple が初回だけ渡してくる名前**。指定がなければ Auth 側の
  /// 表示名を使う（Google 連携のとき）。
  ///
  /// **表示名に一意の制約は無い**（firestore.rules の `users/{userId}` は
  /// 重複を見ておらず、予約用のコレクションも Callable も無い）。
  /// だから連携ログインでも「名前を確認する画面」へ寄り道させず、
  /// [DisplayNameResolver.initial] の優先順位で黙って決めてよい。
  ///
  /// **公開されるぶんと私的なぶんの 2 つを作る**（2026-08-11）。
  /// 片方だけ書くと、表示名はあるのに表示言語が無い（またはその逆）に
  /// なるため、まとめて 1 回で書く。
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
      photoUrl: user.photoURL,
      isWithdrawn: false,
    );
    // メールアドレスはサーバーが書く（ルールで本人には書かせない）。
    // ここで作るのは、本人が持つべき設定だけ。
    final private = UserPrivate(
      // **表示言語は、いま使っている言語で作る（仕様書 2 章）。**
      // ここを 'ja' 固定にしていたため、英語で登録した人も
      // 登録し終えた瞬間に日本語へ切り替わっていた（監査 第3回）。
      // 確認メールだけは使っている言語で送っていたので、
      // メールは英語・画面は日本語という食い違いになっていた。
      // 規則は domain/signup_locale.dart に置き、回帰テストが本物を見る。
      locale: SignupLocalePolicy.localeFor(languageCode),
      notificationSettings: NotificationSettings.defaults(),
    );

    await (_db.batch()
          ..set(ref, appUser.toCreateMap())
          ..set(
            _db.doc(FirestorePaths.userPrivate(user.uid)),
            private.toCreateMap(),
          ))
        .commit();
  }
}
