# Changelog

All notable changes to this project are documented here. This project adheres to
[Semantic Versioning](https://semver.org/) and its releases are cut from
[Conventional Commits](https://www.conventionalcommits.org/).

## Unreleased

Compliance and release-blocker fixes from the first partner integration review.
No API change. Bump `pubspec.yaml` and `lib/src/version.dart` together to cut
this as a release.

### Fixed

- **Android honors the limit-ad-tracking flag.** Play Services returns the real
  advertising ID with `isLimitAdTrackingEnabled` set on API 24–30, and the plugin
  forwarded it. It now reports an empty identifier whenever the flag is set,
  matching what the iOS side already did on an ATT denial. Sending it was a Play
  policy violation that attached to the host app's listing.
- **`android.permission.INTERNET` is declared by the plugin.** Flutter's app
  template declares it in the debug and profile manifests only, so a host app
  making no network calls of its own served ads in every test build and nothing
  in the store build.
- **An ad's `action_path` is restricted to `https`, `http` and store schemes.**
  A server-supplied URL reached `LaunchMode.externalApplication` unvalidated,
  which on Android let an `intent://` path name a target package and carry extras
  into it. A refused path reports the interaction and refreshes the zone exactly
  as a failed launch does; only the launch is withheld. `Uri.tryParse` also
  replaces `Uri.parse`, which threw synchronously out of the gesture handler on a
  malformed path.
- **The two `debugPrint` calls in `ad_zone.dart` are behind `kDebugMode`**, as
  the SDK's own logger already was, so ad IDs and platform errors stay out of
  release logs.
- **A `creative_url` that will not parse fails the zone instead of killing it.**
  `Uri.parse` threw `FormatException` synchronously from `_loadCreative`, past
  the `try` in `_fetchAd` and before `_displayAd` had armed the refresh
  countdown, so one malformed value left the zone with no ad, no timer and
  nothing to wake it — reporting nothing to the host or the API. It is now
  reported as `render_failed` like any other creative that will not display.

### Added

- **`ios/.../PrivacyInfo.xcprivacy`**, declared by both the podspec and
  `Package.swift`. Apple requires a third-party tracking SDK to ship one, and its
  absence made every partner reconstruct the SDK's data practices from source.
  `NSPrivacyTrackingDomains` is deliberately empty; see the comment in the file.

### Changed

- **The example app requests App Tracking Transparency before `initialize()`**,
  using `app_tracking_transparency`, and no longer passes a hardcoded
  `advertiserId`. It is the only runnable reference partners have, and a literal
  copied from it ships one advertising ID for an entire user base.

## 0.1.2

No change to the library. The only published files that differ from 0.1.1 are
the two version declarations and this changelog; every line of `lib/`, `android/`
and `ios/` is identical. The release exists to exercise the automated publishing
pipeline end to end — tag, OIDC exchange, upload — which had never run, so that
its first execution is not one that matters.

## 0.1.1

Packaging only, ahead of the first publish to pub.dev. No change to the library.

### Changed

- The published archive no longer carries CI config, `tool/`, `renovate.json` or
  `CLAUDE.md`. `example/` stays, since pub.dev renders it as the Example tab.
- Added pub.dev `topics`.

## 0.1.0

Initial release. A port of `adadapted-react-native-sdk` for Flutter.

### Added

- `AdadaptedFlutterSdk` — session lifecycle, keyword intercepts, out-of-app
  payloads, list reporting and add-to-list acknowledgement.
- `AdZone` — one ad per zone, with its own request, refresh countdown and
  impression pairing, ported from Android's `AdZonePresenter`.
- Android and iOS platform channel implementations for device info, the
  advertising identifier and the ad-tracking permission.
- Zones measure their own visibility; `isVisible` is an optional override rather
  than a required prop.
- `handleDeepLink(url)` for out-of-app payload links, so the SDK does not
  compete with the host app for the platform's link stream.
