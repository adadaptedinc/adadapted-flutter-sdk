/// "Out of app" payloads, from both the payload server and a deep link, and the
/// acknowledgement that earns an add-to-list ad its interaction.
library;

import 'dart:convert';

import 'package:adadapted_flutter_sdk/adadapted_flutter_sdk.dart';
import 'package:adadapted_flutter_sdk/src/ad_request_context.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

/// The payload the fake payload server hands back.
const Map<String, Object> _pickupResponse = <String, Object>{
  'payloads': <Map<String, Object>>[
    <String, Object>{
      'payload_id': 'PAYLOAD_1',
      'detailed_list_items': <Map<String, Object>>[
        <String, Object>{
          'product_title': 'Test Product 1',
          'product_barcode': '111',
          'product_sku': 'SKU1',
          'product_image': '',
          'product_discount': '',
          'product_brand': 'Brand',
          'product_category': 'Dairy',
        },
        <String, Object>{
          'product_title': 'Test Product 2',
          'product_barcode': '222',
          'product_sku': 'SKU2',
          'product_image': '',
          'product_discount': '',
          'product_brand': 'Brand',
          'product_category': 'Dairy',
        },
      ],
    },
  ],
};

/// Encodes a deep link payload the way the platform sends one.
/// @param data - The payload object to encode.
String _link(Object data) {
  final encoded = base64Encode(utf8.encode(jsonEncode(data)));

  return 'testapp://payload?data=$encoded';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend backend;
  late AdadaptedFlutterSdk sdk;
  late List<OutOfAppDataPayload> received;

  setUp(() {
    resetSdkStatics();
    installFakeDeviceInfoChannel();

    backend = FakeBackend();
    received = <OutOfAppDataPayload>[];
    sdk = buildSdk(backend);
  });

  tearDown(() {
    sdk.unmount();
    removeFakeDeviceInfoChannel();
  });

  /// Initializes the SDK with the payload callback wired to [received].
  Future<void> initialize() async {
    await sdk.initialize(
      appId: 'TEST_APP_ID',
      apiEnv: ApiEnv.dev,
      onOutOfAppPayloadAvailable: received.addAll,
    );

    await pumpEventQueue();
  }

  group('payload server', () {
    test('hands the host one payload per item', () async {
      backend.responses['/v/1/pickup'] = _pickupResponse;

      await initialize();

      expect(received.length, 2);
      expect(received.every((p) => p.payloadId == 'PAYLOAD_1'), isTrue);
      expect(received.first.detailedListItems.length, 1);
      expect(
        received.first.detailedListItems.first.productTitle,
        'Test Product 1',
      );
    });

    test('does not call back when there is nothing outstanding', () async {
      await initialize();

      expect(received, isEmpty);
    });

    test('does not call back when the pickup fails', () async {
      backend.failingPaths.add('/v/1/pickup');

      await initialize();

      expect(received, isEmpty);
      expect(sdk.sessionId, isNotNull);
    });
  });

  group('deep links', () {
    test('decodes a payload and hands it to the host', () async {
      await initialize();

      sdk.handleDeepLink(
        _link(<String, Object>{
          'payload_id': 'DEEP_LINK_PAYLOAD',
          'detailed_list_items': <Map<String, Object>>[
            <String, Object>{
              'product_title': 'Deep Linked Item',
              'product_barcode': '333',
              'product_sku': 'SKU3',
              'product_image': '',
              'product_discount': '',
              'product_brand': 'Brand',
              'product_category': 'Snacks',
            },
          ],
        }),
      );

      expect(received.length, 1);
      expect(received.first.payloadId, 'DEEP_LINK_PAYLOAD');
      expect(
        received.first.detailedListItems.first.productTitle,
        'Deep Linked Item',
      );
    });

    test('stops the payload at the next query parameter', () async {
      await initialize();

      final url =
          '${_link(<String, Object>{
            'payload_id': 'BOUNDED',
            'detailed_list_items': <Map<String, Object>>[
              <String, Object>{'product_title': 'Bounded Item'},
            ],
          })}&utm_source=email';

      sdk.handleDeepLink(url);

      // Slicing to the end of the URL would put "&utm_source=email" inside the
      // base64 and decode to garbage.
      expect(received.single.payloadId, 'BOUNDED');
    });

    test('ignores a link with no data parameter', () async {
      await initialize();

      sdk.handleDeepLink('testapp://open?screen=home');

      expect(received, isEmpty);
    });

    test('ignores a malformed payload rather than throwing', () async {
      await initialize();

      expect(
        () => sdk.handleDeepLink('testapp://payload?data=not-base64!!'),
        returnsNormally,
      );
      expect(received, isEmpty);
    });

    test('ignores a payload carrying no items', () async {
      await initialize();

      sdk.handleDeepLink(
        _link(<String, Object>{
          'payload_id': 'EMPTY',
          'detailed_list_items': <Map<String, Object>>[],
        }),
      );

      expect(received, isEmpty);
    });
  });

  group('acknowledge', () {
    /// Registers a pending ATL ad the way a zone click does.
    /// @param zoneId - The zone the ad was served into.
    /// @param adId - The ad the items came from.
    /// @param itemName - The product title the ad offers.
    void clickAtlAd(String zoneId, String adId, String itemName) {
      AdRequestContextRegistry.context!.setPendingAtlContent(
        PendingAtlContent(
          adId: adId,
          zoneId: zoneId,
          impressionId: 'IMP_$adId',
          items: <DetailedListItem>[
            DetailedListItem(
              productBarcode: '',
              productBrand: '',
              productCategory: '',
              productDiscount: '',
              productImage: '',
              productSku: '',
              productTitle: itemName,
            ),
          ],
        ),
      );
    }

    test('reports an interaction for the ad that offered the item', () async {
      await initialize();

      clickAtlAd('zone-1', 'ad-1', 'Milk');

      sdk.acknowledge('Milk');

      await pumpEventQueue();

      final event = backend.requestsTo('/ad/events').last.events.first;

      expect(event['event_type'], 'interaction');
      expect(event['ad_id'], 'ad-1');
      expect(event['zone_id'], 'zone-1');
      expect(event['impression_id'], 'IMP_ad-1');
    });

    test('reports the interaction only once per click', () async {
      await initialize();

      clickAtlAd('zone-1', 'ad-1', 'Milk');

      sdk.acknowledge('Milk');
      sdk.acknowledge('Milk');

      await pumpEventQueue();

      expect(
        backend.reportedAdEvents.where((e) => e == 'interaction').length,
        1,
      );
    });

    test('reports atl_item_added_to_list on every acknowledgement', () async {
      await initialize();

      clickAtlAd('zone-1', 'ad-1', 'Milk');

      sdk.acknowledge('Milk');
      sdk.acknowledge('Milk');

      await pumpEventQueue();

      expect(
        backend.reportedSdkEvents
            .where((e) => e == 'atl_item_added_to_list')
            .length,
        2,
      );
    });

    test('ignores an item that belongs to no clicked ad', () async {
      await initialize();

      clickAtlAd('zone-1', 'ad-1', 'Milk');

      final before = backend.requests.length;

      sdk.acknowledge('Something The User Typed');

      await pumpEventQueue();

      expect(backend.requests.length, before);
    });

    test('keeps a pending ad per zone rather than one slot', () async {
      await initialize();

      clickAtlAd('zone-1', 'ad-1', 'Milk');
      clickAtlAd('zone-2', 'ad-2', 'Eggs');

      sdk.acknowledge('Milk');
      sdk.acknowledge('Eggs');

      await pumpEventQueue();

      final interactions = backend
          .requestsTo('/ad/events')
          .expand((r) => r.events)
          .where((e) => e['event_type'] == 'interaction')
          .map((e) => e['ad_id'])
          .toList();

      // A single slot meant a click in one zone discarded the other zone's
      // pending content and lost its interaction.
      expect(interactions, containsAll(<String>['ad-1', 'ad-2']));
    });

    test('resolves the newest click when zones share an item name', () async {
      await initialize();

      clickAtlAd('zone-1', 'ad-1', 'Milk');
      clickAtlAd('zone-2', 'ad-2', 'Milk');

      sdk.acknowledge('Milk');

      await pumpEventQueue();

      final interaction = backend
          .requestsTo('/ad/events')
          .expand((r) => r.events)
          .firstWhere((e) => e['event_type'] == 'interaction');

      expect(interaction['ad_id'], 'ad-2');
    });

    test('re-clicking a zone moves it to the front of the scan', () async {
      await initialize();

      clickAtlAd('zone-1', 'ad-1', 'Milk');
      clickAtlAd('zone-2', 'ad-2', 'Milk');
      clickAtlAd('zone-1', 'ad-3', 'Milk');

      sdk.acknowledge('Milk');

      await pumpEventQueue();

      final interaction = backend
          .requestsTo('/ad/events')
          .expand((r) => r.events)
          .firstWhere((e) => e['event_type'] == 'interaction');

      // Re-keying an existing zone must not leave it at its original insertion
      // position, or the newest-first scan picks an older zone's ad.
      expect(interaction['ad_id'], 'ad-3');
    });

    test('forgets everything pending once the SDK is unmounted', () async {
      await initialize();

      clickAtlAd('zone-1', 'ad-1', 'Milk');

      sdk.unmount();

      final before = backend.requests.length;

      sdk.acknowledge('Milk');

      await pumpEventQueue();

      expect(backend.requests.length, before);
    });
  });
}
