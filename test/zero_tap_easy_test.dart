import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:zero_tap_easy/zero_tap_easy.dart';

/// Records calls and replays scripted outcomes, so the facade's retry and
/// null-handling logic can be exercised without a device.
class _FakeZeroTap extends ZeroTapEasyPlatform with MockPlatformInterfaceMixin {
  _FakeZeroTap({
    this.supported = true,
    this.assertion,
    this.throwE2eeWhenCloudBackup = false,
    this.throwOnEveryCreate,
  });

  final bool supported;
  final String? assertion;
  final bool throwE2eeWhenCloudBackup;
  final Object? throwOnEveryCreate;

  final List<bool> createCalls = <bool>[];
  int clearCalls = 0;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<String> createRestoreKey(
    String requestJson, {
    required bool isCloudBackupEnabled,
  }) async {
    createCalls.add(isCloudBackupEnabled);
    if (throwOnEveryCreate != null) throw throwOnEveryCreate!;
    if (throwE2eeWhenCloudBackup && isCloudBackupEnabled) {
      throw const ZeroTapE2eeUnavailableException('no screen lock');
    }
    return '{"id":"abc","cloud":$isCloudBackupEnabled}';
  }

  @override
  Future<String?> getRestoreKey(String requestJson) async => assertion;

  @override
  Future<void> clearRestoreKey() async => clearCalls++;
}

void main() {
  group('isSupported', () {
    test('passes the platform answer straight through', () async {
      ZeroTapEasyPlatform.instance = _FakeZeroTap(supported: false);
      expect(await ZeroTapEasy.isSupported(), isFalse);

      ZeroTapEasyPlatform.instance = _FakeZeroTap();
      expect(await ZeroTapEasy.isSupported(), isTrue);
    });
  });

  group('createRestoreKey', () {
    test('defaults to cloud backup and reports that it used it', () async {
      final fake = _FakeZeroTap();
      ZeroTapEasyPlatform.instance = fake;

      final result = await ZeroTapEasy.createRestoreKey('{}');

      expect(fake.createCalls, <bool>[true]);
      expect(result.usedCloudBackup, isTrue);
      expect(result.responseJson, contains('"cloud":true'));
    });

    test('retries without cloud backup when E2EE is unavailable', () async {
      final fake = _FakeZeroTap(throwE2eeWhenCloudBackup: true);
      ZeroTapEasyPlatform.instance = fake;

      final result = await ZeroTapEasy.createRestoreKey('{}');

      expect(fake.createCalls, <bool>[true, false],
          reason: 'should try cloud first, then fall back');
      expect(result.usedCloudBackup, isFalse);
    });

    test('rethrows when the caller opted out of the retry', () async {
      final fake = _FakeZeroTap(throwE2eeWhenCloudBackup: true);
      ZeroTapEasyPlatform.instance = fake;

      await expectLater(
        ZeroTapEasy.createRestoreKey('{}', retryWithoutCloudBackup: false),
        throwsA(isA<ZeroTapE2eeUnavailableException>()),
      );
      expect(fake.createCalls, <bool>[true]);
    });

    test('does not retry when cloud backup was already off', () async {
      final fake = _FakeZeroTap(
        throwOnEveryCreate: const ZeroTapE2eeUnavailableException('nope'),
      );
      ZeroTapEasyPlatform.instance = fake;

      await expectLater(
        ZeroTapEasy.createRestoreKey('{}', isCloudBackupEnabled: false),
        throwsA(isA<ZeroTapE2eeUnavailableException>()),
      );
      expect(fake.createCalls, <bool>[false]);
    });

    test('propagates a malformed-request error without retrying', () async {
      final fake = _FakeZeroTap(
        throwOnEveryCreate: const ZeroTapRequestJsonException('bad user.id'),
      );
      ZeroTapEasyPlatform.instance = fake;

      await expectLater(
        ZeroTapEasy.createRestoreKey('{}'),
        throwsA(isA<ZeroTapRequestJsonException>()),
      );
      expect(fake.createCalls, <bool>[true]);
    });
  });

  group('getRestoreKey', () {
    test('returns null when the device holds no key', () async {
      ZeroTapEasyPlatform.instance = _FakeZeroTap();
      expect(await ZeroTapEasy.getRestoreKey('{}'), isNull);
    });

    test('returns the assertion JSON when a key is present', () async {
      ZeroTapEasyPlatform.instance = _FakeZeroTap(assertion: '{"sig":"x"}');
      expect(await ZeroTapEasy.getRestoreKey('{}'), '{"sig":"x"}');
    });
  });

  group('clearRestoreKey', () {
    test('reaches the platform', () async {
      final fake = _FakeZeroTap();
      ZeroTapEasyPlatform.instance = fake;

      await ZeroTapEasy.clearRestoreKey();

      expect(fake.clearCalls, 1);
    });
  });

  group('exceptions', () {
    test('every typed exception carries its stable code', () {
      expect(
        const ZeroTapUnsupportedException('x').code,
        ZeroTapErrorCode.unsupported,
      );
      expect(
        const ZeroTapE2eeUnavailableException('x').code,
        ZeroTapErrorCode.e2eeUnavailable,
      );
      expect(
        const ZeroTapRequestJsonException('x').code,
        ZeroTapErrorCode.invalidRequestJson,
      );
      expect(
        const ZeroTapCancelledException('x').code,
        ZeroTapErrorCode.cancelled,
      );
    });

    test('all typed exceptions are catchable as ZeroTapException', () {
      expect(const ZeroTapUnsupportedException('x'), isA<ZeroTapException>());
      expect(
        const ZeroTapE2eeUnavailableException('x'),
        isA<ZeroTapException>(),
      );
    });

    test('toString includes the code and message', () {
      expect(
        const ZeroTapRequestJsonException('missing user.id').toString(),
        'ZeroTapException(INVALID_REQUEST_JSON): missing user.id',
      );
    });
  });
}
