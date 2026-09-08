/// The HTTP client for every AdAdapted backend the SDK talks to.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../component_types/device.dart';
import '../component_types/environment.dart';
import 'adadapted_api_requests_mock.dart' as mocks;
import 'adadapted_api_types.dart';

/// How long any single request may take before it is abandoned.
///
/// Deliberately below `minimumAdRefreshSeconds` in AdZone: a request that
/// outlives its own zone's refresh interval is of no use by the time it lands,
/// and a request that never settles at all would leave that zone's in-flight
/// latch set and stop it ever serving again.
const Duration requestTimeout = Duration(seconds: 10);

/// Thrown when a request reaches the server but is answered with a non-success
/// status.
///
/// The callers treat a throw as "this request failed", which is how a zone
/// reaches [ZoneUnfilledReason.requestFailed]. `package:http` returns a
/// response for a 500 rather than throwing, so without this a server error
/// would be parsed as if it were an ad.
class AdadaptedApiException implements Exception {
  /// The status code the server answered with.
  final int statusCode;

  /// The URL that was requested.
  final String url;

  /// Creates an exception describing a failed request.
  const AdadaptedApiException(this.statusCode, this.url);

  @override
  String toString() =>
      'AdadaptedApiException: request to $url failed with status $statusCode.';
}

/// Makes every API request the SDK needs.
///
/// The HTTP client is injectable so tests can drive the SDK without a network,
/// which is the Dart equivalent of the mock environment the other SDKs use, and
/// composes with it: a caller can point at [ApiEnv.mock] for canned content, or
/// supply a client for request-level assertions.
class AdadaptedApiRequests {
  /// The client every request is issued through.
  final http.Client _client;

  /// Whether this instance created [_client] and therefore owns closing it.
  final bool _ownsClient;

  /// Creates an API client.
  /// @param client - The HTTP client to issue requests through. One is created
  ///      when none is given.
  AdadaptedApiRequests({http.Client? client})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  /// Releases the underlying HTTP client, when this instance created it.
  ///
  /// A caller supplied client is left alone: it may well outlive the SDK, and
  /// closing something we were only lent would break the rest of the host app.
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  /// Retrieves a single ad for one zone.
  ///
  /// NOTE: The v1.0.0 routes carry no `{os}` path segment and take the app ID
  ///       in the `x-api-key` header rather than the body. Platform attribution
  ///       comes from the session ID prefix instead ("FL" here, "RN" on React
  ///       Native, "JS" on web, "ANDROID" on Android).
  /// @param requestData - The data to be sent with the request.
  /// @param appId - The app ID, sent as the API key header.
  /// @param apiEnv - The API environment to use when making the API request.
  Future<AdRetrieveResponse> retrieveAd(
    AdRetrieveRequest requestData,
    String appId,
    ApiEnv apiEnv,
  ) async {
    if (apiEnv == ApiEnv.mock) {
      return mocks.retrieveAd();
    }

    final body = await _post(
      '${apiEnv.url}/v/1.0.0/ad/retrieve',
      requestData.toJson(),
      appId: appId,
    );

    return AdRetrieveResponse.fromJson(body ?? <String, dynamic>{});
  }

  /// Reports an ad event that has occurred.
  ///
  /// A valid session is required for this API endpoint to respond successfully.
  /// @param requestData - The data to be sent with the request.
  /// @param appId - The client's app ID, sent as the API key.
  /// @param apiEnv - The API environment to use when making the API request.
  Future<void> reportAdEvent(
    ReportAdEventRequest requestData,
    String appId,
    ApiEnv apiEnv,
  ) async {
    if (apiEnv == ApiEnv.mock) {
      return;
    }

    await _post(
      '${apiEnv.url}/v/1.0.0/ad/events',
      requestData.toJson(),
      appId: appId,
    );
  }

