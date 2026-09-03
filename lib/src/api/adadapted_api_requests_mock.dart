/// Mock responses served when the SDK is pointed at a `mock` environment.
///
/// These exist so an integration can be developed without network access, and
/// so the widget tests have deterministic content to render.
library;

import 'adadapted_api_types.dart';

/// Mock data for a v1.0.0 [Zone] response, which carries exactly one ad.
final Zone _adZoneData = Zone.fromJson(<String, dynamic>{
  'port_height': 250,
  'port_width': 320,
  'ad': <String, dynamic>{
    'id': '1815',
    'impression_id': '100838::C4D792785EA1EC91',
    'refresh_time': 60,
    'creative_url':
        'https://testurl.com/a/NTLKNZKYMMI2NTM1;100838;1815?session_id=TEST_SESSION_ID&amp;udid=00000000-0000-0000-0000-000000000000',
    'action_type': 'c',
    'action_path': '',
    'payload': <String, dynamic>{
      'detailed_list_items': <Map<String, dynamic>>[
        <String, dynamic>{
          'product_barcode': '0',
          'product_brand': 'Brand',
          'product_category': '',
          'product_discount': '',
          'product_image': '',
          'product_sku': '',
          'product_title': 'Sample Product',
        },
      ],
    },
  },
});

/// Mock data for a [KeywordIntercepts] object.
final KeywordIntercepts _keywordInterceptData = KeywordIntercepts.fromJson(
  <String, dynamic>{
    'search_id': 'test-search-id',
    'terms': <Map<String, dynamic>>[
      <String, dynamic>{
        'term_id': 'test-term-id-1',
        'term': 'Milk',
        'replacement': 'Fairlife Milk',
        'priority': 1,
      },
      <String, dynamic>{
        'term_id': 'test-term-id-2',
        'term': 'milk',
        'replacement': 'A2 Milk',
        'priority': 0,
      },
      <String, dynamic>{
        'term_id': 'test-term-id-3',
        'term': 'CHEESE',
        'replacement': 'Kraft Singles',
        'priority': 0,
      },
      <String, dynamic>{
        'term_id': 'test-term-id-4',
        'term': 'cOfFeE',
        'replacement': 'Folgers Instant Coffee',
        'priority': 0,
      },
    ],
  },
);

/// Mocks the API call for retrieving a single ad for one zone.
Future<AdRetrieveResponse> retrieveAd() async {
  return AdRetrieveResponse(data: _adZoneData, success: true);
}

/// Mocks the API call for getting keyword intercepts.
Future<InterceptRetrieveResponse> getKeywordIntercepts() async {
  return InterceptRetrieveResponse(data: _keywordInterceptData, success: true);
}

/// Mocks the API call for getting outstanding payload content.
Future<RetrievePayloadItemDataResponse> retrievePayloadContent() async {
  return RetrievePayloadItemDataResponse.fromJson(<String, dynamic>{
    'payloads': <Map<String, dynamic>>[
      <String, dynamic>{
        'payload_id': 'TEST_PAYLOAD_1',
        'detailed_list_items': <Map<String, dynamic>>[
          <String, dynamic>{
            'product_title': 'Test Product 1',
            'product_barcode': '',
            'product_sku': '',
            'product_image': '',
            'product_discount': '',
            'product_brand': '',
            'product_category': '',
          },
        ],
      },
    ],
  });
}
