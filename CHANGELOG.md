# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.1.1

### Fixed

- Correct repository, homepage, and issue tracker URLs in package metadata.

## 0.1.0

Initial release.

### Added

- `ZeroTapEasy.isSupported()` — Android 9 (API 28) and Google Play services
  24220000 detection. Returns `false` rather than throwing on every other
  platform, so the package is safe to call from shared code.
- `ZeroTapEasy.createRestoreKey()` — creates a restore key, automatically
  retrying with cloud backup disabled when the device has no Google backup or
  no screen lock, and reporting which happened via
  `RestoreKeyCreation.usedCloudBackup`.
- `ZeroTapEasy.getRestoreKey()` — returns the WebAuthn assertion JSON, or
  `null` when the device holds no key.
- `ZeroTapEasy.clearRestoreKey()` — for sign-out, account deletion, and
  server-side session invalidation.
- Typed exceptions (`ZeroTapUnsupportedException`,
  `ZeroTapE2eeUnavailableException`, `ZeroTapRequestJsonException`,
  `ZeroTapCancelledException`) with stable error codes, replacing bare
  `PlatformException`s.
- `ZeroTapEasyPlatform` — swappable for unit testing without a device.
- Example app with integration tests and test fixtures for local testing
  without a relying-party server.

### Known limitations

- Foreground (tier 2) restoration only. Background restoration via
  `BackupAgent.onRestoreFinished()` is not implemented yet.
- Android only — by design.
