// On-device tests.
//
//   flutter test integration_test -d <device-id>
//
// The first test asserts isSupported() is TRUE rather than skipping on it.
// That is deliberate: the later tests are guarded by isSupported(), so if the
// device did not meet the API 28 / GMS 24220000 bar they would pass vacuously
// and report green while testing nothing. Run this on a device that is meant
// to support restore keys; a failure here means your test device is wrong, not
// that the plugin is broken.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zero_tap_easy/zero_tap_easy.dart';

/// A syntactically valid, deliberately unmatched request.
const String kRequestOptions = '{"challenge":"dGVzdA","rpId":"example.com",'
    '"allowCredentials":[],"userVerification":"required"}';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('isSupported is true on a device that should support restore keys',
      (tester) async {
    final bool supported = await ZeroTapEasy.isSupported();
    expect(
      supported,
      isTrue,
      reason: 'isSupported() returned false. Either this device is below '
          'Android 9 (API 28), or Google Play services is missing or older '
          'than 24220000. Check with:\n'
          '  adb shell getprop ro.build.version.sdk\n'
          '  adb shell dumpsys package com.google.android.gms | grep versionCode',
    );
  });

  testWidgets('getRestoreKey returns null when the device holds no key',
      (tester) async {
    // A restore key only becomes retrievable after a backup/restore event.
    // On a plain install this is the expected path, and it must be a null
    // return rather than an exception.
    expect(await ZeroTapEasy.getRestoreKey(kRequestOptions), isNull);
  });

  testWidgets('clearRestoreKey is safe when there is nothing to clear',
      (tester) async {
    await ZeroTapEasy.clearRestoreKey();
  });
}
