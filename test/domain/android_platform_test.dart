/// Android のプラットフォーム設定の見張り（docs/MOBILE-APP-DESIGN.md 5-9）
///
/// **ここで守るものは、どれも「壊れても静かに壊れる」ものばかり。**
///
/// | 破れると | 何が起きるか |
/// | --- | --- |
/// | デバッグ署名フォールバックの復活 | 鍵の無い環境の release が**エラーも警告も出さずに**デバッグ鍵の成果物を出す |
/// | `allowBackup` の消滅 | Firebase Auth のリフレッシュトークンが Google ドライブへ複製され、**別端末の復元でログイン状態ごと持ち込まれる** |
/// | `FirebaseInitProvider` の復活 | 環境を分けたビルドが `[core/duplicate-app]` で**起動画面のまま無言で停止** |
/// | `applicationId` と `namespace` の同一化 | 検証環境の Android アプリが作れなくなる（Google ログインの OAuth クライアントが「パッケージ名＋署名鍵の SHA-1」でプロジェクトをまたいで一意） |
/// | App Links の `autoVerify` の消滅 | 共有リンクが**黙ってブラウザで開く**。エラーは出ない |
///
/// **どれもビルドは通る。** 気づく手段がここしかない。
///
/// **コメントを取り除いてから当てている**（共有ドキュメント AP-54
/// 「文字列一致の見張りが、コメントの中で当たる」）。この 2 ファイルは
/// **説明のコメントが本文より長い**ので、素の `contains` だと設定を消しても
/// 説明文に残った同じ語で緑のままになる。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _gradlePath = 'android/app/build.gradle.kts';
const _manifestPath = 'android/app/src/main/AndroidManifest.xml';
const _extractionRulesPath =
    'android/app/src/main/res/xml/data_extraction_rules.xml';

/// Kotlin DSL からコメントを取り除いて返す。
String _gradle() => File(_gradlePath)
    .readAsStringSync()
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// AndroidManifest から XML コメントを取り除いて返す。
String _manifest() => File(_manifestPath)
    .readAsStringSync()
    .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// data_extraction_rules.xml から XML コメントを取り除いて返す。
String _extractionRules() => File(_extractionRulesPath)
    .readAsStringSync()
    .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

/// `名前 = "値"` の代入を読む。**名前がどこかに出てくるかではなく、
/// 代入の形で読む**（docs/MOBILE-APP-DESIGN.md 6 節の 1 番）。
String? _assignment(String source, String name) => RegExp(
  '$name\\s*=\\s*"([^"]+)"',
).firstMatch(source)?.group(1);

/// 除外したいドメイン（Session Concierge と同じ 5 つ）。
const _domains = ['root', 'file', 'database', 'sharedpref', 'external'];

