# Testing zero_tap_easy in a debug environment

Everything below was executed on **emulator-5554** (Pixel_7 AVD, **API 36**, `google_apis_playstore` image, **GMS 262031038**) on 2026-09-18. Observed output is quoted verbatim. Where something could not be verified, it says so.

---

## The one thing to understand first

A restore key is **not retrievable on the device that created it**. `createRestoreKey` stashes a credential for the backup system; `getRestoreKey` only returns it *after a restore event has delivered it to a device*. On a normal install `getRestoreKey` returns `null`, and that is correct behaviour, not a failure.

Observed:

```
create → PROBE_RESULT: SUCCESS usedCloudBackup=false
get    → PROBE_GET: NULL - no key found     # same install, no restore in between
```

So testing splits into two tiers: what you can verify on one device in seconds, and the full migration round trip, which needs a backup/restore cycle.

---

## Tier 0 — device prerequisites (30 seconds)

```bash
adb shell getprop ro.build.version.sdk                                    # must be >= 28
adb shell dumpsys package com.google.android.gms | grep versionCode       # must be >= 24220000
```

Observed on the Pixel_7 AVD:

```
36
versionCode=262031038  versionName=26.20.31
```

**Emulator requirements:** a **Google Play** system image (not plain `google_apis` — you need Play services). All three AVDs on this machine already qualify (`PlayStore.enabled=true`). API 33–36 all work.

For the cloud-backup path you additionally need a Google account signed in **and a screen lock set**. Without a screen lock you get `E2eeUnavailableException` and the plugin silently falls back to a local-only key — which is exactly what happened above (`usedCloudBackup=false`). That fallback working is itself worth verifying; see Tier 1.

---

## Tier 1 — automated, no server needed (~1 minute)

```bash
cd example
flutter test integration_test -d emulator-5554
```

Observed:

```
00:00 +0: isSupported is true on a device that should support restore keys
00:02 +1: getRestoreKey returns null when the device holds no key
00:06 +2: clearRestoreKey is safe when there is nothing to clear
00:10 +3: All tests passed!
```

This covers the channel round trip, the API/GMS gate, the null-not-throw contract, and clear-when-empty.

> **Why the first test asserts instead of skips.** The other two are guarded by `isSupported()`. If the device didn't meet the gate they would pass vacuously and report green while testing nothing. The suite asserts `isSupported() == true` up front so a wrong test device fails loudly. This mistake was made and caught during the initial review — don't reintroduce it.

---

## Tier 2 — create a real key by hand (~2 minutes, no server needed)

This surprised us and is the most useful discovery for local testing.

**You do not need a relying-party server, and you do not need `assetlinks.json`, to create a restore key.** Hand-written options JSON with an arbitrary `rp.id` works.

`example/test_fixtures/creation_options.json` is ready to use. Run the example app on the emulator, paste the file's contents into the `requestJson` field, and press **Create**.

```bash
cd example && flutter run -d emulator-5554
```

Observed result — a genuine, fully-formed WebAuthn attestation:

```json
{"id":"vKx_U35XaqB84ohC5zQIge_64GpE2pyyRlBaveyrdbc",
 "type":"public-key","authenticatorAttachment":"platform",
 "response":{"clientDataJSON":"…","attestationObject":"…",
             "transports":["internal","hybrid"],"publicKeyAlgorithm":-7}}
```

Decoding the `clientDataJSON` explains why no assetlinks was needed:

```json
{
  "type": "webauthn.create",
  "challenge": "xWiqF-ZQ8KRcFLeRBGnFSlGFiW1U_3r_iojyiqlqJ-w",
  "origin": "android:apk-key-hash:fIYtWWqFTBf6LH9xmZm4_iZ8_DVPAWE3aqgyMrFs1EA",
  "androidPackageName": "com.zerotap.zero_tap_easy_example"
}
```

The origin is the **APK signing-key hash**, not a web origin, and the package name is carried alongside it. The credential is bound to *package + signing certificate*, not to a domain.

### Two consequences

1. **Local testing is far cheaper than expected.** You can exercise create end-to-end today with no backend and no domain.
2. **Your server must validate `origin` and `androidPackageName`.** This is the real package/signature binding — the control §1.4 of the QA plan was reaching for. A server that ignores these accepts a credential minted by any app. Pin `origin` to the apk-key-hash of your release signing cert (and your debug cert in non-prod), and `androidPackageName` to your applicationId.

