// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Music Lists';

  @override
  String get navHome => 'Home';

  @override
  String get navNotifications => 'Notifications';

  @override
  String get navSettings => 'Settings';

  @override
  String get navSiteAdmin => 'Site admin';

  @override
  String get environmentBannerStaging => 'Staging';

  @override
  String get signIn => 'Sign in';

  @override
  String get signUp => 'Create account';

  @override
  String get signOut => 'Sign out';

  @override
  String get signInWithGoogle => 'Sign in with Google';

  @override
  String get signInWithEmail => 'Sign in with email';

  @override
  String get emailLabel => 'Email address';

  @override
  String get passwordLabel => 'Password';

  @override
  String get emailRequired => 'Please enter your email address';

  @override
  String get passwordRequired => 'Please enter your password';

  @override
  String get passwordTooShort => 'Password must be at least 6 characters';

  @override
  String get urlRequired => 'Please enter a URL';

  @override
  String get fileRequired => 'Please choose a file';

  @override
  String get forgotPassword => 'Forgot your password?';

  @override
  String get resetPassword => 'Reset password';

  @override
  String get resetPasswordSent =>
      'We sent you a reset link. Please check your email.';

  @override
  String get verifyEmailTitle => 'Check your email';

  @override
  String verifyEmailBody(String email) {
    return 'We sent a verification email to $email. Open the link in that email to start using the app.';
  }

  @override
  String get verifyEmailResend => 'Resend verification email';

  @override
  String get verifyEmailRecheck => 'I have verified, continue';

  @override
  String get homeTitle => 'Your lists';

  @override
  String get homeEmpty => 'You have not joined any list yet.';

  @override
  String get homeEmptyHint =>
      'To start a new list, submit a request. To join an existing one, ask a member for its share URL.';

  @override
  String get requestNewList => 'Request a new list';

  @override
  String get myRequests => 'My requests';

  @override
  String get roleListAdmin => 'List admin';

  @override
  String get roleSuperUser => 'Super User';

  @override
  String get roleReadOnly => 'Read Only';

  @override
  String get roleSiteAdmin => 'Site admin';

  @override
  String itemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String quotaUsage(String used, String total) {
    return '$used / $total';
  }

  @override
  String get columnSeq => 'No.';

  @override
  String get columnDate => 'Date';

  @override
  String get columnTitle => 'Title';

  @override
  String get columnArtist => 'Artist';

  @override
  String get columnRegistrant => 'Added by';

  @override
  String get sortBy => 'Sort by';

  @override
  String get searchHint => 'Search by title, artist, or file name';

  @override
  String get showDeletedItems => 'Show deleted items';

  @override
  String get itemDeleted => 'Deleted';

  @override
  String get withdrawnUser => 'Former member';

  @override
  String get addItem => 'Add';

  @override
  String get editItem => 'Edit';

  @override
  String get deleteItem => 'Delete';

  @override
  String get restoreItem => 'Restore';

  @override
  String get tabFile => 'File';

  @override
  String get tabUrl => 'URL';

  @override
  String get chooseFile => 'Choose a file';

  @override
  String get urlLabel => 'URL';

  @override
  String get dateLabel => 'Date';

  @override
  String get titleLabel => 'Title (optional)';

  @override
  String get artistLabel => 'Artist (optional)';

  @override
  String get commentLabel => 'Comment (optional)';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String uploadProgress(int percent) {
    return 'Uploading… $percent%';
  }

  @override
  String get uploadFailed => 'Upload failed. Please try again.';

  @override
  String get quotaExceeded =>
      'Storage limit reached. Please contact the list admin.';

  @override
  String quotaRemaining(String remaining) {
    return '$remaining left';
  }

  @override
  String get comments => 'Comments';

  @override
  String get writeComment => 'Write a comment';

  @override
  String get reply => 'Reply';

  @override
  String get commentDeleted => 'Deleted';

  @override
  String get conflictTitle => 'Could not save';

  @override
  String get conflictBody =>
      'Someone else updated this item. Please reload the latest version.';

  @override
  String get reload => 'Reload';

  @override
  String get joinRequestTitle => 'Join this list';

  @override
  String get joinRequestBody =>
      'The contents of this list stay hidden until your request is approved.';

  @override
  String get joinRequestButton => 'Request to join';

  @override
  String get joinRequestSent =>
      'Your request has been sent. Please wait for approval.';

  @override
  String get leaveList => 'Leave this list';

  @override
  String get inviteAccepted => 'You have joined the list.';

  @override
  String get inviteExpired =>
      'This invitation has expired. Please ask for a new one.';

  @override
  String get inviteAlreadyUsed =>
      'This invitation has already been used. Please ask for a new one.';

  @override
  String get inviteRevoked => 'This invitation has been revoked.';

  @override
  String get inviteNotFound => 'Invitation not found. Please check the URL.';

  @override
  String get inviteAlreadyMember => 'You are already a member of this list.';

  @override
  String get createInvite => 'Create invite URL';

  @override
  String get myRequestsEmpty => 'You have no requests yet.';

  @override
  String get myJoinRequests => 'Your join requests';

  @override
  String get open => 'Open';

  @override
  String get requestStatusPending => 'Pending';

  @override
  String get requestStatusApproved => 'Approved';

  @override
  String get requestStatusRejected => 'Rejected';

  @override
  String get requestAgain => 'Request again';

  @override
  String get approve => 'Approve';

  @override
  String get reject => 'Reject';

  @override
  String get members => 'Members';

  @override
  String get manageMembers => 'Manage members';

  @override
  String get joinRequests => 'Join requests';

  @override
  String get removeMember => 'Remove from list';

  @override
  String get changeRole => 'Change role';

  @override
  String get listSettings => 'List settings';

  @override
  String get deleteList => 'Delete list';

  @override
  String get deleteListWarning =>
      'Deleting this list also deletes all of its files and comments. This cannot be undone.';

  @override
  String get siteAdminListRequests => 'List requests';

  @override
  String get siteAdminLists => 'Lists and storage';

  @override
  String get siteAdminUsers => 'Users';

  @override
  String get siteAdminSettings => 'Site settings';

  @override
  String get listsWithoutAdmin => 'Lists without an admin';

  @override
  String get assignListAdmin => 'Assign a list admin';

  @override
  String get promoteToSiteAdmin => 'Make site admin';

  @override
  String get lastSiteAdminBlocked =>
      'You are currently the only site admin. Please appoint another site admin first.';

  @override
  String get displayName => 'Display name';

  @override
  String get language => 'Language';

  @override
  String get notificationSettings => 'Notifications';

  @override
  String get notificationMaster => 'All notifications';

  @override
  String get withdraw => 'Delete my account';

  @override
  String get withdrawWarning =>
      'Your items and comments stay in the lists after you leave. Your name will be shown as \"Former member\".';

  @override
  String get notifyItemAdded => 'An item was added';

  @override
  String get notifyCommentAdded => 'A comment was posted';

  @override
  String get notifyQuotaNotice => 'Storage passed 80%';

  @override
  String get notifyQuotaWarning => 'Storage passed 90%';

  @override
  String get notifyListRequested => 'A list was requested';

  @override
  String get notifyJoinRequested => 'Someone asked to join';

  @override
  String get notifyRequestApproved => 'Your request was approved';

  @override
  String get notificationsEmpty => 'No notifications.';

  @override
  String get markAllAsRead => 'Mark all as read';

  @override
  String get errorGeneric => 'Something went wrong. Please try again later.';

  @override
  String get errorNoPermission => 'You do not have permission to do this.';

  @override
  String get notFound => 'Page not found.';
}
