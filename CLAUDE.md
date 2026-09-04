# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
flutter pub get
flutter analyze                        # must be clean; public_member_api_docs is an error here
flutter test                           # full suite, fast (~2s)
flutter test test/ad_zone_test.dart    # a single file
flutter test --plain-name "some test"  # a single test
dart format .
dart run tool/check_version.dart       # pubspec version vs lib/src/version.dart

cd example && flutter run              # the demo app; see example/README.md
```

Running the demo needs a booted device: `flutter emulators --launch <id>` for
Android, `open -a Simulator` for iOS. Neither emulator supplies a real
advertising identifier, so the demo's Device ID is empty there — that is the
environment, not a fault. `example/README.md` has the full setup.

The example's iOS target builds through Swift Package Manager and through CocoaPods (`flutter config --no-enable-swift-package-manager`). If Xcode ever reports `identity 'adadapted-flutter-sdk' doesn't match override's identity`, the generated package is stale rather than the layout being wrong: `rm -rf example/ios/Flutter/ephemeral example/ios/Pods example/ios/Podfile.lock && flutter clean`.

Pre-commit runs format, analyze, the version check and the full test suite, plus Conventional Commits on the commit message. Install it with `pip install pre-commit && pre-commit install`.

`main` is protected: changes go through a PR, and the required status check is the CI job literally named `validation` — do not rename that job. Merging to `main` tags a release; bump `pubspec.yaml` and `lib/src/version.dart` together in the PR you intend to release.

## Architecture

A port of `adadapted-react-native-sdk`, which is itself a port of the Android SDK's `AdZonePresenter` / `AaZoneView`. **The Android SDK is the reference client** for the v1.0.0 single-ad-per-zone API. When a behaviour here looks odd, it is almost always deliberate parity with Android, and the source comment says so — read it before "fixing" it.

### Data flow

1. **Initialization** — the host calls `AdadaptedFlutterSdk.initialize()` with an `appId`. The SDK gathers device info over the platform channel, mints a session, then fetches keyword intercepts and payloads.
2. **Session** — generated in Dart, held in memory, **never persisted**, mirroring Android's `SessionClient`. A relaunch therefore always starts a new session; only a foreground within 30 minutes resumes one. IDs are `FL` + 32 characters from `[A-Z0-9]`, and reporting resolves the platform from that prefix (the v1.0.0 routes have no `{os}` path segment).
3. **Ad rendering** — the **host** declares its zones as `AdZone(zoneId: ...)`, because nothing in the API reports which zones exist. Each widget owns one zone: its own request, its own pausable countdown and its own impression pairing. Nothing is shared statically except the request context.
4. **Event tracking** — impressions, clicks and zone lifecycle events go through the request context's `reportAdEvent`. Every ad event carries a `zone_id`; `zone_*` events send empty `ad_id` / `impression_id`. An `impression_end` is reported at most once per impressed ad.
5. **Refresh** — per zone, from the ad's own `refresh_time` (`<= 0` → 60s, otherwise floored at 15s). The countdown freezes when the zone goes off screen or the app backgrounds; an ad that outlived its refresh time while frozen is replaced on return rather than shown for time nobody saw.

### Module responsibilities

| File | Responsibility |
| --- | --- |
| `lib/adadapted_flutter_sdk.dart` | The public surface. Nothing outside this is exported. |
| `lib/src/adadapted_flutter_sdk.dart` | The SDK class — initialization, session lifecycle, intercepts, payloads, deep links, reporting |
| `lib/src/ad_request_context.dart` | The context an `AdZone` reads session/device info from, and the notifications the SDK sends its zones; also breaks the SDK ↔ AdZone import cycle |
| `lib/src/components/ad_zone.dart` | One ad zone: its own request, countdown and impression pairing (port of `AdZonePresenter`) |
| `lib/src/components/report_ad_button.dart` | The optional "report this ad" affordance |
| `lib/src/api/adadapted_api_requests.dart` | The HTTP client for all API calls; injectable for tests |
| `lib/src/api/adadapted_api_types.dart` | Every request, response and model, with the snake_case wire keys |
| `lib/src/api/adadapted_api_requests_mock.dart` | Canned content for `ApiEnv.mock` |
| `lib/src/component_types/device.dart` | `DeviceOS` and `DeviceInfo` |
| `lib/src/component_types/environment.dart` | The three environment enums and their hosts |
| `lib/src/device_info_channel.dart` | The platform channel wrapper |
| `lib/src/version.dart` | The reported SDK version, kept in step with the pubspec by `tool/check_version.dart` |
| `android/`, `ios/` | Device info, advertising identifier and ad-tracking permission |

`android/build.gradle.kts` deliberately does **not** apply `kotlin-android` and has no `kotlinOptions` block: Flutter 3.44+ applies Kotlin to plugin modules itself, and a plugin that applies it again is warned on every build and breaks when the built-in path becomes the only one. That is why the pubspec requires Flutter >= 3.44.

### Key patterns

- **Callback-based API** — the SDK uses callbacks (`onAddToListTriggered`, `onOutOfAppPayloadAvailable`) rather than streams for consumer-facing events. A zone with no `onAddToListTriggered` falls back to the one given to `initialize()`.
- **Keyword intercepts** — `performKeywordSearch()` matches search terms against API-provided intercepts. `min_match_length` is no longer served, so the minimum is hardcoded to 3, as `KeywordInterceptMatcher` does. Only terms that *start with* the search are matched.
- **Deferred ATL interaction** — clicking an "add to list" ad reports `atl_ad_clicked`, **not** an interaction. The interaction is earned when the host confirms the items reached the list, via `acknowledge()`. Ported from `AdContent.itemAcknowledge`, including its guard against one click reporting two interactions.
- **`success: false` on a 200** — the v1.0.0 envelope is `{ data, success }`, and the service returns `success: false` with a populated `data` for business rejections. The status code alone is not enough to detect failure.
- **Non-2xx must throw** — `package:http` returns a response for a 500 where axios rejects, and the zone reaches its `request_failed` reason by catching. `AdadaptedApiRequests._post` throws `AdadaptedApiException` to preserve that.
- **The event routes follow the React Native SDK, not Android.** Ad and intercept events go to `/v/1.0.0/ad/events` and `/v/1.0.0/intercept/events`, matching `adadapted-react-native-sdk`. The Android SDK — the reference client for everything else here — is still on `/v/0.9.5/android/` for events and puts `sdk_version` in the envelope. This is deliberate parity with RN, but it has **not been confirmed against the event store**, and it should be before the first tagged release.
- **A 200 from the event routes means nothing.** `/v/1.0.0/ad/events` answers `{"message":"processing events"}` with HTTP 200 for a garbage session, a garbage ad ID, and even a wrong `x-api-key` — verified by hand against sandbox. Nothing on the device can tell a landed event from a discarded one, and `reportAdEvent` never reads the response anyway. Do not treat a successful POST as evidence that reporting works; that check has to happen server-side.
- **Every wall-clock read goes through `package:clock`** — that is what makes the session window and the refresh countdown testable under `fakeAsync`. Do not reintroduce `DateTime.now()`.

### Divergences from the React Native SDK

These are intentional. Do not "restore parity" without a reason.

| | React Native | Flutter |
| --- | --- | --- |
| Session ID prefix | `RN` | `FL` |
| `systemName` | `*_react_native` | `*_flutter` |
| Zone visibility | required prop | measured by `VisibilityDetector`, `isVisible` an optional override |
| Deep links | SDK subscribes to `Linking` | host calls `handleDeepLink(url)` |

**Measured visibility is three-state, not a bool.** `_measuredVisibility` is null until the detector produces a usable measurement, because `visibility_detector` never calls back for a widget whose first measurement is off screen (`_fireCallback` returns early when `oldInfo == null && !visible`). Treating unmeasured as visible bills every zone that mounts below the fold. Two predicates come off it: `_isOnScreen()` gates the impression events and is pessimistic — unmeasured is not on screen; `_shouldPace()` gates the refresh countdown and treats a zone with nothing to render as live, because a zero-sized zone can never be measured and would otherwise stay unfilled forever.

**Measured visibility has one further rule worth knowing**: an unfilled zone occupies no space, so what the detector measures is an artifact of there being nothing to see, not a statement about the slot. `_onVisibilityInfo` ignores any measurement whose `size.isEmpty`, and the last real measurement stands. Removing that guard freezes the countdown of every zone the moment it goes unfilled, and it never asks for another ad.

## Testing

- `test/support/test_harness.dart` — a fake backend (`MockClient`) that records every request, a fake device info channel, and `buildSdk()` with a seeded `Random`.
- `test/support/fake_webview_platform.dart` — a `WebViewPlatform` that renders nothing and lets a test fire `finishLoad()` / `failLoad()` by hand. A `WebViewController` cannot be built at all without it.
- **In `testWidgets`, use `settle(tester)`, never `pumpEventQueue()`** — the latter waits on real event-queue turns that never come inside a widget test's fake async, and hangs the run. Plain `test()` bodies use `pumpEventQueue()` normally.
- Reporting is fire-and-forget, so assertions on reported events need the queue drained first.
- `AdRequestContextRegistry` is static and outlives a test. `resetSdkStatics()` in `setUp` or one test's zones report into the next.

## Documentation owed to docs.adadapted.com

The README is nine lines by design, matching the other AdAdapted SDK repos. That means the following have no home in this repository and need to reach the Flutter section of the docs site — ideally before the first tagged release, since a consumer cannot integrate without several of them:

- **Install**: the SSH git dependency, because the repository is private and an anonymous HTTPS fetch fails with `Repository not found`.
- **`NSUserTrackingUsageDescription`** in `ios/Runner/Info.plist`, and that **the host must request ATT before `initialize()`** — the status is read once, when device info is gathered, so a permission granted afterwards is not picked up until the next initialize.
- **Minimum versions**: Flutter 3.44, Dart 3.12, iOS 15 (Flutter's own floor; the plugin declares 12.0 and does not raise it), Android SDK 24.
- **The `handleDeepLink(url)` contract** — the host owns its link routing and passes every incoming link, including the launch link.
- **`acknowledge()` versus `reportItemsAddedToList()`** — the former is what earns an add-to-list ad its interaction; the latter is list telemetry. Both are usually called for the same item.
- **Zone sizing**: an unfilled zone is `SizedBox.shrink()`, and a filled one fills whatever the parent gives it, so it must be bounded.
- **One SDK instance per app**, with `unmount()` in `dispose()`.
- **`advertiserId` is iOS only** and is ignored on Android.
