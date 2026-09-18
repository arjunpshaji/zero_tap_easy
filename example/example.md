# zero_tap_easy example

## Quick start

```dart
import 'package:zero_tap_easy/zero_tap_easy.dart';

// After the user signs in, once per account per device:
if (await ZeroTapEasy.isSupported()) {
  final options = await api.getRegistrationOptions();
  final created = await ZeroTapEasy.createRestoreKey(options);
  await api.verifyRegistration(created.responseJson);
}

// On app launch, when nobody is signed in:
if (await ZeroTapEasy.isSupported()) {
  final options = await api.getAuthenticationOptions();
  final assertion = await ZeroTapEasy.getRestoreKey(options);
  if (assertion != null) {
    await api.verifyAssertion(assertion); // returns a session
  }
}

// On sign-out:
await ZeroTapEasy.clearRestoreKey();
```

## Full integration in a sign-in flow

```dart
import 'package:flutter/material.dart';
import 'package:zero_tap_easy/zero_tap_easy.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(home: const SignInPage());
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  bool _checking = true;
  String _status = 'Checking for restore key…';

  @override
  void initState() {
    super.initState();
    _tryRestore();
  }

  Future<void> _tryRestore() async {
    try {
      if (!await ZeroTapEasy.isSupported()) {
        setState(() {
          _status = 'Restore keys not supported on this device.';
          _checking = false;
        });
        return;
      }

      // Request authentication options from your server.
      // Use an empty allowCredentials for discoverable credentials.
      final options = '{'
          '"challenge":"dGVzdA",'
          '"rpId":"example.com",'
          '"allowCredentials":[],'
          '"userVerification":"required"'
          '}';

      final assertion = await ZeroTapEasy.getRestoreKey(options);

      if (assertion != null) {
        // POST this to your server's verification endpoint.
        // The server identifies the user from the credential and returns
        // a session token. Then navigate to your home screen.
        setState(() {
          _status = 'Restored! Assertion ready for server verification.';
          _checking = false;
        });
      } else {
        setState(() {
          _status = 'No restore key. Show the sign-in screen.';
          _checking = false;
        });
      }
    } on ZeroTapException catch (e) {
      // A restore key is a convenience — never block launch.
      setState(() {
        _status = 'Restore failed (${e.code}). Show the sign-in screen.';
        _checking = false;
      });
    }
  }

  /// Call this after a successful sign-in to create a restore key
  /// for the user's next device.
  Future<void> _createRestoreKey() async {
    if (!await ZeroTapEasy.isSupported()) return;

    try {
      // Fetch registration options from your relying-party server.
      final options = '{'
          '"challenge":"xWiqF-ZQ8KRcFLeRBGnFSlGFiW1U_3r_iojyiqlqJ-w",'
          '"rp":{"id":"example.com","name":"My App"},'
          '"user":{"id":"dGVzdA","name":"user@example.com","displayName":"User"},'
          '"pubKeyCredParams":[{"type":"public-key","alg":-7}],'
          '"authenticatorSelection":{'
          '  "authenticatorAttachment":"platform",'
          '  "residentKey":"required",'
          '  "requireResidentKey":true,'
          '  "userVerification":"required"'
          '}'
          '}';

      final created = await ZeroTapEasy.createRestoreKey(options);

      // POST created.responseJson to your server's registration endpoint.
      debugPrint('Restore key created (cloud: ${created.usedCloudBackup})');
    } on ZeroTapException catch (e) {
      debugPrint('Could not create restore key: ${e.code}');
    }
  }

  /// Call this on sign-out.
  Future<void> _signOut() async {
    await ZeroTapEasy.clearRestoreKey();
    setState(() => _status = 'Signed out. Restore key cleared.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('zero_tap_easy example')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_checking) const CircularProgressIndicator(),
            Text(_status, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _checking ? null : _createRestoreKey,
              child: const Text('Create restore key'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _checking ? null : _signOut,
              child: const Text('Sign out (clear key)'),
            ),
          ],
        ),
      ),
    );
  }
}
```

## Unit testing with a fake

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zero_tap_easy/zero_tap_easy.dart';

class FakeZeroTap extends ZeroTapEasyPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<bool> isSupported() async => true;

  @override
  Future<String> createRestoreKey(
    String requestJson, {
    required bool isCloudBackupEnabled,
  }) async => '{"id":"test","type":"public-key"}';

  @override
  Future<String?> getRestoreKey(String requestJson) async =>
      '{"sig":"test-assertion"}';

  @override
  Future<void> clearRestoreKey() async {}
}

void main() {
  setUp(() => ZeroTapEasyPlatform.instance = FakeZeroTap());

  test('getRestoreKey returns an assertion', () async {
    expect(await ZeroTapEasy.getRestoreKey('{}'), isNotNull);
  });
}
```

## Running the full example app

```console
cd example
flutter run -d <device-id>
```

The full example app is in [`example/lib/main.dart`](lib/main.dart) — a test
bench that exercises create, get, and clear with hand-entered WebAuthn JSON.
See [`TESTING.md`](../TESTING.md) for device testing instructions.
