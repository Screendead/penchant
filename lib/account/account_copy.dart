// What Account Settings, sign-in and sign-out say about the account and its
// data. Jack approves the deletion copy before release.
abstract final class AccountCopy {
  static const String dataSection = 'Your data';

  static const String profileLoadFailed =
      'Could not load your account. Try again.';

  static const String exportTitle = 'Export my data';
  static const String exportSubtitle =
      'A spreadsheet of every entry and a full copy of your account, '
      'through the share sheet.';
  static const String exportSubject = 'Tracker data export';
  static String exportFailed(String reason) =>
      "Couldn't export your data. $reason";

  static const String deleteTitle = 'Delete account';
  static const String deleteSubtitle =
      'Permanently remove your account and everything you have logged.';

  static const String deleteConfirmTitle = 'Delete your account?';
  static const String deleteConfirmBody =
      'This permanently deletes your account and everything in it: every vice '
      'and every entry you have logged, from our servers and from this '
      'device.\n\n'
      'It cannot be undone, and we cannot recover anything afterwards. If you '
      'want a copy, export your data first.';
  static const String deleteConfirmExportFirst = 'Export first';
  static const String deleteConfirmContinue = 'Continue';

  static const String passwordPromptTitle = 'Confirm it is you';
  static String deletePasswordPrompt(String email) =>
      'Enter the password for $email to delete the account.';
  static String emailChangePasswordPrompt(String email) =>
      'Enter the password for $email to change its email address.';
  static const String deleteConfirmAction = 'Delete account';

  static const String deleting = 'Deleting your account…';
  static const String deleted = 'Your account and all of its data are deleted.';
  static String deleteFailed(String reason) =>
      'Your account is not deleted. $reason Nothing was removed.';
  static String deleteIncomplete(String reason) =>
      'Your account is not deleted. $reason Some entries may already be gone; '
      'try again to finish.';

  static const String cancel = 'Cancel';
  static const String password = 'Password';

  static const String forgotPassword = 'Forgot password?';
  static const String resetTitle = 'Reset your password';
  static const String resetBody =
      'We will email you a link to choose a new password.';
  static const String resetSend = 'Send link';
  static String resetSent(String email) =>
      'If an account exists for $email, a link to reset its password is on '
      'its way.';

  static const String verified = 'Email verified';
  static const String notVerified = 'Email not verified';
  static const String resendVerification = 'Resend link';
  static String verificationSent(String email) =>
      'We sent a verification link to $email.';

  static String emailChangeSent(String email) =>
      'Follow the link we sent to $email to finish changing your address.';

  static const String signOutUnsyncedTitle = 'Entries not synced';
  static const String signOutUnsyncedBody =
      'Some entries on this device have not reached the server yet. Signing '
      'out now deletes them. Connect to the internet and wait a moment to keep '
      'them.';
  static const String signOutAnyway = 'Sign out anyway';
  static String signOutFailed(String reason) => "Couldn't sign out. $reason";
}
