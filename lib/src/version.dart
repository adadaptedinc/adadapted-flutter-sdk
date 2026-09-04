/// The SDK version, reported to the API as `sdkId` and `sdk_version`.
///
/// Dart has no runtime access to its own pubspec, so this is the single source
/// of truth the requests read, and it is maintained by hand.
///
/// Nothing rewrites it at publish time — this package has no publish step, so
/// there is no equivalent of `npm version` stamping the package the way the
/// React Native and JS SDKs get for free. `tool/check_version.dart` keeps it in
/// step with `pubspec.yaml`, and the release job derives the git tag from that
/// same pubspec version, so forgetting to bump fails the release rather than
/// silently shipping a tag that disagrees with the `sdk_version` every request
/// carries.
library;

/// The current SDK version.
const String sdkVersion = '0.1.0';
