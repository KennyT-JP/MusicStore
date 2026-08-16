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
/// | **AGP を 9 に上げる** | **release ビルドが作れなくなる**（`file_picker` と `audio_session` の要求が正面から衝突する）。`flutter run`（debug）は通るので、debug で確かめた人は気づかない |
/// | **`src/dev/google-services.json` の消滅** | dev ビルドが**黙って本番の設定で組み上がる**（既定の置き場所のファイルが代替として読まれる）。実行して初めて本番に繋がる |
/// | **フレーバーの `.dev` 接尾辞の消滅** | 検証と本番が同じ識別子になり、Google ログインが失敗する。端末にも並べて入らなくなる |
///
/// **どれもビルドは通る。** 気づく手段がここしかない。
///
/// **コメントを取り除いてから当てている**（共有ドキュメント AP-54
/// 「文字列一致の見張りが、コメントの中で当たる」）。この 2 ファイルは
/// **説明のコメントが本文より長い**ので、素の `contains` だと設定を消しても
/// 説明文に残った同じ語で緑のままになる。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _gradlePath = 'android/app/build.gradle.kts';
const _settingsGradlePath = 'android/settings.gradle.kts';
const _manifestPath = 'android/app/src/main/AndroidManifest.xml';
const _extractionRulesPath =
    'android/app/src/main/res/xml/data_extraction_rules.xml';

/// 本番の `google-services.json`。
///
/// **既定の置き場所**（フレーバー別のフォルダに無いときの代替）。
/// `flutterfire configure` の出力先もここ。
const _prodServiceFilePath = 'android/app/google-services.json';

/// 検証（dev フレーバー）の `google-services.json`。
const _devServiceFilePath = 'android/app/src/dev/google-services.json';

/// Kotlin DSL からコメントを取り除いて返す。
String _stripKotlinComments(String source) => source
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

String _gradle() => _stripKotlinComments(File(_gradlePath).readAsStringSync());