  /// Gets all possible keyword intercepts for the session.
  ///
  /// A valid session is required for this API endpoint to respond successfully.
  /// @param requestData - The data to be sent with the request.
  /// @param appId - The client's app ID, sent as the API key.
  /// @param apiEnv - The API environment to use when making the API request.
  Future<InterceptRetrieveResponse> getKeywordIntercepts(
    InterceptRetrieveRequest requestData,
    String appId,
    ApiEnv apiEnv,
  ) async {
    if (apiEnv == ApiEnv.mock) {
      return mocks.getKeywordIntercepts();
    }

    final body = await _post(
      '${apiEnv.url}/v/1.0.0/intercept/retrieve',
      requestData.toJson(),
      appId: appId,
    );

    return InterceptRetrieveResponse.fromJson(body ?? <String, dynamic>{});
  }

  /// Reports an intercept event that has occurred.
  ///
  /// A valid session is required for this API endpoint to respond successfully.
  /// @param requestData - The data to be sent with the request.
  /// @param appId - The client's app ID, sent as the API key.
  /// @param apiEnv - The API environment to use when making the API request.
  Future<void> reportInterceptEvent(
    ReportInterceptEventRequest requestData,
    String appId,
    ApiEnv apiEnv,
  ) async {
    if (apiEnv == ApiEnv.mock) {
      return;
    }

    await _post(
      '${apiEnv.url}/v/1.0.0/intercept/events',
      requestData.toJson(),
      appId: appId,
    );
  }

  /// Reports List Manager events.
  ///
  /// A valid session is required for this API endpoint to respond successfully.
  /// @param requestData - The data to be sent with the request.
  /// @param deviceOs - The operating system being run on the device.
  /// @param apiEnv - The API environment to use when making the API request.
  Future<void> reportListManagerEvents(
    ReportListManagerDataRequest requestData,
    DeviceOS deviceOs,
    ListManagerApiEnv apiEnv,
  ) async {
    if (apiEnv == ListManagerApiEnv.mock) {
      return;
    }

    await _post(
      '${apiEnv.url}/v/1/${deviceOs.value}/events',
      requestData.toJson(),
    );
  }

  /// Reports the results of an "out of app" add to list payload received.
  ///
  /// A valid session is required for this API endpoint to respond successfully.
  /// @param requestData - The data to be sent with the request.
  /// @param apiEnv - The API environment to use when making the API request.
  Future<void> reportPayloadContentStatus(
    ReportPayloadDataRequest requestData,
    PayloadApiEnv apiEnv,
  ) async {
    if (apiEnv == PayloadApiEnv.mock) {
      return;
    }

    await _post('${apiEnv.url}/v/1/tracking', requestData.toJson());
  }

  /// Gets all outstanding add to list payloads for a given user.
  ///
  /// A valid session is required for this API endpoint to respond successfully.
  /// @param requestData - The data to be sent with the request.
  /// @param apiEnv - The API environment to use when making the API request.
  Future<RetrievePayloadItemDataResponse> retrievePayloadContent(
    RetrievePayloadItemDataRequest requestData,
    PayloadApiEnv apiEnv,
  ) async {
    if (apiEnv == PayloadApiEnv.mock) {
      return mocks.retrievePayloadContent();
    }

    final body = await _post('${apiEnv.url}/v/1/pickup', requestData.toJson());

    return RetrievePayloadItemDataResponse.fromJson(
      body ?? <String, dynamic>{},
    );
  }

  /// Issues one POST and decodes its JSON body.
  ///
  /// Throws [AdadaptedApiException] for any non-2xx status. `package:http`
  /// hands back a response object for a server error where axios rejects, and
  /// the callers are written against the rejecting behaviour: a zone reaches
  /// its `request_failed` reason by catching, so a 500 that returned normally
  /// here would be parsed as an ad response instead.
  /// @param url - The URL to post to.
  /// @param body - The request body, encoded as JSON.
  /// @param appId - The app ID to send as the API key, for the routes that take
  ///      one.
  Future<Map<String, dynamic>?> _post(
    String url,
    Map<String, dynamic> body, {
    String? appId,
  }) async {
    final response = await _client
        .post(
          Uri.parse(url),
          headers: <String, String>{
            'accept': 'application/json',
            'Content-Type': 'application/json',
            'x-api-key': ?appId,
          },
          body: jsonEncode(body),
        )
        .timeout(requestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AdadaptedApiException(response.statusCode, url);
    }

    if (response.body.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(response.body);

    return decoded is Map<String, dynamic> ? decoded : null;
  }
}
