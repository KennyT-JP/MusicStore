/// 共有リンクをアプリで開くための配信面（docs/MOBILE-APP-DESIGN.md 5-8-2）
///
/// 共有リンク（`https://<host>/#/invite/abc123`）をスマホで叩いたとき、
/// アプリが入っている端末ではアプリが開く。そのために、ドメイン側へ
/// 2 つのファイルを置く。
///
///   `/.well-known/assetlinks.json`              Android（App Links）
///   `/.well-known/apple-app-site-association`   iOS（Universal Links）
///
/// **この 2 つは、間違っていてもエラーが出ない。**
/// OS の照合が黙って失敗し、**リンクがブラウザで開くだけ**になる。
/// 「壊れている」と「まだ動いていない」が区別できないので、
/// **人の目では守れない。** だからここで機械的に見張る。
///
/// 見張るのは 4 つ。
///
/// 1. **2 ファイルが在ること。** 片方だけだと、片方の OS だけ静かに失敗する。
/// 2. **`apple-app-site-association` に拡張子が無いこと。** `.json` を
///    付けると Apple はそのパスを見に来ない（**付けたくなる形**なので、
///    ここで固定する）。
/// 3. **`firebase.json` が、その 2 つを届く形で配れること。**
///    - `ignore` が `.well-known` を落としていないこと
///    - 拡張子の無い `apple-app-site-association` に `application/json` が
///      付くこと（**Hosting は拡張子で Content-Type を決める**）
///    - その指定が**既定のブロックより後ろ**に在ること（**後勝ち**）
/// 4. **値がプレースホルダのままか、正しい形かのどちらかであること。**
///
/// > **なぜ「200 が返ること」を見ないのか。**
/// > このアプリの `firebase.json` は `**` → `/index.html` の catch-all
/// > rewrite を持っている。**ファイルが配信されていなくても 200 が返る**
/// > （中身はアプリの HTML）。状態コードでは何も分からない。
/// > 2026-08-15 に `robots.txt` と `sitemap.xml` で実際に踏んだ形で、
/// > ads_placement_test.dart の「読み物に辿り着けること」と同じ理由。
/// > **外から確かめるときは `curl -i` で Content-Type と中身まで見ること。**
///
/// **2026-08-16 の実測。** ローカルの Hosting エミュレータ
/// （`firebase emulators:start --only hosting`）へ curl を通し、
/// 2 ファイルとも 200 で**中身の JSON が返る**こと（rewrite の
/// `index.html` ではない）を確認した。同時に、firebase-tools 15.24.0 の
/// `lib/listFiles.js`（配信が実際に呼ぶ関数）へこの `firebase.json` の
/// `ignore` を渡し、2 ファイルとも配信対象に入ることを確認した。
/// **エミュレータは `headers` を反映しない**（既存の `**` の
/// Cache-Control すら付かない）ので、**ヘッダの検証はこのテストが担う。**
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 配信面の置き場所。**ドット始まりのディレクトリ**であることが、
/// `firebase.json` の `ignore` との関係で意味を持つ。
const _dir = 'web/.well-known';

/// **拡張子を付けない。** Apple はこのパスをそのまま見に来る。
const _aasa = 'apple-app-site-association';
const _assetlinks = 'assetlinks.json';

/// docs/MOBILE-APP-DESIGN.md 3 節（論点 16）で決めたアプリ ID。
const _bundleId = 'jp.sessionconcierge.trackcabinet';

/// 未設定を表す印。**このリポジトリの流儀**（lib/env の接続設定と同じ）。
const _placeholder = 'REPLACE_ME';

/// 署名鍵の指紋の形。大文字 16 進のコロン区切りで 32 バイト。
final _sha256Fingerprint = RegExp(r'^[0-9A-F]{2}(:[0-9A-F]{2}){31}$');

/// Apple の Team ID の形。英数 10 桁。
final _teamId = RegExp(r'^[0-9A-Z]{10}$');

