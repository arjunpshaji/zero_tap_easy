/// Error codes exchanged between the Android plugin and Dart.
///
/// These are internal, but are exposed on [ZeroTapException.code] so callers
/// can log or branch on them without string-matching a message.
abstract final class ZeroTapErrorCode {
  /// Restore keys are not usable on this platform, OS version or device.
  static const String unsupported = 'UNSUPPORTED';

  /// Cloud backup is unavailable: no Google backup, or no screen lock.
  static const String e2eeUnavailable = 'E2EE_UNAVAILABLE';

  /// The supplied `requestJson` was not valid WebAuthn.
  static const String invalidRequestJson = 'INVALID_REQUEST_JSON';

  /// The operation was cancelled, usually by the user or the system.
  static const String cancelled = 'CANCELLED';

  /// Credential Manager failed for any other reason.
  static const String failed = 'FAILED';
}

/// Base class for every error thrown by `zero_tap_easy`.
///
/// Catch this to handle any restore-key failure uniformly. Because a restore
/// key is a convenience and never a requirement, the right response to almost
/// every one of these is to carry on with your normal sign-in flow.
class ZeroTapException implements Exception {
  /// Creates a [ZeroTapException].
  const ZeroTapException(this.code, this.message, {this.details});

  /// A stable code from [ZeroTapErrorCode].
  final String code;

  /// A human-readable description, intended for logs rather than for users.
  final String message;

  /// The underlying platform error, when there was one.
  final Object? details;

  @override
  String toString() => 'ZeroTapException($code): $message';
}

/// Thrown when restore keys cannot be used here at all.
///
/// This means one of: the platform is not Android; the device is below
/// Android 9 (API 28); or Google Play services is missing or older than
/// version 24220000.
///
/// Check [ZeroTapEasy.isSupported] first to avoid this entirely.
class ZeroTapUnsupportedException extends ZeroTapException {
  /// Creates a [ZeroTapUnsupportedException].
  const ZeroTapUnsupportedException(String message, {Object? details})
      : super(ZeroTapErrorCode.unsupported, message, details: details);
}

/// Thrown when a restore key cannot be backed up to the cloud.
///
/// Raised when `isCloudBackupEnabled` was `true` but the device has no Google
/// backup enabled, or no screen lock (pattern, PIN, password or biometric) set,
/// so end-to-end encryption is unavailable.
///
/// [ZeroTapEasy.createRestoreKey] retries automatically with cloud backup
/// disabled unless you pass `retryWithoutCloudBackup: false`, so you will only
/// see this if you opted out of that retry.
class ZeroTapE2eeUnavailableException extends ZeroTapException {
  /// Creates a [ZeroTapE2eeUnavailableException].
  const ZeroTapE2eeUnavailableException(String message, {Object? details})
      : super(ZeroTapErrorCode.e2eeUnavailable, message, details: details);
}

/// Thrown when the `requestJson` handed to the plugin was rejected.
///
/// The JSON must come from your relying-party server and follow the WebAuthn
/// `PublicKeyCredentialCreationOptionsJSON` or
/// `PublicKeyCredentialRequestOptionsJSON` shape. A common cause is a missing
/// or malformed `user.id`. This is a server-side bug, not a device condition —
/// it will fail the same way on every device.
class ZeroTapRequestJsonException extends ZeroTapException {
  /// Creates a [ZeroTapRequestJsonException].
  const ZeroTapRequestJsonException(String message, {Object? details})
      : super(ZeroTapErrorCode.invalidRequestJson, message, details: details);
}

/// Thrown when the operation was cancelled by the user or the system.
class ZeroTapCancelledException extends ZeroTapException {
  /// Creates a [ZeroTapCancelledException].
  const ZeroTapCancelledException(String message, {Object? details})
      : super(ZeroTapErrorCode.cancelled, message, details: details);
}
