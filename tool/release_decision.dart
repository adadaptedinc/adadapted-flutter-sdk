/// Decides whether a push to `main` should cut a release.
///
/// Split from the workflow so the rule can be tested. The decision is a pure
/// function of three inputs; only `main` below touches git or the filesystem.
library;

import 'dart:io';

/// What the release job should do with a push.
enum ReleaseAction {
  /// Cut the release: tag the pubspec version and publish it.
  release,

  /// Do nothing. The version has already been released and this push did not
  /// change it, which is the ordinary case for a CI, docs or dependency change.
  skip,

  /// Stop, loudly. The version was bumped to one that has already been
  /// released, so tagging it would either fail or overwrite history.
  fail,
}

/// A decision and the reason for it, so the workflow can log something useful.
class ReleaseDecision {
  /// What to do.
  final ReleaseAction action;

  /// Why, in a form worth printing in a CI log.
  final String reason;

  /// Creates a decision.
  const ReleaseDecision(this.action, this.reason);
}

/// Decides what a push to `main` should do.
///
/// The rule, in order:
///
/// - **No tag for the current version** — release it. This is a version that has
///   never shipped, which covers both an ordinary bump and recovering from a
///   release that failed partway.
/// - **Tag exists and the version did not change in this push** — skip. Forcing
///   a bump on every merge would mean a release for every dependency bump
///   Renovate automerges, and failing instead would leave `main` permanently red
///   between releases.
/// - **Tag exists and the version did change** — fail. A bump naming a version
///   that has already shipped is a mistake worth stopping for.
///
/// This cannot reintroduce the drift it replaced. The tag is derived from the
/// pubspec, so skipping creates no tag and leaves the matching one in place —
/// there is nothing for `sdk_version` to disagree with.
///
/// @param currentVersion - The version in `pubspec.yaml` after the push.
/// @param previousVersion - The version before it, or null when that cannot be
///      determined, which is treated as a change.
/// @param tagExists - Whether `v$currentVersion` is already tagged on the remote.
ReleaseDecision decideRelease({
  required String currentVersion,
  required String? previousVersion,
  required bool tagExists,
}) {
  if (!tagExists) {
    return ReleaseDecision(
      ReleaseAction.release,
      'v$currentVersion has not been released yet.',
    );
  }

  if (previousVersion == currentVersion) {
    return ReleaseDecision(
      ReleaseAction.skip,
      'Version is unchanged at $currentVersion and v$currentVersion is already '
      'released. Nothing to do.',
    );
  }

  return ReleaseDecision(
    ReleaseAction.fail,
    'Version was changed to $currentVersion, but v$currentVersion is already '
    'released. Pick a version that has not shipped.',
  );
}

/// Reads the `version:` field out of a pubspec.
/// @param pubspec - The contents of a `pubspec.yaml`.
String? versionFrom(String pubspec) {
  final match = RegExp(
    r'^version:\s*(\S+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);

  return match?.group(1);
}

/// Gathers the inputs from git and prints the decision for the workflow.
///
/// Writes `release` and `tag` to `GITHUB_OUTPUT` when there is one, and exits
/// non-zero only for [ReleaseAction.fail].
/// @param args - The SHA the push started from, if the workflow knows it.
Future<void> main(List<String> args) async {
  final currentVersion = versionFrom(File('pubspec.yaml').readAsStringSync());

  if (currentVersion == null) {
    stderr.writeln('No version found in pubspec.yaml.');
    exit(1);
  }

  final before = args.isNotEmpty ? args.first : '';
  String? previousVersion;

  // An all-zero SHA is what GitHub sends for a branch that did not exist before
  // the push, and a missing pubspec there is possible too. Either way the
  // version counts as changed, and the tag check below is what still guards.
  if (before.isNotEmpty && !RegExp(r'^0+$').hasMatch(before)) {
    final show = await Process.run('git', <String>[
      'show',
      '$before:pubspec.yaml',
    ]);

    if (show.exitCode == 0) {
      previousVersion = versionFrom(show.stdout as String);
    }
  }

  final tag = 'v$currentVersion';
  final lsRemote = await Process.run('git', <String>[
    'ls-remote',
    '--tags',
    'origin',
    'refs/tags/$tag',
  ]);
  final tagExists = (lsRemote.stdout as String).trim().isNotEmpty;

  final decision = decideRelease(
    currentVersion: currentVersion,
    previousVersion: previousVersion,
    tagExists: tagExists,
  );

  stdout.writeln(decision.reason);

  if (decision.action == ReleaseAction.fail) {
    exit(1);
  }

  final output = Platform.environment['GITHUB_OUTPUT'];

  if (output != null) {
    File(output).writeAsStringSync(
      'release=${decision.action == ReleaseAction.release}\ntag=$tag\n',
      mode: FileMode.append,
    );
  }
}
