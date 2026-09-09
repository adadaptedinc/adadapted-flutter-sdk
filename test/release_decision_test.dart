/// The rule deciding whether a push to `main` cuts a release.
///
/// Tested because the failure mode is silence: a real bump misread as unchanged
/// would skip a release with nothing downstream to catch it.
library;

import 'package:flutter_test/flutter_test.dart';

import '../tool/release_decision.dart';

void main() {
  group('decideRelease', () {
    test('releases a version that has never been tagged', () {
      final decision = decideRelease(
        currentVersion: '0.2.0',
        previousVersion: '0.1.1',
        tagExists: false,
      );

      expect(decision.action, ReleaseAction.release);
    });

    test('skips when the version is unchanged and already released', () {
      // The ordinary case for a docs change or a dependency bump Renovate
      // automerged. Failing here would leave main red between releases.
      final decision = decideRelease(
        currentVersion: '0.1.1',
        previousVersion: '0.1.1',
        tagExists: true,
      );

      expect(decision.action, ReleaseAction.skip);
    });

    test('fails when a bump names a version already released', () {
      final decision = decideRelease(
        currentVersion: '0.1.1',
        previousVersion: '0.1.0',
        tagExists: true,
      );

      expect(decision.action, ReleaseAction.fail);
      expect(decision.reason, contains('already'));
    });

    test('releases an unchanged version that was never tagged', () {
      // Recovery: a release that failed partway leaves the version on main with
      // no tag. Skipping on "unchanged" alone would strand it unreleased.
      final decision = decideRelease(
        currentVersion: '0.1.1',
        previousVersion: '0.1.1',
        tagExists: false,
      );

      expect(decision.action, ReleaseAction.release);
    });

    test('treats an unknown previous version as a change', () {
      // The previous pubspec cannot always be read — a new branch, or a shallow
      // checkout. Assuming "changed" keeps the tag check as the real guard
      // rather than silently skipping a release.
      expect(
        decideRelease(
          currentVersion: '0.1.1',
          previousVersion: null,
          tagExists: true,
        ).action,
        ReleaseAction.fail,
      );
      expect(
        decideRelease(
          currentVersion: '0.2.0',
          previousVersion: null,
          tagExists: false,
        ).action,
        ReleaseAction.release,
      );
    });
  });

  group('versionFrom', () {
    test('reads the version out of a pubspec', () {
      expect(versionFrom('name: x\nversion: 1.2.3\ndescription: y\n'), '1.2.3');
    });

    test('is not fooled by a version field nested under another key', () {
      // `version:` indented under `environment:` or a dependency must not be
      // mistaken for the package's own.
      expect(
        versionFrom('name: x\ndependencies:\n  foo:\n    version: 9.9.9\n'),
        isNull,
      );
    });

    test('returns null when there is no version', () {
      expect(versionFrom('name: x\ndescription: y\n'), isNull);
    });
  });
}
