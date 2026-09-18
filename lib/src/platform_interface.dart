import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel.dart';

/// The interface that implementations of `zero_tap_easy` must implement.
///
/// Swap [instance] for a fake in tests to exercise your sign-in logic without
/// a device:
///
/// ```dart
/// ZeroTapEasyPlatform.instance = MyFakeZeroTap();
/// ```
abstract class ZeroTapEasyPlatform extends PlatformInterface {
  /// Constructs a [ZeroTapEasyPlatform].
  ZeroTapEasyPlatform() : super(token: _token);

  static final Object _token = Object();

  static ZeroTapEasyPlatform _instance = MethodChannelZeroTapEasy();

  /// The current platform implementation.
  ///
  /// Defaults to [MethodChannelZeroTapEasy].
  static ZeroTapEasyPlatform get instance => _instance;

  /// Sets the platform implementation.
  ///
  /// Implementations must extend [ZeroTapEasyPlatform] rather than implement
  /// it, so that new methods can be added without a breaking change.
  static set instance(ZeroTapEasyPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Whether restore keys can be used on this device.
  Future<bool> isSupported() {
    throw UnimplementedError('isSupported() has not been implemented.');
  }

  /// Creates a restore key and returns the WebAuthn registration response JSON.
  Future<String> createRestoreKey(
    String requestJson, {
    required bool isCloudBackupEnabled,
  }) {
    throw UnimplementedError('createRestoreKey() has not been implemented.');
  }

  /// Asserts the restore key and returns the WebAuthn authentication response
  /// JSON, or `null` when this device holds no restore key.
  Future<String?> getRestoreKey(String requestJson) {
    throw UnimplementedError('getRestoreKey() has not been implemented.');
  }

  /// Deletes the restore key held by this device.
  Future<void> clearRestoreKey() {
    throw UnimplementedError('clearRestoreKey() has not been implemented.');
  }
}
