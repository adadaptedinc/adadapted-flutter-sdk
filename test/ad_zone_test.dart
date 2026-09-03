/// The ad zone state machine: serving, the refresh countdown, impression
/// pairing, unfilled reasons and clicks.
library;

import 'package:adadapted_flutter_sdk/adadapted_flutter_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'support/fake_webview_platform.dart';
import 'support/test_harness.dart';

/// An ad response the fake backend serves.
/// @param id - The ad ID. Empty means the API had nothing to serve.
/// @param refreshTime - How long the ad is displayed for.
/// @param creativeUrl - The creative to render.
/// @param actionType - What interacting with the ad does.
/// @param actionPath - Where interacting with the ad navigates.
/// @param items - The add-to-list items the ad offers.
Map<String, Object> adResponse({
  String id = 'ad-1',
  int refreshTime = 30,
  String creativeUrl = 'https://creatives.test/ad-1',
  String actionType = 'c',
  String actionPath = '',
  List<Map<String, Object>>? items,
}) {
  return <String, Object>{
    'success': true,
    'data': <String, Object>{
      'port_height': 250,
      'port_width': 320,
      'ad': <String, Object>{
        'id': id,
        'impression_id': 'imp-$id',
        'refresh_time': refreshTime,
        'creative_url': creativeUrl,
        'action_type': actionType,
        'action_path': actionPath,
        'payload': <String, Object>{
          'detailed_list_items':
              items ??
              <Map<String, Object>>[
                <String, Object>{
                  'product_title': 'Sample Product',
                  'product_barcode': '0',
                  'product_brand': 'Brand',
                  'product_category': '',
                  'product_discount': '',
                  'product_image': '',
                  'product_sku': '',
                },
              ],
        },
      },
    },
  };
}

/// Drains the microtasks an ad request and its callbacks run through.
/// @param tester - The widget tester.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(Duration.zero);
  }
}

/// Pumps a zone inside a sized, laid out app.
/// @param tester - The widget tester.
/// @param zone - The zone to place.
Future<void> pumpZone(WidgetTester tester, Widget zone) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 320, height: 250, child: zone)),
      ),
    ),
  );

  await settle(tester);
}

/// The controller the zone most recently built.
FakeWebViewController get controller => fakeWebViewControllers.last;

/// Reports that the creative rendered, and lets the settle timer fire.
/// @param tester - The widget tester.
Future<void> finishCreative(WidgetTester tester) async {
  controller.finishLoad();

  await settle(tester);
}

