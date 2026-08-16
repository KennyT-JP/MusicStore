/// モバイルでのログイン（docs/MOBILE-APP-DESIGN.md 5-5 / 5-6）
///
/// **`signInWithPopup` は Web 専用の API。** ネイティブでは動かないので、
/// `google_sign_in` で資格情報だけ取って `signInWithCredential` へ渡す。
/// Apple も同じ形で、違うのは nonce の扱いと名前の出どころだけ。
///
/// **ここは本物の [AuthRepository] を動かす。**
/// プラグインの入口（`GoogleSignInPlatform` / `SignInWithApplePlatform`）だけを
/// 差し替えるので、**実機に出す前に、実際に投げている値まで確かめられる。**
///
/// | 守るもの | 破れると |
/// | --- | --- |
/// | ネイティブは `signInWithCredential` を通る | **ログインできない**（`signInWithPopup` が Web 専用） |
/// | キャンセルを失敗にしない | シートを閉じただけで**画面に赤いメッセージ**が出る |
/// | Apple に SHA-256、Firebase に生の nonce | `invalid-credential`。**実機でしか気づけない** |
/// | Apple の名前は初回に受け取ったものを使う | 2 回目以降は必ず空。取り逃すと名前欄が空のまま |
library;

import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:mocktail/mocktail.dart';
import 'package:music_list_app/data/repositories/auth_repository.dart';
import 'package:sign_in_with_apple_platform_interface/sign_in_with_apple_platform_interface.dart';

// ---------------------------------------------------------------------------
// Firebase 側の作りもの
// ---------------------------------------------------------------------------

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockDb extends Mock implements FirebaseFirestore {}

class _MockUserCredential extends Mock implements UserCredential {}

class _MockUser extends Mock implements User {}

// **`DocumentReference` と `DocumentSnapshot` は sealed。**
// 素直には模擬できないので、ここだけ解析の警告を外す
// （test/domain/user_privacy_test.dart は模擬を避けて Map を直に渡す形に
// したが、こちらは「users を作るところまで通す」のが目的なので、
// 本物の [AuthRepository] に読ませる相手が要る）。
// **本番の型ではなく、テストの中だけの話**なので影響は閉じている。
// ignore: subtype_of_sealed_class
class _MockDocRef extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class _MockSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

// ---------------------------------------------------------------------------
// Google のプラグインの入口
// ---------------------------------------------------------------------------

/// `GoogleSignInPlatform` の差し替え。
///
/// **implements ではなく extends。** `PlatformInterface` の持ち主確認
/// （token）を通すには、素直に継承するのがいちばん簡単。
///
/// **使わないはずのメソッドは投げるままにしてある。** 本番が余計なものを
/// 呼び始めたら、ここで気づける。
class _FakeGoogleSignInPlatform extends GoogleSignInPlatform {
  _FakeGoogleSignInPlatform({this.result, this.error, this.initError});

  /// `authenticate()` が返すもの。
  final AuthenticationResults? result;

  /// `authenticate()` が投げるもの（キャンセルの再現に使う）。
  final GoogleSignInException? error;

  /// `init()` が投げるもの（初期化の失敗の再現に使う）。
  final Object? initError;

  int initCalls = 0;
  int authenticateCalls = 0;

  @override
  Future<void> init(InitParameters params) async {
    initCalls++;
    final failure = initError;
    if (failure != null) throw failure;
  }

  @override
  Future<AuthenticationResults> authenticate(AuthenticateParameters params) {
    authenticateCalls++;
    final failure = error;
    if (failure != null) return Future<AuthenticationResults>.error(failure);
    return Future.value(result!);
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) => throw UnimplementedError('本番が呼ぶはずのないメソッド');

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) => throw UnimplementedError('本番が呼ぶはずのないメソッド');

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) => throw UnimplementedError('本番が呼ぶはずのないメソッド');

  @override
  Future<void> signOut(SignOutParams params) async {}

  @override
  Future<void> disconnect(DisconnectParams params) async {}
}

// ---------------------------------------------------------------------------
// Apple のプラグインの入口
// ---------------------------------------------------------------------------

class _FakeApplePlatform extends SignInWithApplePlatform {
  _FakeApplePlatform({this.credential, this.error});

  final AuthorizationCredentialAppleID? credential;
  final SignInWithAppleAuthorizationException? error;

