/// Device types gathered over the platform channel at initialize().
library;

/// The device operating system.
///
/// The value is the path segment the List Manager route takes, so it must stay
/// lowercase and must match what the native SDKs send.
enum DeviceOS {
  /// The Android operating system.
  android('android'),

  /// The iOS operating system.
  ios('ios');

  /// The value sent on the wire.
  final String value;

  /// Associates each operating system with its wire value.
  const DeviceOS(this.value);
}

/// Everything the SDK knows about the device it is running on.
///
/// Gathered once, at initialize(), by the platform side of this plugin. The
/// field names mirror the React Native SDK's `DeviceInfo` so the two stay
/// comparable; the wire names they map to are applied where a request is built.
class DeviceInfo {
  /// The unique device ID (GAID on Android, IDFA on iOS). Empty when the user
  /// has not permitted ad tracking.
  final String udid;

  /// The device name.
  final String deviceName;

  /// The operating system name, as reported to the API: `android_flutter` or
  /// `ios_flutter`.
  final String systemName;

  /// The operating system version.
  final String systemVersion;

  /// The device model.
  final String deviceModel;

  /// The device screen width in pixels.
  final String deviceWidth;

  /// The device screen height in pixels.
  final String deviceHeight;

  /// The device screen density.
  final String deviceScreenDensity;

  /// The current device locale.
  final String deviceLocale;

  /// The device carrier name, or `n/a` when there is none.
  final String deviceCarrier;

  /// The bundle ID of the host app.
  final String bundleId;

  /// The bundle version of the host app.
  final String bundleVersion;

  /// The current device timezone.
  final String deviceTimezone;

  /// Whether ad tracking is permitted on this device.
  final bool isAdTrackingEnabled;

  /// Creates device info from its individual fields.
  const DeviceInfo({
    required this.udid,
    required this.deviceName,
    required this.systemName,
    required this.systemVersion,
    required this.deviceModel,
    required this.deviceWidth,
    required this.deviceHeight,
    required this.deviceScreenDensity,
    required this.deviceLocale,
    required this.deviceCarrier,
    required this.bundleId,
    required this.bundleVersion,
    required this.deviceTimezone,
    required this.isAdTrackingEnabled,
  });

  /// Builds device info from the map the platform channel resolves.
  ///
  /// Every field is coerced rather than cast. The two platform implementations
  /// disagree on the type of several values — Android sends the screen
  /// dimensions as integers where iOS sends strings — and a missing key is
  /// possible on any platform version, so a hard cast here would turn a
  /// cosmetic difference into a failed initialize().
  /// @param map - The map resolved by the platform channel.
  factory DeviceInfo.fromMap(Map<Object?, Object?> map) {
    String string(String key) => map[key]?.toString() ?? '';

    return DeviceInfo(
      udid: string('udid'),
      deviceName: string('deviceName'),
      systemName: string('systemName'),
      systemVersion: string('systemVersion'),
      deviceModel: string('deviceModel'),
      deviceWidth: string('deviceWidth'),
      deviceHeight: string('deviceHeight'),
      deviceScreenDensity: string('deviceScreenDensity'),
      deviceLocale: string('deviceLocale'),
      deviceCarrier: string('deviceCarrier'),
      bundleId: string('bundleId'),
      bundleVersion: string('bundleVersion'),
      deviceTimezone: string('deviceTimezone'),
      isAdTrackingEnabled: map['isAdTrackingEnabled'] == true,
    );
  }

  /// A copy of this device info with the given fields replaced.
  ///
  /// Used to substitute a caller supplied advertiser ID for the platform's own.
  /// @param udid - The unique device ID to use instead.
  DeviceInfo copyWith({String? udid}) {
    return DeviceInfo(
      udid: udid ?? this.udid,
      deviceName: deviceName,
      systemName: systemName,
      systemVersion: systemVersion,
      deviceModel: deviceModel,
      deviceWidth: deviceWidth,
      deviceHeight: deviceHeight,
      deviceScreenDensity: deviceScreenDensity,
      deviceLocale: deviceLocale,
      deviceCarrier: deviceCarrier,
      bundleId: bundleId,
      bundleVersion: bundleVersion,
      deviceTimezone: deviceTimezone,
      isAdTrackingEnabled: isAdTrackingEnabled,
    );
  }
}