/// `android/settings.gradle.kts` からコメントを取り除いて返す。
///
/// **AGP を止めておく理由が、この直前に長いコメントで書いてある。**
/// 素の `contains` だと、その説明文の中の版番号を拾って通ってしまう。
String _settingsGradle() =>
    _stripKotlinComments(File(_settingsGradlePath).readAsStringSync());

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

  group('Android Gradle Plugin を 8 系に留める（2026-08-16）', () {
    /// `id("...") version "X.Y.Z"` の版を読む。`version("X.Y.Z")` の形も拾う。
    String? pluginVersion(String source, String pluginId) => RegExp(
      'id\\s*\\(\\s*"${RegExp.escape(pluginId)}"\\s*\\)\\s*version\\s*\\(?\\s*"([^"]+)"',
    ).firstMatch(source)?.group(1);

    test('AGP のメジャー版が 8 である', () {
      final version = pluginVersion(
        _settingsGradle(),
        'com.android.application',
      );

      expect(
        version,
        isNotNull,
        reason:
            '$_settingsGradlePath に com.android.application の版がありません。\n'
            '書き方を変えたなら、この見張りも直してください',
      );

      // **AGP 9 に上げると release ビルドが作れなくなる。**
      //
      // AGP 9 は Kotlin の適用を `android.builtInKotlin` という
      // **プロジェクト全体にひとつだけ**のスイッチで決めるようになった。
      // ところが `file_picker` は「AGP 9 では Kotlin プラグインを自分で
      // 適用しない」側、`audio_session` は「AGP 9 では不要」と判断して
      // 適用を拒否する側で、**どちらに倒しても片方が壊れる。**
      // スイッチは 1 つしかないので逃げ道が無い。
      //
      // **`flutter run`（debug）は通ってしまう。** debug で確かめた人は
      // 気づかず、release を作る段になって初めて詰まる。
      //
      // 上げ直すなら、まず file_picker と audio_session の両方が AGP 9 に
      // 対応した版を出したことを確かめ、`flutter build apk --release` を
      // 通しきってからにすること。経緯は $_settingsGradlePath の
      // plugins ブロックの上に書いてある。
      final major = int.tryParse(version!.split('.').first);
      expect(
        major,
        8,
        reason:
            'AGP が $version になっています。**8 系から動かさないでください。**\n'
            'AGP 9 では file_picker と audio_session の要求が正面から衝突し、\n'
            'release ビルドが作れません（debug は通るので気づきにくい）。\n'
            '理由の全文は $_settingsGradlePath の plugins ブロックの上にあります',
      );
    });

    test('Kotlin と Gradle wrapper も噛み合った版のままである', () {
      // **3 つは互いに噛み合っている。** 1 つだけ動かすと崩れる。
      final kotlin = pluginVersion(
        _settingsGradle(),
        'org.jetbrains.kotlin.android',
      );
      expect(
        kotlin,
        isNotNull,
        reason: '$_settingsGradlePath に Kotlin プラグインの版がありません',
      );
      expect(
        int.tryParse(kotlin!.split('.').first),
        2,
        reason: 'Kotlin が $kotlin になっています。AGP 8 系と組む版のままにしてください',
      );

      final wrapper = File(
        'android/gradle/wrapper/gradle-wrapper.properties',
      ).readAsStringSync();
      final gradle = RegExp(
        r'gradle-(\d+)\.[\d.]+-(?:all|bin)\.zip',
      ).firstMatch(wrapper)?.group(1);
      expect(
        gradle,
        isNotNull,
        reason: 'gradle-wrapper.properties から Gradle の版を読めませんでした',
      );
      expect(
        int.tryParse(gradle!),
        8,
        reason:
            'Gradle wrapper が $gradle 系になっています。\n'
            '**AGP 8.11.1 は Gradle 9 では動きません**（8.14 に固定してあります）',
      );
    });
  });

  group('フレーバー（docs/MOBILE-APP-DESIGN.md 5-2）', () {
    /// `productFlavors { ... }` の中身。
    ///
    /// **ブロックの中だけを見る。** ファイル全体を `contains` で探すと、
    /// `applicationIdSuffix` が別の場所へ移っても通ってしまう。
    String flavorsBlock() {
      final source = _gradle();
      final start = source.indexOf('productFlavors');
      expect(
        start,
        isNot(-1),
        reason: 'productFlavors がありません（5-2。prod / dev の 2 つが要ります）',
      );

      // 対応する `}` まで数える。
      final open = source.indexOf('{', start);
      expect(open, isNot(-1));
      var depth = 0;
      for (var i = open; i < source.length; i++) {
        if (source[i] == '{') depth++;
        if (source[i] == '}') {
          depth--;
          if (depth == 0) return source.substring(open + 1, i);
        }
      }
      fail('productFlavors のブロックが閉じていません');
    }

    /// `create("名前") { ... }` の中身。
    String flavorBody(String flavors, String name) {
      final start = flavors.indexOf('create("$name")');
      expect(
        start,
        isNot(-1),
        reason: 'フレーバー $name がありません（5-2）',
      );
      final open = flavors.indexOf('{', start);
      expect(open, isNot(-1));
      var depth = 0;
      for (var i = open; i < flavors.length; i++) {
        if (flavors[i] == '{') depth++;
        if (flavors[i] == '}') {
          depth--;
          if (depth == 0) return flavors.substring(open + 1, i);
        }
      }
      fail('フレーバー $name のブロックが閉じていません');
    }

    test('prod と dev の 2 つがあり、次元が宣言されている', () {
      final source = _gradle();

      // 次元の宣言が無いと AGP が設定段階で落ちる。
      expect(
        source,
        contains('flavorDimensions'),
        reason: 'flavorDimensions の宣言がありません',
      );

      final flavors = flavorsBlock();
      for (final name in ['prod', 'dev']) {
        expect(
          flavors,
          contains('create("$name")'),
          reason: 'フレーバー $name がありません（5-2）',
        );
      }
    });

    test('dev だけに .dev の接尾辞が付く', () {
      final flavors = flavorsBlock();

      // **これが消えると本番と同じ識別子になる。**
      // Google ログインの OAuth クライアントは「パッケージ名＋署名鍵の
      // SHA-1」で作られ、その組み合わせはプロジェクトをまたいで一意。
      // 本番が押さえているので、検証環境のログインが失敗する。
      // 端末にも並べて入らなくなる（入れ替えになる）。
      expect(
        flavorBody(flavors, 'dev'),
        contains('applicationIdSuffix = ".dev"'),
        reason: 'dev フレーバーに applicationIdSuffix = ".dev" がありません（5-2）',
      );

      // **prod には付けない。** 公開後の applicationId は変更できない。
      expect(
        flavorBody(flavors, 'prod'),
        isNot(contains('applicationIdSuffix')),
        reason: 'prod に applicationIdSuffix が付いています。公開後は変えられません',
      );
    });
  });

  group('google-services.json の配置（5-3）', () {
    /// `google-services.json` の `client[].client_info` から
    /// `android_client_info.package_name` を集める。
    List<String> packageNames(String path) {
      final file = File(path);
      expect(
        file.existsSync(),
        isTrue,
        reason:
            '$path がありません。\n'
            '**`com.google.gms.google-services` プラグインが変種ごとに\n'
            'このファイルを探します。** 無いとビルドが落ちるか、既定の\n'
            '置き場所のもの（＝本番）が黙って使われます（5-3）',
      );

      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      return (json['client'] as List)
          .map(
            (client) =>
                ((client as Map)['client_info']
                        as Map)['android_client_info']
                    as Map,
          )
          .map((info) => info['package_name'] as String)
          .toList();
    }

    /// `google-services.json` の `oauth_client` の件数。
    int oauthClientCount(String path) {
      final json =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      return (json['client'] as List)
          .map((client) => ((client as Map)['oauth_client'] as List?) ?? const [])
          .fold<int>(0, (sum, list) => sum + list.length);
    }

    test('本番と検証の両方に置いてある', () {
      // **どちらか片方でも欠けると壊れる。**
      // `src/dev/` が欠けたときは**エラーが出ない**——既定の置き場所の
      // ファイルが代替として読まれ、**dev ビルドが本番に繋がる。**
      expect(
        File(_prodServiceFilePath).existsSync(),
        isTrue,
        reason: '$_prodServiceFilePath がありません（prod フレーバー用）',
      );
      expect(
        File(_devServiceFilePath).existsSync(),
        isTrue,
        reason:
            '$_devServiceFilePath がありません（dev フレーバー用）。\n'
            '**無いと dev ビルドが黙って本番の設定で組み上がります。**\n'
            'エラーは出ません',
      );
    });

    test('中の package_name が、そのフレーバーの applicationId と一致する', () {
      final applicationId = _assignment(_gradle(), 'applicationId');
      expect(applicationId, isNotNull);

      // **食い違うと Google ログインが失敗する**（「そのパッケージ名の
      // アプリは知らない」）。ビルドは通る。
      expect(
        packageNames(_prodServiceFilePath),
        contains(applicationId),
        reason:
            '$_prodServiceFilePath に $applicationId の登録がありません。\n'
            'applicationId を変えたら google-services.json も取り直すこと',
      );
      expect(
        packageNames(_devServiceFilePath),
        contains('$applicationId.dev'),
        reason:
            '$_devServiceFilePath に $applicationId.dev の登録がありません。\n'
            '**本番用のファイルを置いていませんか。**\n'
            'dev の接尾辞（build.gradle.kts の applicationIdSuffix）と\n'
            '揃っている必要があります',
      );
    });

    test('configure-firebase.mjs が渡すパッケージ名が、フレーバーと揃っている', () {
      // **flutterfire は `applicationId`（接尾辞なし＝本番の値）を既定に使う。**
      // 検証環境へ流すときに `--android-package-name` を渡さないと、
      // **検証プロジェクトに「本番と同じパッケージ名」のアプリが新しく
      // 作られる。** しかもエラーにならない——作成に成功してしまうので、
      // 気づくのは「Google ログインが検証環境で動かない」と分かったとき。
      //
      // そこでスクリプト側に値を書いたが、**書き写した値はずれる。**
      // build.gradle.kts を正本として、ここで突き合わせる。
      final applicationId = _assignment(_gradle(), 'applicationId');
      expect(applicationId, isNotNull);

      final script = File('scripts/configure-firebase.mjs').readAsStringSync();
      final passed = RegExp(r'--android-package-name=([\w.]+)').firstMatch(script);

      expect(
        passed,
        isNotNull,
        reason: 'configure-firebase.mjs が --android-package-name を渡していません。\n'
            '**渡さないと、検証環境に本番と同じパッケージ名のアプリが作られます。**',
      );
      expect(
        passed!.group(1),
        '$applicationId.dev',
        reason: 'configure-firebase.mjs が渡すパッケージ名が、\n'
            'build.gradle.kts の applicationId + applicationIdSuffix と'
            '食い違っています',
      );
    });

    test('oauth_client が入っている（Google ログインを有効化した後に取ること）', () {
      // **Google ログインを有効化する「前」にダウンロードしたファイルは
      // `oauth_client` が 0 件になる。** そのまま置くと Android は
      // 「serverClientId が無い」で失敗する（Session Concierge が実際に
      // 踏んでいる。設計 5-3）。**設定を変えたら、その設定から生成した
      // ファイルも取り直す。**
      for (final path in [_prodServiceFilePath, _devServiceFilePath]) {
        expect(
          oauthClientCount(path),
          greaterThanOrEqualTo(2),
          reason:
              '$path の oauth_client が足りません。\n'
              '**Google ログインを有効化した「あと」に取り直してください。**\n'
              '有効化前のファイルは 0 件で、Android のログインが\n'
              '「serverClientId が無い」で失敗します（5-3）',
        );
      }
    });
  });

  group('com.google.gms.google-services プラグイン（5-3）', () {
    test('app に適用され、版が settings.gradle.kts で固定されている', () {
      // **google-services.json を置くだけでは読まれない。**
      // このプラグインが変種ごとに JSON を探し、
      // `R.string.default_web_client_id` などのリソースへ展開する。
      // **Google ログインが serverClientId をそこから読む**ので、
      // 外すと「ビルドは通るのにログインだけ失敗する」。
      expect(
        _gradle(),
        contains('id("com.google.gms.google-services")'),
        reason:
            '$_gradlePath の plugins に com.google.gms.google-services が\n'
            'ありません。**置いた google-services.json が読まれません**（5-3）',
      );
      expect(
        _settingsGradle(),
        contains('com.google.gms.google-services'),
        reason: '$_settingsGradlePath でプラグインの版を固定していません',
      );
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
