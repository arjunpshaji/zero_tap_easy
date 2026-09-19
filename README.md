# zero_tap_easy

[![pub package](https://img.shields.io/pub/v/zero_tap_easy.svg)](https://pub.dev/packages/zero_tap_easy)
[![likes](https://img.shields.io/pub/likes/zero_tap_easy)](https://pub.dev/packages/zero_tap_easy/score)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)

Zero-tap sign-in restoration for Android. Silently recreate a signed-in session
on a user's new device using Credential Manager's
[Restore Credentials](https://developer.android.com/identity/sign-in/restore-credentials).

Your user buys a new phone, restores their apps, opens yours — and is already
signed in. No password, no OAuth round trip, no tap.

> **Google Play requires this from April 2027.** Apps with sign-in that don't
> support Zero-Tap Sign-In restoration will lose full publishing capability and
> Play Store visibility.
> [Play technical quality requirements →](https://support.google.com/googleplay/android-developer/answer/17492799)

## Features

- **4 methods, 1 import** — `isSupported`, `createRestoreKey`, `getRestoreKey`,
  `clearRestoreKey`.
- **Automatic E2EE fallback** — retries with local-only key when the device has
  no backup or screen lock.
- **Typed exceptions** with stable error codes — no string-matching on platform
  errors.
- **Platform-safe** — `isSupported()` returns `false` on iOS, web, and desktop;
  never throws.
- **Testable** — swap the platform interface for a fake with zero device
  dependency.
- **No manifest changes** — no `allowBackup` edits, no Gradle changes, no
  `MainActivity` subclassing.

## Getting started

### Prerequisites

| Requirement | Minimum |
|---|---|
| Android | 9 (API 28) |
| Google Play services | 24220000 |
| Flutter | 3.3.0 |
| Dart SDK | 3.5.0 |

The plugin's `minSdk` is 21. Restore keys are gated at runtime, so a low
`minSdk` still compiles and runs — `isSupported()` simply returns `false` on
older devices.

### You need a server

**Restore keys are WebAuthn credentials.** This package handles the device half.
Your backend must issue and verify
[WebAuthn options](https://developers.google.com/identity/passkeys/developer-guides/server-introduction),
exactly as a passkey relying party does. If you already run a passkey server,
reuse it.

**Firebase Auth alone is not enough.** Firebase has no WebAuthn relying party.
You need your own endpoints; for Firebase, mint a custom token server-side and
call `signInWithCustomToken`.

### Installation

Add `zero_tap_easy` to your `pubspec.yaml`:

```yaml
dependencies:
  zero_tap_easy: ^0.1.0
```

Or install via the command line:

```console
$ flutter pub add zero_tap_easy
```

That is the whole setup. No manifest edits, no Gradle changes.

## Usage

### Quick start

```dart
import 'package:zero_tap_easy/zero_tap_easy.dart';

// ── After the user signs in (once per account per device) ────────────
if (await ZeroTapEasy.isSupported()) {
  final options = await api.getRegistrationOptions();
  final created = await ZeroTapEasy.createRestoreKey(options);
  await api.verifyRegistration(created.responseJson);
}

// ── On app launch, when nobody is signed in ──────────────────────────
if (await ZeroTapEasy.isSupported()) {
  final options = await api.getAuthenticationOptions();
  final assertion = await ZeroTapEasy.getRestoreKey(options);
  if (assertion != null) {
    await api.verifyAssertion(assertion); // returns a session
  }
}

// ── On sign-out ──────────────────────────────────────────────────────
await ZeroTapEasy.clearRestoreKey();
```

### Full integration example

Below is a production-style sign-in flow showing where each method fits.

```dart
import 'package:zero_tap_easy/zero_tap_easy.dart';

class AuthService {
  final ApiClient api;
  final LocalStorage storage;

  AuthService(this.api, this.storage);

  /// Call on app launch before showing the sign-in screen.
  Future<String?> tryRestoreSession() async {
    if (!await ZeroTapEasy.isSupported()) return null;
    if (storage.hasSession) return null; // already signed in

    try {
      final options = await api.getAuthenticationOptions();
      final assertion = await ZeroTapEasy.getRestoreKey(options);
      if (assertion == null) return null; // no key on this device

      // Server verifies the assertion and returns a session token.
      final session = await api.verifyRestoreAssertion(assertion);
      await storage.saveSession(session);
      return session;
    } on ZeroTapException catch (e) {
      // A restore key is a convenience — never block launch.
      print('Restore failed (${e.code}): ${e.message}');
      return null;
    }
  }

  /// Call after a successful sign-in or registration.
  Future<void> registerRestoreKey() async {
    if (!await ZeroTapEasy.isSupported()) return;
    if (storage.hasRestoreKey) return; // already registered on this device

    try {
      final options = await api.getRegistrationOptions();
      final created = await ZeroTapEasy.createRestoreKey(options);
      await api.verifyRestoreRegistration(created.responseJson);

      if (!created.usedCloudBackup) {
        // Key is local-only. It survives device-to-device transfer
        // but NOT a cloud restore (how most people migrate).
        print('Warning: restore key is local-only');
      }

      storage.hasRestoreKey = true;
    } on ZeroTapException catch (e) {
      print('Restore key creation failed (${e.code}): ${e.message}');
    }
  }

  /// Call on sign-out, account deletion, or server-side session revocation.
  Future<void> signOut() async {
    await ZeroTapEasy.clearRestoreKey();
    await api.revokeSession();
    storage.clearAll();
  }
}
```

### Handling the cloud-backup fallback

When the device cannot support cloud backup (no Google backup or no screen
lock), Android raises `E2eeUnavailableException`. By default,
`createRestoreKey` retries once with cloud backup off. You can opt out:

```dart
try {
  final created = await ZeroTapEasy.createRestoreKey(
    options,
    retryWithoutCloudBackup: false, // don't auto-retry
  );
} on ZeroTapE2eeUnavailableException {
  // Device can't do cloud backup — decide what to do yourself.
  showDialog('Enable a screen lock and Google backup for best results.');
}
```

## API reference

### `ZeroTapEasy.isSupported()`

```dart
static Future<bool> isSupported()
```

Returns `true` only on Android 9+ with Play services ≥ 24220000. Returns
`false` — never throws — on iOS, web, desktop, older Android, and devices
without Play services. Guard the other three methods with this.

### `ZeroTapEasy.createRestoreKey()`

```dart
static Future<RestoreKeyCreation> createRestoreKey(
  String requestJson, {
  bool isCloudBackupEnabled = true,
  bool retryWithoutCloudBackup = true,
})
```

Creates a restore key. `requestJson` is a WebAuthn
`PublicKeyCredentialCreationOptionsJSON` from your server.

Returns a `RestoreKeyCreation` with:
- `responseJson` — the WebAuthn registration response to POST to your server.
- `usedCloudBackup` — whether the key was backed up to the cloud.

**Call once per account per device**, not on every login. Track with a flag in
your own storage.

### `ZeroTapEasy.getRestoreKey()`

```dart
static Future<String?> getRestoreKey(String requestJson)
```

Returns the WebAuthn assertion JSON, or `null` when this device holds no restore
key. `requestJson` is a `PublicKeyCredentialRequestOptionsJSON` from your server
with an empty `allowCredentials` (discoverable).

Call on first launch before showing your sign-in screen. **Give it a timeout and
treat every failure as "show the sign-in screen."**

### `ZeroTapEasy.clearRestoreKey()`

```dart
static Future<void> clearRestoreKey()
```

Deletes the restore key. Call on sign-out, account deletion, and server-side
session revocation (HTTP 401 after a password reset or remote logout).

Credential Manager will not do this for you. Without this call, a signed-out
user is silently signed back in on their next device. Safe to call when no key
exists.

## Error handling

Every exception thrown is a `ZeroTapException` with a stable `code`:

| Exception | Code | When |
|---|---|---|
| `ZeroTapUnsupportedException` | `UNSUPPORTED` | Not Android, below API 28, or Play services missing/old |
| `ZeroTapE2eeUnavailableException` | `E2EE_UNAVAILABLE` | No backup or screen lock; only surfaces if retry is disabled |
| `ZeroTapRequestJsonException` | `INVALID_REQUEST_JSON` | Server payload is malformed — a bug, not a device condition |
| `ZeroTapCancelledException` | `CANCELLED` | User or system cancelled the operation |
| `ZeroTapException` | `FAILED` | Anything else from Credential Manager |

**Recommended pattern** — one `catch` that logs and falls through:

```dart
try {
  final assertion = await ZeroTapEasy.getRestoreKey(options);
  if (assertion != null) {
    await api.verifyAssertion(assertion);
  }
} on ZeroTapException catch (e) {
  analytics.log('restore_failed', {'code': e.code, 'message': e.message});
  // Fall through to the normal sign-in screen.
}
```

## Server-side contract

Your backend needs four WebAuthn endpoints:

| Endpoint | Authenticated? | Returns |
|---|---|---|
| Registration options | Yes — user just signed in | `PublicKeyCredentialCreationOptionsJSON` with a valid `user.id` |
| Registration verify | Yes | 200; stores the public key against the user |
| Authentication options | **No** | `PublicKeyCredentialRequestOptionsJSON`, discoverable (empty `allowCredentials`) |
| Authentication verify | **No** | A session for the identified user |

The two unauthenticated endpoints are the part people get wrong. At restore
time your app has no session — that is the entire point.

### Verify `origin` and `androidPackageName`

Restore keys bind to your **package name and signing certificate**, not to a
domain. The `clientDataJSON` looks like:

```json
{
  "type": "webauthn.create",
  "challenge": "…",
  "origin": "android:apk-key-hash:<base64url SHA-256 of your signing cert>",
  "androidPackageName": "com.example.yourapp"
}
```

**Your server must check both fields.** Pin `origin` to the apk-key-hash of
your release signing certificate (plus debug in non-production), and
`androidPackageName` to your `applicationId`.

### Server best practices

Google's guidance for the server side:

1. **Distinguish restore credentials from passkeys** — never list them in
   passkey management UI.
2. **Expect orphaned keys** — uninstall deletes the key locally with no
   callback. Delete old keys when a new one registers.
3. **Long TTL** — a user may sign out mid-migration; the server key must
   survive.
4. **Multiple devices per user** — one active key per device, not per user.
5. **Clear on server-side invalidation** — password reset, remote logout.

## Testing

### Unit testing (no device needed)

Swap the platform implementation to test your sign-in logic without a device:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zero_tap_easy/zero_tap_easy.dart';

class FakeZeroTap extends ZeroTapEasyPlatform
    with MockPlatformInterfaceMixin {
  String? assertionToReturn;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<String> createRestoreKey(
    String requestJson, {
    required bool isCloudBackupEnabled,
  }) async => '{"id":"abc","type":"public-key"}';

  @override
  Future<String?> getRestoreKey(String requestJson) async =>
      assertionToReturn;

  @override
  Future<void> clearRestoreKey() async {}
}

void main() {
  late FakeZeroTap fake;

  setUp(() {
    fake = FakeZeroTap();
    ZeroTapEasyPlatform.instance = fake;
  });

  test('restore sign-in when a key is present', () async {
    fake.assertionToReturn = '{"sig":"x"}';
    final assertion = await ZeroTapEasy.getRestoreKey('{}');
    expect(assertion, isNotNull);
  });

  test('falls through when no key is present', () async {
    fake.assertionToReturn = null;
    final assertion = await ZeroTapEasy.getRestoreKey('{}');
    expect(assertion, isNull);
  });
}
```

### Integration testing (on device or emulator)

The `example/` app includes on-device integration tests:

```console
$ cd example
$ flutter test integration_test -d emulator-5554
```

This verifies the channel round trip, the API/GMS gate, and the null-not-throw
contract on a real device.

### End-to-end: the full migration round trip

This is the only test that proves zero-tap actually works.

1. Launch the emulator **from Android Studio** (2025.2.1+).
2. Run the example app and create a restore key.
3. Running Devices toolbar → **Backup App Data**.
4. Uninstall and reinstall the app.
5. Toolbar → **Restore App Data** → select the backup.
6. Reopen the app — `getRestoreKey` should return a non-null assertion.

See [`TESTING.md`](TESTING.md) for detailed instructions and known gotchas.

## Comparison

| Package | Restore Credentials |
|---|---|
| `credential_manager` | No — one-tap, passwords, passkeys, federated only |
| `passkeys` | Yes, since 2.23.0, as part of a passkey-first API |
| **`zero_tap_easy`** | **Purpose-built for this one job, with no passkey surface** |

If you already use `passkeys` for real passkeys, use its restore support. If
you just need to satisfy the Play requirement with minimal surface area, use
this.

## Limitations

- **Android only.** Every method no-ops or throws elsewhere, by design.
- **Foreground restoration only** (tier 2). Background restoration via
  `BackupAgent.onRestoreFinished()` is planned, not shipped.
- **One account per app.** Restore Credentials does not support multiple
  simultaneous accounts.
- **Tied to your package name.** A different `applicationId` is a different
  restore key.
- **Mobile and tablet only.** Does not cross form factors.
- **First-setup profile only** on multi-profile devices.

## Additional information

- [About Restore Credentials](https://developer.android.com/identity/sign-in/restore-credentials)
- [Implement Restore Credentials](https://developer.android.com/identity/sign-in/restore-credentials-implementation)
- [Test Restore Credentials](https://developer.android.com/identity/sign-in/test-restore-credentials)
- [Play Console technical quality requirements](https://support.google.com/googleplay/android-developer/answer/17492799)
- [Passkeys server guides](https://developers.google.com/identity/passkeys/developer-guides/server-introduction)

### Contributing

Contributions are welcome! Please file issues and pull requests on the
[GitHub repository](https://github.com/arjunpshaji/zero_tap_easy).

### License

MIT — see [LICENSE](LICENSE) for details.
