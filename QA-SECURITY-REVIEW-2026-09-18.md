# zero_tap_easy — QA & Security Review

**Date:** 2026-09-18
**Target:** `zero_tap_easy` 0.1.0 — Flutter plugin wrapping Android Credential Manager Restore Credentials
**Method:** static/code analysis, Dart unit tests, Kotlin compile, built-APK binary scan, **on-device verification**
**Not covered:** the full backup/restore round trip (needs the Android Studio GUI), a relying-party server, GMS-less/OEM environments

> **Addendum 2026-09-18 — device pass completed.** Tests were subsequently run on emulator-5554 (Pixel_7 AVD, API 36, `google_apis_playstore`, GMS 262031038). Closed as **PASS on device**: `isSupported()` returns true (asserted, not skipped); `getRestoreKey` returns `null` rather than throwing when no key exists; `clearRestoreKey` is safe when empty; `createRestoreKey` produces a valid WebAuthn attestation; and the `E2eeUnavailableException` → local-only retry path fired for real (`usedCloudBackup=false` on a device with no screen lock). One item was **found to be recorded incorrectly** — see F-08. Details in `TESTING.md`.

---

## Scope correction — read this first

This test plan is written for **an application** that integrates zero-tap sign-in. `zero_tap_easy` is **a library**, and it deliberately has no backend, no storage, no network stack, no session model and no UI. A large fraction of the plan's security items therefore cannot pass or fail here — they are the *integrator's* obligations. Marking them "pass" because the plugin doesn't do the wrong thing would be misleading, so they are marked **N/A (integrator)** with a note on what the integrating app must do.

Two factual corrections to the plan itself:

1. **§0.5 "how the app behaves below API 34"** — Restore Credentials is not the API-34 Credential Manager story. It works from **Android 9 (API 28)** via the Google Play services backport, and additionally requires **GMS core ≥ 24220000**. There is no API-34 cliff. The device matrix in §5 should read API 28 / 30 / 33 / 34 / latest, plus one sub-28 device to confirm clean degradation.
2. **§2 "multiple saved credentials → auto-pick vs picker"** and **§2 "biometric enrollment changes"** — both are N/A for this credential type. Restore Credentials supports **one account per app** and is **not user-verified** (no biometric prompt, no picker; the whole flow is silent and invisible). These items belong to a passkey/password test plan, not this one.

---

## 0. Context gathered

| Item | Finding |
|---|---|
| Public Dart API | `ZeroTapEasy.isSupported / createRestoreKey / getRestoreKey / clearRestoreKey` — `lib/src/zero_tap_easy_base.dart` |
| Bridge | Plain `MethodChannel` (not Pigeon), channel name `zero_tap_easy` — `ZeroTapEasyPlugin.kt:39,150` |
| Native impl | `android/src/main/kotlin/com/zerotap/zero_tap_easy/RestoreCredentialHandler.kt` |
| Credential type | **Restore key only** — `CreateRestoreCredentialRequest` / `GetRestoreCredentialOption` (`RestoreCredentialHandler.kt:50,99`). No passkey, Google ID token or saved-password path exists. |
| SDK levels | plugin `minSdk = 21`, `compileSdk = 36`, JVM 17 — `android/build.gradle.kts:31,51,73` |
| Sub-API-28 behaviour | Hard runtime gate: `isSupported()` returns `false` below API 28 — `RestoreCredentialHandler.kt:41` |
| Post-retrieval storage | **None.** The plugin returns a JSON string to Dart and retains nothing. |
| Backend session exchange | **None in the plugin** — by design. The caller POSTs `responseJson` / the assertion to their own RP server. |
| `allowBackup` | Plugin manifest sets **nothing** — `android/src/main/AndroidManifest.xml` |

---

## 1. Security

### 1.1 Credential storage — PASS

