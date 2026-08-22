/// 死蔵コードが増えていないことの確認
///
/// **回帰テスト。** 2 回の監査で毎回同じ指摘が出た。
///
/// 判定ロジックを `lib/domain/` に切り出してテストを厚く書いたのに、
/// **画面やリポジトリはそれを呼ばず、同じ判定を直接書いていた**。
/// テストは緑のまま、本番では別のコードが動いている状態が続いた
/// （監査 S8・S11・第2回）。
///
/// - `Permissions` の 6 メソッドが本番から 0 参照
/// - `sequence.dart` と `invite.dart` が本番から 0 参照
///   （どちらも仕様 12.6 が「自動テスト必須」に挙げた領域）
///
/// **テストがあることと、守られていることは別。**
/// 呼ばれているかどうかは機械的に確かめられるので、ここで固定する。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/repo_files.dart';

/// `lib/` のうち、本番コードとみなす場所。
///
/// `lib/domain/` 自身は「定義側」なので、参照元としては数えない。
/// **除外は `/` にそろえたパスで行う。** Windows では円記号区切りで
/// 返るため、そのままだと `lib/domain/` を除外できず、
/// **定義側どうしの参照を「本番から呼ばれている」と数えてしまう**
/// （見逃す側に倒れる／2026-08-07）。
List<File> _productionFiles() => filesUnder('lib')
    .where((e) => !e.path.startsWith('lib/domain/'))
    .where((e) => !e.path.startsWith('lib/l10n/')) // 生成物
    .map((e) => e.file)
    .toList();

/// `//`・`///` のコメント行と `/* */` のブロックコメントを取り除く。
///
/// **コメントに書いた名前は「呼び出し」ではない。** 以前はコメント行も
/// そのまま数えていたため、実装を消してコメントに名前だけ残しても
/// 緑のままだった（監査 第4回・実験で実証）。
///
/// 行の途中から始まるコメント（`foo(); // 説明`）も落とす。
/// 文字列リテラル内の `//`（URL など）を巻き添えにしないよう、
/// 直前が `:` のもの（`https://`）は残す。
///
/// **改行コードを先にそろえる。** `.` は `\r` に一致しないので、
/// ファイルが CRLF だと `//.*$` が**行末（`\r` の手前）で止まって
/// `$` に届かず、1 行もコメントを落とせない。**
/// そうなると、コメントの中にしか無い名前まで「本番からの呼び出し」と
/// 数えるので、**このテストは緑のまま何も守らなくなる**
/// （docs/AUDIT-CHECKLIST.md 観点 4「前提が崩れると自動的に通る」）。
/// `.gitattributes` が LF に統一しているとはいえ、
/// 編集の仕方ひとつで CRLF は混ざる（2026-08-16 に実際に混ざった）。
///
/// **監査 第6回 B1: この helper 自身に単体テストが無かった。**
/// 過去の 6 つの抜け道はすべて手当て済みだが、その手当てが将来退行しても
/// 誰も気づけない状態だったため、下の `group('_stripComments…')` で
/// 意地悪な入力を固定する。その過程で、`/* */` のブロックコメントは
/// 元々まったく除去されていなかったことが分かったので、非貪欲・複数行
/// 対応で合わせて除去するようにした（現状 `lib/` にブロックコメントは
/// 無いため既存の走査結果への影響は無い）。
String _stripComments(String source) => source
    .replaceAll('\r\n', '\n')
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((line) => line.replaceFirst(RegExp(r'(?<!:)//.*$'), ''))
    .join('\n');

