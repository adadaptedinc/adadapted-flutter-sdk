# Changelog

All notable changes to this project are documented here. This project adheres to
[Semantic Versioning](https://semver.org/) and its releases are cut from
[Conventional Commits](https://www.conventionalcommits.org/).

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
