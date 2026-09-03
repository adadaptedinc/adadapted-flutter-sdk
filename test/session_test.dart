/// Session lifecycle: minting, resuming, backgrounding and teardown.
library;

import 'package:adadapted_flutter_sdk/adadapted_flutter_sdk.dart';
import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend backend;
  late AdadaptedFlutterSdk sdk;

  setUp(() {
    resetSdkStatics();
    installFakeDeviceInfoChannel();

    backend = FakeBackend();
    sdk = buildSdk(backend);
  });

  tearDown(() {
    sdk.unmount();
    removeFakeDeviceInfoChannel();
  });

  group('session id', () {
    test('is prefixed and 34 characters long', () async {
      await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      final sessionId = sdk.sessionId!;

      expect(sessionId, startsWith('FL'));
      expect(sessionId.length, 34);
    });

    test('draws its characters only from the documented alphabet', () async {
      await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      expect(sdk.sessionId!.substring(2), matches(RegExp(r'^[A-Z0-9]{32}$')));
    });

    test('does not collide with the other SDK prefixes', () async {
      await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      // Reporting resolves the platform from this prefix alone, so a collision
      // would attribute Flutter traffic to another SDK.
      for (final other in <String>['RN', 'JS', 'AN', 'IO']) {
        expect(sdk.sessionId!.startsWith(other), isFalse);
      }
    });

    test('is not persisted, so a second SDK mints its own', () async {
      await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      final first = sdk.sessionId;

      sdk.unmount();
      resetSdkStatics();

      final second = buildSdk(backend, randomSeed: 7);

      await second.initialize(appId: 'APP', apiEnv: ApiEnv.dev);

      expect(second.sessionId, isNot(first));

      second.unmount();
    });
  });

  group('lifecycle events', () {
    test('reports SESSION_CREATED on a cold initialize', () async {
      await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      expect(backend.reportedSdkEvents, contains('SESSION_CREATED'));
    });

    test('reports the session id as an event param', () async {
      await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      final event = backend.requestsTo('/events').first.events.first;
      final params = event['event_params'] as Map<String, dynamic>;

      expect(params['sessionId'], sdk.sessionId);
      expect(event['event_source'], 'sdk');
    });

    test('reports SESSION_BACKGROUNDED when the app is paused', () async {
      await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      await _sendLifecycle(AppLifecycleState.paused);

      expect(backend.reportedSdkEvents, contains('SESSION_BACKGROUNDED'));
    });

    test('resumes the same session inside the session window', () async {
      await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      final original = sdk.sessionId;

      await _sendLifecycle(AppLifecycleState.paused);
      await _sendLifecycle(AppLifecycleState.resumed);

      expect(sdk.sessionId, original);
      expect(backend.reportedSdkEvents, contains('SESSION_RESUMED'));
    });

    test('mints a new session once the window has elapsed', () async {
      final start = DateTime(2026, 9, 2, 12);

      late String original;

      await withClock(Clock.fixed(start), () async {
        await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
        await pumpEventQueue();

        original = sdk.sessionId!;

        await _sendLifecycle(AppLifecycleState.paused);
      });

      await withClock(
        Clock.fixed(
          start.add(
            const Duration(
              seconds: AdadaptedFlutterSdk.sessionLifetimeSeconds + 1,
            ),
          ),
        ),
        () async {
          await _sendLifecycle(AppLifecycleState.resumed);
        },
      );

      expect(sdk.sessionId, isNot(original));
      expect(
        backend.reportedSdkEvents.where((e) => e == 'SESSION_CREATED').length,
        2,
      );
    });

    test('ignores inactive, which iOS raises for the app switcher', () async {
      await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      final before = backend.reportedSdkEvents.length;

      await _sendLifecycle(AppLifecycleState.inactive);

      expect(backend.reportedSdkEvents.length, before);
    });

    test('ignores a resume that never followed a background', () async {
      await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      final before = backend.reportedSdkEvents.length;

      // iOS raises inactive then resumed during the launch animation. Acting on
      // it would report a resume for a session that never left.
      await _sendLifecycle(AppLifecycleState.inactive);
      await _sendLifecycle(AppLifecycleState.resumed);

      expect(backend.reportedSdkEvents.length, before);
    });

    test('a second initialize does not double-report backgrounding', () async {
      await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
      await pumpEventQueue();
      await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      await _sendLifecycle(AppLifecycleState.paused);

      expect(
        backend.reportedSdkEvents
            .where((e) => e == 'SESSION_BACKGROUNDED')
            .length,
        1,
      );
    });
  });

  group('unmount', () {
    test('releases the session and device info', () async {
      await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      sdk.unmount();

      expect(sdk.sessionId, isNull);
      expect(sdk.deviceInfo, isNull);
    });

    test('stops the lifecycle observer from reporting', () async {
      await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      sdk.unmount();

      final before = backend.reportedSdkEvents.length;

      await _sendLifecycle(AppLifecycleState.paused);

      expect(backend.reportedSdkEvents.length, before);
    });

    test('stops the public reporting methods from posting', () async {
      await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      sdk.unmount();

      final before = backend.requests.length;

      sdk.reportItemsAddedToList(<String>['Milk'], 'My list');
      sdk.markPayloadContentAcknowledged('PAYLOAD');

      expect(backend.requests.length, before);
    });
  });

  group('device info', () {
    test('is exposed once initialize resolves', () async {
      await sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      expect(sdk.deviceInfo!.udid, 'TEST-UDID');
      expect(sdk.deviceInfo!.bundleId, 'com.test.app');
    });

    test('takes a custom advertiser id on iOS only', () async {
      installFakeDeviceInfoChannel(
        deviceInfo: <String, Object>{
          ...fakeDeviceInfo,
          'systemName': 'ios_flutter',
        },
      );

      await sdk.initialize(
        appId: 'APP',
        apiEnv: ApiEnv.dev,
        advertiserId: 'CUSTOM-ID',
      );
      await pumpEventQueue();

      expect(sdk.deviceInfo!.udid, 'CUSTOM-ID');
    });

    test('ignores a custom advertiser id on Android', () async {
      await sdk.initialize(
        appId: 'APP',
        apiEnv: ApiEnv.dev,
        advertiserId: 'CUSTOM-ID',
      );
      await pumpEventQueue();

      expect(sdk.deviceInfo!.udid, 'TEST-UDID');
    });

    test('propagates a platform failure out of initialize', () async {
      installFakeDeviceInfoChannel(fail: true);

      await expectLater(
        sdk.initialize(appId: 'APP', apiEnv: ApiEnv.dev),
        throwsA(isA<Exception>()),
      );
    });
  });
}

/// Delivers a lifecycle state to every registered observer.
///
/// The SDK observes the binding rather than owning a widget, so this is how a
/// test raises a foreground or background transition.
/// @param state - The state to deliver.
Future<void> _sendLifecycle(AppLifecycleState state) async {
  WidgetsBinding.instance.handleAppLifecycleStateChanged(state);

  await pumpEventQueue();
}