| Check | Status | Evidence |
|---|---|---|
| Token never written to plain `SharedPreferences` | **PASS** | `grep -rni "SharedPreferences\|DataStore\|Keystore\|secure_storage\|openFileOutput\|SQLite\|Room\|writeAsString"` across `android/src` + `lib/` → **0 matches**. The plugin has no persistence layer at all. |
| Encrypted/Keystore-backed storage used | **N/A** | Nothing is stored, so there is nothing to encrypt. Strongest possible outcome for this control. |
| Token not logged | **PASS** | `grep -rn "Log\.\|println\|System.out\|print(\|debugPrint"` across `android/src` + `lib/` → **0 matches**. The plugin emits no logs in any build type. |
| ProGuard strips logging in release | **N/A** | No logging exists to strip; the plugin ships no `consumer-rules.pro` and needs none. |
| Not in crash reports | **PASS (by construction)** | No crash reporter is integrated. Additionally `RestoreKeyCreation.toString()` prints only `responseJson.length`, never the payload — `lib/src/zero_tap_easy_base.dart:30-32`. This is the right default for breadcrumb capture. |

> **Integrator obligation:** the plugin hands you a WebAuthn assertion JSON. That is short-lived proof-of-possession material. Do not persist it, do not log it, and exclude it from crash-reporter custom keys.

### 1.2 Backup & export exposure — PASS (plugin) / NEEDS DEVICE (end-to-end)

| Check | Status | Evidence |
|---|---|---|
| Plugin does not alter host backup config | **PASS** | `android/src/main/AndroidManifest.xml` declares only a `<queries>` element for `com.google.android.gms`. No `allowBackup`, no `fullBackupContent`, no `dataExtractionRules`, no `backupAgent`. This is deliberate and correct — Google's guidance explicitly forbids a library changing the host's backup setting. |
| `adb backup` / `bmgr backupnow` inspection | **NEEDS DEVICE** | Not run. Note this control is largely moot for the plugin: it writes no files, so it contributes nothing to a backup archive. It remains meaningful for the integrating app. |

### 1.3 Token replay & expiry — N/A (server)

Both items are properties of the relying-party server's challenge/counter handling. The plugin performs **no verification of its own** and correctly does not try to — it passes opaque JSON in both directions. There is no client-side token cache to reuse (§1.1), so "client silently reuses an expired token" is structurally impossible here.

**Untestable until an RP server exists.** Flagged in the plan of record as the blocking prerequisite.

### 1.4 Origin / package binding — N/A (platform-enforced) + NEEDS DEVICE

Origin binding for restore keys is enforced by Credential Manager and the WebAuthn RP ID ↔ Digital Asset Links association, not by application code. The plugin cannot weaken it and does not attempt to override `rpId` — the `requestJson` is passed through verbatim (`RestoreCredentialHandler.kt:50,99`).

**UPDATED 2026-09-18 after device testing — this item was originally recorded incorrectly.** Restore keys bind to **package name + signing certificate**, not to a domain. A key created on an API 36 emulator with an arbitrary `rp.id` and **no `assetlinks.json` present** succeeded, producing `"origin": "android:apk-key-hash:fIYtWWqFTBf6LH9xmZm4_iZ8_DVPAWE3aqgyMrFs1EA"` and `"androidPackageName": "com.zerotap.zero_tap_easy_example"` in the signed `clientDataJSON`.

**The real control is server-side:** the RP must pin `origin` to the apk-key-hash of the release signing certificate and `androidPackageName` to the applicationId. A server ignoring these accepts a credential minted by any app. `README.md` has been corrected. See `TESTING.md` Tier 2.

The "re-sign with a different keystore and confirm rejection" test is a genuine and valuable check — **NEEDS DEVICE + server**.

### 1.5 Network / MITM — N/A (no network in plugin)

| Check | Status | Evidence |
|---|---|---|
| Certificate pinning | **N/A** | `grep -rni "http\|OkHttp\|URLConnection\|Socket\|Retrofit\|dio"` across `android/src` + `lib/` → only two **documentation-comment** matches (`lib/src/zero_tap_easy_base.dart:156`, and the manifest XML namespace URL). The plugin opens no sockets. |

> **Integrator obligation — do not read this as a pass for your app.** Your four RP endpoints carry registration/assertion material, and two of them are necessarily **unauthenticated** (the device has no session at restore time). Per the plan's own guidance, absence of pinning on those endpoints is a **Medium–High** finding at the app layer. Assess it there.

### 1.6 Device integrity — N/A (server)

Play Integrity attestation belongs server-side, at assertion-verification time. The plugin does not check it, and should not — a client-side integrity check is trivially bypassable and would provide false assurance.

**Behaviour on rooted/emulator environments is NEEDS DEVICE.** Note a structural point in this feature's favour: a restore key is bound to the device's credential store and verified by the RP server, so a rooted device cannot forge one without the private key.