void main() {
  late String production;

  setUpAll(() {
    production = _stripComments(
      _productionFiles().map((f) => f.readAsStringSync()).join('\n'),
    );
  });

  group('_stripComments（コメント除去 helper 自身の検査／監査 第6回 B1）', () {
    // 「見張りの見張り」不在の是正。ここより上のテストは、この helper が
    // 正しく動くことを前提にしている。helper 自身が将来退行しても、
    // ここが赤くならない限り誰も気づけない。

    test('コメントだけに書いた名前は、除去後は見つからない', () {
      const source = '''
// oldMethod() はもう呼ばれていない
void other() {}
''';
      // ストリップ前は文字列としてまだ含まれている＝素朴に検索すると
      // 「使用あり」と誤判定してしまう、という抜け道そのものを示す。
      expect(source.contains('oldMethod()'), isTrue);
      // ストリップ後は消えている＝正しく「死蔵」に戻る。
      expect(_stripComments(source).contains('oldMethod()'), isFalse);
    });

    test('行末コメント（`呼び出し(); // 説明`）も落ちる', () {
      const source = 'realCall(); // fakeCall() は説明の中だけ';
      final stripped = _stripComments(source);
      expect(stripped.contains('realCall()'), isTrue);
      expect(stripped.contains('fakeCall()'), isFalse);
    });

    test('CRLF 混じりでもコメントを落とせる', () {
      // `.` が `\r` に一致しないための取りこぼしが、
      // 2026-08-16 に実際に起きた（コメント参照）。
      const source =
          'realCall();\r\n// fakeCall() はコメントの中だけ\r\nother();';
      final stripped = _stripComments(source);
      expect(stripped.contains('realCall()'), isTrue);
      expect(stripped.contains('other()'), isTrue);
      expect(stripped.contains('fakeCall()'), isFalse);
    });

    test('URL の // はコメントとして落とさない（直前が `:`）', () {
      const source = "final url = 'https://example.com/fakeCall';";
      expect(_stripComments(source).contains('fakeCall'), isTrue);
    });

    test('`/* */` ブロックコメントの中の名前も落ちる', () {
      const source = '/* fakeCall() は無効化中 */\nrealCall();';
      final stripped = _stripComments(source);
      expect(stripped.contains('realCall()'), isTrue);
      expect(stripped.contains('fakeCall()'), isFalse);
    });

    test('複数行にまたがるブロックコメントも落ちる', () {
      const source = '''
/*
 * fakeCall() はここに書いてあるだけで
 * 本当は呼ばれていない
 */
realCall();
''';
      final stripped = _stripComments(source);
      expect(stripped.contains('realCall()'), isTrue);
      expect(stripped.contains('fakeCall()'), isFalse);
    });

    test('複数のブロックコメントを1つに巻き込まない（非貪欲）', () {
      // `.*` を貪欲にすると、離れた 2 つの `/* */` の間の
      // realCall() まで巻き添えで消えてしまう。
      const source = '/* fakeA() */ realCall(); /* fakeB() */';
      final stripped = _stripComments(source);
      expect(stripped.contains('realCall()'), isTrue);
      expect(stripped.contains('fakeA()'), isFalse);
      expect(stripped.contains('fakeB()'), isFalse);
    });
  });

  test('Permissions のメソッドはすべて本番から呼ばれている', () {
    final source = File('lib/domain/permissions.dart').readAsStringSync();
    final methods = RegExp(r'static bool (\w+)')
        .allMatches(source)
        .map((m) => m.group(1)!)
        .toSet();

    expect(methods, isNotEmpty, reason: '判定関数を 1 つも見つけられていない');

    final unused = methods
        .where((m) => !production.contains('Permissions.$m'))
        .toList()
      ..sort();

    expect(
      unused,
      isEmpty,
      reason:
          '本番から呼ばれていない判定関数: $unused\n'
          '画面が同じ判定を直接書いていないか確かめてください。'
          '使わないなら消してください。',
    );
  });

  test('lib/domain のモジュールはすべて本番から使われている', () {
    final modules = filesUnder('lib/domain')
        .map((e) => e.path.split('/').last)
        .toList();

    expect(modules, isNotEmpty);

    final unused = modules
        .where((name) => !production.contains('domain/$name'))
        .toList()
      ..sort();

    expect(
      unused,
      isEmpty,
      reason:
          '本番から使われていないモジュール: $unused\n'
          '実際に動いている実装が別の場所にないか確かめてください。',
    );
  });

  test('lib/domain の static メソッドはすべて本番から呼ばれている', () {
    // モジュール単位の検査（上）だけでは、**ファイルは使われているのに
    // 一部のメソッドだけ死蔵**という形を見逃す。QuotaPolicy の通知判定
    // 3 本と SequencePolicy がまさにそれで、本番で効いているのは
    // functions 側だった（監査 第4回）。メソッド粒度でも固定する。
    final unused = <String>[];

    for (final entry in filesUnder('lib/domain')) {
      final source = entry.file.readAsStringSync();
      final fileName = entry.path.split('/').last;

      // static メソッドを、それを包む class / enum の名前と組にする。
      final owners = RegExp(
        r'^(?:abstract )?(?:class|enum) (\w+)',
        multiLine: true,
      ).allMatches(source).toList();

      // `static const …` は定数（フィールド）なので対象にしない。
      for (final match in RegExp(
        r'^  static (?!const\b)[\w<>?,() ]+ (\w+)[(<]',
        multiLine: true,
      ).allMatches(source)) {
        final method = match.group(1)!;
        if (method.startsWith('_')) continue;

        final owner = owners.lastWhere((o) => o.start < match.start);
        final call = '${owner.group(1)}.$method';
        if (!production.contains(call)) unused.add('$fileName の $call');
      }
    }

    expect(
      unused,
      isEmpty,
      reason:
          '本番から呼ばれていない domain の static メソッド: $unused\n'
          '本番で効いている実装が別の場所（functions など）にないか'
          '確かめてください。サーバーが正なら、クライアント側の写しは'
          '消してください。',
    );
  });

  test('リポジトリの公開メソッドが本番から呼ばれている', () {
    // 呼び出し元の無い公開メソッドは、たいてい「同じことを別の場所で
    // 直接やっている」印。isListNameTaken と canWithdraw がそうだった。
    final repositories = filesUnder('lib/data/repositories').map((e) => e.file);

    final unused = <String>[];
    for (final file in repositories) {
      final source = file.readAsStringSync();
      final name = file.uri.pathSegments.last;
      // **戻り値の型は貪欲に読む。** 以前は `Future<[^>]*>` で、
      // 入れ子のジェネリクス（`Future<List<X>>` など）に一致せず、
      // そのメソッドは**走査対象から黙って漏れていた**
      // （監査 第4回・実験で実証）。
      for (final match in RegExp(
        r'^  (?:Future<.+>|Stream<.+>|void|bool|String) (\w+)\(',
        multiLine: true,
      ).allMatches(source)) {
        final method = match.group(1)!;
        if (method.startsWith('_')) continue;
        // 自分自身のファイル以外からの参照を数える。
        //
        // **`.name(` だけを探すと足りない。** コールバックとして
        // 関数そのものを渡す書き方（`_run(auth.signInWithGoogle)`）が
        // あるため、括弧の無い参照も数える。
        final calls = _productionFiles()
            .where((f) => f.uri.pathSegments.last != name)
            .where((f) {
              final source = _stripComments(f.readAsStringSync());
              return RegExp('\\.$method\\b').hasMatch(source);
            })
            .length;
        if (calls == 0) unused.add('$name の $method');
      }
    }

    expect(
      unused,
      isEmpty,
      reason:
          '本番から呼ばれていないリポジトリのメソッド: $unused\n'
          '同じことを画面が直接していないか確かめてください。',
    );
  });
}
