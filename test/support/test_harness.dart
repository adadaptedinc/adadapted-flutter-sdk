/// Shared fixtures for driving the SDK without a network or a platform.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:adadapted_flutter_sdk/adadapted_flutter_sdk.dart';
import 'package:adadapted_flutter_sdk/src/ad_request_context.dart';
import 'package:adadapted_flutter_sdk/src/device_info_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A request the fake server received.
class RecordedRequest {
  /// The URL the request went to.
  final String url;

  /// The decoded JSON body.
  final Map<String, dynamic> body;

  /// The headers the request carried.
  final Map<String, String> headers;

  /// Records one request.
  const RecordedRequest({
    required this.url,
    required this.body,
    required this.headers,
  });

  /// The events array the request carried, if any.
  List<Map<String, dynamic>> get events =>
      (body['events'] as List<dynamic>? ?? <dynamic>[])
          .cast<Map<String, dynamic>>();
}

/// A fake AdAdapted backend that records what it was asked and answers with
/// whatever the test set up.
class FakeBackend {
  /// Every request received, in order.
  final List<RecordedRequest> requests = <RecordedRequest>[];

  /// Bodies to answer specific paths with. Keyed by the path suffix that
  /// identifies a route.
  final Map<String, Object> responses = <String, Object>{};

  /// Paths that should fail outright, answered with a 500.
  final Set<String> failingPaths = <String>{};

  /// Paths that stop answering once this many requests have been served.
  ///
  /// A request that never settles is how a test holds a zone on one ad: the
  /// zone keeps showing what it has until a replacement arrives.
  final Map<String, int> hangAfter = <String, int>{};

  /// How many requests each path in [hangAfter] has served.
  final Map<String, int> _served = <String, int>{};

  /// How long each path takes to answer.
  ///
  /// A request that is open for a known length of time is how a test reaches
  /// the state a zone is in mid-request, which is where several of the trickier
  /// invariants live.
  final Map<String, Duration> delays = <String, Duration>{};

  /// The client to hand the SDK.
  late final http.Client client = MockClient((request) async {
    final url = request.url.toString();
    final decoded = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body);

    requests.add(
      RecordedRequest(
        url: url,
        body: decoded is Map<String, dynamic> ? decoded : <String, dynamic>{},
        headers: request.headers,
      ),
    );

    for (final entry in delays.entries) {
      if (url.contains(entry.key)) {
        await Future<void>.delayed(entry.value);

        break;
      }
    }

    for (final entry in hangAfter.entries) {
      if (!url.contains(entry.key)) {
        continue;
      }

      final served = (_served[entry.key] ?? 0) + 1;

      _served[entry.key] = served;

      if (served > entry.value) {
        return Completer<http.Response>().future;
      }
    }

    for (final path in failingPaths) {
      if (url.contains(path)) {
        return http.Response('{"error":"boom"}', 500);
      }
    }

    for (final entry in responses.entries) {
      if (url.contains(entry.key)) {
        return http.Response(jsonEncode(entry.value), 200);
      }
    }

    return http.Response('{}', 200);
  });

  /// Every request whose URL contains [path].
  /// @param path - The route fragment to match on.
  List<RecordedRequest> requestsTo(String path) =>
      requests.where((request) => request.url.contains(path)).toList();

  /// Every reported event name across every List Manager request, in order.
  List<String> get reportedSdkEvents => requestsTo('/events')
      .expand((request) => request.events)
      .map((event) => event['event_name']?.toString() ?? '')
      .toList();

  /// Every reported ad event type across every ad event request, in order.
  List<String> get reportedAdEvents => requestsTo('/ad/events')
      .expand((request) => request.events)
      .map((event) => event['event_type']?.toString() ?? '')
      .toList();
}

/// The device info the fake platform channel resolves.
const Map<String, Object> fakeDeviceInfo = <String, Object>{
  'udid': 'TEST-UDID',
  'deviceName': 'TestDevice',
  'systemName': 'android_flutter',
  'systemVersion': '15',
  'deviceModel': 'TestModel',
  'deviceWidth': '1080',
  'deviceHeight': '2400',
  'deviceScreenDensity': '3.0',
  'deviceLocale': 'en_US',
  'deviceCarrier': 'TestCarrier',
  'bundleId': 'com.test.app',
  'bundleVersion': '1.2.3',
  'deviceTimezone': 'America/Indiana/Indianapolis',
  'isAdTrackingEnabled': true,
};

/// The channel the plugin's Dart side invokes.
const MethodChannel _deviceInfoChannel = MethodChannel(
  'com.adadapted.flutter_sdk/device_info',
);

/// Stands in for the platform side of the plugin.
///
/// @param deviceInfo - The device info to resolve. Defaults to
///      [fakeDeviceInfo].
/// @param fail - When true, the channel throws instead, standing in for a
///      platform that could not identify the device.
void installFakeDeviceInfoChannel({
  Map<String, Object>? deviceInfo,
  bool fail = false,
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_deviceInfoChannel, (call) async {
        if (call.method != 'getDeviceInfo') {
          return null;
        }

        if (fail) {
          throw PlatformException(code: 'FAILED');
        }

        return deviceInfo ?? fakeDeviceInfo;
      });
}

/// Removes the fake platform channel.
void removeFakeDeviceInfoChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_deviceInfoChannel, null);
}

/// Clears the statics the SDK and its zones share, which outlive one test.
void resetSdkStatics() {
  AdRequestContextRegistry.resetForTesting();
}

/// Builds an SDK wired to [backend], with a deterministic session ID source.
///
/// @param backend - The fake backend to issue requests through.
/// @param randomSeed - The seed for the session ID generator.
AdadaptedFlutterSdk buildSdk(FakeBackend backend, {int randomSeed = 42}) {
  return AdadaptedFlutterSdk(
    httpClient: backend.client,
    deviceInfoChannel: const DeviceInfoChannel(channel: _deviceInfoChannel),
    random: Random(randomSeed),
  );
}