  /// **Apple へ渡された nonce**（SHA-256 のはず）。
  String? receivedNonce;
  int calls = 0;

  @override
  Future<AuthorizationCredentialAppleID> getAppleIDCredential({
    required List<AppleIDAuthorizationScopes> scopes,
    WebAuthenticationOptions? webAuthenticationOptions,
    String? nonce,
    String? state,
  }) {
    calls++;
    receivedNonce = nonce;
    final failure = error;
    if (failure != null) {
      return Future<AuthorizationCredentialAppleID>.error(failure);
    }
    return Future.value(credential!);
  }
}

void main() {
  late _MockAuth auth;
  late _MockDb db;
  late AuthRepository repo;

  setUpAll(() {
    // mocktail は any() を使う引数に既定値が要る。
    registerFallbackValue(GoogleAuthProvider.credential(idToken: 'fallback'));
  });

  /// ログインが成功したときの Firebase 側を組む。
  ///
  /// users ドキュメントは**すでにある**ことにして、書き込みまで作り込まない
  /// （ここで見たいのは「何を Firebase に渡したか」まで）。
  void givenSignInSucceeds() {
    final user = _MockUser();
    when(() => user.uid).thenReturn('uid-1');
    when(() => user.displayName).thenReturn(null);
    when(() => user.email).thenReturn('someone@example.com');
    when(() => user.photoURL).thenReturn(null);

    final credential = _MockUserCredential();
    when(() => credential.user).thenReturn(user);
    when(
      () => auth.signInWithCredential(any()),
    ).thenAnswer((_) async => credential);

    final snapshot = _MockSnapshot();
    when(() => snapshot.exists).thenReturn(true);
    final ref = _MockDocRef();
    when(ref.get).thenAnswer((_) async => snapshot);
    when(() => db.doc(any())).thenReturn(ref);
  }

  /// `_auth.signInWithCredential` に実際に渡ったものを取り出す。
  OAuthCredential capturedCredential() {
    final captured = verify(
      () => auth.signInWithCredential(captureAny()),
    ).captured;
    expect(captured, hasLength(1));
    return captured.single as OAuthCredential;
  }

  setUp(() {
    auth = _MockAuth();
    db = _MockDb();
    repo = AuthRepository(auth, db);
  });

  group('Google（ネイティブ）', () {
    test('資格情報を取ってから signInWithCredential へ渡す', () async {
      final platform = _FakeGoogleSignInPlatform(
        result: const AuthenticationResults(
          user: GoogleSignInUserData(id: 'g-1', email: 'g@example.com'),
          authenticationTokens: AuthenticationTokenData(
            idToken: 'google-id-token',
          ),
        ),
      );
      GoogleSignInPlatform.instance = platform;
      givenSignInSucceeds();

      await repo.signInWithGoogle(languageCode: 'ja');

      // **v7 の作法。** initialize してから authenticate。
      expect(platform.initCalls, 1);
      expect(platform.authenticateCalls, 1);

      final credential = capturedCredential();
      expect(credential.providerId, 'google.com');
      // v7 の `authentication` が返すのは idToken だけ。それで足りる。
      expect(credential.idToken, 'google-id-token');
    });

    test('initialize は、何度押しても 1 回だけ', () async {
      // **v7 の `initialize()` は「ちょうど 1 回だけ呼ぶこと」と決まっている。**
      // 呼ぶたびにプラグイン側の認証イベントを購読し直す作りなので、
      // 毎回呼ぶと**押すたびに購読が積み上がる。**
      final platform = _FakeGoogleSignInPlatform(
        result: const AuthenticationResults(
          user: GoogleSignInUserData(id: 'g-1', email: 'g@example.com'),
          authenticationTokens: AuthenticationTokenData(idToken: 'id-token'),
        ),
      );
      GoogleSignInPlatform.instance = platform;
      givenSignInSucceeds();

      await repo.signInWithGoogle(languageCode: 'ja');
      await repo.signInWithGoogle(languageCode: 'ja');
      await repo.signInWithGoogle(languageCode: 'ja');

      expect(platform.initCalls, 1);
      expect(platform.authenticateCalls, 3);
    });

    test('initialize に失敗したら、次に押したときやり直す', () async {
      // **失敗を覚え込むと、たまたま通信が悪かった 1 回のせいで
      // 以後ずっと Google ログインが使えなくなる。**
      final failing = _FakeGoogleSignInPlatform(initError: StateError('だめ'));
      GoogleSignInPlatform.instance = failing;

      await expectLater(
        repo.signInWithGoogle(languageCode: 'ja'),
        throwsA(isA<StateError>()),
      );

      final working = _FakeGoogleSignInPlatform(
        result: const AuthenticationResults(
          user: GoogleSignInUserData(id: 'g-1', email: 'g@example.com'),
          authenticationTokens: AuthenticationTokenData(idToken: 'id-token'),
        ),
      );
      GoogleSignInPlatform.instance = working;
      givenSignInSucceeds();

      await repo.signInWithGoogle(languageCode: 'ja');
      expect(working.initCalls, 1, reason: '2 度目の initialize をあきらめています');
      expect(working.authenticateCalls, 1);
    });

    test('やめたときは、失敗にしない（何事もなく戻る）', () async {
      // **シートを閉じただけで赤いメッセージが出るのを防ぐ。**
      // 画面は例外を捕まえて ErrorMessage を出すので、ここで投げると
      // 「やめた」が「エラー」になる。
      GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform(
        error: const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
        ),
      );

      await expectLater(repo.signInWithGoogle(languageCode: 'ja'), completes);

      // サインインも users の作成も、始まってすらいないこと。
      verifyNever(() => auth.signInWithCredential(any()));
      verifyZeroInteractions(db);
    });

    test('やめた以外の失敗は、握り潰さずに投げる', () async {
      // **「やめた」だけを黙らせる。** 通信の失敗まで黙ると、
      // 押しても何も起きないボタンになり、原因も分からない。
      GoogleSignInPlatform.instance = _FakeGoogleSignInPlatform(
        error: const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
        ),
      );

      await expectLater(
        repo.signInWithGoogle(languageCode: 'ja'),
        throwsA(isA<GoogleSignInException>()),
      );
    });
  });

  group('Apple', () {
    AuthorizationCredentialAppleID appleCredential({
      String? givenName,
      String? familyName,
    }) => AuthorizationCredentialAppleID(
      userIdentifier: 'apple-1',
      givenName: givenName,
      familyName: familyName,
      authorizationCode: 'code',
      email: 'a@privaterelay.appleid.com',
      identityToken: 'apple-id-token',
      state: null,
    );

    test('Apple には SHA-256、Firebase には生の nonce を渡す', () async {
      // **取り違えると `invalid-credential` になる。**
      // Apple は受け取ったハッシュを ID トークンに載せて返し、
      // Firebase は生の値を自分でハッシュして突き合わせる。
      final platform = _FakeApplePlatform(credential: appleCredential());
      SignInWithApplePlatform.instance = platform;
      givenSignInSucceeds();

      await repo.signInWithApple(languageCode: 'ja');

      final rawNonce = capturedCredential().rawNonce;
      final sentToApple = platform.receivedNonce;

      expect(rawNonce, isNotNull, reason: 'Firebase に rawNonce を渡していません');
      expect(sentToApple, isNotNull, reason: 'Apple に nonce を渡していません');

      // **同じ値を両方へ渡していないこと**（これがいちばんやりがちな取り違え）。
      expect(sentToApple, isNot(rawNonce));
      // Apple 側は、生の nonce の SHA-256 そのもの。
      expect(sentToApple, sha256.convert(utf8.encode(rawNonce!)).toString());
      // 生のほうがハッシュでないこと（左右を入れ替えていない証拠）。
      expect(rawNonce.length, 32);
    });

    test('Firebase へは apple.com の資格情報として渡す', () async {
      SignInWithApplePlatform.instance = _FakeApplePlatform(
        credential: appleCredential(),
      );
      givenSignInSucceeds();

      await repo.signInWithApple(languageCode: 'ja');

      final credential = capturedCredential();
      expect(credential.providerId, 'apple.com');
      expect(credential.idToken, 'apple-id-token');
    });

    test('やめたときは、失敗にしない（何事もなく戻る）', () async {
      SignInWithApplePlatform.instance = _FakeApplePlatform(
        error: const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.canceled,
          message: 'canceled',
        ),
      );

      await expectLater(repo.signInWithApple(languageCode: 'ja'), completes);

      verifyNever(() => auth.signInWithCredential(any()));
      verifyZeroInteractions(db);
    });

    test('やめた以外の失敗は、握り潰さずに投げる', () async {
      SignInWithApplePlatform.instance = _FakeApplePlatform(
        error: const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.failed,
          message: 'failed',
        ),
      );

      await expectLater(
        repo.signInWithApple(languageCode: 'ja'),
        throwsA(isA<SignInWithAppleAuthorizationException>()),
      );
    });

    test('初回に来た名前を、users を作るときに使う', () async {
      // **Apple が名前を渡すのは初回だけ。** 2 回目以降は必ず空で返るので、
      // `user.displayName` を当てにできない。users ドキュメントを作るのも
      // 初回の 1 回だけなので、ここで渡し損ねると取り返しがつかない。
      SignInWithApplePlatform.instance = _FakeApplePlatform(
        credential: appleCredential(givenName: '花子', familyName: '音源'),
      );

      final user = _MockUser();
      when(() => user.uid).thenReturn('uid-1');
      // Apple 連携では Firebase 側の表示名は空で来る。
      when(() => user.displayName).thenReturn(null);
      when(() => user.email).thenReturn('a@privaterelay.appleid.com');
      when(() => user.photoURL).thenReturn(null);
      final credential = _MockUserCredential();
      when(() => credential.user).thenReturn(user);
      when(
        () => auth.signInWithCredential(any()),
      ).thenAnswer((_) async => credential);

      // users がまだ無い状態にして、書き込む中身を捕まえる。
      final snapshot = _MockSnapshot();
      when(() => snapshot.exists).thenReturn(false);
      final ref = _MockDocRef();
      when(ref.get).thenAnswer((_) async => snapshot);
      when(() => db.doc(any())).thenReturn(ref);

      final batch = _RecordingBatch();
      when(db.batch).thenReturn(batch);

      await repo.signInWithApple(languageCode: 'ja');

      expect(batch.committed, isTrue, reason: 'users を作っていません');
      // 並びは Apple が返す順（given → family）。**初期値でしかない**——
      // 表示名に一意の制約は無く、設定画面でいつでも変えられる。
      expect(
        batch.writes.map((w) => w['displayName']),
        contains('花子 音源'),
        reason: 'Apple が初回に渡した名前を使っていません',
      );
    });

    test('2 回目以降（名前が空）でも、ログインそのものは通る', () async {
      SignInWithApplePlatform.instance = _FakeApplePlatform(
        credential: appleCredential(), // 名前は来ない
      );
      givenSignInSucceeds();

      await expectLater(repo.signInWithApple(languageCode: 'ja'), completes);
      verify(() => auth.signInWithCredential(any())).called(1);
    });
  });

  group('Web の経路を変えていない', () {
    // `kIsWeb` は Dart VM の上では必ず false なので、Web の分岐そのものは
    // ここでは動かせない。**その代わり、分岐が残っていることを見る。**
    // 消えたら Web のログインが丸ごと止まる。
    test('kIsWeb のときは signInWithPopup を使う', () {
      final source = File('lib/data/repositories/auth_repository.dart')
          .readAsStringSync()
          .replaceAll('\r\n', '\n')
          .split('\n')
          .map((line) => line.replaceFirst(RegExp(r'(?<!:)//.*$'), ''))
          .join('\n');

      final branch = source.indexOf('if (kIsWeb)');
      expect(branch, isNot(-1), reason: 'Web の分岐が消えています');

      final popup = source.indexOf('signInWithPopup');
      expect(popup, isNot(-1), reason: 'Web の signInWithPopup が消えています');
      expect(
        popup,
        greaterThan(branch),
        reason: 'signInWithPopup は kIsWeb の中だけで呼ぶこと（ネイティブでは動きません）',
      );

      // ネイティブ側は google_sign_in を通ること。
      expect(source, contains('GoogleSignIn.instance'));
      expect(source, contains('signInWithCredential('));
    });
  });
}

/// 書き込む中身を覚えておく [WriteBatch]。
///
/// `set` に渡された map を並べておくだけ。commit しても何も送らない。
class _RecordingBatch extends Mock implements WriteBatch {
  final List<Map<String, dynamic>> writes = [];
  bool committed = false;

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    writes.add(data as Map<String, dynamic>);
  }

  @override
  Future<void> commit() async => committed = true;
}
