/// Fails when `pubspec.yaml` and `lib/src/version.dart` disagree.
///
/// Dart has no runtime access to its own pubspec, so the version reported to the
/// API is a constant that has to be kept in step by hand. A mismatch is invisible
/// at runtime and shows up only as SDK version reporting that quietly went stale,
/// which is exactly the kind of thing that survives a release unnoticed.
library;

import 'dart:io';

/// Compares the two declared versions and exits non-zero when they differ.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final source = File('lib/src/version.dart').readAsStringSync();

  final pubspecVersion = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec)?.group(1);

  final sourceVersion = RegExp(
    r"""sdkVersion\s*=\s*['"]([^'"]+)['"]""",
  ).firstMatch(source)?.group(1);

  if (pubspecVersion == null) {
    stderr.writeln('No version found in pubspec.yaml.');
    exit(1);
  }

  if (sourceVersion == null) {
    stderr.writeln('No sdkVersion found in lib/src/version.dart.');
    exit(1);
  }

  if (pubspecVersion != sourceVersion) {
    stderr.writeln(
      'Version mismatch: pubspec.yaml says $pubspecVersion, '
      'lib/src/version.dart says $sourceVersion.',
    );
    exit(1);
  }

  stdout.writeln('Version $pubspecVersion is consistent.');
}
