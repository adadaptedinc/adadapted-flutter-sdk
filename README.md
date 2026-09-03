# AdAdapted Flutter SDK

The `AdAdapted Flutter SDK` allows for implementation of the AdAdapted Ad Platform into your Flutter project.

## Documentation

Please visit the following site to view all documentation for the AdAdapted SDK:

[AdAdapted SDK Docs](https://docs.adadapted.com/#/)

---

## Requirements

- Flutter 3.44 or later. The Android module takes its Kotlin from Flutter rather than applying the Kotlin Gradle plugin itself, which is only supported from 3.44.
- Dart 3.12 or later.

## Install

```yaml
dependencies:
    adadapted_flutter_sdk:
        git:
            url: https://github.com/adadaptedinc/adadapted-flutter-sdk.git
            ref: v0.1.0
```

### iOS

The SDK reports the advertising identifier (IDFA) only when the user has permitted tracking through App Tracking Transparency. Add a usage description to `ios/Runner/Info.plist`, or the prompt cannot be shown and every user is reported as having refused:

```xml
<key>NSUserTrackingUsageDescription</key>
<string>This identifier is used to deliver and measure relevant ads.</string>
```

Requesting the permission itself is the host app's call, so that it can be asked at a moment that makes sense to the user. Until it is granted the SDK still serves ads; it just reports an empty identifier.

Minimum deployment target: iOS 12.

### Android

The plugin declares `com.google.android.gms.permission.AD_ID` for you. Nothing else is needed. Minimum SDK: 24.

## Use

```dart
import 'package:adadapted_flutter_sdk/adadapted_flutter_sdk.dart';

final sdk = AdadaptedFlutterSdk();

await sdk.initialize(
  appId: 'YOUR_APP_ID',
  apiEnv: ApiEnv.prod,
  onAddToListTriggered: (items) {
    for (final item in items) {
      // Add the item to the user's list, then tell the SDK it landed.
      addToYourList(item.productTitle);

      sdk.acknowledge(item.productTitle);
    }
  },
);
```

Place a zone for each zone ID you have been allocated:

```dart
SizedBox(
  height: 250,
  child: AdZone(zoneId: 'YOUR_ZONE_ID'),
)
```

Call `sdk.unmount()` when the widget that owns the SDK is disposed, or you will leak the lifecycle observer and the HTTP client.

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

### Keyword intercepts

```dart
final results = sdk.performKeywordSearch(userInput);

// Report only the terms you actually showed the user.
sdk.reportKeywordInterceptTermsPresented(results.map((r) => r.termId).toList());

// And when one is picked:
sdk.reportKeywordInterceptTermSelected(result.termId);
```

Search terms shorter than three characters are not matched and report nothing.

### Deep links

Out-of-app add-to-list payloads arrive as deep links. Flutter has no built-in link stream and your app almost certainly owns its own routing already, so hand links to the SDK rather than letting it compete for them:

```dart
sdk.handleDeepLink(incomingUri.toString());
```

Call it for every incoming link, including the one that launched the app. Anything that is not an AdAdapted payload link is ignored.

### Reporting list activity

```dart
sdk.reportItemsAddedToList(<String>['Milk'], 'My grocery list');
sdk.reportItemsCrossedOffList(<String>['Milk'], 'My grocery list');
sdk.reportItemsDeletedFromList(<String>['Milk'], 'My grocery list');
```

`acknowledge(itemName)` is separate and is what earns an add-to-list ad its interaction. Call it for every item a user adds, ad-sourced or not; names that belong to no recently clicked ad are ignored.

## Development

```bash
flutter pub get
flutter analyze
flutter test
dart run tool/check_version.dart   # pubspec version must match lib/src/version.dart
```

### Running the example app

The example is the quickest way to see the SDK serving. It exercises the whole
public surface — a zone, keyword intercepts, add-to-list, and a second zone
below the fold for watching visibility pause and resume.

```bash
# Android
flutter emulators --launch Pixel_9_Pro
cd example && flutter run

# iOS
open -a Simulator
cd example && flutter run
```

With more than one device connected, pass `-d` (`flutter devices` lists the
ids). Note that **neither emulator supplies a real advertising identifier**, so
the demo's Device ID is usually empty — that is the environment, not the SDK.
[`example/README.md`](example/README.md) covers emulator setup, what to look
for, and troubleshooting.

### Cutting a release

Merging to `main` tags a release from the Conventional Commits since the last
tag. The version the SDK *reports* to the API is a constant, so bump
`pubspec.yaml` and `lib/src/version.dart` together in the PR you intend to
release; `dart run tool/check_version.dart` (also a CI step and a pre-commit
hook) fails when they disagree.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/), enforced by a pre-commit hook (`pip install pre-commit && pre-commit install`).

## Relationship to the other SDKs

This is a port of [`adadapted-react-native-sdk`](https://github.com/adadaptedinc/adadapted-react-native-sdk), which is itself a port of the Android SDK's `AdZonePresenter` / `AaZoneView`. The Android SDK is the reference client for the v1.0.0 single-ad-per-zone API, and the wire contract, session semantics and event ordering here follow it deliberately. Where this SDK diverges, the source says why.

The visible divergences:

| | React Native | Flutter |
| --- | --- | --- |
| Session ID prefix | `RN` | `FL` |
| `systemName` | `android_react_native` / `ios_react_native` | `android_flutter` / `ios_flutter` |
| Zone visibility | required prop, host-driven | measured, `isVisible` optional override |
| Deep links | SDK subscribes to `Linking` | host calls `handleDeepLink(url)` |
