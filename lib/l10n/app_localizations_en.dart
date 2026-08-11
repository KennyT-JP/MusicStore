// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Track Cabinet';

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
  String get verifyEmailAutoDetect =>
      'Once you open the link, this page moves on by itself.';

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
  String get edit => 'Edit';

  @override
  String get cancelUpload => 'Cancel upload';

  @override
  String get authInvalidEmail => 'That email address is not valid.';

  @override
  String get authUserDisabled => 'This account has been disabled.';

  @override
  String get authWrongCredential =>
      'The email address or password is incorrect.';

  @override
  String get authEmailInUse =>
      'That email address is already in use. Please sign in instead.';

  @override
  String get authWeakPassword =>
      'That password is too short. Use at least 6 characters.';

  @override
  String get authTooManyRequests =>
      'Too many attempts. Please wait a while and try again.';

  @override
  String get authPopupClosed => 'Sign-in was cancelled.';

  @override
  String get authNetworkFailed =>
      'Could not reach the network. Please check your connection.';

  @override
  String get authPopupBlocked =>
      'Your browser blocked the sign-in window. Allow pop-ups for this site and try again.';

  @override
  String get authProviderDisabled =>
      'This sign-in method is not available right now. Please contact an administrator.';

  @override
  String get authUnauthorizedDomain =>
      'Sign-in is not allowed from this address. Please contact an administrator.';

  @override
  String get requestSubmitted => 'Request submitted.';

  @override
  String get requestSubmittedBody =>
      'Please wait for a site administrator to review and approve it.';

  @override
  String get listNameLabel => 'List name';

  @override
  String get listNameHelper => 'A name already in use is not allowed';

  @override
  String get listNameRequired => 'Please enter a list name';

  @override
  String get estimatedTrackCountLabel => 'Estimated number of tracks';

  @override
  String get expectedUserCountLabel => 'Expected number of users';

  @override
  String get purposeLabel => 'Purpose';

  @override
  String get purposeRequired => 'Please enter a purpose';

  @override
  String get nonNegativeNumberRequired => 'Please enter a number of 0 or more';

  @override
  String get openList => 'Open list';

  @override
  String get startPlayback => 'Play';

  @override
  String get pausePlayback => 'Pause';

  @override
  String get stopPlayback => 'Stop';

  @override
  String get playbackFailed => 'Could not play this. Please try again.';

  @override
  String get showDetails => 'Details';

  @override
  String get close => 'Close';

  @override
  String get removeMemberBody =>
      'This member will be removed from the list.\n\nTheir items and comments stay, but their name will be shown as \"Former member\". They can request to join again.';

  @override
  String get leaveListBody =>
      'You will leave this list.\n\nYour items and comments stay, but your name will be shown as \"Former member\".';

  @override
  String get noPendingRequests => 'There are no pending requests.';

  @override
  String get chooseApprovalRole => 'Choose the role to grant';

  @override
  String deleteListBody(String name) {
    return 'This will delete \"$name\".\n\nThere is no backup, so deleted content cannot be restored.';
  }

  @override
  String get usedCapacity => 'Storage used';

  @override
  String get quotaOver90 =>
      'Over 90% of the limit. Ask a site administrator to raise it.';

  @override
  String get quotaOver80 => 'Over 80% of the limit.';

  @override
  String get quotaGraceNote =>
      'Files from deleted items are kept for a while, so deleting does not free space immediately.';

  @override
  String get shareUrl => 'Share URL';

  @override
  String get shareUrlNote =>
      'Anyone with this URL can request to join. They cannot see the contents until approved.';

  @override
  String get noPendingListRequests => 'There are no pending requests.';

  @override
  String get requesterLabel => 'Requested by';

  @override
  String get trackCountLabel => 'Tracks';

  @override
  String trackCountValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'About $count tracks',
      one: 'About 1 track',
    );
    return '$_temp0';
  }

  @override
  String userCountValue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
    );
    return '$_temp0';
  }

  @override
  String get noListsYet => 'There are no lists yet.';

  @override
  String get changeQuota => 'Change storage limit';

  @override
  String changeQuotaBody(Object name) {
    return 'Enter the limit for \"$name\" in MB.';
  }

  @override
  String siteAdminCountSummary(Object admins, Object total) {
    return '$admins of $total users are site admins';
  }

  @override
  String memberCountHeading(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Members ($count)',
      one: 'Members (1)',
    );
    return '$_temp0';
  }

  @override
  String changeRoleTo(String role) {
    return 'Change role: $role';
  }

  @override
  String approveAs(String role) {
    return 'Approve as $role';
  }

  @override
  String get withdrawIrreversible => 'This cannot be undone.';

  @override
  String noItemsHint(String addItem) {
    return 'Use \"$addItem\" at the bottom right to add a file or a URL.';
  }

  @override
  String get removeSiteAdmin => 'Remove as administrator';

  @override
  String get siteAdminGranted =>
      'They are now a site admin. The change applies after they sign in again.';

  @override
  String get siteAdminRevoked =>
      'They are no longer a site admin. The change applies after they sign in again.';

  @override
  String get defaultQuotaLabel => 'Default storage limit for new lists';

  @override
  String get defaultQuotaHelp =>
      'Default 1024 (1GB). Change existing lists from \"Lists and storage\".';

  @override
  String get purgeGraceLabel => 'Days to keep deleted files';

  @override
  String get unitDays => 'days';

  @override
  String get purgeGraceHelp =>
      'Default 30. List administrators can restore during this period, and the space stays used.';

  @override
  String get invalidNumber => 'Please enter a valid number.';

  @override
  String get saved => 'Saved.';

  @override
  String get verificationResent => 'Verification email resent.';

  @override
  String get verificationNotYet =>
      'Not verified yet. Please open the link in the email.';

  @override
  String get displayNameHelper => 'You can change this later';

  @override
  String get passwordHelper => 'At least 6 characters';

  @override
  String get noItemsYet => 'There are no items yet.';

  @override
  String get noSearchResults => 'No items matched your search.';

  @override
  String deleteItemBody(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other:
          'This item will be deleted.\n\nThe file is kept for $days days, and list admins can restore it during that time.',
      one:
          'This item will be deleted.\n\nThe file is kept for 1 day, and list admins can restore it during that time.',
    );
    return '$_temp0';
  }

  @override
  String restorableUntil(Object date) {
    return 'List administrators can restore this until $date.';
  }

  @override
  String get noCommentsYet => 'There are no comments yet.';

  @override
  String replyingTo(Object body) {
    return 'Replying to \"$body\"';
  }

  @override
  String fileWithSize(Object name, Object size) {
    return '$name ($size)';
  }

  @override
  String get fileReplaceNotSupported =>
      'Replacing the file is not implemented yet. You can still change the title, artist and date.';

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
  String get conflictBody =>
      'Someone else updated this item. Please reload the latest version.';

  @override
  String get reload => 'Reload';

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
  String get manageMembers => 'Manage members';

  @override
  String get joinRequests => 'Join requests';

  @override
  String get removeMember => 'Remove from list';

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
  String get withdraw => 'Withdraw from the service';

  @override
  String get withdrawWarning =>
      'Your items and comments stay in the lists after you leave. Your name will be shown as \"Former member\".';

  @override
  String get notifyItemAdded => 'A song was added';

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
  String get notifyItemAddedDetail =>
      'When a song is added to a list you belong to, including lists you manage.';

  @override
  String get notifyCommentAddedDetail =>
      'When a comment is posted on a list you manage, or on something you posted.';

  @override
  String get notifyQuotaNoticeDetail =>
      'When a list you manage passes 80% of its storage limit.';

  @override
  String get notifyQuotaWarningDetail =>
      'When a list you manage passes 90% of its storage limit.';

  @override
  String get notifyListRequestedDetail =>
      'When someone requests a new list. Site admins only.';

  @override
  String get notifyJoinRequestedDetail =>
      'When someone asks to join a list you manage.';

  @override
  String get notifyRequestApprovedDetail =>
      'When a request you submitted is approved.';

  @override
  String get notificationsEmpty => 'No notifications.';

  @override
  String get markAllAsRead => 'Mark all as read';

  @override
  String get functionErrorSignInRequired => 'Please sign in.';

  @override
  String get functionErrorEmailNotVerified =>
      'Your email address is not verified yet. Please open the link in the verification email.';

  @override
  String get functionErrorSiteAdminOnly => 'Only site admins can do this.';

  @override
  String get functionErrorListAdminOnly => 'Only list admins can do this.';

  @override
  String get functionErrorListNotFound => 'That list was not found.';

  @override
  String get functionErrorUserNotFound => 'That user was not found.';

  @override
  String get functionErrorRequestNotFound => 'That request was not found.';

  @override
  String get functionErrorRequestAlreadyHandled =>
      'This request has already been handled.';

  @override
  String get functionErrorListNameMissing => 'The list name is missing.';

  @override
  String get functionErrorRequesterUnknown => 'The requester is unknown.';

  @override
  String get functionErrorInvalidTrackCount =>
      'Please enter a valid number of tracks.';

  @override
  String get functionErrorInvalidUserCount =>
      'Please enter a valid number of users.';

  @override
  String get functionErrorInvalidQuota => 'The limit must be at least 1 byte.';

  @override
  String get functionErrorLastSiteAdmin =>
      'You are currently the only site admin. Please appoint another site admin first.';

  @override
  String get functionErrorAlreadyMember => 'You have already joined this list.';

  @override
  String get functionErrorRoleNotAllowed =>
      'Please choose Super User or Read Only.';

  @override
  String get functionErrorMissingField => 'Something required is missing.';

  @override
  String get functionErrorFieldTooLong => 'That value is too long.';

  @override
  String get functionErrorSelfNotAllowed =>
      'You cannot do this to your own account. To leave, use the withdrawal option in Settings.';

  @override
  String get functionErrorEmailInvalid => 'That email address is not valid.';

  @override
  String get functionErrorPasswordTooShort =>
      'The password must be at least 6 characters.';

  @override
  String get functionErrorEmailAlreadyInUse =>
      'That email address is already in use.';

  @override
  String get addUser => 'Add user';

  @override
  String get addUserBody =>
      'You choose the password. Ask them to change it once you have handed it over.';

  @override
  String get addUserSubmit => 'Add';

  @override
  String get displayNameRequired => 'Please enter a display name';

  @override
  String get userAdded => 'User added.';

  @override
  String get disableUser => 'Disable';

  @override
  String get enableUser => 'Re-enable';

  @override
  String get deleteUser => 'Delete';

  @override
  String get userDisabledLabel => 'Disabled';

  @override
  String disableUserBody(String name) {
    return 'This will disable \"$name\".\n\nThey can no longer sign in and will be removed from the lists they belong to. Their tracks, audio files, and comments are kept.\n\nYou can re-enable them later.';
  }

  @override
  String enableUserBody(String name) {
    return 'This will re-enable \"$name\".\n\nThey can sign in again. They are not returned to the lists they belonged to, so invite them again if needed.';
  }

  @override
  String deleteUserBody(String name) {
    return 'This will delete \"$name\".\n\nTheir account and the tracks and audio files they added will be removed. Their comments stay, shown as \"Former member\".\n\nThere is no backup, so this cannot be undone. Disabling instead keeps their data.';
  }

  @override
  String get userDisabled => 'User disabled.';

  @override
  String get userEnabled => 'User re-enabled.';

  @override
  String get userDeleted => 'User deleted.';

  @override
  String functionErrorListNameTaken(String listName) {
    return '\"$listName\" is already in use or pending.';
  }

  @override
  String get errorGeneric => 'Something went wrong. Please try again later.';

  @override
  String get errorNoPermission => 'You do not have permission to do this.';

  @override
  String get operationFailed =>
      'Could not complete the action. Please check your connection and try again.';

  @override
  String get notFound => 'Page not found.';

  @override
  String get createShareLink => 'Create a share link';

  @override
  String get copyShareLink => 'Copy link';

  @override
  String get shareLinkCopied => 'Link copied.';

  @override
  String get shareLinkReusableNote =>
      'It never expires and can be used by any number of people, any number of times. Revoke it to stop it.';

  @override
  String get shareLinkCopyFailed =>
      'Could not copy the link. Please try again.';

  @override
  String get copyItemShareLink => 'Copy a link to this track';

  @override
  String get revokeShareLink => 'Revoke link';

  @override
  String get shareLinkRevokedDone => 'Link revoked. It can no longer be used.';

  @override
  String get shareLinkReceived => 'A link was shared with you';

  @override
  String get shareLinkChooseHint => 'Choose one. You can change this later.';

  @override
  String get shareLinkJoinTitle => 'Become a list member';

  @override
  String get shareLinkJoinBody =>
      'You become a member. You can add tracks and comments. Your name appears in the member list and you are notified when tracks are added.';

  @override
  String get shareLinkViewTitle => 'View without becoming a member';

  @override
  String get shareLinkViewBody =>
      'You do not become a member. You can browse the tracks and listen to them. You will not appear in the member list, receive no notifications, and cannot post.';

  @override
  String get shareLinkChangeLaterNote =>
      'If you choose to view without becoming a member and later change your mind, just open the same link again.';

  @override
  String get shareLinkNotFound => 'Link not found. Please check the URL.';

  @override
  String get shareLinkRevoked =>
      'This link has been revoked. Please ask for a new one.';

  @override
  String get functionErrorShareLinkNotFound =>
      'Link not found. Please check the URL.';

  @override
  String get functionErrorShareLinkRevoked => 'This link has been revoked.';

  @override
  String get functionErrorItemNotFound => 'Track not found.';

  @override
  String get viewersTitle => 'Viewing without joining';

  @override
  String get viewersEmpty => 'No one yet.';

  @override
  String get addToList => 'Add to a list';

  @override
  String addToListTitle(String name) {
    return 'Add $name to a list';
  }

  @override
  String get addToListEmpty => 'There are no lists yet.';

  @override
  String addAs(String role) {
    return 'Add as $role';
  }

  @override
  String addToListDone(String list) {
    return 'Added to $list';
  }

  @override
  String get functionErrorUserDisabled =>
      'That user is disabled. Enable them first.';

  @override
  String get functionErrorUserWithdrawn => 'That user has withdrawn.';
}
