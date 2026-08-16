/// オフライン再生の猶予（docs/DOWNLOAD-DESIGN.md 4.2 / 6.1 / 8.1）
///
/// **境界を必ず確かめる。** 30 日ちょうど・その前後、
/// 予告の 7 日ちょうど・その前後を、8.1 の表のとおりに固定する。
///
/// **端末の時計が戻っているときの挙動も、ここで仕様として固定してある。**
/// 直感に反するので、テストが無いと後から見た人が「バグだ」と直してしまう。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_list_app/domain/offline_access.dart';

/// 最終確認の時刻。以降はここからの経過で組み立てる。
final _verified = DateTime.utc(2026, 8, 16, 9, 0, 0);

DateTime _after(Duration elapsed) => _verified.add(elapsed);

bool _playable(DateTime now) =>
    OfflineAccessPolicy.isPlayableOffline(lastVerifiedAt: _verified, now: now);

int _remaining(DateTime now) =>
    OfflineAccessPolicy.remainingDays(lastVerifiedAt: _verified, now: now);

OfflineNoticeBand _band(DateTime now) =>
    OfflineAccessPolicy.band(lastVerifiedAt: _verified, now: now);

void main() {
  test('猶予は 30 日（論点 13b）', () {
    // **`siteConfig.itemPurgeGraceDays` とは別物**（10 節の 9）。
    // たまたま同じ 30 日だが、混ぜて siteConfig から読むようにすると、
    // 削除の猶予を 15 日に変えた瞬間にオフラインで聴ける期間も 15 日になる。
    expect(kOfflineGrace, const Duration(days: 30));
    expect(kOfflineGrace.inMilliseconds, 2592000000);
  });

  group('オフライン再生の可否（4.2・8.1 の表）', () {
    test('29 日 23 時間 59 分 59 秒 → 再生できる', () {
      expect(
        _playable(
          _after(const Duration(days: 29, hours: 23, minutes: 59, seconds: 59)),
        ),
        isTrue,
      );
    });

    test('30 日 − 1 ミリ秒 → 再生できる', () {
      expect(
        _playable(
          _after(const Duration(days: 30) - const Duration(milliseconds: 1)),
        ),
        isTrue,
      );
    });

    test('30 日ちょうど → 再生できない', () {
      // **ちょうどは「切れている」側に倒す。**
      // functions/src/domain/premium.ts の isPremiumActive が
      // `untilMs > nowMs`（ちょうどは含まない）としており、
      // 境界の扱いがファイルごとに違うと、どちらが正しいかを
      // 読む側が毎回調べ直すことになる。
      expect(_playable(_after(const Duration(days: 30))), isFalse);
    });

    test('30 日 + 1 ミリ秒 → 再生できない', () {
      expect(
        _playable(
          _after(const Duration(days: 30) + const Duration(milliseconds: 1)),
        ),
        isFalse,
      );
    });

    test('一度も確認できていない（null）→ 再生できない（安全側）', () {
      // ダウンロードは権限確認を通ったあとにしか始まらないので、
      // 実際には起きないはず。**それでも既定は安全側に倒す**
      // （ListRole.tryParse が未知の値に役割を与えないのと同じ考え）。
      expect(
        OfflineAccessPolicy.isPlayableOffline(
          lastVerifiedAt: null,
          now: _after(Duration.zero),
        ),
        isFalse,
      );
    });

    test('確認した直後は当然できる', () {
      expect(_playable(_after(Duration.zero)), isTrue);
    });
  });

  group('端末の時計が戻っているとき（4.2 の注記）', () {
    // ------------------------------------------------------------------
    // **これは仕様であって、不具合ではない。直さないこと。**
    //
    // この設計は端末の時計に依存している。端末の日付を戻せば猶予は伸びる。
    // 塞ぐには「時刻をサーバーからしか取らない」しかなく、
    // **それはオフライン再生と両立しない**（オフラインで聴けることが要求）。
    //
    // **これは「保証」ではなく「歯止め」。** 意図せず圏外にいた人が
    // 急に聴けなくなるのを防ぐための猶予であって、悪意ある人を止める
    // 仕組みではない。同じ理由で、index.json を書き換えて
    // lastVerifiedAt を伸ばすこともできる（暗号化しても復号鍵を端末に
    // 置く以上、結論は変わらない／9 節）。
    //
    // **ここに「時計を戻したら止まるべき」というテストを足さないこと。**
    // 足した瞬間、圏外にいただけの人を巻き添えにする実装が入る。
    // ------------------------------------------------------------------

    test('now が lastVerifiedAt より前でも再生できる（仕様として固定）', () {
      expect(_playable(_verified.subtract(const Duration(days: 100))), isTrue);
    });

    test('猶予を過ぎたあとに時計を戻せば、また再生できる（仕様として固定）', () {
      // 「時計を戻すと再生できる」ことを、いちばん露骨な形で残しておく。
      expect(_playable(_after(const Duration(days: 40))), isFalse);
      expect(_playable(_after(const Duration(days: 1))), isTrue);
    });
  });

  group('残り日数（6.1・論点 21・8.1 の表）', () {
    test('22 日経過 → 残り 8 日', () {
      expect(_remaining(_after(const Duration(days: 22))), 8);
    });

    test('22 日 23 時間 59 分 59 秒経過 → 残り 7 日（切り捨て）', () {
      // 残りは 7 日 0 時間 0 分 1 秒。inDays は切り捨てなので 7。
      expect(
        _remaining(
          _after(const Duration(days: 22, hours: 23, minutes: 59, seconds: 59)),
        ),
        7,
      );
    });

    test('23 日ちょうど経過 → 残り 7 日', () {
      expect(_remaining(_after(const Duration(days: 23))), 7);
    });

    test('残り 7 日 12 時間は「あと 7 日」（切り上げない）', () {
      // **切り上げにしないこと。** 「あと 8 日」と出したのに 7 日後に
      // 止まると、1 日ぶん嘘をついたことになる。**短めに出すのが安全側。**
      expect(_remaining(_after(const Duration(days: 22, hours: 12))), 7);
    });

    test('29 日 23 時間経過 → 残り 0 日（「あと 0 日」を許す）', () {
      expect(_remaining(_after(const Duration(days: 29, hours: 23))), 0);
    });

    test('30 日ちょうど → 0', () {
      expect(_remaining(_after(const Duration(days: 30))), 0);
    });

    test('31 日経過 → 0（マイナスにしない）', () {
      expect(_remaining(_after(const Duration(days: 31))), 0);
    });

    test('一度も確認できていない（null）→ 0', () {
      expect(
        OfflineAccessPolicy.remainingDays(
          lastVerifiedAt: null,
          now: _after(Duration.zero),
        ),
        0,
      );
    });
  });

  group('予告の帯（6.1・論点 21）', () {
    test('22 日経過（残り 8 日）→ 帯を出さない', () {
      expect(_band(_after(const Duration(days: 22))), OfflineNoticeBand.none);
    });

    test('23 日ちょうど（残り 7 日）→ 予告を出す', () {
      // 残り 7 日を「切ったら」ではなく「7 日以下で」出す（6.1 の表）。
      expect(
        _band(_after(const Duration(days: 23))),
        OfflineNoticeBand.expiring,
      );
    });

    test('22 日 23 時間 59 分 59 秒（残り 7 日）→ 予告を出す', () {
      expect(
        _band(
          _after(const Duration(days: 22, hours: 23, minutes: 59, seconds: 59)),
        ),
        OfflineNoticeBand.expiring,
      );
    });

    test('29 日 23 時間（残り 0 日）→ まだ予告（「あと 0 日」）', () {
      // **残り 0 日と停止は別。** 日数だけで分けると、この 1 段がずれる。
      expect(
        _band(_after(const Duration(days: 29, hours: 23))),
        OfflineNoticeBand.expiring,
      );
    });

    test('30 日ちょうど → 停止の帯に変わる', () {
      expect(
        _band(_after(const Duration(days: 30))),
        OfflineNoticeBand.stopped,
      );
    });

    test('31 日 → 停止の帯', () {
      expect(
        _band(_after(const Duration(days: 31))),
        OfflineNoticeBand.stopped,
      );
    });

    test('一度も確認できていない（null）→ 停止の帯', () {
      expect(
        OfflineAccessPolicy.band(
          lastVerifiedAt: null,
          now: _after(Duration.zero),
        ),
        OfflineNoticeBand.stopped,
      );
    });

    test('帯と再生可否は必ず揃う', () {
      // 「聴けないのに予告の帯」「聴けるのに停止の帯」が起きないこと。
      for (var hours = 0; hours <= 31 * 24; hours += 6) {
        final now = _after(Duration(hours: hours));
        final band = _band(now);
        expect(
          band == OfflineNoticeBand.stopped,
          !_playable(now),
          reason: '経過 $hours 時間で帯と再生可否が食い違っている',
        );
      }
    });
  });
}
