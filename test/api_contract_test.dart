/// The wire contract: routes, headers and field names shared with the Android,
/// iOS, React Native and web SDKs.
///
/// These assertions are deliberately literal. The snake_case keys and the route
/// paths are not this package's to rename, and a rename that only breaks
/// reporting would otherwise ship silently.
library;

import 'package:adadapted_flutter_sdk/adadapted_flutter_sdk.dart';
import 'package:adadapted_flutter_sdk/src/ad_request_context.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend backend;
  late AdadaptedFlutterSdk sdk;

  setUp(() async {
    resetSdkStatics();
    installFakeDeviceInfoChannel();

    backend = FakeBackend();
    sdk = buildSdk(backend);

    await sdk.initialize(appId: 'TEST_APP_ID', apiEnv: ApiEnv.dev);
    await pumpEventQueue();
  });

  tearDown(() {
    sdk.unmount();
    removeFakeDeviceInfoChannel();
  });

  group('environments', () {
    test('dev points every backend at its sandbox tier', () async {
      sdk.reportItemsAddedToList(<String>['Milk']);
      sdk.markPayloadContentAcknowledged('PAYLOAD');

      await pumpEventQueue();

      expect(
        backend.requestsTo('sandec.adadapted.com'),
        isNotEmpty,
        reason: 'the list manager must follow the requested environment',
      );
      expect(
        backend.requestsTo('sandpayload.adadapted.com'),
        isNotEmpty,
        reason: 'the payload server must follow the requested environment',
      );
    });

    test('prod is the default when no environment is given', () async {
      resetSdkStatics();

      final other = buildSdk(backend);

      await other.initialize(appId: 'TEST_APP_ID');
      await pumpEventQueue();

      expect(backend.requestsTo('ec.adadapted.com'), isNotEmpty);

      other.unmount();
    });
  });

  group('list manager events', () {
    test('post to the versioned per-OS route', () {
      expect(
        backend.requestsTo('/events').first.url,
        'https://sandec.adadapted.com/v/1/android/events',
      );
    });

    test('carry the device fields the native SDKs send', () {
      final body = backend.requestsTo('/events').first.body;

      expect(body['session_id'], sdk.sessionId);
      expect(body['app_id'], 'TEST_APP_ID');
      expect(body['udid'], 'TEST-UDID');
      expect(body['bundle_id'], 'com.test.app');
      expect(body['bundle_version'], '1.2.3');
      expect(body['locale'], 'en_US');
      expect(body['allow_retargeting'], 1);
      expect(body['device'], 'TestDevice');
      expect(body['os'], 'android_flutter');
      expect(body['osv'], '15');
      expect(body['timezone'], 'America/Indiana/Indianapolis');
      expect(body['carrier'], 'TestCarrier');
      expect(body['density'], '3.0');
    });

    test('send the screen dimensions as numbers, not strings', () {
      final body = backend.requestsTo('/events').first.body;

      expect(body['dw'], 1080);
      expect(body['dh'], 2400);
    });

    test('report allow_retargeting as 0 when tracking is refused', () async {
      resetSdkStatics();
      installFakeDeviceInfoChannel(
        deviceInfo: <String, Object>{
          ...fakeDeviceInfo,
          'isAdTrackingEnabled': false,
        },
      );

      final other = FakeBackend();
      final tracked = buildSdk(other);

      await tracked.initialize(appId: 'TEST_APP_ID', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      expect(other.requestsTo('/events').first.body['allow_retargeting'], 0);

      tracked.unmount();
    });

    test('name the add, cross off and delete events as the API does', () async {
      sdk.reportItemsAddedToList(<String>['Milk'], 'My list');
      sdk.reportItemsCrossedOffList(<String>['Eggs'], 'My list');
      sdk.reportItemsDeletedFromList(<String>['Bread']);

      await pumpEventQueue();

      expect(
        backend.reportedSdkEvents,
        containsAll(<String>[
          'user_added_to_list',
          'user_crossed_off_list',
          'user_deleted_from_list',
        ]),
      );
    });

    test('report one event per item name', () async {
      sdk.reportItemsAddedToList(<String>['Milk', 'Eggs', 'Bread'], 'My list');

      await pumpEventQueue();

      final request = backend
          .requestsTo('/events')
          .where((r) => r.events.first['event_source'] == 'app')
          .first;

      expect(request.events.length, 3);
      expect(
        request.events
            .map(
              (e) => (e['event_params'] as Map<String, dynamic>)['item_name'],
            )
            .toList(),
        <String>['Milk', 'Eggs', 'Bread'],
      );
    });

    test('omit list_name entirely when there is no list', () async {
      sdk.reportItemsAddedToList(<String>['Milk']);

      await pumpEventQueue();

      final request = backend
          .requestsTo('/events')
          .where((r) => r.events.first['event_source'] == 'app')
          .first;
      final params =
          request.events.first['event_params'] as Map<String, dynamic>;

      // Left off the payload rather than sent as null, matching what
      // JSON.stringify does for an undefined field in the other SDKs.
      expect(params.containsKey('list_name'), isFalse);
      expect(params['item_name'], 'Milk');
    });
  });

  group('payload tracking', () {
    test('posts to the tracking route with the documented statuses', () async {
      sdk.markPayloadContentAcknowledged('PAYLOAD_1');
      sdk.markPayloadContentRejected('PAYLOAD_2');

      await pumpEventQueue();

      final requests = backend.requestsTo('/v/1/tracking');

      expect(requests.length, 2);
      expect(
        requests.first.url,
        'https://sandpayload.adadapted.com/v/1/tracking',
      );

      final statuses = requests
          .expand((r) => (r.body['tracking'] as List<dynamic>))
          .cast<Map<String, dynamic>>()
          .map((t) => t['status'])
          .toList();

      expect(statuses, <String>['delivered', 'rejected']);
    });

    test('pickup carries the session, app and device identity', () {
      final body = backend.requestsTo('/v/1/pickup').first.body;

      expect(body['app_id'], 'TEST_APP_ID');
      expect(body['session_id'], sdk.sessionId);
      expect(body['udid'], 'TEST-UDID');
    });
  });

  group('intercept retrieve', () {
    test('posts to the v1.0.0 route with the api key header', () {
      final request = backend.requestsTo('/v/1.0.0/intercept/retrieve').first;

      expect(
        request.url,
        'https://sandbox.adadapted.com/v/1.0.0/intercept/retrieve',
      );
      expect(request.headers['x-api-key'], 'TEST_APP_ID');
    });

    test('names the SDK version sdkId and the device userId', () {
      final body = backend.requestsTo('/v/1.0.0/intercept/retrieve').first.body;

      expect(body['sdkId'], isNotEmpty);
      expect(body['userId'], 'TEST-UDID');
      expect(body['bundleId'], 'com.test.app');
      expect(body['sessionId'], sdk.sessionId);
      // Intercepts are not zone scoped.
      expect(body['zoneId'], '');
    });
  });

  group('v1.0.0 event envelopes', () {
    // The two routes this SDK moved to the v1.0.0 shape. FakeBackend answers an
    // unmatched route with an empty 200, so without these assertions dropping
    // app_id, udid or session_id from either envelope would pass green. The
    // per-event fields are covered in the zone tests; this is the wrapper.

    test('ad events identify the app, device and session', () async {
      AdRequestContextRegistry.context!.reportAdEvent(
        const AdEventReport(
          adId: 'ad-1',
          zoneId: 'zone-1',
          impressionId: 'imp-1',
          eventType: ReportedEventType.impression,
        ),
      );

      await pumpEventQueue();

      final request = backend.requestsTo('/v/1.0.0/ad/events').single;

      expect(request.headers['x-api-key'], 'TEST_APP_ID');
      expect(request.body['app_id'], 'TEST_APP_ID');
      expect(request.body['udid'], 'TEST-UDID');
      expect(request.body['session_id'], sdk.sessionId);
      expect(request.events, hasLength(1));
    });

    test('intercept events identify the app, device and session', () async {
      resetSdkStatics();

      final other = FakeBackend();

      other.responses['/intercept/retrieve'] = <String, Object>{
        'success': true,
        'data': <String, Object>{
          'search_id': 'search-1',
          'terms': <Map<String, Object>>[
            <String, Object>{
              'term_id': 'term-1',
              'term': 'milk',
              'replacement': 'Milk',
              'priority': 0,
            },
          ],
        },
      };

      final searching = buildSdk(other);

      await searching.initialize(appId: 'TEST_APP_ID', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      searching.performKeywordSearch('milk');

      await pumpEventQueue();

      final request = other.requestsTo('/v/1.0.0/intercept/events').single;

      expect(request.headers['x-api-key'], 'TEST_APP_ID');
      expect(request.body['app_id'], 'TEST_APP_ID');
      expect(request.body['udid'], 'TEST-UDID');
      expect(request.body['session_id'], searching.sessionId);
      expect(request.events, hasLength(1));

      searching.unmount();
    });
  });

  group('failures', () {
    test('a failing intercept fetch leaves the SDK usable', () async {
      resetSdkStatics();

      final other = FakeBackend()..failingPaths.add('/intercept/retrieve');
      final resilient = buildSdk(other);

      await resilient.initialize(appId: 'TEST_APP_ID', apiEnv: ApiEnv.dev);
      await pumpEventQueue();

      expect(resilient.sessionId, isNotNull);
      expect(resilient.performKeywordSearch('milk'), isEmpty);

      resilient.unmount();
    });

    test('a failing report does not throw at the caller', () async {
      resetSdkStatics();

      final other = FakeBackend()..failingPaths.add('/events');
      final resilient = buildSdk(other);

      await resilient.initialize(appId: 'TEST_APP_ID', apiEnv: ApiEnv.dev);

      expect(
        () => resilient.reportItemsAddedToList(<String>['Milk']),
        returnsNormally,
      );

      await pumpEventQueue();

      resilient.unmount();
    });
  });
}
