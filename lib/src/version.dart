/// The SDK version, reported to the API as `sdkId` and `sdk_version`.
///
/// Dart has no runtime access to its own pubspec, so this is the single source
/// of truth the requests read. It must stay in step with the `version` field in
/// `pubspec.yaml`; `tool/check_version.dart` fails the build when it does not,
/// and the release workflow rewrites both together.
library;

/// The current SDK version.
const String sdkVersion = '0.1.0';