Map<String, dynamic> _hosting() {
  final config =
      jsonDecode(File('firebase.json').readAsStringSync())
          as Map<String, dynamic>;
  return config['hosting'] as Map<String, dynamic>;
}

List<Map<String, dynamic>> _headerRules() =>
    (_hosting()['headers'] as List).cast<Map<String, dynamic>>();

/// Hosting の source（glob）を正規表現へ。
///
/// **hosting_cache_test.dart と同じ変換**（同じ `firebase.json` の同じ
/// 記法を読むため）。支えるのは `**`・`**/`・`*`・`@(a|b)` だけ。
/// 記法を足したら両方を育てること。
RegExp _globToRegExp(String glob) {
  final g = glob.startsWith('/') ? glob.substring(1) : glob;
  final out = StringBuffer('^');
  var i = 0;
  while (i < g.length) {
    final c = g[i];
    if (c == '*') {
      if (i + 1 < g.length && g[i + 1] == '*') {
        if (i + 2 < g.length && g[i + 2] == '/') {
          out.write('(?:.*/)?');
          i += 3;
        } else {
          out.write('.*');
          i += 2;
        }
      } else {
        out.write('[^/]*');
        i += 1;
      }
    } else if (c == '@' && i + 1 < g.length && g[i + 1] == '(') {
      out.write('(?:');
      i += 2;
    } else if (c == '|' || c == ')') {
      out.write(c);
      i += 1;
    } else {
      out.write(RegExp.escape(c));
      i += 1;
    }
  }
  out.write(r'$');
  return RegExp(out.toString());
}

/// [path] に実際に付くヘッダ [key] の値。
///
/// **同じパスに複数のブロックが一致するときは、最後の 1 件が効く**
/// （後勝ち）。書いてあることではなく、**実効値**を見る。
String? _effectiveHeader(String path, String key) {
  String? value;
  for (final rule in _headerRules()) {
    if (!_globToRegExp(rule['source'] as String).hasMatch(path)) continue;
    for (final header in (rule['headers'] as List)) {
      final entry = (header as Map).cast<String, dynamic>();
      if ((entry['key'] as String).toLowerCase() == key.toLowerCase()) {
        value = entry['value'] as String; // 後勝ち。break しない
      }
    }
  }
  return value;
}

/// [path] へ [key] を与えている**最後の**ブロックの位置。無ければ -1。
int _lastRuleIndexFor(String path, String key) {
  final rules = _headerRules();
  var found = -1;
  for (var i = 0; i < rules.length; i++) {
    if (!_globToRegExp(rules[i]['source'] as String).hasMatch(path)) continue;
    for (final header in (rules[i]['headers'] as List)) {
      final entry = (header as Map).cast<String, dynamic>();
      if ((entry['key'] as String).toLowerCase() == key.toLowerCase()) found = i;
    }
  }
  return found;
}

dynamic _json(String path) => jsonDecode(File(path).readAsStringSync());