### 1.7 Multi-account & revocation — PARTIAL PASS / NEEDS DEVICE

| Check | Status | Evidence |
|---|---|---|
| Sign-out clears local state | **PASS (API exists + unit-tested)** | `ZeroTapEasy.clearRestoreKey()` → `ClearCredentialStateRequest(TYPE_CLEAR_RESTORE_CREDENTIAL)` — `RestoreCredentialHandler.kt:134-139`. Dart contract covered by `test/zero_tap_easy_test.dart` ("clearRestoreKey reaches the platform"). |
| Account A → B with no bleed | **N/A + NEEDS DEVICE** | Restore Credentials supports **one account per app**; there is no multi-account state in the plugin to bleed. The real risk lives in the integrator's session handling. |
| Revoke server-side → silent restore fails | **NEEDS SERVER** | Correct behaviour is server rejection of the assertion. Untestable here. |

> **The single highest-consequence integrator obligation in this whole review:** Credential Manager is **stateless and never auto-deletes a restore key**. If the app fails to call `clearRestoreKey()` on sign-out, a user who deliberately signed out is silently signed back in on their next device. This is documented in `README.md` and `lib/src/zero_tap_easy_base.dart:150-158`, but it cannot be enforced by the library.

### 1.8 App cloning / dual apps — NEEDS DEVICE

Not testable without OEM hardware. Structurally, restore keys are bound to package name, and Google documents that the restore key is available only to the **first-setup profile** on multi-profile devices — which suggests clones do not receive it. Unverified.

### 1.9 Static binary analysis — PASS

| Check | Status | Evidence |
|---|---|---|
| No hardcoded secrets in source | **PASS** | `grep -rniE "client_?id\|api_?key\|secret\|password\|BEGIN (RSA\|PRIVATE)\|AIza"` across `android/src` + `lib/` → 3 matches, **all in doc comments** (`exceptions.dart:60`, `zero_tap_easy_base.dart:43,157`), none a value. |
| No secrets in compiled output | **PASS** | Scanned all 8 dex files of `example/build/app/outputs/flutter-apk/app-debug.apk` for `AIza…`, `*.apps.googleusercontent.com`, `GOCSPX-`, `client_secret`, PEM private-key headers → **0 hits**, with a **sanity control of 27 `zero_tap_easy` strings** confirming the extraction actually worked. |

> **Process note:** the first run of this check used `strings`, which is **not installed on this machine**. It returned empty and would have been recorded as a false pass. It was re-run in Python with an explicit positive control. Any future run of this item must include a sanity control.

Full `jadx` decompilation was **not** performed — **NEEDS MANUAL** — though with zero secret material in source, the residual risk is low.

---

## 2. Feature / functional

| Item | Status | Notes |
|---|---|---|
| First launch, no credential → graceful fallback | **PASS (contract) / NEEDS DEVICE (runtime)** | `NoCredentialException` → `return null`, not an exception — `RestoreCredentialHandler.kt:109-111`. Covered by `test/zero_tap_easy_test.dart` and by `example/integration_test/plugin_integration_test.dart` (device-gated). Good API choice: callers write `if`, not `try`. |
| Exactly one credential → restore succeeds | **NEEDS SERVER + DEVICE** | Cannot construct a valid `requestJson` without an RP. |
| Multiple credentials → picker vs auto-pick | **N/A** | One account per app; no picker exists in this flow. |
| User cancels prompt | **PARTIAL** | `GetCredentialCancellationException` / `CreateCredentialCancellationException` → `ZeroTapCancelledException` (`RestoreCredentialHandler.kt:79-84,112-117`). Mapping is unit-tested; real cancellation is **NEEDS DEVICE**. Note the flow is silent, so user-visible cancellation is unlikely in practice. |
| GMS missing / outdated / disabled | **PASS (logic) / NEEDS DEVICE** | `gmsVersion()` returns `0L` on `NameNotFoundException` → `isSupported()` false — `RestoreCredentialHandler.kt:157-167,41-42`. Fails closed. |
| No Google account on device | **NEEDS DEVICE** | Expected to surface as `E2eeUnavailableException` → auto-retry local-only. Logic unit-tested; device behaviour unverified. |
| Airplane mode / no network | **FAIL — see F-02** | No timeout is enforced anywhere. |
| Sign-out clears state | **PASS** | See §1.7. |
| Uninstall + reinstall | **NEEDS DEVICE** | |
| Biometric enrollment change | **N/A** | Restore keys are not user-verified. |