void main() {
  group('アプリ ID（docs/MOBILE-APP-DESIGN.md 3-4）', () {
    test('applicationId と namespace が別の値である', () {
      final source = _gradle();
      final applicationId = _assignment(source, 'applicationId');
      final namespace = _assignment(source, 'namespace');

      expect(applicationId, isNotNull, reason: 'applicationId の代入がありません');
      expect(namespace, isNotNull, reason: 'namespace の代入がありません');

      // **同じにすると詰む。** Google ログインの OAuth クライアントは
      // 「パッケージ名＋署名鍵の SHA-1」で作られ、その組み合わせは Firebase
      // プロジェクトをまたいで一意でなければならない。本番が押さえていると
      // 検証環境側に作れず、あとから applicationId を変えるしかなくなるが、
      // **公開後の applicationId は変更できない。**
      expect(
        applicationId,
        isNot(namespace),
        reason: 'applicationId と namespace は別の値にすること（3-4）',
      );

      // 雛形の TODO 値のまま出さない。**1 回でも提出すると固定される。**
      expect(applicationId, isNot(startsWith('com.musiclist.')));
      // Gradle は applicationId にハイフンを受け付けない。
      expect(applicationId, isNot(contains('-')));
    });
  });

  group('デバッグ署名フォールバックの廃止（5-9-2）', () {
    test('release の署名にデバッグ鍵を使わない', () {
      final source = _gradle();

      // **これが復活すると、鍵の無い環境の release が黙ってデバッグ鍵で
      // 署名された成果物を出す。** Play は弾くが、APK を直接配る経路では
      // それが本番として流通しうる。
      expect(
        source,
        isNot(contains('getByName("debug")')),
        reason: 'デバッグ署名へのフォールバックが復活しています（5-9-2）',
      );

      // release は配布用の署名だけを使う。
      expect(source, contains('signingConfig = signingConfigs.getByName("release")'));
    });

    test('鍵が無い release は失敗させる（判定は buildTypes の外）', () {
      final source = _gradle();

      // タスク名を見て止める形であること。
      expect(source, contains('gradle.startParameter.taskNames'));
      expect(source, contains('throw GradleException'));

      // **判定を buildTypes の中に書いてはいけない。** buildTypes は debug
      // ビルドでも設定段階で必ず評価されるので、そこで throw すると鍵を
      // 持たない開発機で `flutter run`（debug）まで落ちる。
      final buildTypesAt = source.indexOf('buildTypes');
      final throwAt = source.indexOf('throw GradleException');
      expect(buildTypesAt, isNot(-1));
      expect(
        throwAt,
        lessThan(buildTypesAt),
        reason: '鍵の判定を buildTypes の中に書くと debug ビルドまで落ちます',
      );
    });
  });

  group('バックアップを止める（5-9-1）', () {
    test('AndroidManifest に allowBackup=false と dataExtractionRules がある', () {
      final manifest = _manifest();

      // 指定しないと Android の既定は allowBackup=true。
      expect(
        manifest,
        contains('android:allowBackup="false"'),
        reason: 'allowBackup を false にすること（既定は true）',
      );
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
        reason: 'dataExtractionRules を指していません',
      );
    });

    test('data_extraction_rules.xml が存在する', () {
      expect(
        File(_extractionRulesPath).existsSync(),
        isTrue,
        reason: '$_extractionRulesPath がありません',
      );
    });

    test('クラウドバックアップと端末間移行の両方でドメインを除外している', () {
      final rules = _extractionRules();

      // **allowBackup=false はクラウドバックアップしか止めない。**
      // Android 12 以降の端末間データ移行は device-transfer 側で除外する。
      // 片方だけ書いても、もう片方から素通りする。
      for (final section in ['cloud-backup', 'device-transfer']) {
        final block = RegExp(
          '<$section>(.*?)</$section>',
          dotAll: true,
        ).firstMatch(rules);
        expect(block, isNotNull, reason: '<$section> がありません');

        final body = block!.group(1)!;
        for (final domain in _domains) {
          expect(
            body,
            contains('<exclude domain="$domain"'),
            reason: '<$section> が $domain を除外していません',
          );
        }
      }
    });
  });

  group('Firebase の自動初期化を止める（5-4）', () {
    test('FirebaseInitProvider を tools:node="remove" で外している', () {
      final manifest = _manifest();

      // 宣言が無いと `tools:` 名前空間が解決できず、ビルドが落ちる。
      expect(
        manifest,
        contains('xmlns:tools="http://schemas.android.com/tools"'),
        reason: 'xmlns:tools の宣言がありません',
      );

      // **provider の中身ごと見る。** 名前だけ・属性だけを別々に探すと、
      // 片方が消えても通ってしまう。
      final provider = RegExp(
        r'<provider\b(.*?)/>',
        dotAll: true,
      ).allMatches(manifest).map((m) => m.group(1)!).firstWhere(
            (body) => body.contains(
              'com.google.firebase.provider.FirebaseInitProvider',
            ),
            orElse: () => '',
          );
      expect(
        provider,
        isNotEmpty,
        reason: 'FirebaseInitProvider の <provider> がありません（5-4）',
      );
      expect(
        provider,
        contains('tools:node="remove"'),
        reason: 'FirebaseInitProvider を remove していません（[core/duplicate-app]）',
      );
    });
  });

  group('App Links（5-8-2・案 B）', () {
    /// `autoVerify="true"` を持つ `<intent-filter>` の中身。
    String? autoVerifyFilter() => RegExp(
      r'<intent-filter[^>]*android:autoVerify="true"[^>]*>(.*?)</intent-filter>',
      dotAll: true,
    ).firstMatch(_manifest())?.group(1);

    test('autoVerify つきの intent-filter がある', () {
      expect(
        autoVerifyFilter(),
        isNotNull,
        reason: 'App Links の <intent-filter android:autoVerify="true"> がありません',
      );
    });

    test('VIEW / BROWSABLE を受ける', () {
      final filter = autoVerifyFilter();
      expect(filter, isNotNull);
      // どれか 1 つ欠けてもブラウザのリンクからは届かない。
      expect(filter, contains('android.intent.action.VIEW'));
      expect(filter, contains('android.intent.category.DEFAULT'));
      expect(filter, contains('android.intent.category.BROWSABLE'));
    });

    test('本番と検証の両方のホストを、パス / で受ける', () {
      final filter = autoVerifyFilter();
      expect(filter, isNotNull);

      // **共有リンクは `https://<host>/#/invite/abc123` の形で、OS は `#` から
      // 後ろを照合に使わない。** OS から見えるパスは `/` だけ（案 B）。
      for (final host in [
        'music-storage-d79b2.web.app', // 本番
        'music-storage-dev.web.app', // 検証
      ]) {
        expect(
          filter,
          contains('android:host="$host"'),
          reason: '$host を受けていません',
        );
      }
      expect(filter, contains('android:scheme="https"'));
      expect(filter, contains('android:path="/"'));
    });
  });
}
