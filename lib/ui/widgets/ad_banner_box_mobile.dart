/// バナー広告の実体（Android / iOS 用）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../config/ads.dart';

/// バナー広告の実体（Android / iOS 用）。
///
/// **ここは「出すと決まったあと」だけが来る場所。** 出す・出さないの判断は
/// `ad_banner_slot.dart` が `config/ads.dart` の [shouldShowBanner] で行う。
///
/// **`google_mobile_ads` を import してよいのはこのファイルだけ。**
/// 広告要求（[AdRequest]）を作る場所も、リポジトリ全体でここ1か所にする
/// （`test/domain/ad_banner_test.dart` が件数を数えている）。複数箇所で作ると、
/// **片方だけパーソナライズ広告になる**事故が起きる。
class AdBannerBox extends StatefulWidget {
  const AdBannerBox({super.key});

  @override
  State<AdBannerBox> createState() => _AdBannerBoxState();
}

/// **唯一の広告要求。** 必ず非パーソナライズ（仕様: UMP 同意フォームも ATT も
/// 実装しないので、追跡の同意を取る手段が無い）。
///
/// `nonPersonalizedAds: true` は「利用者を追跡しない広告だけを要求する」の意。
/// ここを外す・別の場所でもう1つ [AdRequest] を作る、のどちらも
/// **同意なしの追跡**につながるので、見張りで固定してある。
AdRequest buildAdRequest() => const AdRequest(nonPersonalizedAds: true);

/// AdMob SDK の初期化は**アプリで一度だけ**。
///
/// `main()` ではなくここで行う。**広告を出さない環境（Web・プレミアム・
/// 非対応プラットフォーム）では SDK に一切触らない**ようにするため——起動時に
/// 必ず呼ぶ作りにすると、広告を出さない人にも初期化の通信と待ち時間が発生する。
Future<void>? _initialization;

Future<void> _ensureInitialized() {
  return _initialization ??= () async {
    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      // 初期化に失敗しても**アプリは動かす**（広告が出ないだけ）。
      // ただし理由は捨てない（握りつぶしてよいのは処理の継続だけ）。
      debugPrint('AdMob の初期化に失敗: $e');
    }
  }();
}

/// 読み込みの状態。**失敗したら畳む**（空の帯を残さない）。
enum _AdState { loading, loaded, failed }

class _AdBannerBoxState extends State<AdBannerBox> {
  static const _size = AdSize.banner; // 320x50。変えるなら高さの予約も一緒に

  /// 読み込みを待つ上限。**外部の完了待ちには必ず上限を付ける**——SDK が
  /// 応答しない環境（プラグインの登録漏れ・スクリーンショット採取など）では
  /// `onAdLoaded` も `onAdFailedToLoad` も**永久に来ない**。上限が無いと、
  /// 予約した高さの空き帯が画面の下に残り続ける。
  static const _loadTimeout = Duration(seconds: 10);

  BannerAd? _ad;
  Timer? _timeout;
  _AdState _state = _AdState.loading;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _fail(String why) {
    debugPrint('バナー広告を出さない: $why');
    if (!mounted) return;
    setState(() => _state = _AdState.failed);
  }

  Future<void> _start() async {
    _timeout = Timer(_loadTimeout, () {
      if (_state == _AdState.loading) {
        _fail('${_loadTimeout.inSeconds}秒で応答なし');
      }
    });
    await _ensureInitialized();
    if (!mounted) return;
    final ad = BannerAd(
      size: _size,
      adUnitId: bannerAdUnitId(platform: currentAdPlatform),
      request: buildAdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _state = _AdState.loaded);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _ad = null;
          _fail('読み込みに失敗（$error）');
        },
      ),
    );
    _ad = ad;
    try {
      await ad.load();
    } catch (e) {
      // 端末やテスト環境で SDK が居ないときはここに来る（画面は壊さない）。
      _fail('要求できない（$e）');
    }
  }

  @override
  void dispose() {
    // **必ず止める。** 残すと、画面を離れたあとに setState を呼ぶだけでなく、
    // ウィジェットテストが「Timer が残っている」で落ちる。
    _timeout?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (_state == _AdState.failed || ad == null) {
      // **読み込めなかったら何も置かない。** 空の帯を残すと、画面の下が
      // 意味もなく削られる。
      return const SizedBox.shrink();
    }
    // **読み込み中も高さを予約する。** 後から差し込むと、広告が届いた瞬間に
    // 画面が跳ねる（下部ナビの押す位置がずれるのが一番困る）。
    return SizedBox(
      height: _size.height.toDouble(),
      width: double.infinity,
      child: _state == _AdState.loaded
          ? Center(
              child: SizedBox(
                width: _size.width.toDouble(),
                height: _size.height.toDouble(),
                child: AdWidget(ad: ad),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