---

## 3. Flow / lifecycle

All six items **NEED DEVICE**. Code review surfaced two defects that these tests would likely expose:

- **Rotation / config change while a call is in flight → F-01** (Activity retained).
- **Kill or process death mid-call → F-02 / F-04** (Dart future never settles).

One item passes by construction: the plugin does **not** run at Flutter engine attach — nothing happens until Dart calls a method (`ZeroTapEasyPlugin.kt:36-41` registers a handler and nothing more), so it cannot block first frame. Whether the *integrator* blocks their splash on the call is their design choice; `README.md` and the dartdoc both tell them not to.

---

## 4. Performance

| Item | Status | Notes |
|---|---|---|
| Low-end vs flagship latency | **NEEDS DEVICE** | Note API 26 as specified in the plan is below the API-28 gate, so the restore path won't execute there at all. |
| Cold start with/without plugin | **NEEDS DEVICE** | See §3 — the plugin does no work at attach. |
| Leak check under repeated cycles | **FAIL — F-01** | The plan's own note ("Credential Manager clients are a known leak source if not released in `onDestroy`") is well-aimed. See below. |
| Genuinely async / no main-thread block | **PARTIAL — F-03** | The Credential Manager calls themselves are correctly `suspend` on `Dispatchers.Main`. But a synchronous `PackageManager` binder IPC runs on the platform thread on **every** call. |
| No background polling | **PASS** | No timer, scheduler, `WorkManager`, or loop exists. The plugin is purely call-driven — `ZeroTapEasyPlugin.kt` has no code path not originating from `onMethodCall`. |

---

## 5. Device / OS matrix

**Entirely NEEDS MANUAL / DEVICE.** None of the eight rows were executed. Only one environment was exercised: an `assembleDebug` build against compileSdk 36. Recommended revision to the matrix per the scope correction above: sub-28 (degradation), 28, 30, 33, 34, latest, one One UI, one MIUI, one GMS-less AOSP.

---

## Findings Log

| # | Section | Item | Status | Evidence | Severity |
|---|---|---|---|---|---|
| F-01 | 3, 4.3 | Activity retained for the full duration of an in-flight Credential Manager call | **FAIL** | `ZeroTapEasyPlugin.kt:69` captures `activity` into the handler; the coroutine at `:97` holds it until the suspend call returns. `scope` is cancelled only in `onDetachedFromEngine` (`:45`) — **not** in `onDetachedFromActivity` (`:61-63`), which nulls the field but does not cancel work already running. | **Medium** |
| F-02 | 2, 3 | No timeout on any native call — the Dart `Future` can hang indefinitely | **FAIL** | `grep -rn "withTimeout"` → 0 matches in `android/src`. If Credential Manager never invokes its callback (airplane mode, wedged GMS), `result` is never completed. Compounds F-01 by making the leak window unbounded. `README.md` pushes the timeout onto the integrator; for a library whose job runs on the launch critical path, the safe default belongs in the library. | **Medium** |
| F-03 | 4.4 | Synchronous `PackageManager` IPC on the platform thread on every method call | **FAIL** | `ZeroTapEasyPlugin.kt:69` builds a handler and `:72`/`:76` call `isSupported()` → `gmsVersion()` → `getPackageInfo()` (`RestoreCredentialHandler.kt:158`). A fresh handler *and* a fresh GMS lookup per call; the result is immutable for the process lifetime and should be cached. Not an ANR risk at realistic call rates, but avoidable main-thread binder traffic. | **Low** |
| F-04 | 3 | `CancellationException` rethrow leaves the `MethodChannel` `Result` uncompleted | **FAIL** | `ZeroTapEasyPlugin.kt:125-126`. Only reachable via `scope.cancel()` on engine detach, where the Dart isolate is going away — so benign in practice, but it is an uncompleted-result path and should be documented or handled. | **Low** |
| F-05 | 3, 4.4 | No guard against concurrent/overlapping calls | **FAIL** | `grep -rn "Mutex\|synchronized\|AtomicBoolean"` → 0 matches. Two overlapping `getRestoreKey` calls construct two handlers and two `CredentialManager` instances (`RestoreCredentialHandler.kt:31-33`). Platform behaviour under concurrent requests is undefined by the plugin and untested. | **Low** |
| F-06 | 1.1 | Native error strings interpolate upstream `e.message` | **INFO** | `RestoreCredentialHandler.kt:70,76,121` and `ZeroTapEasyPlugin.kt:128`. Credential Manager is not expected to place credential material in exception messages, but this is unverified and the string crosses into Dart where an integrator may log it. Low residual risk; worth a look if Google ever changes those messages. | **Info** |
| F-08 | 1.4 | Server must pin `origin` (apk-key-hash) and `androidPackageName`; assetlinks is **not** the binding mechanism for restore keys | **OPEN (integrator)** | Empirically confirmed on emulator-5554 (API 36, GMS 262031038): create succeeded with `rp.id: example.com` and no assetlinks. Decoded `clientDataJSON` shows a native-app origin. Original review recorded the assetlinks requirement without testing it. | **Medium (app layer)** |
| F-07 | 1.9 | *Process defect, now corrected* — `strings` absent, producing a false-negative secret scan | **RESOLVED** | First run silently produced empty output because `strings` is not installed. Re-run in Python with a 27-hit positive control. No secrets found. Recorded so the mistake is not repeated. | **Info** |

