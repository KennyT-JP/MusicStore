import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
  ];

  /// アプリ名。ブラウザのタブと上部バーに表示する
  ///
  /// In ja, this message translates to:
  /// **'音源創庫'**
  String get appTitle;

  /// No description provided for @navHome.
  ///
  /// In ja, this message translates to:
  /// **'ホーム'**
  String get navHome;

  /// No description provided for @navNotifications.
  ///
  /// In ja, this message translates to:
  /// **'通知'**
  String get navNotifications;

  /// No description provided for @navSettings.
  ///
  /// In ja, this message translates to:
  /// **'設定'**
  String get navSettings;

  /// No description provided for @navSiteAdmin.
  ///
  /// In ja, this message translates to:
  /// **'サイト管理'**
  String get navSiteAdmin;

  /// 本番以外で作業していることを見失わないための表示（仕様書 12.2）
  ///
  /// In ja, this message translates to:
  /// **'検証環境'**
  String get environmentBannerStaging;

  /// No description provided for @signIn.
  ///
  /// In ja, this message translates to:
  /// **'ログイン'**
  String get signIn;

  /// No description provided for @signUp.
  ///
  /// In ja, this message translates to:
  /// **'アカウントを作成'**
  String get signUp;

  /// No description provided for @signOut.
  ///
  /// In ja, this message translates to:
  /// **'ログアウト'**
  String get signOut;

  /// No description provided for @emailLabel.
  ///
  /// In ja, this message translates to:
  /// **'メールアドレス'**
  String get emailLabel;

  /// No description provided for @passwordLabel.
  ///
  /// In ja, this message translates to:
  /// **'パスワード'**
  String get passwordLabel;

  /// No description provided for @emailRequired.
  ///
  /// In ja, this message translates to:
  /// **'メールアドレスを入力してください'**
  String get emailRequired;

  /// No description provided for @passwordRequired.
  ///
  /// In ja, this message translates to:
  /// **'パスワードを入力してください'**
  String get passwordRequired;

  /// No description provided for @passwordTooShort.
  ///
  /// In ja, this message translates to:
  /// **'パスワードは 6 文字以上で入力してください'**
  String get passwordTooShort;

  /// No description provided for @urlRequired.
  ///
  /// In ja, this message translates to:
  /// **'URL を入力してください'**
  String get urlRequired;

  /// No description provided for @fileRequired.
  ///
  /// In ja, this message translates to:
  /// **'ファイルを選択してください'**
  String get fileRequired;

  /// No description provided for @forgotPassword.
  ///
  /// In ja, this message translates to:
  /// **'パスワードをお忘れですか？'**
  String get forgotPassword;

  /// No description provided for @resetPassword.
  ///
  /// In ja, this message translates to:
  /// **'パスワードを再設定'**
  String get resetPassword;

  /// No description provided for @resetPasswordSent.
  ///
  /// In ja, this message translates to:
  /// **'再設定用のリンクを送信しました。メールをご確認ください。'**
  String get resetPasswordSent;

  /// No description provided for @verifyEmailTitle.
  ///
  /// In ja, this message translates to:
  /// **'確認メールを送りました'**
  String get verifyEmailTitle;

  /// メール確認は必須（仕様書 3.1）
  ///
  /// In ja, this message translates to:
  /// **'{email} 宛に確認メールを送りました。メール内のリンクを開くと、ご利用いただけます。'**
  String verifyEmailBody(String email);

  /// No description provided for @verifyEmailAutoDetect.
  ///
  /// In ja, this message translates to:
  /// **'リンクを開くと、この画面も自動で次に進みます。'**
  String get verifyEmailAutoDetect;

  /// No description provided for @verifyEmailResend.
  ///
  /// In ja, this message translates to:
  /// **'確認メールを再送する'**
  String get verifyEmailResend;

  /// No description provided for @verifyEmailRecheck.
  ///
  /// In ja, this message translates to:
  /// **'確認を済ませたら次へ'**
  String get verifyEmailRecheck;

  /// No description provided for @homeTitle.
  ///
  /// In ja, this message translates to:
  /// **'参加しているリスト'**
  String get homeTitle;

  /// No description provided for @homeEmpty.
  ///
  /// In ja, this message translates to:
  /// **'まだどのリストにも参加していません。'**
  String get homeEmpty;

  /// No description provided for @homeEmptyHint.
  ///
  /// In ja, this message translates to:
  /// **'リストを作りたい場合は作成を申請してください。既にあるリストに入りたい場合は、参加している方から共有 URL を受け取ってください。'**
  String get homeEmptyHint;

  /// No description provided for @requestNewList.
  ///
  /// In ja, this message translates to:
  /// **'リスト作成を申請'**
  String get requestNewList;

  /// No description provided for @myRequests.
  ///
  /// In ja, this message translates to:
  /// **'自分の申請'**
  String get myRequests;

  /// No description provided for @roleListAdmin.
  ///
  /// In ja, this message translates to:
  /// **'リスト管理者'**
  String get roleListAdmin;

  /// No description provided for @roleSuperUser.
  ///
  /// In ja, this message translates to:
  /// **'Super User'**
  String get roleSuperUser;

  /// No description provided for @roleReadOnly.
  ///
  /// In ja, this message translates to:
  /// **'Read Only'**
  String get roleReadOnly;

  /// No description provided for @roleSiteAdmin.
  ///
  /// In ja, this message translates to:
  /// **'サイト管理者'**
  String get roleSiteAdmin;

  /// No description provided for @itemCount.
  ///
  /// In ja, this message translates to:
  /// **'{count, plural, other{{count}件}}'**
  String itemCount(int count);

  /// 容量使用量。リスト管理者以上に表示（仕様書 7.4）
  ///
  /// In ja, this message translates to:
  /// **'{used} / {total}'**
  String quotaUsage(String used, String total);

  /// No description provided for @columnSeq.
  ///
  /// In ja, this message translates to:
  /// **'連番'**
  String get columnSeq;

  /// No description provided for @columnDate.
  ///
  /// In ja, this message translates to:
  /// **'日付'**
  String get columnDate;

  /// No description provided for @columnRegistrant.
  ///
  /// In ja, this message translates to:
  /// **'登録者'**
  String get columnRegistrant;

  /// No description provided for @sortBy.
  ///
  /// In ja, this message translates to:
  /// **'並び替え'**
  String get sortBy;

  /// No description provided for @searchHint.
  ///
  /// In ja, this message translates to:
  /// **'曲名・アーティスト名・ファイル名で検索'**
  String get searchHint;

  /// No description provided for @showDeletedItems.
  ///
  /// In ja, this message translates to:
  /// **'削除済みも表示'**
  String get showDeletedItems;

  /// ソフト削除された項目の表示（仕様書 6.2）
  ///
  /// In ja, this message translates to:
  /// **'削除されました'**
  String get itemDeleted;

  /// 退会・除外・離脱したユーザーの表示名（仕様書 3.5 / 5.4）
  ///
  /// In ja, this message translates to:
  /// **'退会したユーザー'**
  String get withdrawnUser;

  /// No description provided for @addItem.
  ///
  /// In ja, this message translates to:
  /// **'追加'**
  String get addItem;

  /// No description provided for @editItem.
  ///
  /// In ja, this message translates to:
  /// **'編集'**
  String get editItem;

  /// No description provided for @deleteItem.
  ///
  /// In ja, this message translates to:
  /// **'削除'**
  String get deleteItem;

  /// No description provided for @restoreItem.
  ///
  /// In ja, this message translates to:
  /// **'復元'**
  String get restoreItem;

  /// No description provided for @tabFile.
  ///
  /// In ja, this message translates to:
  /// **'ファイル'**
  String get tabFile;

  /// No description provided for @tabUrl.
  ///
  /// In ja, this message translates to:
  /// **'URL'**
  String get tabUrl;

  /// No description provided for @chooseFile.
  ///
  /// In ja, this message translates to:
  /// **'ファイルを選択'**
  String get chooseFile;

  /// No description provided for @urlLabel.
  ///
  /// In ja, this message translates to:
  /// **'URL'**
  String get urlLabel;

  /// No description provided for @dateLabel.
  ///
  /// In ja, this message translates to:
  /// **'日付'**
  String get dateLabel;

  /// No description provided for @titleLabel.
  ///
  /// In ja, this message translates to:
  /// **'曲名（任意）'**
  String get titleLabel;

  /// No description provided for @artistLabel.
  ///
  /// In ja, this message translates to:
  /// **'アーティスト名（任意）'**
  String get artistLabel;

  /// No description provided for @commentLabel.
  ///
  /// In ja, this message translates to:
  /// **'コメント（任意）'**
  String get commentLabel;

  /// No description provided for @edit.
  ///
  /// In ja, this message translates to:
  /// **'編集'**
  String get edit;

  /// No description provided for @cancelUpload.
  ///
  /// In ja, this message translates to:
  /// **'アップロードを中止'**
  String get cancelUpload;

  /// No description provided for @authInvalidEmail.
  ///
  /// In ja, this message translates to:
  /// **'メールアドレスの形式が正しくありません。'**
  String get authInvalidEmail;

  /// No description provided for @authUserDisabled.
  ///
  /// In ja, this message translates to:
  /// **'このアカウントは無効になっています。'**
  String get authUserDisabled;

  /// No description provided for @authWrongCredential.
  ///
  /// In ja, this message translates to:
  /// **'メールアドレスまたはパスワードが違います。'**
  String get authWrongCredential;

  /// No description provided for @authEmailInUse.
  ///
  /// In ja, this message translates to:
  /// **'このメールアドレスはすでに使われています。ログインしてください。'**
  String get authEmailInUse;

  /// No description provided for @authWeakPassword.
  ///
  /// In ja, this message translates to:
  /// **'パスワードが短すぎます。6 文字以上にしてください。'**
  String get authWeakPassword;

  /// No description provided for @authTooManyRequests.
  ///
  /// In ja, this message translates to:
  /// **'試行回数が多すぎます。しばらく待ってからお試しください。'**
  String get authTooManyRequests;

  /// No description provided for @authPopupClosed.
  ///
  /// In ja, this message translates to:
  /// **'ログインがキャンセルされました。'**
  String get authPopupClosed;

  /// No description provided for @authNetworkFailed.
  ///
  /// In ja, this message translates to:
  /// **'ネットワークに接続できませんでした。通信状況をご確認ください。'**
  String get authNetworkFailed;

  /// No description provided for @signUpPrompt.
  ///
  /// In ja, this message translates to:
  /// **'はじめての方はこちら（新規登録）'**
  String get signUpPrompt;

  /// No description provided for @orSeparator.
  ///
  /// In ja, this message translates to:
  /// **'または'**
  String get orSeparator;

  /// No description provided for @continueWithGoogle.
  ///
  /// In ja, this message translates to:
  /// **'Google で続ける'**
  String get continueWithGoogle;

  /// No description provided for @showPassword.
  ///
  /// In ja, this message translates to:
  /// **'パスワードを表示'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In ja, this message translates to:
  /// **'パスワードを隠す'**
  String get hidePassword;

  /// No description provided for @authPopupBlocked.
  ///
  /// In ja, this message translates to:
  /// **'ログイン用のウィンドウがブラウザにブロックされました。このサイトのポップアップを許可してから、もう一度お試しください。'**
  String get authPopupBlocked;

  /// No description provided for @authProviderDisabled.
  ///
  /// In ja, this message translates to:
  /// **'この方法でのログインは、いま利用できません。管理者にお問い合わせください。'**
  String get authProviderDisabled;

  /// No description provided for @authUnauthorizedDomain.
  ///
  /// In ja, this message translates to:
  /// **'このアドレスからはログインできない設定になっています。管理者にお問い合わせください。'**
  String get authUnauthorizedDomain;

  /// No description provided for @requestSubmitted.
  ///
  /// In ja, this message translates to:
  /// **'申請しました。'**
  String get requestSubmitted;

  /// No description provided for @requestSubmittedBody.
  ///
  /// In ja, this message translates to:
  /// **'サイト管理者が確認して承認するまでお待ちください。'**
  String get requestSubmittedBody;

  /// No description provided for @listNameLabel.
  ///
  /// In ja, this message translates to:
  /// **'リスト名'**
  String get listNameLabel;

  /// No description provided for @listNameHelper.
  ///
  /// In ja, this message translates to:
  /// **'既にあるリストと同じ名前は使えません'**
  String get listNameHelper;

  /// No description provided for @listNameRequired.
  ///
  /// In ja, this message translates to:
  /// **'リスト名を入力してください'**
  String get listNameRequired;

  /// No description provided for @estimatedTrackCountLabel.
  ///
  /// In ja, this message translates to:
  /// **'概算の登録曲数'**
  String get estimatedTrackCountLabel;

  /// No description provided for @expectedUserCountLabel.
  ///
  /// In ja, this message translates to:
  /// **'使用者数'**
  String get expectedUserCountLabel;

  /// No description provided for @purposeLabel.
  ///
  /// In ja, this message translates to:
  /// **'作成目的'**
  String get purposeLabel;

  /// No description provided for @purposeRequired.
  ///
  /// In ja, this message translates to:
  /// **'作成目的を入力してください'**
  String get purposeRequired;

  /// No description provided for @nonNegativeNumberRequired.
  ///
  /// In ja, this message translates to:
  /// **'0 以上の数値を入力してください'**
  String get nonNegativeNumberRequired;

  /// No description provided for @openList.
  ///
  /// In ja, this message translates to:
  /// **'リストを開く'**
  String get openList;

  /// No description provided for @startPlayback.
  ///
  /// In ja, this message translates to:
  /// **'再生'**
  String get startPlayback;

  /// No description provided for @pausePlayback.
  ///
  /// In ja, this message translates to:
  /// **'一時停止'**
  String get pausePlayback;

  /// No description provided for @stopPlayback.
  ///
  /// In ja, this message translates to:
  /// **'停止'**
  String get stopPlayback;

  /// No description provided for @playbackFailed.
  ///
  /// In ja, this message translates to:
  /// **'再生できませんでした。もう一度お試しください。'**
  String get playbackFailed;

  /// No description provided for @showDetails.
  ///
  /// In ja, this message translates to:
  /// **'詳細'**
  String get showDetails;

  /// No description provided for @help.
  ///
  /// In ja, this message translates to:
  /// **'使い方'**
  String get help;

  /// No description provided for @close.
  ///
  /// In ja, this message translates to:
  /// **'閉じる'**
  String get close;

  /// No description provided for @removeMemberBody.
  ///
  /// In ja, this message translates to:
  /// **'このメンバーをリストから外します。\n\n登録した項目やコメントは残りますが、表示名は「退会したユーザー」になります。あらためて参加申請することもできます。'**
  String get removeMemberBody;

  /// No description provided for @leaveListBody.
  ///
  /// In ja, this message translates to:
  /// **'このリストから抜けます。\n\n登録した項目やコメントは残りますが、表示名は「退会したユーザー」になります。'**
  String get leaveListBody;

  /// No description provided for @noPendingRequests.
  ///
  /// In ja, this message translates to:
  /// **'保留中の申請はありません。'**
  String get noPendingRequests;

  /// No description provided for @chooseApprovalRole.
  ///
  /// In ja, this message translates to:
  /// **'承認する役割を選んでください'**
  String get chooseApprovalRole;

  /// No description provided for @deleteListBody.
  ///
  /// In ja, this message translates to:
  /// **'「{name}」を削除します。\n\nバックアップは取っていないため、削除した内容は元に戻せません。'**
  String deleteListBody(String name);

  /// No description provided for @quotaOver90.
  ///
  /// In ja, this message translates to:
  /// **'上限の 90% を超えています。上限の引き上げはサイト管理者に依頼してください。'**
  String get quotaOver90;

  /// No description provided for @quotaOver80.
  ///
  /// In ja, this message translates to:
  /// **'上限の 80% を超えています。'**
  String get quotaOver80;

  /// No description provided for @quotaGraceNote.
  ///
  /// In ja, this message translates to:
  /// **'削除した項目のファイルは一定期間保持されるため、削除してもすぐには空きが増えません。'**
  String get quotaGraceNote;

  /// No description provided for @shareUrl.
  ///
  /// In ja, this message translates to:
  /// **'共有 URL'**
  String get shareUrl;

  /// No description provided for @shareUrlNote.
  ///
  /// In ja, this message translates to:
  /// **'この URL を渡すと、受け取った人は参加を申請できます。中身は承認するまで見えません。'**
  String get shareUrlNote;

  /// No description provided for @noPendingListRequests.
  ///
  /// In ja, this message translates to:
  /// **'保留中の申請はありません。'**
  String get noPendingListRequests;

  /// No description provided for @requesterLabel.
  ///
  /// In ja, this message translates to:
  /// **'申請者'**
  String get requesterLabel;

  /// No description provided for @trackCountLabel.
  ///
  /// In ja, this message translates to:
  /// **'登録曲数'**
  String get trackCountLabel;

  /// No description provided for @trackCountValue.
  ///
  /// In ja, this message translates to:
  /// **'{count, plural, other{約 {count} 曲}}'**
  String trackCountValue(int count);

  /// No description provided for @userCountValue.
  ///
  /// In ja, this message translates to:
  /// **'{count, plural, other{{count} 人}}'**
  String userCountValue(int count);

  /// No description provided for @noListsYet.
  ///
  /// In ja, this message translates to:
  /// **'リストはまだありません。'**
  String get noListsYet;

  /// No description provided for @changeQuota.
  ///
  /// In ja, this message translates to:
  /// **'容量上限を変更'**
  String get changeQuota;

  /// No description provided for @changeQuotaBody.
  ///
  /// In ja, this message translates to:
  /// **'「{name}」の上限を MB 単位で入力してください。'**
  String changeQuotaBody(Object name);

  /// No description provided for @siteAdminCountSummary.
  ///
  /// In ja, this message translates to:
  /// **'サイト管理者 {admins} 人 / 全 {total} 人'**
  String siteAdminCountSummary(Object admins, Object total);

  /// No description provided for @memberCountHeading.
  ///
  /// In ja, this message translates to:
  /// **'{count, plural, other{メンバー（{count}）}}'**
  String memberCountHeading(int count);

  /// No description provided for @changeRoleTo.
  ///
  /// In ja, this message translates to:
  /// **'役割を変更：{role}'**
  String changeRoleTo(String role);

  /// No description provided for @approveAs.
  ///
  /// In ja, this message translates to:
  /// **'承認：{role}'**
  String approveAs(String role);

  /// No description provided for @withdrawIrreversible.
  ///
  /// In ja, this message translates to:
  /// **'この操作は取り消せません。'**
  String get withdrawIrreversible;

  /// No description provided for @noItemsHint.
  ///
  /// In ja, this message translates to:
  /// **'右下の「{addItem}」から音源や URL を登録できます。'**
  String noItemsHint(String addItem);

  /// No description provided for @removeSiteAdmin.
  ///
  /// In ja, this message translates to:
  /// **'管理者から外す'**
  String get removeSiteAdmin;

  /// No description provided for @siteAdminGranted.
  ///
  /// In ja, this message translates to:
  /// **'サイト管理者にしました。反映には本人の再ログインが必要です。'**
  String get siteAdminGranted;

  /// No description provided for @siteAdminRevoked.
  ///
  /// In ja, this message translates to:
  /// **'サイト管理者から外しました。反映には本人の再ログインが必要です。'**
  String get siteAdminRevoked;

  /// No description provided for @defaultQuotaLabel.
  ///
  /// In ja, this message translates to:
  /// **'新規リストの容量上限'**
  String get defaultQuotaLabel;

  /// No description provided for @defaultQuotaHelp.
  ///
  /// In ja, this message translates to:
  /// **'初期値 1024（1GB）。既存リストの上限は「リストと容量」から変更します。'**
  String get defaultQuotaHelp;

  /// No description provided for @purgeGraceLabel.
  ///
  /// In ja, this message translates to:
  /// **'削除ファイルの保持日数'**
  String get purgeGraceLabel;

  /// No description provided for @unitDays.
  ///
  /// In ja, this message translates to:
  /// **'日'**
  String get unitDays;

  /// No description provided for @purgeGraceHelp.
  ///
  /// In ja, this message translates to:
  /// **'初期値 30。この期間はリスト管理者が復元でき、容量も消費し続けます。'**
  String get purgeGraceHelp;

  /// No description provided for @orphanGraceLabel.
  ///
  /// In ja, this message translates to:
  /// **'行き場を失ったファイルの保持時間'**
  String get orphanGraceLabel;

  /// No description provided for @unitHours.
  ///
  /// In ja, this message translates to:
  /// **'時間'**
  String get unitHours;

  /// No description provided for @orphanGraceHelp.
  ///
  /// In ja, this message translates to:
  /// **'初期値 24。アップロードは終わったのに曲として登録されなかったファイルを、この時間が過ぎてから消します。短くしすぎると、登録の直前のファイルまで巻き添えで消えます。'**
  String get orphanGraceHelp;

  /// No description provided for @invalidNumber.
  ///
  /// In ja, this message translates to:
  /// **'数値を正しく入力してください。'**
  String get invalidNumber;

  /// No description provided for @saved.
  ///
  /// In ja, this message translates to:
  /// **'保存しました。'**
  String get saved;

  /// No description provided for @verificationResent.
  ///
  /// In ja, this message translates to:
  /// **'確認メールを再送しました。'**
  String get verificationResent;

  /// No description provided for @verificationNotYet.
  ///
  /// In ja, this message translates to:
  /// **'まだ確認が済んでいないようです。メール内のリンクを開いてください。'**
  String get verificationNotYet;

  /// No description provided for @displayNameHelper.
  ///
  /// In ja, this message translates to:
  /// **'後から変更できます'**
  String get displayNameHelper;

  /// No description provided for @passwordHelper.
  ///
  /// In ja, this message translates to:
  /// **'6 文字以上'**
  String get passwordHelper;

  /// No description provided for @noItemsYet.
  ///
  /// In ja, this message translates to:
  /// **'まだ項目がありません。'**
  String get noItemsYet;

  /// No description provided for @noSearchResults.
  ///
  /// In ja, this message translates to:
  /// **'該当する項目が見つかりませんでした。'**
  String get noSearchResults;

  /// No description provided for @deleteItemBody.
  ///
  /// In ja, this message translates to:
  /// **'{days, plural, other{この項目を削除します。\n\nファイル本体は {days} 日間保持され、その間はリスト管理者以上が復元できます。}}'**
  String deleteItemBody(int days);

  /// No description provided for @restorableUntil.
  ///
  /// In ja, this message translates to:
  /// **'{date} まではリスト管理者が復元できます。'**
  String restorableUntil(Object date);

  /// No description provided for @noCommentsYet.
  ///
  /// In ja, this message translates to:
  /// **'まだコメントはありません。'**
  String get noCommentsYet;

  /// No description provided for @replyingTo.
  ///
  /// In ja, this message translates to:
  /// **'「{body}」への返信'**
  String replyingTo(Object body);

  /// No description provided for @fileWithSize.
  ///
  /// In ja, this message translates to:
  /// **'{name}（{size}）'**
  String fileWithSize(Object name, Object size);

  /// No description provided for @save.
  ///
  /// In ja, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In ja, this message translates to:
  /// **'キャンセル'**
  String get cancel;

  /// No description provided for @uploadProgress.
  ///
  /// In ja, this message translates to:
  /// **'アップロード中… {percent}%'**
  String uploadProgress(int percent);

  /// No description provided for @uploadFailed.
  ///
  /// In ja, this message translates to:
  /// **'アップロードに失敗しました。もう一度お試しください。'**
  String get uploadFailed;

  /// 上限超過時のアップロードブロック（仕様書 7.3）
  ///
  /// In ja, this message translates to:
  /// **'上限を超えました。リスト管理者にご連絡ください。'**
  String get quotaExceeded;

  /// No description provided for @quotaRemaining.
  ///
  /// In ja, this message translates to:
  /// **'残り {remaining}'**
  String quotaRemaining(String remaining);

  /// No description provided for @comments.
  ///
  /// In ja, this message translates to:
  /// **'コメント'**
  String get comments;

  /// No description provided for @writeComment.
  ///
  /// In ja, this message translates to:
  /// **'コメントを書く'**
  String get writeComment;

  /// No description provided for @reply.
  ///
  /// In ja, this message translates to:
  /// **'返信'**
  String get reply;

  /// No description provided for @commentDeleted.
  ///
  /// In ja, this message translates to:
  /// **'削除されました'**
  String get commentDeleted;

  /// 同時編集の検出（仕様書 6.3）
  ///
  /// In ja, this message translates to:
  /// **'ほかの方がこの項目を更新しました。最新の内容を読み込み直してください。'**
  String get conflictBody;

  /// No description provided for @reload.
  ///
  /// In ja, this message translates to:
  /// **'読み込み直す'**
  String get reload;

  /// No description provided for @joinRequestBody.
  ///
  /// In ja, this message translates to:
  /// **'このリストの中身は、参加が承認されるまで表示されません。'**
  String get joinRequestBody;

  /// No description provided for @joinRequestButton.
  ///
  /// In ja, this message translates to:
  /// **'参加を申請'**
  String get joinRequestButton;

  /// No description provided for @joinRequestSent.
  ///
  /// In ja, this message translates to:
  /// **'参加を申請しました。承認されるまでお待ちください。'**
  String get joinRequestSent;

  /// No description provided for @leaveList.
  ///
  /// In ja, this message translates to:
  /// **'このリストから抜ける'**
  String get leaveList;

  /// No description provided for @stopViewing.
  ///
  /// In ja, this message translates to:
  /// **'このリストを見るのをやめる'**
  String get stopViewing;

  /// No description provided for @stopViewingBody.
  ///
  /// In ja, this message translates to:
  /// **'このリストの閲覧をやめます。\n\n中身は見られなくなりますが、同じ共有リンクからまた入れます。あなたが書いたコメントは残ります。'**
  String get stopViewingBody;

  /// No description provided for @myRequestsEmpty.
  ///
  /// In ja, this message translates to:
  /// **'まだ申請はありません。'**
  String get myRequestsEmpty;

  /// No description provided for @myJoinRequests.
  ///
  /// In ja, this message translates to:
  /// **'自分の参加申請'**
  String get myJoinRequests;

  /// No description provided for @open.
  ///
  /// In ja, this message translates to:
  /// **'開く'**
  String get open;

  /// No description provided for @openLink.
  ///
  /// In ja, this message translates to:
  /// **'リンクを開く'**
  String get openLink;

  /// No description provided for @downloadFile.
  ///
  /// In ja, this message translates to:
  /// **'ファイルをダウンロード'**
  String get downloadFile;

  /// No description provided for @requestStatusPending.
  ///
  /// In ja, this message translates to:
  /// **'申請中'**
  String get requestStatusPending;

  /// No description provided for @requestStatusApproved.
  ///
  /// In ja, this message translates to:
  /// **'承認済み'**
  String get requestStatusApproved;

  /// No description provided for @requestStatusRejected.
  ///
  /// In ja, this message translates to:
  /// **'却下済み'**
  String get requestStatusRejected;

  /// No description provided for @requestAgain.
  ///
  /// In ja, this message translates to:
  /// **'もう一度申請する'**
  String get requestAgain;

  /// No description provided for @approve.
  ///
  /// In ja, this message translates to:
  /// **'承認'**
  String get approve;

  /// No description provided for @reject.
  ///
  /// In ja, this message translates to:
  /// **'却下'**
  String get reject;

  /// No description provided for @manageMembers.
  ///
  /// In ja, this message translates to:
  /// **'メンバー管理'**
  String get manageMembers;

  /// No description provided for @joinRequests.
  ///
  /// In ja, this message translates to:
  /// **'参加申請'**
  String get joinRequests;

  /// No description provided for @removeMember.
  ///
  /// In ja, this message translates to:
  /// **'リストから外す'**
  String get removeMember;

  /// No description provided for @listSettings.
  ///
  /// In ja, this message translates to:
  /// **'リスト設定'**
  String get listSettings;

  /// No description provided for @deleteList.
  ///
  /// In ja, this message translates to:
  /// **'リストを削除'**
  String get deleteList;

  /// No description provided for @deleteListWarning.
  ///
  /// In ja, this message translates to:
  /// **'リストを削除すると、そのリストのファイル・コメントもすべて削除されます。この操作は取り消せません。'**
  String get deleteListWarning;

  /// No description provided for @siteAdminListRequests.
  ///
  /// In ja, this message translates to:
  /// **'リスト作成申請'**
  String get siteAdminListRequests;

  /// No description provided for @siteAdminLists.
  ///
  /// In ja, this message translates to:
  /// **'リストと容量'**
  String get siteAdminLists;

  /// No description provided for @siteAdminUsers.
  ///
  /// In ja, this message translates to:
  /// **'ユーザー管理'**
  String get siteAdminUsers;

  /// No description provided for @siteAdminSettings.
  ///
  /// In ja, this message translates to:
  /// **'サイト設定'**
  String get siteAdminSettings;

  /// No description provided for @listsWithoutAdmin.
  ///
  /// In ja, this message translates to:
  /// **'管理者不在のリスト'**
  String get listsWithoutAdmin;

  /// No description provided for @assignListAdmin.
  ///
  /// In ja, this message translates to:
  /// **'リスト管理者を指名'**
  String get assignListAdmin;

  /// No description provided for @promoteToSiteAdmin.
  ///
  /// In ja, this message translates to:
  /// **'サイト管理者にする'**
  String get promoteToSiteAdmin;

  /// 最後のサイト管理者は降格・退会できない（仕様書 4.5）
  ///
  /// In ja, this message translates to:
  /// **'あなたは現在ただ 1 人のサイト管理者です。先に別の方をサイト管理者に指名してください。'**
  String get lastSiteAdminBlocked;

  /// No description provided for @displayName.
  ///
  /// In ja, this message translates to:
  /// **'表示名'**
  String get displayName;

  /// No description provided for @language.
  ///
  /// In ja, this message translates to:
  /// **'表示言語'**
  String get language;

  /// No description provided for @notificationSettings.
  ///
  /// In ja, this message translates to:
  /// **'通知設定'**
  String get notificationSettings;

  /// No description provided for @notificationMaster.
  ///
  /// In ja, this message translates to:
  /// **'すべての通知'**
  String get notificationMaster;

  /// No description provided for @withdraw.
  ///
  /// In ja, this message translates to:
  /// **'退会する'**
  String get withdraw;

  /// No description provided for @withdrawWarning.
  ///
  /// In ja, this message translates to:
  /// **'退会しても、登録した項目やコメントは残ります。表示名は「退会したユーザー」になります。'**
  String get withdrawWarning;

  /// No description provided for @notifyItemAdded.
  ///
  /// In ja, this message translates to:
  /// **'曲が追加されました'**
  String get notifyItemAdded;

  /// No description provided for @notifyCommentAdded.
  ///
  /// In ja, this message translates to:
  /// **'コメントが付きました'**
  String get notifyCommentAdded;

  /// No description provided for @notifyQuotaNotice.
  ///
  /// In ja, this message translates to:
  /// **'容量が 80% を超えました'**
  String get notifyQuotaNotice;

  /// No description provided for @notifyQuotaWarning.
  ///
  /// In ja, this message translates to:
  /// **'容量が 90% を超えました'**
  String get notifyQuotaWarning;

  /// No description provided for @notifyListRequested.
  ///
  /// In ja, this message translates to:
  /// **'リスト作成の申請がありました'**
  String get notifyListRequested;

  /// No description provided for @notifyJoinRequested.
  ///
  /// In ja, this message translates to:
  /// **'参加申請がありました'**
  String get notifyJoinRequested;

  /// No description provided for @notifyRequestApproved.
  ///
  /// In ja, this message translates to:
  /// **'申請が承認されました'**
  String get notifyRequestApproved;

  /// No description provided for @notifyItemAddedDetail.
  ///
  /// In ja, this message translates to:
  /// **'参加しているリストに曲が追加されたときに届きます。管理しているリストも含みます。'**
  String get notifyItemAddedDetail;

  /// No description provided for @notifyCommentAddedDetail.
  ///
  /// In ja, this message translates to:
  /// **'自分が管理しているリスト、または自分の投稿にコメントが付いたときに届きます。'**
  String get notifyCommentAddedDetail;

  /// No description provided for @notifyQuotaNoticeDetail.
  ///
  /// In ja, this message translates to:
  /// **'管理しているリストの使用容量が上限の 80% を超えたときに届きます。'**
  String get notifyQuotaNoticeDetail;

  /// No description provided for @notifyQuotaWarningDetail.
  ///
  /// In ja, this message translates to:
  /// **'管理しているリストの使用容量が上限の 90% を超えたときに届きます。'**
  String get notifyQuotaWarningDetail;

  /// No description provided for @notifyListRequestedDetail.
  ///
  /// In ja, this message translates to:
  /// **'リスト作成の申請が出されたときに届きます。サイト管理者だけが受け取ります。'**
  String get notifyListRequestedDetail;

  /// No description provided for @notifyJoinRequestedDetail.
  ///
  /// In ja, this message translates to:
  /// **'管理しているリストに参加を申し込まれたときに届きます。'**
  String get notifyJoinRequestedDetail;

  /// No description provided for @notifyRequestApprovedDetail.
  ///
  /// In ja, this message translates to:
  /// **'自分が出した申請が承認されたときに届きます。'**
  String get notifyRequestApprovedDetail;

  /// No description provided for @notificationsEmpty.
  ///
  /// In ja, this message translates to:
  /// **'通知はありません。'**
  String get notificationsEmpty;

  /// No description provided for @markAllAsRead.
  ///
  /// In ja, this message translates to:
  /// **'すべて既読にする'**
  String get markAllAsRead;

  /// No description provided for @functionErrorSignInRequired.
  ///
  /// In ja, this message translates to:
  /// **'ログインが必要です。'**
  String get functionErrorSignInRequired;

  /// No description provided for @functionErrorEmailNotVerified.
  ///
  /// In ja, this message translates to:
  /// **'メールアドレスの確認が済んでいません。確認メールのリンクを開いてください。'**
  String get functionErrorEmailNotVerified;

  /// No description provided for @functionErrorSiteAdminOnly.
  ///
  /// In ja, this message translates to:
  /// **'この操作はサイト管理者のみ行えます。'**
  String get functionErrorSiteAdminOnly;

  /// No description provided for @functionErrorListAdminOnly.
  ///
  /// In ja, this message translates to:
  /// **'この操作はリスト管理者のみ行えます。'**
  String get functionErrorListAdminOnly;

  /// No description provided for @functionErrorListNotFound.
  ///
  /// In ja, this message translates to:
  /// **'リストが見つかりません。'**
  String get functionErrorListNotFound;

  /// No description provided for @functionErrorUserNotFound.
  ///
  /// In ja, this message translates to:
  /// **'ユーザーが見つかりません。'**
  String get functionErrorUserNotFound;

  /// No description provided for @functionErrorRequestNotFound.
  ///
  /// In ja, this message translates to:
  /// **'申請が見つかりません。'**
  String get functionErrorRequestNotFound;

  /// No description provided for @functionErrorRequestAlreadyHandled.
  ///
  /// In ja, this message translates to:
  /// **'この申請はすでに処理されています。'**
  String get functionErrorRequestAlreadyHandled;

  /// No description provided for @functionErrorListNameMissing.
  ///
  /// In ja, this message translates to:
  /// **'リスト名がありません。'**
  String get functionErrorListNameMissing;

  /// No description provided for @functionErrorRequesterUnknown.
  ///
  /// In ja, this message translates to:
  /// **'申請者が不明です。'**
  String get functionErrorRequesterUnknown;

  /// No description provided for @functionErrorInvalidTrackCount.
  ///
  /// In ja, this message translates to:
  /// **'登録曲数を正しく入力してください。'**
  String get functionErrorInvalidTrackCount;

  /// No description provided for @functionErrorInvalidUserCount.
  ///
  /// In ja, this message translates to:
  /// **'使用者数を正しく入力してください。'**
  String get functionErrorInvalidUserCount;

  /// No description provided for @functionErrorInvalidQuota.
  ///
  /// In ja, this message translates to:
  /// **'上限は 1 バイト以上で指定してください。'**
  String get functionErrorInvalidQuota;

  /// No description provided for @functionErrorLastSiteAdmin.
  ///
  /// In ja, this message translates to:
  /// **'あなたは現在ただ 1 人のサイト管理者です。先に別の方をサイト管理者に指名してください。'**
  String get functionErrorLastSiteAdmin;

  /// No description provided for @functionErrorAlreadyMember.
  ///
  /// In ja, this message translates to:
  /// **'すでにこのリストに参加しています。'**
  String get functionErrorAlreadyMember;

  /// No description provided for @functionErrorRoleNotAllowed.
  ///
  /// In ja, this message translates to:
  /// **'役割は Super User か Read Only を指定してください。'**
  String get functionErrorRoleNotAllowed;

  /// No description provided for @functionErrorMissingField.
  ///
  /// In ja, this message translates to:
  /// **'入力が足りません。'**
  String get functionErrorMissingField;

  /// No description provided for @functionErrorFieldTooLong.
  ///
  /// In ja, this message translates to:
  /// **'入力が長すぎます。'**
  String get functionErrorFieldTooLong;

  /// No description provided for @functionErrorSelfNotAllowed.
  ///
  /// In ja, this message translates to:
  /// **'ご自身に対しては行えません。退会される場合は設定からお願いします。'**
  String get functionErrorSelfNotAllowed;

  /// No description provided for @functionErrorEmailInvalid.
  ///
  /// In ja, this message translates to:
  /// **'メールアドレスの形式が正しくありません。'**
  String get functionErrorEmailInvalid;

  /// No description provided for @functionErrorPasswordTooShort.
  ///
  /// In ja, this message translates to:
  /// **'パスワードは 6 文字以上で入力してください。'**
  String get functionErrorPasswordTooShort;

  /// No description provided for @functionErrorEmailAlreadyInUse.
  ///
  /// In ja, this message translates to:
  /// **'このメールアドレスはすでに使われています。'**
  String get functionErrorEmailAlreadyInUse;

  /// No description provided for @addUser.
  ///
  /// In ja, this message translates to:
  /// **'ユーザーを追加'**
  String get addUser;

  /// No description provided for @addUserBody.
  ///
  /// In ja, this message translates to:
  /// **'サイト管理者がパスワードを決めます。お渡ししたあとで、ご本人に変更していただいてください。'**
  String get addUserBody;

  /// No description provided for @addUserSubmit.
  ///
  /// In ja, this message translates to:
  /// **'追加する'**
  String get addUserSubmit;

  /// No description provided for @displayNameRequired.
  ///
  /// In ja, this message translates to:
  /// **'表示名を入力してください'**
  String get displayNameRequired;

  /// No description provided for @userAdded.
  ///
  /// In ja, this message translates to:
  /// **'ユーザーを追加しました。'**
  String get userAdded;

  /// No description provided for @disableUser.
  ///
  /// In ja, this message translates to:
  /// **'無効にする'**
  String get disableUser;

  /// No description provided for @enableUser.
  ///
  /// In ja, this message translates to:
  /// **'有効に戻す'**
  String get enableUser;

  /// No description provided for @deleteUser.
  ///
  /// In ja, this message translates to:
  /// **'削除する'**
  String get deleteUser;

  /// No description provided for @userDisabledLabel.
  ///
  /// In ja, this message translates to:
  /// **'無効'**
  String get userDisabledLabel;

  /// No description provided for @disableUserBody.
  ///
  /// In ja, this message translates to:
  /// **'「{name}」を無効にします。\n\nログインできなくなり、参加中のリストからも外れます。登録した曲・音源ファイル・コメントは残ります。\n\nあとから有効に戻せます。'**
  String disableUserBody(String name);

  /// No description provided for @enableUserBody.
  ///
  /// In ja, this message translates to:
  /// **'「{name}」を有効に戻します。\n\nまたログインできるようになります。参加していたリストには戻らないため、必要であれば改めてご案内ください。'**
  String enableUserBody(String name);

  /// No description provided for @deleteUserBody.
  ///
  /// In ja, this message translates to:
  /// **'「{name}」を削除します。\n\nアカウントと、その方が登録した曲・音源ファイルを消します。書かれたコメントは残り、表示名が「退会したユーザー」になります。\n\nバックアップは取っていないため、削除した内容は元に戻せません。無効にするだけであれば、データは残ります。'**
  String deleteUserBody(String name);

  /// No description provided for @userDisabled.
  ///
  /// In ja, this message translates to:
  /// **'無効にしました。'**
  String get userDisabled;

  /// No description provided for @userEnabled.
  ///
  /// In ja, this message translates to:
  /// **'有効に戻しました。'**
  String get userEnabled;

  /// No description provided for @userDeleted.
  ///
  /// In ja, this message translates to:
  /// **'削除しました。'**
  String get userDeleted;

  /// No description provided for @functionErrorListNameTaken.
  ///
  /// In ja, this message translates to:
  /// **'「{listName}」は既に使われているか、申請中です。'**
  String functionErrorListNameTaken(String listName);

  /// No description provided for @errorGeneric.
  ///
  /// In ja, this message translates to:
  /// **'エラーが発生しました。しばらくしてからもう一度お試しください。'**
  String get errorGeneric;

  /// No description provided for @errorNoPermission.
  ///
  /// In ja, this message translates to:
  /// **'この操作を行う権限がありません。'**
  String get errorNoPermission;

  /// 書き込み（削除・復元・投稿など）が例外で返ったときの共通文言（仕様書 14.4）
  ///
  /// In ja, this message translates to:
  /// **'操作を完了できませんでした。通信状況をご確認のうえ、もう一度お試しください。'**
  String get operationFailed;

  /// No description provided for @notFound.
  ///
  /// In ja, this message translates to:
  /// **'ページが見つかりません。'**
  String get notFound;

  /// No description provided for @createShareLink.
  ///
  /// In ja, this message translates to:
  /// **'共有リンクを作る'**
  String get createShareLink;

  /// 共有リンクをコピーする操作（仕様書 3.3）。リンクは 1 種類だけで、相手の役割は選ばない
  ///
  /// In ja, this message translates to:
  /// **'リンクをコピー'**
  String get copyShareLink;

  /// No description provided for @shareLinkCopied.
  ///
  /// In ja, this message translates to:
  /// **'リンクをコピーしました。'**
  String get shareLinkCopied;

  /// No description provided for @shareLinkReusableNote.
  ///
  /// In ja, this message translates to:
  /// **'有効期限はありません。何人でも、何度でも使えます。止めるときは取り消してください。'**
  String get shareLinkReusableNote;

  /// No description provided for @shareLinkCopyFailed.
  ///
  /// In ja, this message translates to:
  /// **'リンクをコピーできませんでした。もう一度お試しください。'**
  String get shareLinkCopyFailed;

  /// No description provided for @copyItemShareLink.
  ///
  /// In ja, this message translates to:
  /// **'この曲のリンクをコピー'**
  String get copyItemShareLink;

  /// No description provided for @revokeShareLink.
  ///
  /// In ja, this message translates to:
  /// **'リンクを取り消す'**
  String get revokeShareLink;

  /// No description provided for @shareLinkRevokedDone.
  ///
  /// In ja, this message translates to:
  /// **'リンクを取り消しました。以降このリンクからは入れません。'**
  String get shareLinkRevokedDone;

  /// No description provided for @shareLinkReceived.
  ///
  /// In ja, this message translates to:
  /// **'リンクが共有されました'**
  String get shareLinkReceived;

  /// No description provided for @shareLinkChooseHint.
  ///
  /// In ja, this message translates to:
  /// **'どちらかを選んでください。あとから変えられます。'**
  String get shareLinkChooseHint;

  /// No description provided for @shareLinkJoinTitle.
  ///
  /// In ja, this message translates to:
  /// **'リストのメンバーになる'**
  String get shareLinkJoinTitle;

  /// No description provided for @shareLinkJoinBody.
  ///
  /// In ja, this message translates to:
  /// **'メンバーになります。曲やコメントを追加できます。メンバー一覧に名前が出て、曲が追加されると通知が届きます。'**
  String get shareLinkJoinBody;

  /// No description provided for @shareLinkViewTitle.
  ///
  /// In ja, this message translates to:
  /// **'リストのメンバーにならずに見る'**
  String get shareLinkViewTitle;

  /// No description provided for @shareLinkViewBody.
  ///
  /// In ja, this message translates to:
  /// **'メンバーにはなりません。曲の一覧を見て、音を聴くことはできます。メンバー一覧には出ず、通知も届きません。書き込みもできません。'**
  String get shareLinkViewBody;

  /// No description provided for @shareLinkChangeLaterNote.
  ///
  /// In ja, this message translates to:
  /// **'「リストのメンバーにならずに見る」を選んだあとでメンバーになりたくなったら、同じリンクをもう一度開いてください。'**
  String get shareLinkChangeLaterNote;

  /// No description provided for @shareLinkNotFound.
  ///
  /// In ja, this message translates to:
  /// **'リンクが見つかりません。URL をご確認ください。'**
  String get shareLinkNotFound;

  /// No description provided for @shareLinkRevoked.
  ///
  /// In ja, this message translates to:
  /// **'このリンクは取り消されています。共有した方に新しいリンクを依頼してください。'**
  String get shareLinkRevoked;

  /// No description provided for @functionErrorShareLinkNotFound.
  ///
  /// In ja, this message translates to:
  /// **'リンクが見つかりません。URL をご確認ください。'**
  String get functionErrorShareLinkNotFound;

  /// No description provided for @functionErrorShareLinkRevoked.
  ///
  /// In ja, this message translates to:
  /// **'このリンクは取り消されています。'**
  String get functionErrorShareLinkRevoked;

  /// No description provided for @functionErrorItemNotFound.
  ///
  /// In ja, this message translates to:
  /// **'曲が見つかりません。'**
  String get functionErrorItemNotFound;

  /// No description provided for @functionErrorItemDeleted.
  ///
  /// In ja, this message translates to:
  /// **'削除済みの曲は差し替えられません。先に復元してください。'**
  String get functionErrorItemDeleted;

  /// No description provided for @functionErrorCannotEditItem.
  ///
  /// In ja, this message translates to:
  /// **'この曲を編集する権限がありません。'**
  String get functionErrorCannotEditItem;

  /// No description provided for @functionErrorFileNotInThisItem.
  ///
  /// In ja, this message translates to:
  /// **'ファイルの置き場所が正しくありません。もう一度やり直してください。'**
  String get functionErrorFileNotInThisItem;

  /// No description provided for @functionErrorUploadNotFound.
  ///
  /// In ja, this message translates to:
  /// **'アップロードしたファイルが見つかりません。通信の状態を確かめて、もう一度お試しください。'**
  String get functionErrorUploadNotFound;

  /// No description provided for @functionErrorSameStoragePath.
  ///
  /// In ja, this message translates to:
  /// **'同じ場所へ上書きされています。もう一度ファイルを選び直してください。'**
  String get functionErrorSameStoragePath;

  /// No description provided for @viewersTitle.
  ///
  /// In ja, this message translates to:
  /// **'参加せずに見ている人'**
  String get viewersTitle;

  /// No description provided for @viewersEmpty.
  ///
  /// In ja, this message translates to:
  /// **'まだいません。'**
  String get viewersEmpty;

  /// No description provided for @addToList.
  ///
  /// In ja, this message translates to:
  /// **'リストに追加'**
  String get addToList;

  /// No description provided for @addToListTitle.
  ///
  /// In ja, this message translates to:
  /// **'{name} をリストに追加'**
  String addToListTitle(String name);

  /// No description provided for @addToListEmpty.
  ///
  /// In ja, this message translates to:
  /// **'リストがまだありません。'**
  String get addToListEmpty;

  /// No description provided for @addAs.
  ///
  /// In ja, this message translates to:
  /// **'追加：{role}'**
  String addAs(String role);

  /// No description provided for @addToListDone.
  ///
  /// In ja, this message translates to:
  /// **'{list} に追加しました'**
  String addToListDone(String list);

  /// No description provided for @functionErrorUserDisabled.
  ///
  /// In ja, this message translates to:
  /// **'この利用者は無効にされています。先に有効に戻してください。'**
  String get functionErrorUserDisabled;

  /// No description provided for @functionErrorUserWithdrawn.
  ///
  /// In ja, this message translates to:
  /// **'この利用者は退会しています。'**
  String get functionErrorUserWithdrawn;

  /// 設定画面のプレミアム欄（docs/PREMIUM-DESIGN.md 5）
  ///
  /// In ja, this message translates to:
  /// **'プレミアム'**
  String get premiumSection;

  /// No description provided for @premiumActiveUntil.
  ///
  /// In ja, this message translates to:
  /// **'{date} までプレミアムをご利用いただけます。'**
  String premiumActiveUntil(String date);

  /// No description provided for @premiumInactive.
  ///
  /// In ja, this message translates to:
  /// **'現在はプレミアムではありません。'**
  String get premiumInactive;

  /// No description provided for @premiumInactiveNote.
  ///
  /// In ja, this message translates to:
  /// **'プレミアムでない間も、これまでに保存した音源やリストはそのまま残ります。新しいリストを申請なしで作れないだけです。'**
  String get premiumInactiveNote;

  /// No description provided for @couponCodeLabel.
  ///
  /// In ja, this message translates to:
  /// **'クーポンコード'**
  String get couponCodeLabel;

  /// No description provided for @couponCodeRequired.
  ///
  /// In ja, this message translates to:
  /// **'クーポンコードを入力してください'**
  String get couponCodeRequired;

  /// No description provided for @couponRedeem.
  ///
  /// In ja, this message translates to:
  /// **'クーポンを適用'**
  String get couponRedeem;

  /// No description provided for @couponRedeemed.
  ///
  /// In ja, this message translates to:
  /// **'クーポンを適用しました。{date} までプレミアムをご利用いただけます。'**
  String couponRedeemed(String date);

  /// No description provided for @createList.
  ///
  /// In ja, this message translates to:
  /// **'リストを作る'**
  String get createList;

  /// No description provided for @createListNote.
  ///
  /// In ja, this message translates to:
  /// **'プレミアムの方は、申請せずにその場でリストを作成できます。'**
  String get createListNote;

  /// No description provided for @listCreated.
  ///
  /// In ja, this message translates to:
  /// **'リストを作成しました。'**
  String get listCreated;

  /// No description provided for @myStorageTitle.
  ///
  /// In ja, this message translates to:
  /// **'使用中の容量（あなたの合計）'**
  String get myStorageTitle;

  /// No description provided for @myStorageNote.
  ///
  /// In ja, this message translates to:
  /// **'あなたが作成したすべてのリストの合計です。上限はリストごとではなく、この合計に対してかかります。'**
  String get myStorageNote;

  /// No description provided for @myStorageUnknown.
  ///
  /// In ja, this message translates to:
  /// **'使用量はまだ集計されていません。音源を追加すると表示されます。'**
  String get myStorageUnknown;

  /// No description provided for @ownerQuotaTitle.
  ///
  /// In ja, this message translates to:
  /// **'使用中の容量（作成者の合計）'**
  String get ownerQuotaTitle;

  /// No description provided for @ownerQuotaCaption.
  ///
  /// In ja, this message translates to:
  /// **'作成者の合計'**
  String get ownerQuotaCaption;

  /// No description provided for @ownerQuotaNote.
  ///
  /// In ja, this message translates to:
  /// **'このリストを作成した方が持つ、すべてのリストの合計です。このリスト 1 つ分の量ではありません。どなたが音源を追加しても、作成した方の容量から引かれます。'**
  String get ownerQuotaNote;

  /// No description provided for @ownerQuotaUnknown.
  ///
  /// In ja, this message translates to:
  /// **'作成者の合計容量は、まだ集計されていません。しばらくしてからご確認ください。'**
  String get ownerQuotaUnknown;

  /// No description provided for @siteAdminCoupons.
  ///
  /// In ja, this message translates to:
  /// **'クーポン'**
  String get siteAdminCoupons;

  /// No description provided for @couponListEmpty.
  ///
  /// In ja, this message translates to:
  /// **'まだクーポンはありません。'**
  String get couponListEmpty;

  /// No description provided for @couponCreate.
  ///
  /// In ja, this message translates to:
  /// **'クーポンを発行'**
  String get couponCreate;

  /// No description provided for @couponMonthsLabel.
  ///
  /// In ja, this message translates to:
  /// **'付与する月数'**
  String get couponMonthsLabel;

  /// No description provided for @couponMaxUsesLabel.
  ///
  /// In ja, this message translates to:
  /// **'使える人数'**
  String get couponMaxUsesLabel;

  /// No description provided for @couponExpiresLabel.
  ///
  /// In ja, this message translates to:
  /// **'クーポンの有効期限'**
  String get couponExpiresLabel;

  /// No description provided for @couponNoExpiry.
  ///
  /// In ja, this message translates to:
  /// **'期限なし'**
  String get couponNoExpiry;

  /// No description provided for @couponChooseExpiry.
  ///
  /// In ja, this message translates to:
  /// **'期限を決める'**
  String get couponChooseExpiry;

  /// No description provided for @couponClearExpiry.
  ///
  /// In ja, this message translates to:
  /// **'期限を外す'**
  String get couponClearExpiry;

  /// No description provided for @couponCodeAuto.
  ///
  /// In ja, this message translates to:
  /// **'自動で作る'**
  String get couponCodeAuto;

  /// No description provided for @couponCodeManual.
  ///
  /// In ja, this message translates to:
  /// **'文字列を指定'**
  String get couponCodeManual;

  /// No description provided for @couponCodeManualLabel.
  ///
  /// In ja, this message translates to:
  /// **'指定するコード'**
  String get couponCodeManualLabel;

  /// No description provided for @couponCodeManualWarning.
  ///
  /// In ja, this message translates to:
  /// **'指定した文字列は覚えやすいぶん、推測もされやすくなります。使える人数と有効期限を必ず決めてください。'**
  String get couponCodeManualWarning;

  /// No description provided for @couponMonthsValue.
  ///
  /// In ja, this message translates to:
  /// **'{months} か月'**
  String couponMonthsValue(int months);

  /// No description provided for @couponUsesValue.
  ///
  /// In ja, this message translates to:
  /// **'{used} / {max} 人'**
  String couponUsesValue(int used, int max);

  /// No description provided for @couponExpiresOn.
  ///
  /// In ja, this message translates to:
  /// **'期限 {date}'**
  String couponExpiresOn(String date);

  /// No description provided for @couponDisabledLabel.
  ///
  /// In ja, this message translates to:
  /// **'停止中'**
  String get couponDisabledLabel;

  /// No description provided for @couponUsedUpLabel.
  ///
  /// In ja, this message translates to:
  /// **'上限に達しました'**
  String get couponUsedUpLabel;

  /// No description provided for @couponExpiredLabel.
  ///
  /// In ja, this message translates to:
  /// **'期限切れ'**
  String get couponExpiredLabel;

  /// No description provided for @couponDisable.
  ///
  /// In ja, this message translates to:
  /// **'停止する'**
  String get couponDisable;

  /// No description provided for @couponEnable.
  ///
  /// In ja, this message translates to:
  /// **'停止を解除'**
  String get couponEnable;

  /// No description provided for @couponChangeMaxUses.
  ///
  /// In ja, this message translates to:
  /// **'人数を変える'**
  String get couponChangeMaxUses;

  /// No description provided for @couponChangeMaxUsesBody.
  ///
  /// In ja, this message translates to:
  /// **'「{code}」を使える人数を入力してください。すでに使った方より少ない人数にもできます。その場合、これ以上は使えなくなるだけで、すでに使った方のプレミアムは取り消されません。'**
  String couponChangeMaxUsesBody(String code);

  /// No description provided for @couponViewRedemptions.
  ///
  /// In ja, this message translates to:
  /// **'使った人を見る'**
  String get couponViewRedemptions;

  /// No description provided for @couponRedemptionsTitle.
  ///
  /// In ja, this message translates to:
  /// **'「{code}」を使った方'**
  String couponRedemptionsTitle(String code);

  /// No description provided for @couponRedemptionsEmpty.
  ///
  /// In ja, this message translates to:
  /// **'まだどなたも使っていません。'**
  String get couponRedemptionsEmpty;

  /// No description provided for @couponCreated.
  ///
  /// In ja, this message translates to:
  /// **'クーポンを発行しました：{code}'**
  String couponCreated(String code);

  /// No description provided for @couponCopyCode.
  ///
  /// In ja, this message translates to:
  /// **'コードをコピー'**
  String get couponCopyCode;

  /// No description provided for @couponCodeCopied.
  ///
  /// In ja, this message translates to:
  /// **'コードをコピーしました。'**
  String get couponCodeCopied;

  /// No description provided for @extendPremium.
  ///
  /// In ja, this message translates to:
  /// **'プレミアムを延長'**
  String get extendPremium;

  /// No description provided for @extendPremiumBody.
  ///
  /// In ja, this message translates to:
  /// **'{name} のプレミアムを延長します。すでに期限がある場合は、その後ろに足されます。'**
  String extendPremiumBody(String name);

  /// No description provided for @extendPremiumMonthsLabel.
  ///
  /// In ja, this message translates to:
  /// **'延長する月数'**
  String get extendPremiumMonthsLabel;

  /// No description provided for @extendPremiumDone.
  ///
  /// In ja, this message translates to:
  /// **'{date} まで延長しました。'**
  String extendPremiumDone(String date);

  /// No description provided for @setUserQuotaTitle.
  ///
  /// In ja, this message translates to:
  /// **'利用者の容量上限を変更'**
  String get setUserQuotaTitle;

  /// No description provided for @setUserQuotaBody.
  ///
  /// In ja, this message translates to:
  /// **'{name} の容量上限を MB 単位で入力してください。リストごとではなく、その方が作成したすべてのリストの合計に効きます。'**
  String setUserQuotaBody(String name);

  /// No description provided for @setUserQuotaDone.
  ///
  /// In ja, this message translates to:
  /// **'容量上限を変更しました。'**
  String get setUserQuotaDone;

  /// No description provided for @functionErrorPremiumRequired.
  ///
  /// In ja, this message translates to:
  /// **'この操作にはプレミアムが必要です。設定画面でクーポンコードを入力してください。'**
  String get functionErrorPremiumRequired;

  /// No description provided for @functionErrorCouponNotFound.
  ///
  /// In ja, this message translates to:
  /// **'そのクーポンコードは見つかりません。入力した文字をご確認ください。'**
  String get functionErrorCouponNotFound;

  /// No description provided for @functionErrorCouponDisabled.
  ///
  /// In ja, this message translates to:
  /// **'このクーポンは停止されています。配布元にお問い合わせください。'**
  String get functionErrorCouponDisabled;

  /// No description provided for @functionErrorCouponExpired.
  ///
  /// In ja, this message translates to:
  /// **'このクーポンは有効期限が切れています。'**
  String get functionErrorCouponExpired;

  /// No description provided for @functionErrorCouponUsedUp.
  ///
  /// In ja, this message translates to:
  /// **'このクーポンは、使える人数の上限に達しています。'**
  String get functionErrorCouponUsedUp;

  /// No description provided for @functionErrorCouponAlreadyUsed.
  ///
  /// In ja, this message translates to:
  /// **'このクーポンはすでにお使いです。同じクーポンは一度だけ使えます。'**
  String get functionErrorCouponAlreadyUsed;

  /// No description provided for @functionErrorCouponCodeTaken.
  ///
  /// In ja, this message translates to:
  /// **'そのコードはすでに使われています。別の文字列を指定してください。'**
  String get functionErrorCouponCodeTaken;

  /// No description provided for @functionErrorMonthsInvalid.
  ///
  /// In ja, this message translates to:
  /// **'月数は 1 以上の整数で指定してください。'**
  String get functionErrorMonthsInvalid;

  /// No description provided for @functionErrorMaxUsesInvalid.
  ///
  /// In ja, this message translates to:
  /// **'使える人数は 1 以上の整数で指定してください。'**
  String get functionErrorMaxUsesInvalid;

  /// No description provided for @functionErrorTooManyLists.
  ///
  /// In ja, this message translates to:
  /// **'一度に確認できるリストは 50 件までです。オフラインに保存するリストを減らしてから、もう一度お試しください。'**
  String get functionErrorTooManyLists;
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
    case 'ja':
      return AppL10nJa();
  }

  throw FlutterError(
    'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
