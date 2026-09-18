# zero_tap_easy — example app

A test bench for exercising the three restore-key operations by hand.

## What it does

- Shows whether restore keys are supported on the current device.
- **Create** — creates a restore key from WebAuthn options JSON you paste in.
- **Get** — retrieves the restore key assertion (or `null` on a fresh install).
- **Clear** — deletes the restore key (for sign-out testing).

## Running

```console
# On an emulator with Google Play services
flutter run -d emulator-5554

# On a physical device
flutter run -d <device-id>
```

## Testing without a server

You don't need a relying-party server to test `createRestoreKey`. Paste the
contents of [`test_fixtures/creation_options.json`](test_fixtures/creation_options.json)
into the text field and press **Create**. It works with an arbitrary `rp.id`
because the credential binds to your APK signing key, not a domain.

For `getRestoreKey`, paste [`test_fixtures/request_options.json`](test_fixtures/request_options.json).
On a fresh install it returns `null` — this is correct, not a failure. A restore
key only becomes retrievable after a backup/restore event.

## Integration tests

```console
flutter test integration_test -d emulator-5554
```

Runs three on-device tests:
1. `isSupported` is `true` on a qualifying device.
2. `getRestoreKey` returns `null` when no key exists.
3. `clearRestoreKey` succeeds when nothing to clear.

## Full migration round trip

See [`TESTING.md`](../TESTING.md) for the complete backup/restore procedure
using Android Studio's device controls.
