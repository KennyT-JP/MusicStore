/// Firebase エミュレータへの接続（仕様書 12.6）
///
/// クラウド上の Firebase プロジェクトを作らなくても、ローカルのエミュレータで
/// アプリを動かせるようにする。検証環境のデータにも触れないため、
/// 気兼ねなく試せる。
///
/// ```sh
/// # 別のターミナルでエミュレータを起動しておく
/// firebase emulators:start --project demo-musiclist
///
/// # アプリをエミュレータに接続して起動
/// flutter run -d chrome --dart-define=USE_EMULATOR=true
/// ```
///
/// 本番環境（`APP_ENV=prod`）では、この指定があっても**接続しない**。
/// 本番のつもりでエミュレータに繋いでいた、という取り違えを防ぐため。
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'app_environment.dart';

/// エミュレータのホスト。
///
/// Android の実機・エミュレータから繋ぐ場合は `10.0.2.2` などに変える必要がある。
const String kEmulatorHost = '127.0.0.1';

/// firebase.json の emulators セクションと揃えること。
const int kAuthEmulatorPort = 9099;
const int kFirestoreEmulatorPort = 8080;
const int kStorageEmulatorPort = 9199;
const int kFunctionsEmulatorPort = 5001;

/// エミュレータに接続する設定になっているか。
bool get useFirebaseEmulators {
  const requested = bool.fromEnvironment('USE_EMULATOR');
  // 本番環境ではエミュレータに繋がない。
  if (AppEnvironment.current.isProduction) return false;
  return requested;
}

/// 各サービスをエミュレータに向ける。
///
/// `Firebase.initializeApp()` のあと、最初の読み書きより前に呼ぶ。
Future<void> connectToFirebaseEmulators() async {
  await FirebaseAuth.instance.useAuthEmulator(
    kEmulatorHost,
    kAuthEmulatorPort,
  );
  FirebaseFirestore.instance.useFirestoreEmulator(
    kEmulatorHost,
    kFirestoreEmulatorPort,
  );
  FirebaseStorage.instance.useStorageEmulator(
    kEmulatorHost,
    kStorageEmulatorPort,
  );
  FirebaseFunctions.instance.useFunctionsEmulator(
    kEmulatorHost,
    kFunctionsEmulatorPort,
  );
}
