/// The platform channel the SDK gathers device info over.
library;

import 'package:flutter/services.dart';

import 'component_types/device.dart';

/// Gathers device info from the platform side of this plugin.
///
/// The values it returns — the advertising identifier, whether ad tracking is
/// permitted, the carrier, the bundle version — have no Dart-only equivalent,
/// which is why this plugin ships native code at all.
class DeviceInfoChannel {
  /// The channel name. Must match the value the Android and iOS plugin classes
  /// register.
  static const MethodChannel _channel = MethodChannel(
    'com.adadapted.flutter_sdk/device_info',
  );

  /// The channel to invoke. Overridable so tests can stand in for the platform.
  final MethodChannel channel;

  /// Creates a device info channel.
  /// @param channel - The channel to invoke, defaulting to the plugin's own.
  const DeviceInfoChannel({this.channel = _channel});

  /// Gathers the device info for this device.
  ///
  /// Throws whatever the platform side throws. initialize() lets it propagate:
  /// a host that cannot identify its device cannot report anything meaningful,
  /// so failing loudly beats serving ads nothing can be attributed to.
  Future<DeviceInfo> getDeviceInfo() async {
    final result = await channel.invokeMapMethod<String, Object?>(
      'getDeviceInfo',
    );

    if (result == null) {
      throw PlatformException(
        code: 'NO_DEVICE_INFO',
        message: 'The platform returned no device info.',
      );
    }

    return DeviceInfo.fromMap(result);
  }
}
