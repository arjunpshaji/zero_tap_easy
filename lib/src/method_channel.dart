import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'exceptions.dart';
import 'platform_interface.dart';

/// The default [ZeroTapEasyPlatform], backed by a [MethodChannel].
///
/// Every method short-circuits off Android rather than reaching the channel,
/// so a host app can call into this package unconditionally on any platform.
class MethodChannelZeroTapEasy extends ZeroTapEasyPlatform {
  /// The channel used to talk to the Android implementation.
  @visibleForTesting
  final MethodChannel methodChannel = const MethodChannel('zero_tap_easy');

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> isSupported() async {
    if (!_isAndroid) return false;
    try {
      return await methodChannel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<String> createRestoreKey(
    String requestJson, {
    required bool isCloudBackupEnabled,
  }) async {
    _assertAndroid();
    try {
      final String? response = await methodChannel.invokeMethod<String>(
        'createRestoreKey',
        <String, dynamic>{
          'requestJson': requestJson,
          'isCloudBackupEnabled': isCloudBackupEnabled,
        },
      );
      if (response == null) {
        throw const ZeroTapException(
          ZeroTapErrorCode.failed,
          'Credential Manager returned no registration response.',
        );
      }
      return response;
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    } on MissingPluginException catch (e) {
      throw _missingPlugin(e);
    }
  }

  @override
  Future<String?> getRestoreKey(String requestJson) async {
    _assertAndroid();
    try {
      // The Android side replies with null when no restore key is present,
      // which is the ordinary case on a fresh install.
      return await methodChannel.invokeMethod<String>(
        'getRestoreKey',
        <String, dynamic>{'requestJson': requestJson},
      );
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    } on MissingPluginException catch (e) {
      throw _missingPlugin(e);
    }
  }

  @override
  Future<void> clearRestoreKey() async {
    _assertAndroid();
    try {
      await methodChannel.invokeMethod<void>('clearRestoreKey');
    } on PlatformException catch (e) {
      throw _mapPlatformException(e);
    } on MissingPluginException catch (e) {
      throw _missingPlugin(e);
    }
  }

  void _assertAndroid() {
    if (_isAndroid) return;
    throw ZeroTapUnsupportedException(
      'Restore keys are an Android feature. Current platform: '
      '${kIsWeb ? 'web' : defaultTargetPlatform.name}. '
      'Guard your calls with ZeroTapEasy.isSupported().',
    );
  }

  ZeroTapException _missingPlugin(MissingPluginException e) =>
      ZeroTapUnsupportedException(
        'The zero_tap_easy Android implementation is not registered.',
        details: e,
      );

  ZeroTapException _mapPlatformException(PlatformException e) {
    final String message = e.message ?? e.code;
    switch (e.code) {
      case ZeroTapErrorCode.unsupported:
        return ZeroTapUnsupportedException(message, details: e.details);
      case ZeroTapErrorCode.e2eeUnavailable:
        return ZeroTapE2eeUnavailableException(message, details: e.details);
      case ZeroTapErrorCode.invalidRequestJson:
        return ZeroTapRequestJsonException(message, details: e.details);
      case ZeroTapErrorCode.cancelled:
        return ZeroTapCancelledException(message, details: e.details);
      default:
        return ZeroTapException(
          ZeroTapErrorCode.failed,
          message,
          details: e.details,
        );
    }
  }
}