void main() {
  late FakeBackend backend;
  late AdadaptedFlutterSdk sdk;

  setUp(() {
    resetSdkStatics();
    installFakeDeviceInfoChannel();
    installFakeWebViewPlatform();

    // The detector batches its callbacks on a timer by default, which a widget
    // test never advances far enough to fire.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;

    backend = FakeBackend();
    backend.responses['/ad/retrieve'] = adResponse();

    sdk = buildSdk(backend);
  });

  tearDown(() {
    sdk.unmount();
    removeFakeDeviceInfoChannel();
  });

  /// Initializes the SDK and lets its opening requests settle.
  /// @param tester - The widget tester.
  Future<void> initialize(WidgetTester tester) async {
    await sdk.initialize(appId: 'TEST_APP_ID', apiEnv: ApiEnv.dev);
    await settle(tester);
  }

  group('mounting', () {
    testWidgets('reports zone_mounted once the SDK is ready', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      expect(backend.reportedAdEvents, contains('zone_mounted'));
    });

    testWidgets('waits for the SDK before reporting anything', (tester) async {
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      expect(backend.reportedAdEvents, isEmpty);

      await initialize(tester);
      await settle(tester);

      // A host builds its layout immediately, while initialize() is still
      // gathering device info, so a zone normally mounts before there is any
      // context to request with.
      expect(backend.reportedAdEvents, contains('zone_mounted'));
    });

    testWidgets('requests an ad for its own zone id', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      final request = backend.requestsTo('/ad/retrieve').first;

      expect(request.body['zoneId'], 'zone-1');
      expect(request.body['sessionId'], sdk.sessionId);
      expect(request.headers['x-api-key'], 'TEST_APP_ID');
    });

    testWidgets('carries the recipe context on the request', (tester) async {
      await initialize(tester);
      await pumpZone(
        tester,
        const AdZone(zoneId: 'zone-1', isVisible: true, contextId: 'recipe-9'),
      );

      expect(
        backend.requestsTo('/ad/retrieve').first.body['contextId'],
        'recipe-9',
      );
    });

    testWidgets('reports zone_unmounted when disposed', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await tester.pumpWidget(const SizedBox.shrink());

      expect(backend.reportedAdEvents, contains('zone_unmounted'));
    });

    testWidgets('pairs its mount and unmount one to one', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await tester.pumpWidget(const SizedBox.shrink());

      expect(
        backend.reportedAdEvents.where((e) => e == 'zone_mounted').length,
        1,
      );
      expect(
        backend.reportedAdEvents.where((e) => e == 'zone_unmounted').length,
        1,
      );
    });
  });

  group('layout', () {
    testWidgets('fills the space its parent gives it', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      expect(tester.getSize(find.byType(AdZone)), const Size(320, 250));
    });

    testWidgets('fills a loosely constrained parent too', (tester) async {
      await initialize(tester);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                SizedBox(
                  height: 250,
                  child: AdZone(zoneId: 'zone-1', isVisible: true),
                ),
              ],
            ),
          ),
        ),
      );

      await settle(tester);
      await finishCreative(tester);

      // Every child of the zone's stack is positioned, so without an expanding
      // fit the zone collapses to nothing and renders an ad no one can see.
      expect(tester.getSize(find.byType(AdZone)).height, 250);
      expect(tester.getSize(find.byType(AdZone)).width, greaterThan(0));
    });

    testWidgets('takes up no space while it has no ad', (tester) async {
      backend.responses['/ad/retrieve'] = adResponse(id: '');

      await initialize(tester);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[AdZone(zoneId: 'zone-1', isVisible: true)],
            ),
          ),
        ),
      );

      await settle(tester);

      expect(tester.getSize(find.byType(AdZone)), Size.zero);
    });
  });

  group('impressions', () {
    testWidgets('are not reported until the creative renders', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      // The ad has arrived, but nothing has painted. Reporting on the response
      // alone bills ads whose creative failed.
      expect(backend.reportedAdEvents, isNot(contains('impression')));

      await finishCreative(tester);

      expect(backend.reportedAdEvents, contains('impression'));
    });

    testWidgets('inject the creative pixels before reporting', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      // Without this, third party verification sees no impressions at all
      // however healthy our own numbers look.
      expect(controller.runJavaScripts, contains('loadTrackingPixels()'));
    });

    testWidgets('are reported once per ad', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      controller.finishLoad();

      await settle(tester);

      expect(
        backend.reportedAdEvents.where((e) => e == 'impression').length,
        1,
      );
    });

    testWidgets('are not reported for a zone that is off screen', (
      tester,
    ) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: false));
      await finishCreative(tester);

      expect(backend.reportedAdEvents, isNot(contains('impression')));
    });

    testWidgets('are reported when an off screen zone comes back', (
      tester,
    ) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: false));
      await finishCreative(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      expect(backend.reportedAdEvents, contains('impression'));
    });

    testWidgets('end when the zone leaves the screen', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: false));

      expect(backend.reportedAdEvents, contains('impression_end'));
    });

    testWidgets('end at most once per ad', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: false));
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: false));

      expect(
        backend.reportedAdEvents.where((e) => e == 'impression_end').length,
        1,
      );
    });

    testWidgets('are not owed for an ad whose creative failed', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      controller.failLoad();

      await settle(tester);

      expect(backend.reportedAdEvents, isNot(contains('impression')));
    });

    testWidgets('survive a load event that precedes an error', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      // Android's WebViewClient reports a finished page for a load that failed.
      // Acting on that first event bills an impression for an ad that failed.
      controller.finishLoad();
      controller.failLoad();

      await settle(tester);

      expect(backend.reportedAdEvents, isNot(contains('impression')));
      expect(backend.reportedAdEvents, contains('zone_unfilled'));
    });

    testWidgets('are not discarded by a sub-resource failure', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      controller.failLoad(isForMainFrame: false);

      await finishCreative(tester);

      expect(backend.reportedAdEvents, contains('impression'));
    });

    testWidgets('end when the app is backgrounded', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

      await settle(tester);

      expect(backend.reportedAdEvents, contains('impression_end'));
    });
  });

  group('unfilled reasons', () {
    testWidgets('report no_ad for an ad object with no id', (tester) async {
      backend.responses['/ad/retrieve'] = adResponse(id: '');

      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      final event = backend
          .requestsTo('/ad/events')
          .expand((r) => r.events)
          .firstWhere((e) => e['event_type'] == 'zone_unfilled');

      expect(event['event_name'], 'no_ad');
    });

    testWidgets('report request_failed when the request fails', (tester) async {
      backend.failingPaths.add('/ad/retrieve');

      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      final event = backend
          .requestsTo('/ad/events')
          .expand((r) => r.events)
          .firstWhere((e) => e['event_type'] == 'zone_unfilled');

      expect(event['event_name'], 'request_failed');
    });

    testWidgets('report request_failed on success:false', (tester) async {
      backend.responses['/ad/retrieve'] = <String, Object>{
        'success': false,
        'data': <String, Object>{},
      };

      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      // The API returns success:false on a 200 for business rejections, so the
      // status code alone is not enough.
      final event = backend
          .requestsTo('/ad/events')
          .expand((r) => r.events)
          .firstWhere((e) => e['event_type'] == 'zone_unfilled');

      expect(event['event_name'], 'request_failed');
    });

    testWidgets('report render_failed for an ad with no creative', (
      tester,
    ) async {
      backend.responses['/ad/retrieve'] = adResponse(creativeUrl: '');

      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      final event = backend
          .requestsTo('/ad/events')
          .expand((r) => r.events)
          .firstWhere((e) => e['event_type'] == 'zone_unfilled');

      expect(event['event_name'], 'render_failed');
    });

    testWidgets('report render_failed when the creative errors', (
      tester,
    ) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      controller.failLoad();

      await settle(tester);

      final event = backend
          .requestsTo('/ad/events')
          .expand((r) => r.events)
          .firstWhere((e) => e['event_type'] == 'zone_unfilled');

      expect(event['event_name'], 'render_failed');
    });

    testWidgets('carry no event_name on any other event type', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      final impression = backend
          .requestsTo('/ad/events')
          .expand((r) => r.events)
          .firstWhere((e) => e['event_type'] == 'impression');

      // Left off the payload entirely rather than sent as null.
      expect(impression.containsKey('event_name'), isFalse);
    });

    testWidgets('are held until an off screen zone is seen', (tester) async {
      backend.responses['/ad/retrieve'] = adResponse(id: '');

      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: false));

      expect(backend.reportedAdEvents, isNot(contains('zone_unfilled')));

      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      expect(backend.reportedAdEvents, contains('zone_unfilled'));
    });
  });

  group('refresh', () {
    testWidgets('requests the next ad when the refresh time elapses', (
      tester,
    ) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      expect(backend.requestsTo('/ad/retrieve').length, 1);

      await tester.pump(const Duration(seconds: 31));
      await settle(tester);

      expect(backend.requestsTo('/ad/retrieve').length, 2);
    });

    testWidgets('floors an unexpectedly small refresh time', (tester) async {
      backend.responses['/ad/retrieve'] = adResponse(refreshTime: 1);

      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      await tester.pump(const Duration(seconds: 5));
      await settle(tester);

      // A tight request loop is what the floor exists to prevent.
      expect(backend.requestsTo('/ad/retrieve').length, 1);

      await tester.pump(const Duration(seconds: 11));
      await settle(tester);

      expect(backend.requestsTo('/ad/retrieve').length, 2);
    });

    testWidgets('honors a refresh time delivered as a string', (tester) async {
      final response = adResponse();
      final data = response['data']! as Map<String, Object>;
      final ad = data['ad']! as Map<String, Object>;

      ad['refresh_time'] = '20';

      backend.responses['/ad/retrieve'] = response;

      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      await tester.pump(const Duration(seconds: 21));
      await settle(tester);

      // The other SDKs coerce this through Number(), so a hard type check here
      // would quietly drop it to the 60 second default.
      expect(backend.requestsTo('/ad/retrieve').length, 2);
    });

    testWidgets('falls back to the default for a zero refresh time', (
      tester,
    ) async {
      backend.responses['/ad/retrieve'] = adResponse(refreshTime: 0);

      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      await tester.pump(const Duration(seconds: 45));
      await settle(tester);

      expect(backend.requestsTo('/ad/retrieve').length, 1);

      await tester.pump(const Duration(seconds: 20));
      await settle(tester);

      expect(backend.requestsTo('/ad/retrieve').length, 2);
    });

    testWidgets('freezes while the zone is off screen', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: false));

      await tester.pump(const Duration(seconds: 120));
      await settle(tester);

      expect(backend.requestsTo('/ad/retrieve').length, 1);
    });

    testWidgets('replaces an ad that outlived its refresh while frozen', (
      tester,
    ) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: false));

      await tester.pump(const Duration(seconds: 120));

      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      // Rather than being shown for time it never spent in front of anyone.
      expect(backend.requestsTo('/ad/retrieve').length, 2);
    });

    testWidgets('freezes while the app is backgrounded', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

      await tester.pump(const Duration(seconds: 120));
      await settle(tester);

      expect(backend.requestsTo('/ad/retrieve').length, 1);
    });

    testWidgets('gives each ad its own impression pair', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      await tester.pump(const Duration(seconds: 31));
      await settle(tester);
      await finishCreative(tester);

      expect(
        backend.reportedAdEvents.where((e) => e == 'impression').length,
        2,
      );
      expect(
        backend.reportedAdEvents.where((e) => e == 'impression_end').length,
        1,
      );
    });

    testWidgets('does not bill an impression pair for a mid-request flip', (
      tester,
    ) async {
      backend.delays['/ad/retrieve'] = const Duration(seconds: 2);

      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      await finishCreative(tester);

      expect(
        backend.reportedAdEvents.where((e) => e == 'impression').length,
        1,
      );

      // The refresh fires and leaves a request open. A visibility flip while one
      // is in flight is routine — returning to the foreground does the same — and
      // the countdown has to stay owned across it, or the zone queues a refetch
      // and then bills an impression and an impression_end for the arriving ad
      // in a single tick.
      await tester.pump(const Duration(seconds: 31));
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: false));
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      await tester.pump(const Duration(seconds: 3));
      await settle(tester);
      await finishCreative(tester);

      expect(backend.requestsTo('/ad/retrieve').length, 2);
      expect(
        backend.reportedAdEvents.where((e) => e == 'impression').length,
        2,
      );
      expect(
        backend.reportedAdEvents.where((e) => e == 'impression_end').length,
        1,
      );
    });

    testWidgets('reloads a repeated creative so its impression lands', (
      tester,
    ) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      await tester.pump(const Duration(seconds: 31));
      await settle(tester);

      // Two ads rotating through the same creative is routine, and the
      // impression is owed on the load event.
      expect(controller.loadedUrls.length, 2);
    });
  });

  group('fill callbacks', () {
    testWidgets('tell the host when the zone fills', (tester) async {
      final states = <bool>[];

      await initialize(tester);
      await pumpZone(
        tester,
        AdZone(zoneId: 'zone-1', isVisible: true, onZoneHasAds: states.add),
      );

      expect(states, <bool>[true]);
    });

    testWidgets('tell the host when the zone does not fill', (tester) async {
      backend.responses['/ad/retrieve'] = adResponse(id: '');

      final states = <bool>[];

      await initialize(tester);
      await pumpZone(
        tester,
        AdZone(zoneId: 'zone-1', isVisible: true, onZoneHasAds: states.add),
      );

      expect(states, <bool>[false]);
    });

    testWidgets('fire only when the fill state changes', (tester) async {
      final states = <bool>[];

      await initialize(tester);
      await pumpZone(
        tester,
        AdZone(zoneId: 'zone-1', isVisible: true, onZoneHasAds: states.add),
      );
      await finishCreative(tester);

      await tester.pump(const Duration(seconds: 31));
      await settle(tester);

      // Firing on every rotation with an unchanged value rebuilds the host for
      // nothing.
      expect(states, <bool>[true]);
    });

    testWidgets('report a load to the host', (tester) async {
      var loaded = 0;
      var failed = 0;

      await initialize(tester);
      await pumpZone(
        tester,
        AdZone(
          zoneId: 'zone-1',
          isVisible: true,
          onAdLoaded: () {
            loaded++;
          },
          onAdLoadFailed: () {
            failed++;
          },
        ),
      );
      await finishCreative(tester);

      expect(loaded, 1);
      expect(failed, 0);
    });

    testWidgets('report a creative that never rendered', (tester) async {
      var loaded = 0;
      var failed = 0;

      await initialize(tester);
      await pumpZone(
        tester,
        AdZone(
          zoneId: 'zone-1',
          isVisible: true,
          onAdLoaded: () {
            loaded++;
          },
          onAdLoadFailed: () {
            failed++;
          },
        ),
      );

      controller.failLoad();

      await settle(tester);

      expect(failed, 1);
      expect(loaded, 0);
    });

    testWidgets('ignore a failure once the creative has rendered', (
      tester,
    ) async {
      var failed = 0;

      await initialize(tester);
      await pumpZone(
        tester,
        AdZone(
          zoneId: 'zone-1',
          isVisible: true,
          onAdLoadFailed: () {
            failed++;
          },
        ),
      );
      await finishCreative(tester);

      controller.failLoad();

      await settle(tester);

      // An ad that has already rendered and been billed must not be discarded
      // by a late error, the same way a late load event cannot bill one that
      // already failed.
      expect(failed, 0);
      expect(backend.requestsTo('/ad/retrieve').length, 1);
    });
  });

  group('zone switching', () {
    testWidgets('closes the old zone and opens the new one', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await pumpZone(tester, const AdZone(zoneId: 'zone-2', isVisible: true));

      final events = backend.requestsTo('/ad/events').expand((r) => r.events);

      expect(
        events
            .where((e) => e['event_type'] == 'zone_unmounted')
            .map((e) => e['zone_id']),
        contains('zone-1'),
      );
      expect(
        events
            .where((e) => e['event_type'] == 'zone_mounted')
            .map((e) => e['zone_id']),
        containsAll(<String>['zone-1', 'zone-2']),
      );
    });

    testWidgets('requests an ad for the zone it moved to', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await pumpZone(tester, const AdZone(zoneId: 'zone-2', isVisible: true));

      expect(
        backend.requestsTo('/ad/retrieve').map((r) => r.body['zoneId']),
        containsAll(<String>['zone-1', 'zone-2']),
      );
    });
  });

  group('recipe context', () {
    testWidgets('refetches when the context changes', (tester) async {
      await initialize(tester);
      await pumpZone(
        tester,
        const AdZone(zoneId: 'zone-1', isVisible: true, contextId: 'recipe-1'),
      );
      await finishCreative(tester);
      await pumpZone(
        tester,
        const AdZone(zoneId: 'zone-1', isVisible: true, contextId: 'recipe-2'),
      );

      expect(
        backend.requestsTo('/ad/retrieve').map((r) => r.body['contextId']),
        containsAll(<String>['recipe-1', 'recipe-2']),
      );
    });

    testWidgets('does not refetch when the context is unchanged', (
      tester,
    ) async {
      await initialize(tester);
      await pumpZone(
        tester,
        const AdZone(zoneId: 'zone-1', isVisible: true, contextId: 'recipe-1'),
      );
      await finishCreative(tester);
      await pumpZone(
        tester,
        const AdZone(zoneId: 'zone-1', isVisible: true, contextId: 'recipe-1'),
      );

      expect(backend.requestsTo('/ad/retrieve').length, 1);
    });
  });

  group('clicks', () {
    testWidgets('hand add-to-list items to the zone handler', (tester) async {
      final received = <DetailedListItem>[];

      await initialize(tester);
      await pumpZone(
        tester,
        AdZone(
          zoneId: 'zone-1',
          isVisible: true,
          onAddToListTriggered: received.addAll,
        ),
      );
      await finishCreative(tester);

      await tester.tapAt(tester.getCenter(find.byType(AdZone)));
      await settle(tester);

      expect(received.single.productTitle, 'Sample Product');
    });

    testWidgets('fall back to the handler given to initialize', (tester) async {
      final received = <DetailedListItem>[];

      await sdk.initialize(
        appId: 'TEST_APP_ID',
        apiEnv: ApiEnv.dev,
        onAddToListTriggered: received.addAll,
      );
      await settle(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      await tester.tapAt(tester.getCenter(find.byType(AdZone)));
      await settle(tester);

      expect(received.single.productTitle, 'Sample Product');
    });

    testWidgets('report atl_ad_clicked, not an interaction', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      await tester.tapAt(tester.getCenter(find.byType(AdZone)));
      await settle(tester);

      // The interaction is earned when the host confirms the items reached the
      // list, through AdadaptedFlutterSdk.acknowledge.
      expect(backend.reportedSdkEvents, contains('atl_ad_clicked'));
      expect(backend.reportedAdEvents, isNot(contains('interaction')));
    });

    testWidgets('report an interaction for an external ad', (tester) async {
      backend.responses['/ad/retrieve'] = adResponse(
        actionType: 'e',
        actionPath: 'https://advertiser.test/landing',
      );

      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      await tester.tapAt(tester.getCenter(find.byType(AdZone)));
      await settle(tester);

      expect(backend.reportedAdEvents, contains('interaction'));
    });

    testWidgets('are ignored past the drag distance', (tester) async {
      final received = <DetailedListItem>[];

      await initialize(tester);
      await pumpZone(
        tester,
        AdZone(
          zoneId: 'zone-1',
          isVisible: true,
          xyDragDistanceAllowed: 10,
          onAddToListTriggered: received.addAll,
        ),
      );
      await finishCreative(tester);

      final center = tester.getCenter(find.byType(AdZone));
      final gesture = await tester.startGesture(center);

      await gesture.moveBy(const Offset(0, -60));
      await gesture.up();
      await settle(tester);

      // A scroll through the zone is not a tap on it.
      expect(received, isEmpty);
    });

    testWidgets('are handled once per ad', (tester) async {
      final received = <DetailedListItem>[];

      // The click asks for the next ad. Holding that request open keeps the ad
      // that was clicked on screen, which is the case the guard exists for: the
      // touch target stays live, and a second tap would otherwise report a
      // second click against the same impression.
      backend.hangAfter['/ad/retrieve'] = 1;

      await initialize(tester);
      await pumpZone(
        tester,
        AdZone(
          zoneId: 'zone-1',
          isVisible: true,
          onAddToListTriggered: received.addAll,
        ),
      );
      await finishCreative(tester);

      final center = tester.getCenter(find.byType(AdZone));

      await tester.tapAt(center);
      await tester.tapAt(center);
      await settle(tester);

      expect(received.length, 1);
      expect(
        backend.reportedSdkEvents.where((e) => e == 'atl_ad_clicked').length,
        1,
      );

      // Let the held request reach its own timeout, so no timer outlives the
      // test. Every request is bounded, which is what stops a zone that loses a
      // response from being stranded with its in-flight latch set.
      await tester.pump(const Duration(seconds: 11));
      await settle(tester);
    });

    testWidgets('do not cost the zone its ad for an unhandled action', (
      tester,
    ) async {
      backend.responses['/ad/retrieve'] = adResponse(actionType: 'n');

      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      await tester.tapAt(tester.getCenter(find.byType(AdZone)));
      await settle(tester);

      expect(backend.requestsTo('/ad/retrieve').length, 1);
    });
  });

  group('sdk teardown', () {
    testWidgets('closes the zone out while it can still report', (
      tester,
    ) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      sdk.unmount();

      await settle(tester);

      expect(backend.reportedAdEvents, contains('impression_end'));
      expect(backend.reportedAdEvents, contains('zone_unmounted'));
    });

    testWidgets('reports one unmount however the zone goes away', (
      tester,
    ) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      sdk.unmount();

      await settle(tester);
      await tester.pumpWidget(const SizedBox.shrink());

      expect(
        backend.reportedAdEvents.where((e) => e == 'zone_unmounted').length,
        1,
      );
    });

    testWidgets('takes the ad down with the SDK', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));
      await finishCreative(tester);

      sdk.unmount();

      await settle(tester);

      // Anything left on screen is an ad nothing can account for, and it would
      // stay tappable.
      expect(find.byType(SizedBox), findsWidgets);
      expect(backend.reportedAdEvents, isNot(contains('interaction')));
    });

    testWidgets('restarts a zone that a later initialize revives', (
      tester,
    ) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1', isVisible: true));

      sdk.unmount();

      await settle(tester);

      final before = backend.requestsTo('/ad/retrieve').length;

      await initialize(tester);
      await settle(tester);

      expect(backend.requestsTo('/ad/retrieve').length, greaterThan(before));
    });
  });

  group('measured visibility', () {
    testWidgets('serves a zone that is on screen', (tester) async {
      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1'));
      await finishCreative(tester);

      expect(backend.reportedAdEvents, contains('impression'));
    });

    testWidgets('keeps an unfilled zone running despite collapsing', (
      tester,
    ) async {
      backend.responses['/ad/retrieve'] = adResponse(id: '', refreshTime: 30);

      await initialize(tester);
      await pumpZone(tester, const AdZone(zoneId: 'zone-1'));

      expect(backend.requestsTo('/ad/retrieve').length, 1);

      await tester.pump(const Duration(seconds: 31));
      await settle(tester);

      // An unfilled zone occupies no space, so what the detector measures is an
      // artifact of there being nothing to see. Acting on it would freeze the
      // countdown of every zone the moment it went unfilled.
      expect(backend.requestsTo('/ad/retrieve').length, 2);
    });

    testWidgets('pauses a filled zone scrolled off screen', (tester) async {
      await initialize(tester);

      final controllerScroll = ScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: controllerScroll,
              children: const <Widget>[
                SizedBox(width: 320, height: 250, child: AdZone(zoneId: 'z')),
                SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      );

      await settle(tester);
      await finishCreative(tester);

      expect(backend.reportedAdEvents, contains('impression'));

      controllerScroll.jumpTo(1500);

      await settle(tester);

      expect(backend.reportedAdEvents, contains('impression_end'));

      controllerScroll.dispose();
    });
  });
}
