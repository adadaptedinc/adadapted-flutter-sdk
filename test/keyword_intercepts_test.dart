/// Keyword intercept matching, ordering and the events each outcome reports.
library;

import 'package:adadapted_flutter_sdk/adadapted_flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_harness.dart';

/// The intercepts the fake backend serves.
const Map<String, Object> _intercepts = <String, Object>{
  'success': true,
  'data': <String, Object>{
    'search_id': 'test-search-id',
    'terms': <Map<String, Object>>[
      <String, Object>{
        'term_id': 'term-1',
        'term': 'Milk',
        'replacement': 'Fairlife Milk',
        'priority': 1,
      },
      <String, Object>{
        'term_id': 'term-2',
        'term': 'milk',
        'replacement': 'A2 Milk',
        'priority': 0,
      },
      <String, Object>{
        'term_id': 'term-3',
        'term': 'CHEESE',
        'replacement': 'Kraft Singles',
        'priority': 0,
      },
    ],
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeBackend backend;
  late AdadaptedFlutterSdk sdk;

  setUp(() async {
    resetSdkStatics();
    installFakeDeviceInfoChannel();

    backend = FakeBackend();
    backend.responses['/intercept/retrieve'] = _intercepts;

    sdk = buildSdk(backend);

    await sdk.initialize(appId: 'TEST_APP_ID', apiEnv: ApiEnv.dev);
    await pumpEventQueue();
  });

  tearDown(() {
    sdk.unmount();
    removeFakeDeviceInfoChannel();
  });

  /// Every intercept event type reported so far, in order.
  List<String> interceptEvents() => backend
      .requestsTo('/intercept/events')
      .expand((request) => request.events)
      .map((event) => event['event_type']?.toString() ?? '')
      .toList();

  group('matching', () {
    test('matches case insensitively on the start of a term', () {
      final results = sdk.performKeywordSearch('mil');

      expect(results.map((r) => r.termId).toSet(), <String>{
        'term-1',
        'term-2',
      });
    });

    test('does not match a term that merely contains the search', () {
      // Deliberately not enabled: the other SDKs have the same restriction, and
      // turning it on would start reporting "matched" for terms the product does
      // not treat as matches.
      expect(sdk.performKeywordSearch('eese'), isEmpty);
    });

    test('ignores a term shorter than the minimum match length', () async {
      final before = backend.requestsTo('/intercept/events').length;

      expect(sdk.performKeywordSearch('mi'), isEmpty);

      await pumpEventQueue();

      // Below the minimum nothing is reported at all — not even not_matched.
      expect(backend.requestsTo('/intercept/events').length, before);
    });

    test('trims the search term before measuring it', () {
      expect(sdk.performKeywordSearch('  milk  '), isNotEmpty);
    });

    test('orders results by priority, lowest number first', () {
      final results = sdk.performKeywordSearch('milk');

      expect(results.first.termId, 'term-2');
      expect(results.first.priority, 0);
    });
  });

  group('reporting', () {
    test('reports matched for every term that matched', () async {
      sdk.performKeywordSearch('milk');

      await pumpEventQueue();

      expect(interceptEvents(), <String>['matched', 'matched']);
    });

    test('reports the search id and user input on each event', () async {
      sdk.performKeywordSearch('milk');

      await pumpEventQueue();

      final event = backend.requestsTo('/intercept/events').first.events.first;

      expect(event['search_id'], 'test-search-id');
      expect(event['user_input'], 'milk');
    });

    test('reports not_matched once when nothing matched', () async {
      sdk.performKeywordSearch('zzz');

      await pumpEventQueue();

      final events = backend.requestsTo('/intercept/events').first.events;

      expect(events.length, 1);
      expect(events.first['event_type'], 'not_matched');
      expect(events.first['search_id'], 'NA');
      expect(events.first['term'], 'NA');
    });

    test('reports selected for a known term', () async {
      sdk.performKeywordSearch('milk');
      sdk.reportKeywordInterceptTermSelected('term-1');

      await pumpEventQueue();

      expect(interceptEvents(), contains('selected'));
    });

    test('reports nothing for an unknown selected term', () async {
      sdk.performKeywordSearch('milk');

      await pumpEventQueue();

      final before = interceptEvents().length;

      sdk.reportKeywordInterceptTermSelected('does-not-exist');

      await pumpEventQueue();

      expect(interceptEvents().length, before);
    });

    test('reports presented for every known term given', () async {
      sdk.reportKeywordInterceptTermsPresented(<String>[
        'term-1',
        'term-2',
        'does-not-exist',
      ]);

      await pumpEventQueue();

      final events = backend.requestsTo('/intercept/events').first.events;

      expect(events.length, 2);
      expect(events.every((e) => e['event_type'] == 'presented'), isTrue);
    });

    test('reports nothing when no given term is known', () async {
      final before = backend.requestsTo('/intercept/events').length;

      sdk.reportKeywordInterceptTermsPresented(<String>['nope']);

      await pumpEventQueue();

      expect(backend.requestsTo('/intercept/events').length, before);
    });

    test(
      'carries the last search value onto a later presented event',
      () async {
        sdk.performKeywordSearch('milk');
        sdk.reportKeywordInterceptTermsPresented(<String>['term-1']);

        await pumpEventQueue();

        final presented = backend
            .requestsTo('/intercept/events')
            .expand((r) => r.events)
            .firstWhere((e) => e['event_type'] == 'presented');

        expect(presented['user_input'], 'milk');
      },
    );
  });

  group('after unmount', () {
    test('search returns nothing and reports nothing', () async {
      sdk.unmount();

      final before = backend.requests.length;

      expect(sdk.performKeywordSearch('milk'), isEmpty);

      await pumpEventQueue();

      expect(backend.requests.length, before);
    });
  });
}