> **Correction to earlier docs.** `README.md` states that `assetlinks.json` with `delegate_permission/common.get_login_creds` is required. That is the rule for *passkeys shared with a website*; it was carried over without testing. Create demonstrably works without it. Whether `getRestoreKey` after a real restore also works without it is **still unverified** — see Tier 3. Treat the README's assetlinks section as unconfirmed until that test runs.

### Verifying the E2EE fallback

The emulator had no screen lock, so the create above returned `usedCloudBackup=false`. That means `E2eeUnavailableException` was raised by Android and the plugin's automatic retry caught it and produced a local-only key — **the fallback path is confirmed working on device**, not just in unit tests. To verify the other branch, set a screen lock (Settings → Security → Screen lock → PIN), sign into a Google account, enable backup, and repeat: you should get `usedCloudBackup=true`.

---

## Tier 3 — the full migration round trip

This is the only tier that proves zero-tap actually works, and **it cannot be driven from the command line.**

### What does not work

```bash
adb shell bmgr enable true
adb shell bmgr transport com.google.android.gms/.backup.migrate.service.D2dTransport
adb shell bmgr backupnow com.zerotap.zero_tap_easy_example
# → Package com.zerotap.zero_tap_easy_example with result: Package not found
```

Same result via `com.android.localtransport/.LocalTransport`. `bmgr` moves **app data**; a restore key lives in the system credential store and is carried by the restore infrastructure, so `bmgr backupnow <pkg>` is the wrong lever. Don't spend time here — we already did.

*(If you ran the commands above, reset the transport afterwards: `adb shell bmgr transport com.google.android.gms/.backup.BackupTransportService`.)*

### What does work — Android Studio

You have **Android Studio 2026.1.2**, comfortably newer than the required Otter 2025.2.1, so the controls are present.

1. Launch the emulator **from Android Studio** (the device controls live in the Running Devices panel, not in a CLI-launched emulator).
2. Run the app and create a restore key (Tier 2).
3. In the running-device window's toolbar → **Backup App Data**.
4. Pick the backup type:
   - **Device to Device** — always works, independent of `allowBackup`.
   - **Cloud** — needs `android:allowBackup="true"` in the host app.
5. Uninstall and reinstall the app — or install on a second emulator.
6. Launch once and confirm you get the signed-out state. `getRestoreKey` should still return `null` here; the key has not been delivered yet.
7. Toolbar → **Restore App data** → select the backup from step 3.
8. Reopen the app and press **Get**. It should now return an assertion rather than `null`.

Step 8 returning a non-null assertion is the pass condition for the whole feature.

Android Studio's restore simulates the device setup wizard, so there is no wizard to click through.

**Run this twice — once with Device to Device, once with Cloud.** Google's own documentation contradicts itself about whether the cloud path works when `allowBackup="false"`, and this is the test that settles it for your app. Most real-world migrations go through cloud backup, so a cloud-path failure is a compliance problem even if D2D passes.

---

## Tier 4 — with a relying-party server

Everything above validates the *device* half. None of it validates:

- challenge freshness and replay rejection
- signature-counter handling
- `origin` / `androidPackageName` enforcement (see Tier 2 — do not skip this)
- credential revocation
- the assertion → session exchange

Those need the RP server, which does not exist yet and is the blocking prerequisite recorded in the plan. `QA-SECURITY-REVIEW-2026-09-18.md` marks MASVS-AUTH as **cannot be assessed** until then.

---

## Quick reference

| Goal | Command | Needs |
|---|---|---|
| Check device eligibility | `adb shell getprop ro.build.version.sdk` + GMS versionCode | device |
| Automated contract tests | `flutter test integration_test -d <id>` | device |
| Create a real key | `flutter run` + paste `test_fixtures/creation_options.json` | device |
| Full round trip | Android Studio Backup/Restore App data | Studio GUI |
| Everything else | — | RP server |

## Known gotchas

- **`strings` is not installed on this machine.** Any binary-scan step must use the Python equivalent, with a positive control. A silent empty result here already produced one false pass.
- **Gradle needs `systemProp.https.protocols=TLSv1.2`** in `android/gradle.properties` or artifact downloads fail with `bad_record_mac`. Already applied to `example/`.
- **API 26 cannot test this at all** — it is below the API 28 gate, so any perf comparison on a low-end API 26 profile measures nothing.
- A CLI-launched emulator (`flutter emulators --launch`) does **not** show Android Studio's device-control toolbar. Launch from Studio for Tier 3.
