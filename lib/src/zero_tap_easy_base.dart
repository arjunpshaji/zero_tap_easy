import 'exceptions.dart';
import 'platform_interface.dart';

/// The outcome of creating a restore key.
///
/// [usedCloudBackup] matters: a key created with cloud backup disabled lives
/// only on this device and will **not** reach a new device restored from a
/// cloud backup. It still works for a device-to-device transfer. Report this to
/// your analytics if you want to understand your real coverage.
class RestoreKeyCreation {
  /// Creates a [RestoreKeyCreation].
  const RestoreKeyCreation({
    required this.responseJson,
    required this.usedCloudBackup,
  });

  /// The WebAuthn registration response JSON.
  ///
  /// POST this to your relying-party server's verification endpoint exactly as
  /// you would a passkey registration response.
  final String responseJson;

  /// Whether the key was created with cloud backup enabled.
  ///
  /// `false` means the create fell back to a local-only key because the device
  /// had no Google backup or no screen lock.
  final bool usedCloudBackup;

  @override
  String toString() =>
      'RestoreKeyCreation(usedCloudBackup: $usedCloudBackup, '
      'responseJson: ${responseJson.length} chars)';
}

/// Zero-tap sign-in restoration for Android, via Credential Manager's
/// Restore Credentials.
///
/// A *restore key* is a system-managed WebAuthn credential your app creates
/// silently after the user signs in. Android Backup carries it to the user's
/// next device, where your app asserts it and signs them straight in — no taps.
/// It is invisible to the user, never appears in passkey management UI, and is
/// independent of how they actually sign in, so your existing Google, Apple,
/// Facebook or password flows are untouched.
///
/// From April 2027 Google Play requires apps with sign-in to support this.
///
/// ## You need a relying-party server
///
/// Restore keys *are* WebAuthn credentials. This package performs the device
/// half; your server must issue and verify the WebAuthn options. Firebase Auth
/// alone is not enough. See the README for the endpoint contract.
///
/// ## Typical use
///
/// ```dart
/// // After the user signs in:
/// if (await ZeroTapEasy.isSupported()) {
///   final options = await api.restoreRegistrationOptions();
///   final created = await ZeroTapEasy.createRestoreKey(options);
///   await api.verifyRestoreRegistration(created.responseJson);
/// }
///
/// // On launch, when nobody is signed in:
/// final options = await api.restoreAuthenticationOptions();
/// final assertion = await ZeroTapEasy.getRestoreKey(options);
/// if (assertion != null) {
///   await api.verifyRestoreAssertion(assertion); // returns a session
/// }
///
/// // On sign-out:
/// await ZeroTapEasy.clearRestoreKey();
/// ```
abstract final class ZeroTapEasy {
  /// Whether restore keys can be used on this device.
  ///
  /// Returns `true` only on Android 9 (API 28) or higher with Google Play
  /// services 24220000 or higher. Returns `false` — never throws — on iOS, web,
  /// desktop, older Android versions and devices without Play services.
  ///
  /// Call this before the other methods; they throw
  /// [ZeroTapUnsupportedException] where this returns `false`.
  static Future<bool> isSupported() => ZeroTapEasyPlatform.instance.isSupported();

  /// Creates a restore key for the user who just signed in.
  ///
  /// [requestJson] is a WebAuthn `PublicKeyCredentialCreationOptionsJSON`
  /// string from your relying-party server. It must carry a valid `user.id`.
  ///
  /// Cloud backup is enabled by default and should stay that way: a key created
  /// without it will not reach a device restored from a cloud backup, which is
  /// how most people migrate. When the device cannot support cloud backup —
  /// no Google backup, or no screen lock — Android raises
  /// `E2eeUnavailableException`; this method then retries once with cloud backup
  /// off and reports that through [RestoreKeyCreation.usedCloudBackup]. Pass
  /// `retryWithoutCloudBackup: false` to get a [ZeroTapE2eeUnavailableException]
  /// instead and decide for yourself.
  ///
  /// Create the key once per account per device, not on every login. Track it
  /// with a flag in your own storage.
  ///
  /// Throws [ZeroTapUnsupportedException] when [isSupported] is `false`, and
  /// [ZeroTapRequestJsonException] when the server payload is malformed.
  static Future<RestoreKeyCreation> createRestoreKey(
    String requestJson, {
    bool isCloudBackupEnabled = true,
    bool retryWithoutCloudBackup = true,
  }) async {
    try {
      final String responseJson =
          await ZeroTapEasyPlatform.instance.createRestoreKey(
        requestJson,
        isCloudBackupEnabled: isCloudBackupEnabled,
      );
      return RestoreKeyCreation(
        responseJson: responseJson,
        usedCloudBackup: isCloudBackupEnabled,
      );
    } on ZeroTapE2eeUnavailableException {
      if (!isCloudBackupEnabled || !retryWithoutCloudBackup) rethrow;
      // The device has no Google backup or no screen lock. A local-only key is
      // still worth having: it survives a device-to-device transfer.
      final String responseJson =
          await ZeroTapEasyPlatform.instance.createRestoreKey(
        requestJson,
        isCloudBackupEnabled: false,
      );
      return RestoreKeyCreation(
        responseJson: responseJson,
        usedCloudBackup: false,
      );
    }
  }

  /// Asserts this device's restore key, if it has one.
  ///
  /// [requestJson] is a WebAuthn `PublicKeyCredentialRequestOptionsJSON` string
  /// from your relying-party server. It should be discoverable — an empty
  /// `allowCredentials` — because at this point you do not know who the user is.
  ///
  /// Returns the WebAuthn authentication response JSON to POST to your server,
  /// which verifies it and hands back a session. Returns `null` when this device
  /// holds no restore key, which is the ordinary case on a fresh install — so
  /// this is an `if`, not a `try`.
  ///
  /// Call it on first launch, before showing your sign-in screen. Give it a
  /// timeout and treat any failure as "show the sign-in screen": a restore key
  /// is a convenience and must never block launch.
  ///
  /// Throws [ZeroTapUnsupportedException] when [isSupported] is `false`.
  static Future<String?> getRestoreKey(String requestJson) =>
      ZeroTapEasyPlatform.instance.getRestoreKey(requestJson);

  /// Deletes the restore key held by this device.
  ///
  /// Call this when the user signs out, when you delete their account, and when
  /// your API reports the session was revoked server-side (an HTTP 401 after a
  /// password reset or a remote logout). Credential Manager is stateless and
  /// will not do it for you — without this call a signed-out user is silently
  /// signed back in on their next device.
  ///
  /// Safe to call when no key exists.
  static Future<void> clearRestoreKey() =>
      ZeroTapEasyPlatform.instance.clearRestoreKey();
}
