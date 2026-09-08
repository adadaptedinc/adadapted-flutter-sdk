# AdAdapted Flutter SDK — example app

A demo integration of `adadapted_flutter_sdk`, and the quickest way to see the SDK actually serving.

It exercises the whole public surface: it initializes the SDK, places an ad zone, runs keyword intercept searches, adds items to a list and acknowledges them, and keeps a second zone below the fold so you can watch a zone pause and resume as it scrolls in and out of view.

The demo points at the **dev** environment (`ApiEnv.dev`) with app ID `7D58810X6333241C`, serving zone `102110` on the home page and `110003` on the off-screen page — the same zones the React Native demo uses.

---

## Prerequisites

Run `flutter doctor` first and resolve anything it flags for the platform you want.

- **Flutter 3.44 or later.**
- **Android** — Android Studio, and an emulator image that includes **Google Play** or **Google APIs**. See [Advertising identifiers on emulators](#advertising-identifiers-on-emulators) for why the image matters.
- **iOS** — Xcode, and its command line tools. CocoaPods is needed only if you build the CocoaPods way; Flutter uses Swift Package Manager by default from 3.47.

Then, from this directory:

```bash
flutter pub get
```

---

## Android emulator

List the emulators you have, then start one:

```bash
flutter emulators
flutter emulators --launch Pixel_9_Pro
```

```
Id                  • Name          • Manufacturer • Platform

apple_ios_simulator • iOS Simulator • Apple        • ios
Pixel_9_Pro         • Pixel 9 Pro   • Google       • android
```

No emulator yet? Create one in Android Studio (**Device Manager → Add a new device**), choosing a **Google Play** system image, or:

```bash
flutter emulators --create --name Pixel_9_Pro
```

Once it has booted, run the app:

```bash
cd example
flutter run
```

If more than one device is connected, `flutter run` asks which to use. To skip the prompt, name the device:

```bash
flutter devices                     # find the id
flutter run -d emulator-5554
```

---

## iOS simulator

Start the simulator, then run:

```bash
open -a Simulator
cd example
flutter run
```

Or name a device explicitly — either the id from `flutter devices` or the simulator's name:

```bash
flutter run -d "iPhone 17 Pro"
```

To pick a different simulator model, use **File → Open Simulator** in the Simulator app, or:

```bash
xcrun simctl list devices available
xcrun simctl boot "iPhone 17 Pro"
```

### Building through CocoaPods instead

Swift Package Manager is the default from Flutter 3.47. The SDK supports both, and you can switch to CocoaPods to check that path:

```bash
flutter config --no-enable-swift-package-manager
cd example && flutter clean && flutter run

# switch back afterwards
flutter config --enable-swift-package-manager
```

That setting is global to your Flutter install, not per project.

---

## A note on `flutter run` with no device flag

This example only has `android/` and `ios/` platform folders. If a desktop or web target is also connected, `flutter run` may offer it and then fail — pass `-d` with a mobile device instead.

---

## What you should see

- **Session** — an ID beginning `FL`, available as soon as `initialize()` resolves. It is generated on device and never persisted, so it changes on every cold start.
- **Device ID** — the advertising identifier, and it differs by platform on purpose:
    - **Android emulator** — a real Google advertising ID from Play Services, e.g. `b4fbbfe6-cea2-48de-b656-787896e75329`.
    - **iOS simulator** — `FLUTTER-TEST-ADVERTISER-ID`, the custom `advertiserId` the demo passes to `initialize()`.

  See [Advertising identifiers on emulators](#advertising-identifiers-on-emulators) for why the two disagree.
- **The ad zone** — collapsed until an ad arrives, then 250pt tall. Tapping an add-to-list ad appends its items to the list at the bottom of the screen.
- **The search box** — type at least three characters (`milk` is a good one) to match keyword intercepts. Tapping a suggestion reports it as selected and adds it to the list.
- **Off-screen zone page** — a zone parked below 900pt of filler. Scroll it into view and it starts its refresh countdown and records an impression; scroll away and both stop. Nothing in the demo reports visibility to the SDK: the zone measures its own.

### If a zone stays collapsed

A zone with nothing to serve collapses to no height and reports `zone_unfilled`, which is the SDK working rather than failing. Two causes are worth telling apart, and `adb logcat -s flutter` or a proxy will show you which:

- **`no_ad`** — the zone exists but the campaign has no dev inventory right now. Nothing to fix in the app.
- **`request_failed` with `{"success": false, "message": "requested ad zone not found"}`** — the zone ID does not exist for this app ID. Check it against the platform. In particular, **never take a zone ID from the SDK's mock fixtures** (`lib/src/api/adadapted_api_requests_mock.dart`): those values are invented for tests and the API rejects them.

You can check a zone without the app at all:

```bash
curl -s -X POST https://sandbox.adadapted.com/v/1.0.0/ad/retrieve \
  -H 'Content-Type: application/json' -H 'x-api-key: 7D58810X6333241C' \
  -d '{"sdkId":"0.1.0","bundleId":"com.adadapted.adadapted_flutter_sdk_example",
       "userId":"test-user","zoneId":"102110","storeId":"","contextId":"",
       "sessionId":"test-session","extra":""}'
```

---

## Advertising identifiers on emulators

- **Android** — a **Google Play** or **Google APIs** emulator image does supply a working advertising ID, so this is the platform to exercise identifier-dependent behaviour on. It is a throwaway tied to the emulator, an AOSP image has none at all, and it is withheld entirely when *Delete advertising ID* is set in **Settings → Google → Ads**.
- **iOS** — the simulator has no IDFA to hand out. The SDK reports the identifier only once App Tracking Transparency has been granted, and on a simulator there is nothing behind that permission, so a real integration reads empty here.

Where there is no identifier the SDK reports an empty string rather than substituting something else — on both platforms, deliberately. Verify anything that depends on a *production* identifier — attribution, retargeting — on physical hardware.

### Why iOS shows an ID here anyway

`initialize()` takes an optional `advertiserId` that replaces the IDFA, and the demo passes one:

```dart
advertiserId: 'FLUTTER-TEST-ADVERTISER-ID',
```

That override is **iOS only**, matching the other AdAdapted SDKs, which is exactly why the same build shows `FLUTTER-TEST-ADVERTISER-ID` on the simulator and the platform's own GAID on the Android emulator. Delete the line in `lib/main.dart` to exercise the real IDFA path.

The example declares `NSUserTrackingUsageDescription` in `ios/Runner/Info.plist`, which is what a real integration needs before it can prompt.

---

## Troubleshooting

**`identity 'adadapted-flutter-sdk' doesn't match override's identity`** — a stale generated Swift package, not a layout problem:

```bash
rm -rf ios/Flutter/ephemeral ios/Pods ios/Podfile.lock
flutter clean && flutter pub get
```

**`All plugins found for ios are Swift Packages, but your project still has CocoaPods integration`** — informational, not an error. The example keeps its `Podfile` deliberately, so the CocoaPods path stays testable; Flutter mentions this on every Swift Package Manager build.

**Changes to the SDK are not picked up** — the example depends on `path: ../`, so a hot restart (`R`) usually suffices. After changing Kotlin or Swift, stop and re-run: native code is not hot reloaded.

**Anything else** — `flutter clean` here and in the repo root, then `flutter pub get` in both.
