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
  /// **'音楽リスト'**
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

  /// No description provided for @signInWithGoogle.
  ///
  /// In ja, this message translates to:
  /// **'Google でログイン'**
  String get signInWithGoogle;

  /// No description provided for @signInWithEmail.
  ///
  /// In ja, this message translates to:
  /// **'メールアドレスでログイン'**
  String get signInWithEmail;

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
  /// **'パスワードをお忘れですか'**
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

  /// No description provided for @verifyEmailResend.
  ///
  /// In ja, this message translates to:
  /// **'確認メールを再送する'**
  String get verifyEmailResend;

  /// No description provided for @verifyEmailRecheck.
  ///
  /// In ja, this message translates to:
  /// **'確認が済んだので次へ'**
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

  /// No description provided for @columnTitle.
  ///
  /// In ja, this message translates to:
  /// **'曲名'**
  String get columnTitle;

  /// No description provided for @columnArtist.
  ///
  /// In ja, this message translates to:
  /// **'アーティスト名'**
  String get columnArtist;

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

  /// No description provided for @inviteRevokedDone.
  ///
  /// In ja, this message translates to:
  /// **'招待を取り消しました。'**
  String get inviteRevokedDone;

  /// No description provided for @inviteExpiryNote.
  ///
  /// In ja, this message translates to:
  /// **'有効期限：{until} まで。この URL は 1 回しか使えません。'**
  String inviteExpiryNote(String until);

  /// No description provided for @cancelUpload.
  ///
  /// In ja, this message translates to:
  /// **'アップロードを中止'**
  String get cancelUpload;

  /// No description provided for @revokeInvite.
  ///
  /// In ja, this message translates to:
  /// **'招待を取り消す'**
  String get revokeInvite;

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

  /// No description provided for @conflictTitle.
  ///
  /// In ja, this message translates to:
  /// **'保存できませんでした'**
  String get conflictTitle;

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

  /// No description provided for @joinRequestTitle.
  ///
  /// In ja, this message translates to:
  /// **'このリストに参加する'**
  String get joinRequestTitle;

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

  /// No description provided for @inviteAccepted.
  ///
  /// In ja, this message translates to:
  /// **'リストに参加しました。'**
  String get inviteAccepted;

  /// 有効期限は受諾時点で判定（仕様書 3.3）
  ///
  /// In ja, this message translates to:
  /// **'招待の有効期限が切れています。招待した方に再発行を依頼してください。'**
  String get inviteExpired;

  /// No description provided for @inviteAlreadyUsed.
  ///
  /// In ja, this message translates to:
  /// **'この招待はすでに使用されています。招待した方に再発行を依頼してください。'**
  String get inviteAlreadyUsed;

  /// No description provided for @inviteRevoked.
  ///
  /// In ja, this message translates to:
  /// **'この招待は取り消されています。'**
  String get inviteRevoked;

  /// No description provided for @inviteNotFound.
  ///
  /// In ja, this message translates to:
  /// **'招待が見つかりません。URL をご確認ください。'**
  String get inviteNotFound;

  /// No description provided for @inviteAlreadyMember.
  ///
  /// In ja, this message translates to:
  /// **'すでにこのリストに参加しています。'**
  String get inviteAlreadyMember;

  /// No description provided for @createInvite.
  ///
  /// In ja, this message translates to:
  /// **'招待 URL を発行'**
  String get createInvite;

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

  /// No description provided for @requestStatusPending.
  ///
  /// In ja, this message translates to:
  /// **'申請中'**
  String get requestStatusPending;

  /// No description provided for @requestStatusApproved.
  ///
  /// In ja, this message translates to:
  /// **'承認'**
  String get requestStatusApproved;

  /// No description provided for @requestStatusRejected.
  ///
  /// In ja, this message translates to:
  /// **'却下'**
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

  /// No description provided for @members.
  ///
  /// In ja, this message translates to:
  /// **'メンバー'**
  String get members;

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

  /// No description provided for @changeRole.
  ///
  /// In ja, this message translates to:
  /// **'役割を変更'**
  String get changeRole;

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
  /// **'項目が追加された'**
  String get notifyItemAdded;

  /// No description provided for @notifyCommentAdded.
  ///
  /// In ja, this message translates to:
  /// **'コメントが付いた'**
  String get notifyCommentAdded;

  /// No description provided for @notifyQuotaNotice.
  ///
  /// In ja, this message translates to:
  /// **'容量が 80% を超えた'**
  String get notifyQuotaNotice;

  /// No description provided for @notifyQuotaWarning.
  ///
  /// In ja, this message translates to:
  /// **'容量が 90% を超えた'**
  String get notifyQuotaWarning;

  /// No description provided for @notifyListRequested.
  ///
  /// In ja, this message translates to:
  /// **'リスト作成の申請があった'**
  String get notifyListRequested;

  /// No description provided for @notifyJoinRequested.
  ///
  /// In ja, this message translates to:
  /// **'参加申請があった'**
  String get notifyJoinRequested;

  /// No description provided for @notifyRequestApproved.
  ///
  /// In ja, this message translates to:
  /// **'申請が承認された'**
  String get notifyRequestApproved;

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

  /// No description provided for @notFound.
  ///
  /// In ja, this message translates to:
  /// **'ページが見つかりません。'**
  String get notFound;
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