void main() {
  group('配信面の 2 ファイル', () {
    test('web/.well-known/ に 2 つとも在る', () {
      for (final name in [_assetlinks, _aasa]) {
        expect(
          File('$_dir/$name').existsSync(),
          isTrue,
          reason: '$_dir/$name がありません。**片方だけだと、その OS の'
              '端末でだけ共有リンクがブラウザで開きます**（エラーは出ません）。',
        );
      }
    });

    test('apple-app-site-association に拡張子が付いていない', () {
      // **中身は JSON なので `.json` を付けたくなる。** 付けると Apple は
      // 拡張子なしのパスしか見に来ないため、Universal Links が黙って
      // 効かなくなる。ディレクトリの中身を数えて、紛らわしい名前ごと弾く。
      final names = Directory(_dir)
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          .where((n) => n.isNotEmpty)
          .toList();

      expect(names, contains(_aasa));
      for (final name in names) {
        if (name == _aasa) continue;
        expect(
          name.startsWith('$_aasa.'),
          isFalse,
          reason: '$_dir/$name があります。**Apple が見に来るのは拡張子の'
              '無い `$_aasa` だけです。** `.json` を付けたものを置いても'
              '使われず、置き換えたつもりで機能だけが消えます。',
        );
      }
    });

    test('2 つとも JSON として読める', () {
      // Apple も Google も JSON として読む。壊れていれば**黙って**弾かれる。
      for (final name in [_assetlinks, _aasa]) {
        expect(
          () => _json('$_dir/$name'),
          returnsNormally,
          reason: '$_dir/$name が JSON として読めません。',
        );
      }
    });
  });

  group('assetlinks.json（Android の App Links）', () {
    test('Android が読む形になっている', () {
      final statements = _json('$_dir/$_assetlinks') as List;
      expect(statements, isNotEmpty);

      for (final statement in statements.cast<Map<String, dynamic>>()) {
        expect(
          statement['relation'],
          contains('delegate_permission/common.handle_all_urls'),
          reason: 'この relation が無いと、リンクを開く権限の委譲になりません。',
        );
        final target = (statement['target'] as Map).cast<String, dynamic>();
        expect(target['namespace'], 'android_app');
        expect(
          target['package_name'],
          _bundleId,
          reason: '**原本は本番の値**（検証環境向けの `.dev` は '
              'scripts/deploy.mjs が配信物の側だけに付けます）。',
        );
      }
    });

    test('署名鍵は「未設定の印」か「正しい形の SHA-256」のどちらか', () {
      // **ここが今回いちばん危ない箇所。**
      //
      // keystore はまだ無く、依頼者にしか作れない。だから**いまは
      // プレースホルダで正しい**。それらしい値を置いた瞬間、照合は
      // 黙って失敗し、リンクはブラウザで開くだけになる（エラーは出ない）。
      //
      // **値が入ったときにこのテストを直す必要は無い**——「未設定の印か、
      // 正しい形か」を見ているので、埋まれば埋まったまま緑になる。
      // **配信を止めるのは scripts/deploy.mjs の仕事**（下の group）。
      final statements = _json('$_dir/$_assetlinks') as List;

      for (final statement in statements.cast<Map<String, dynamic>>()) {
        final target = (statement['target'] as Map).cast<String, dynamic>();
        final fingerprints = (target['sha256_cert_fingerprints'] as List)
            .cast<String>();

        expect(
          fingerprints.length,
          2,
          reason: '**2 つ要ります**：手元のアップロード鍵と、Play アプリ'
              '署名鍵。**Play が AAB を署名し直す**ので、手元の鍵だけだと'
              '**ストアから入れた人だけ**リンクが開きません（開発端末では'
              '動くので気づけません）。',
        );

        for (final fingerprint in fingerprints) {
          expect(
            fingerprint.startsWith(_placeholder) ||
                _sha256Fingerprint.hasMatch(fingerprint),
            isTrue,
            reason: '「$fingerprint」は未設定の印（$_placeholder…）でも、'
                '正しい形の SHA-256（大文字 16 進・コロン区切り 32 バイト）'
                'でもありません。**中途半端な値は、照合が黙って失敗します。**',
          );
        }
      }
    });
  });

  group('apple-app-site-association（iOS の Universal Links）', () {
    test('appIDs が <Team ID>.<Bundle ID> で、値が入っている', () {
      // **ここは assetlinks.json と扱いが違う。**
      // Team ID（Apple の Membership の値）は**すでに分かっている**ので、
      // プレースホルダを許さない。**戻したら赤**。
      final details = ((_json('$_dir/$_aasa')
              as Map)['applinks'] as Map)['details'] as List;
      expect(details, isNotEmpty);

      final appIds = (details.first as Map)['appIDs'] as List;
      expect(appIds, isNotEmpty);

      for (final appId in appIds.cast<String>()) {
        expect(
          appId.endsWith('.$_bundleId'),
          isTrue,
          reason: '「$appId」が Bundle ID（$_bundleId）で終わっていません。',
        );
        final team = appId.substring(0, appId.length - '.$_bundleId'.length);
        expect(
          _teamId.hasMatch(team),
          isTrue,
          reason: '「$team」は Apple の Team ID の形（英数 10 桁）では'
              'ありません。**プレースホルダのままでは Universal Links は'
              '黙って効きません。** 値は分かっているので、埋めること。',
        );
      }
    });

    test('主張するパスが「/」である（案 B）', () {
      // **共有リンクは `https://<host>/#/invite/abc123`。**
      // OS はパスだけで照合し、`#` から後ろは使わない。**このリンクの
      // パスは `/` だけ**なので、`/` を丸ごとアプリに渡す（5-8-2 の案 B）。
      // 代償として、サイトのトップを開こうとした人もアプリに入る。
      // `/help/...` は別パスなので影響しない（読み物はブラウザのまま）。
      final details = ((_json('$_dir/$_aasa')
              as Map)['applinks'] as Map)['details'] as List;
      final components = (details.first as Map)['components'] as List;

      expect(
        components.map((c) => (c as Map)['/']),
        contains('/'),
        reason: '**パス `/` を主張していません。** 共有リンクのパスは '
            '`/` だけ（残りは `#` の後ろで、OS の照合には使われません）。'
            'ここが `/` でないと、共有リンクはアプリで開きません。',
      );
    });
  });

  group('firebase.json が、その 2 つを届く形で配れること', () {
    test('ignore が .well-known を落としていない', () {
      // **`ignore` の既定に `**/.*` が入っている。`.well-known` は
      // ドット始まり。** 落とされると「手元には在るのに配信物に無い」に
      // なり、catch-all rewrite のせいで 404 ではなく 200 で index.html が
      // 返る——Apple / Google からは「壊れた JSON」にしか見えない。
      //
      // **2026-08-16 に実測して、落とされないことを確認した。**
      // firebase-tools 15.24.0 の lib/listFiles.js（配信が呼ぶ関数）へ
      // この ignore をそのまま渡すと、2 ファイルとも配信対象に入る。
      // glob の ignore は、**パターンが `/**` で終わらない限り、一致した
      // ディレクトリの中身までは除外しない**。`**/.*` が当たるのは
      // `.well-known` というディレクトリ自身と、名前がドットで始まる
      // **ファイル**だけ。ここではその規則をそのまま検査する。
      final ignore = (_hosting()['ignore'] as List).cast<String>();

      for (final pattern in ignore) {
        for (final name in [_assetlinks, _aasa]) {
          expect(
            _globToRegExp(pattern).hasMatch('.well-known/$name'),
            isFalse,
            reason: 'ignore の「$pattern」が .well-known/$name を除外します。'
                '**配信物から消えます**（そして 200 で index.html が返るので、'
                '状態コードでは気づけません）。',
          );
        }
        if (pattern.endsWith('/**')) {
          expect(
            _globToRegExp(pattern.substring(0, pattern.length - 3))
                .hasMatch('.well-known'),
            isFalse,
            reason: 'ignore の「$pattern」は `/**` で終わるため、'
                '**.well-known の中身ごと除外します。**',
          );
        }
      }
    });

    test('apple-app-site-association に application/json が付く', () {
      // **拡張子が無いので、Hosting は Content-Type を推測できない。**
      // 明示しないと application/octet-stream 等で返り、**Apple に弾かれる**
      // （2026-08-16 のエミュレータでは `Content-Type: false` が返った）。
      expect(
        _effectiveHeader('.well-known/$_aasa', 'Content-Type'),
        'application/json',
        reason: '**拡張子の無いこのファイルには、Content-Type を明示しないと'
            'いけません。** 無いと Apple は JSON として読まず、'
            'Universal Links が黙って効きません。',
      );
    });

    test('その headers は、既定の `**` ブロックより後ろに在る', () {
      // **後に書いたブロックが勝つ。** 前に置くと、既定の `**` を含む
      // 後続のブロックに負けて無効になる（hosting_cache_test.dart の
      // 冒頭に書いてある、2026-08 に本番で実際に起きた形）。
      // 実効値の検査だけでは順序が守れない——既定の `**` は
      // Content-Type を指定していないので、前に移しても実効値が
      // 変わらないまま壊れる。**だから位置そのものを固定する。**
      final rules = _headerRules();
      final defaultIndex =
          rules.indexWhere((r) => (r['source'] as String) == '**');
      expect(
        defaultIndex,
        isNonNegative,
        reason: '包括の `**` ブロックが消えています。',
      );

      final aasaIndex = _lastRuleIndexFor('.well-known/$_aasa', 'Content-Type');
      expect(
        aasaIndex,
        greaterThan(defaultIndex),
        reason: '$_aasa の Content-Type を与えるブロックが、既定の `**`'
            'ブロック（$defaultIndex 番目）より前（$aasaIndex 番目）に'
            'あります。**Hosting は後勝ちなので、順序が意味を持ちます。**',
      );
    });

    test('2 ファイルとも溜め込ませない', () {
      // assetlinks.json は `**/*.@(js|json)` にも一致する。**そちらより
      // 後ろに置かないと max-age=3600 に負ける。**
      //
      // `autoVerify` の照合は**端末へのインストール時に一度だけ**行われ、
      // あとから直しても自動では再照合されない。鍵を足して配信し直した
      // 直後に古い版が配られると、その端末では二度と自動で有効にならない
      // （入れ直すか、手動で「デフォルトで開く」を設定するしかない）。
      for (final name in [_assetlinks, _aasa]) {
        final value = _effectiveHeader('.well-known/$name', 'Cache-Control');
        expect(
          value,
          isNotNull,
          reason: '.well-known/$name に一致する Cache-Control がありません。',
        );
        expect(
          value,
          contains('no-cache'),
          reason: '.well-known/$name の実効値が no-cache ではありません'
              '（$value）。**`**/*.@(js|json)` のブロックより後ろに'
              '置くこと**（後勝ち）。',
        );
      }
    });
  });

  group('配信スクリプトの見張り', () {
    // **テストは「いまプレースホルダである」ことを許す。**
    // その代わり、**プレースホルダのままなら配信を止める**のは
    // scripts/deploy.mjs の仕事。ここではその判定が生きていることを見る。
    final deploy = File('scripts/deploy.mjs').readAsStringSync();

    test('未設定の印を、deploy.mjs が同じ名前で見張っている', () {
      // 印の名前を片方だけ変えると、**判定が静かに素通りする。**
      final statements = _json('$_dir/$_assetlinks') as List;
      final placeholders = [
        for (final statement in statements.cast<Map<String, dynamic>>())
          for (final f in ((statement['target'] as Map)['sha256_cert_fingerprints']
                  as List)
              .cast<String>())
            if (f.startsWith(_placeholder)) f,
      ];

      for (final placeholder in placeholders) {
        expect(
          deploy,
          contains(placeholder),
          reason: '$_dir/$_assetlinks の「$placeholder」を '
              'scripts/deploy.mjs が見ていません。**未設定のまま配信され、'
              '照合が黙って失敗します。**',
        );
      }
    });

    test('環境ごとの差し替えが deploy.mjs に在る', () {
      // 検証環境の apk は applicationIdSuffix = ".dev" で別アプリになる。
      // **差し替えを外すと、検証環境ではどの端末でもリンクが開かない。**
      expect(deploy, contains('package_name'));
      expect(deploy, contains(".dev"));
      expect(
        deploy,
        contains(_dir.replaceFirst('web/', '')),
        reason: 'scripts/deploy.mjs が .well-known を扱っていません。',
      );
    });
  });
}
