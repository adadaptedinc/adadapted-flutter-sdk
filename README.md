# AdAdapted Flutter SDK

The `AdAdapted Flutter SDK` allows for implementation of the AdAdapted Ad Platform into your Flutter project.

## Documentation

Please visit the following site to view all documentation for the AdAdapted SDK:

[AdAdapted SDK Docs](https://docs.adadapted.com/#/)

---

## Requirements

- **Flutter 3.44** or later, **Dart 3.12** or later. The Android module takes its Kotlin from Flutter rather than applying the Kotlin Gradle plugin itself, which is only supported from 3.44.
- **iOS 15** or later. That is Flutter's own floor from 3.44; the plugin declares 12.0 and does not raise it.
- **Android SDK 24** or later.

## Install

This repository is private, so pub needs credentialed access to it. SSH is simplest:

```yaml
dependencies:
    adadapted_flutter_sdk:
        git:
            url: git@github.com:adadaptedinc/adadapted-flutter-sdk.git
            ref: v0.0.1 # pin to a published tag; see the repository's Releases
```

An HTTPS URL works too, but only where git is already authenticated for it — an anonymous HTTPS fetch of a private repository fails with `Repository not found`.

### iOS

The SDK reports the advertising identifier (IDFA) only when the user has permitted tracking through App Tracking Transparency. Add a usage description to `ios/Runner/Info.plist`, or the prompt cannot be shown and every user is reported as having refused:

```xml
<key>NSUserTrackingUsageDescription</key>
<string>This identifier is used to deliver and measure relevant ads.</string>
```

Requesting the permission itself is the host app's call, so it can be asked at a moment that makes sense to the user. Until it is granted the SDK still serves ads; it just reports an empty identifier.

Both CocoaPods and Swift Package Manager are supported.

### Android

The plugin declares `com.google.android.gms.permission.AD_ID` for you. Nothing else is needed.

## Quick start

```dart
import 'package:adadapted_flutter_sdk/adadapted_flutter_sdk.dart';

final sdk = AdadaptedFlutterSdk();

await sdk.initialize(
  appId: 'YOUR_APP_ID',
  onAddToListTriggered: (items) {
    for (final item in items) {
      addToYourList(item.productTitle);

      // Tell the SDK the item actually landed. This is what earns the ad its
      // interaction — see "Add-to-list acknowledgement" below.
      sdk.acknowledge(item.productTitle);
    }
  },
);
```

Then place a zone for each zone ID you have been allocated:

```dart
SizedBox(
  height: 250,
  child: AdZone(zoneId: 'YOUR_ZONE_ID'),
)
```

A zone fills whatever space its parent gives it, so bound it — with a `SizedBox`, an `AspectRatio`, or the zone's own `width` / `height`.

Call `sdk.unmount()` when the widget that owns the SDK is disposed, or you will leak the lifecycle observer and the HTTP client.

### `initialize` options

| | |
| --- | --- |
| `appId` | **Required.** Provided by AdAdapted. |
| `apiEnv` | `ApiEnv.prod` (default), `ApiEnv.dev`, or `ApiEnv.mock`. See [Environments](#environments). |
| `advertiserId` | Replaces the IDFA. **iOS only**, matching the other AdAdapted SDKs — it is ignored on Android, where the Google advertising ID is always used. |
| `storeId` | Targets ads by store. |
| `xyDragDistanceAllowed` | Touch travel, in logical pixels, below which a touch on a zone counts as a tap rather than a scroll. Defaults to 25. |
| `onAddToListTriggered` | Fallback handler for zones that do not supply their own. |
| `onOutOfAppPayloadAvailable` | Receives out-of-app payloads. See [Out-of-app payloads](#out-of-app-payloads). |

`sdk.sessionId` and `sdk.deviceInfo` are readable once `initialize()` resolves, and are null again after `unmount()`.

## Ad zones

| | |
| --- | --- |
| `zoneId` | **Required.** The zone to serve. |
| `contextId` | The recipe context this zone is showing. Changing it refetches. |
| `isVisible` | Manual visibility override. See [Visibility](#visibility). |
| `width`, `height` | Fixed size, if you would rather not wrap the zone. |
| `xyDragDistanceAllowed` | Per-zone override of the `initialize()` value. |
| `onZoneHasAds` | Fill state changed. |
| `onAdLoaded`, `onAdLoadFailed` | An ad rendered, or could not be retrieved or displayed. |
| `onAddToListTriggered` | Per-zone handler; falls back to the one given to `initialize()`. |

An ad is displayed for its own `refresh_time`, floored at 15 seconds and defaulting to 60 when the API supplies none.

### Collapsing the space around an unfilled zone

A zone with no ad takes up no space of its own, but the layout around it is yours. `onZoneHasAds` fires whenever the fill state changes, and only when it changes:

```dart
SizedBox(
  height: hasAds ? 250 : 0,
  child: AdZone(
    zoneId: 'YOUR_ZONE_ID',
    onZoneHasAds: (value) => setState(() => hasAds = value),
  ),
)
```

### Visibility

An `AdZone` measures its own visibility, and neither refreshes nor records impressions while it is off screen or the app is backgrounded. Nothing is required of the host.

Pass `isVisible` only to take manual control — for a layout whose real visibility the measurement cannot see. Doing so turns the measurement off entirely, so a zone given `isVisible: true` that scrolls away keeps reporting impressions.

## Keyword intercepts

```dart
final results = sdk.performKeywordSearch(userInput);

// Report only the terms you actually showed the user.
sdk.reportKeywordInterceptTermsPresented(results.map((r) => r.termId).toList());

// And when one is picked:
sdk.reportKeywordInterceptTermSelected(result.termId);
```

Search terms shorter than three characters are not matched and report nothing. Only terms that *start with* the search are matched, case-insensitively.

## Out-of-app payloads

Payloads reach the SDK two ways: it fetches any outstanding ones at `initialize()` and whenever the app returns to the foreground, and deep links carry them directly. Both surface through the same callback:

```dart
await sdk.initialize(
  appId: 'YOUR_APP_ID',
  onOutOfAppPayloadAvailable: (payloads) {
    for (final payload in payloads) {
      for (final item in payload.detailedListItems) {
        addToYourList(item.productTitle);
      }

      sdk.markPayloadContentAcknowledged(payload.payloadId);
      // ...or sdk.markPayloadContentRejected(payload.payloadId);
    }
  },
);
```

Flutter has no built-in link stream, and your app almost certainly owns its own routing already, so hand deep links to the SDK rather than letting it compete for them:

```dart
sdk.handleDeepLink(incomingUri.toString());
```

Call it for every incoming link, including the one that launched the app. Anything that is not an AdAdapted payload link is ignored.

## Reporting list activity

```dart
sdk.reportItemsAddedToList(<String>['Milk'], 'My grocery list');
sdk.reportItemsCrossedOffList(<String>['Milk'], 'My grocery list');
sdk.reportItemsDeletedFromList(<String>['Milk'], 'My grocery list');
```

### Add-to-list acknowledgement

`acknowledge(itemName)` is separate from the reporting above, and is what earns an add-to-list ad its interaction. Clicking such an ad only _offers_ the items; your app is the only party that knows whether they reached the user's list.

Call it for every item a user adds, ad-sourced or not — names that belong to no recently clicked ad are ignored, so you do not have to work out which is which.

## Environments

| | Ads | List manager | Payloads |
| --- | --- | --- | --- |
| `ApiEnv.prod` | `ads.adadapted.com` | `ec.adadapted.com` | `payload.adadapted.com` |
| `ApiEnv.dev` | `sandbox.adadapted.com` | `sandec.adadapted.com` | `sandpayload.adadapted.com` |
| `ApiEnv.mock` | local fixtures | local fixtures | local fixtures |

One `apiEnv` sets all three. `ApiEnv.mock` serves canned content with no network at all, which is useful for developing against the SDK offline.

## Development

```bash
flutter pub get
flutter analyze
flutter test
dart run tool/check_version.dart   # pubspec version must match lib/src/version.dart
```

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/), enforced by a pre-commit hook (`pip install pre-commit && pre-commit install`).

### Running the example app

The example is the quickest way to see the SDK serving. It exercises the whole public surface — a zone, keyword intercepts, add-to-list, and a second zone below the fold for watching visibility pause and resume.

```bash
# Android
flutter emulators --launch Pixel_9_Pro
cd example && flutter run

# iOS
open -a Simulator
cd example && flutter run
```

With more than one device connected, pass `-d` (`flutter devices` lists the ids). [`example/README.md`](example/README.md) covers emulator setup, what to look for, and troubleshooting — including why the advertising identifier differs between the two emulators.

### Cutting a release

Merging to `main` tags a release from the Conventional Commits since the last tag. The version the SDK _reports_ to the API is a constant, because Dart has no runtime access to its own pubspec, so bump `pubspec.yaml` and `lib/src/version.dart` together in the PR you intend to release. `dart run tool/check_version.dart` — a CI step and a pre-commit hook — fails when they disagree.

## Relationship to the other SDKs

This is a port of [`adadapted-react-native-sdk`](https://github.com/adadaptedinc/adadapted-react-native-sdk), which is itself a port of the Android SDK's `AdZonePresenter` / `AaZoneView`. The Android SDK is the reference client for the v1.0.0 single-ad-per-zone API, and the wire contract, session semantics and event ordering here follow it deliberately. Where this SDK diverges, the source says why.

The visible divergences:

| | React Native | Flutter |
| --- | --- | --- |
| Session ID prefix | `RN` | `FL` |
| `systemName` | `android_react_native` / `ios_react_native` | `android_flutter` / `ios_flutter` |
| Zone visibility | required prop, host-driven | measured, `isVisible` optional override |
| Deep links | SDK subscribes to `Linking` | host calls `handleDeepLink(url)` |
