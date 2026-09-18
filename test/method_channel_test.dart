import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_tap_easy/src/method_channel.dart';
import 'package:zero_tap_easy/zero_tap_easy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelZeroTapEasy();
  final log = <MethodCall>[];

  void mockChannel(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, (call) {
      log.add(call);
      return handler(call);
    });
  }

  setUp(() {
    log.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, null);
  });

  group('argument encoding', () {
    test('createRestoreKey sends the json and the cloud backup flag', () async {
      mockChannel((_) async => '{"ok":true}');

      final response = await platform.createRestoreKey(
        '{"challenge":"c"}',
        isCloudBackupEnabled: false,
      );

      expect(response, '{"ok":true}');
      expect(log.single.method, 'createRestoreKey');
      expect(log.single.arguments, <String, dynamic>{
        'requestJson': '{"challenge":"c"}',
        'isCloudBackupEnabled': false,
      });
    });

    test('getRestoreKey returns null when the platform returns null', () async {
      mockChannel((_) async => null);
      expect(await platform.getRestoreKey('{}'), isNull);
    });

    test('clearRestoreKey takes no arguments', () async {
      mockChannel((_) async => null);
      await platform.clearRestoreKey();
      expect(log.single.method, 'clearRestoreKey');
      expect(log.single.arguments, isNull);
    });
  });

  group('error mapping', () {
    Future<void> expectMapped(String code, Matcher matcher) async {
      mockChannel((_) async => throw PlatformException(code: code, message: 'm'));
      await expectLater(platform.getRestoreKey('{}'), throwsA(matcher));
    }

    test('E2EE_UNAVAILABLE', () async {
      await expectMapped(
        ZeroTapErrorCode.e2eeUnavailable,
        isA<ZeroTapE2eeUnavailableException>(),
      );
    });

    test('INVALID_REQUEST_JSON', () async {
      await expectMapped(
        ZeroTapErrorCode.invalidRequestJson,
        isA<ZeroTapRequestJsonException>(),
      );
    });

    test('UNSUPPORTED', () async {
      await expectMapped(
        ZeroTapErrorCode.unsupported,
        isA<ZeroTapUnsupportedException>(),
      );
    });

    test('CANCELLED', () async {
      await expectMapped(
        ZeroTapErrorCode.cancelled,
        isA<ZeroTapCancelledException>(),
      );
    });

    test('an unrecognised code falls back to the base exception', () async {
      mockChannel(
        (_) async => throw PlatformException(code: 'SOMETHING_ELSE', message: 'm'),
      );
      await expectLater(
        platform.getRestoreKey('{}'),
        throwsA(
          isA<ZeroTapException>()
              .having((e) => e.code, 'code', ZeroTapErrorCode.failed),
        ),
      );
    });

    test('a missing native implementation reads as unsupported', () async {
      mockChannel((_) async => throw MissingPluginException('no impl'));
      await expectLater(
        platform.clearRestoreKey(),
        throwsA(isA<ZeroTapUnsupportedException>()),
      );
    });
  });

  group('non-Android platforms', () {
    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);

    test('isSupported returns false without touching the channel', () async {
      mockChannel((_) async => true);
      expect(await platform.isSupported(), isFalse);
      expect(log, isEmpty);
    });

    test('the other three throw rather than reaching the channel', () async {
      mockChannel((_) async => 'unreachable');

      await expectLater(
        platform.createRestoreKey('{}', isCloudBackupEnabled: true),
        throwsA(isA<ZeroTapUnsupportedException>()),
      );
      await expectLater(
        platform.getRestoreKey('{}'),
        throwsA(isA<ZeroTapUnsupportedException>()),
      );
      await expectLater(
        platform.clearRestoreKey(),
        throwsA(isA<ZeroTapUnsupportedException>()),
      );
      expect(log, isEmpty);
    });
  });
}