**No Critical or High findings.** Nothing triggered the plan's stop-and-flag conditions: no hardcoded secret, no token in plaintext storage, no missing package/signature check.

---

## Final Deliverable

### Critical / High findings

**None.** The two Medium findings (F-01, F-02) are robustness and lifecycle defects, not credential-exposure defects.

### Pass/fail matrix

| Section | Pass | Fail | N/A | Needs device/server |
|---|---|---|---|---|
| §1 Security (20 items) | 6 | 0 | 9 | 5 |
| §2 Functional (10) | 3 | 1 | 2 | 4 |
| §3 Lifecycle (6) | 1 | 0 | 0 | 5 |
| §4 Performance (5) | 1 | 2 | 0 | 2 |
| §5 Device matrix (8) | 0 | 0 | 0 | 8 |

Automated suites run: `flutter analyze` — clean; `flutter test` — 23/23; `example` widget test — 1/1; `flutter build apk --debug` — succeeds.

### OWASP MASVS assessment

**MASVS-STORAGE — MEETS BASELINE, at the library layer.** The plugin stores nothing, logs nothing and transmits nothing. Verified by exhaustive grep across the whole native and Dart source (zero matches for every persistence, logging and network API), and by a controlled binary scan of all 8 dex files. `RestoreKeyCreation.toString()` deliberately elides the payload. There is no sensitive data at rest to protect.

**This does not transfer to an integrating app.** The assertion JSON handed to the caller is sensitive; MASVS-STORAGE for the app depends entirely on what the caller does with it.

**MASVS-AUTH — CANNOT BE ASSESSED.** MASVS-AUTH is fundamentally about server-side enforcement: challenge freshness, signature counter handling, credential binding, session lifetime, revocation. **None of that exists yet** — there is no relying-party server, which the plan of record already identifies as the blocking prerequisite. The plugin's own behaviour is architecturally correct for MASVS-AUTH (it performs no local verification and treats all material as opaque, delegating trust entirely to the server), but a verdict is impossible until the RP is built. **Re-run this section against the server before any production release.**

### Requires a physical device or manual QA

1. All of §5 — the entire OS/OEM matrix, including a GMS-less AOSP build (graceful failure, not crash).
2. Full backup/restore round trip via Android Studio Otter **Backup App Data** / **Restore App data**, on **both** Device-to-Device and Cloud paths — this also settles the documented `allowBackup` contradiction.
3. `adb backup` / `bmgr backupnow` archive inspection (§1.2).
4. Re-sign with a foreign keystore and confirm rejection (§1.4) — needs an RP server too.
5. Rooted/emulator integrity behaviour (§1.6).
6. OEM app-cloning bleed test (§1.8).
7. All six §3 lifecycle tests — these are the ones most likely to confirm F-01 and F-02.
8. Memory profiling across repeated sign-in/out cycles (§4.3) to quantify F-01.
9. `jadx` decompilation for full §1.9 closure.
10. Everything gated on the RP server: §1.3 replay/expiry, §1.7 revocation, §2 happy-path restore.
