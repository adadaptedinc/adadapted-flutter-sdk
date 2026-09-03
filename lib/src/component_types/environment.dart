/// The API environments the SDK can be pointed at.
///
/// The ad, list manager and payload backends are three separate hosts, each with
/// its own production and sandbox tier, so each has its own enum. A caller picks
/// one [ApiEnv] and the SDK derives the other two from it.
library;

/// The API environment for the ad service.
enum ApiEnv {
  /// The production API environment.
  prod('https://ads.adadapted.com'),

  /// The development (sandbox) API environment.
  dev('https://sandbox.adadapted.com'),

  /// Used only for unit testing/mock data.
  mock('MOCK_DATA');

  /// The base URL requests are made against.
  final String url;

  /// Associates each environment with its base URL.
  const ApiEnv(this.url);
}

/// The API environment for the List Manager (event collection) service.
enum ListManagerApiEnv {
  /// The production API environment.
  prod('https://ec.adadapted.com'),

  /// The development (sandbox) API environment.
  dev('https://sandec.adadapted.com'),

  /// Used only for unit testing/mock data.
  mock('MOCK_DATA');

  /// The base URL requests are made against.
  final String url;

  /// Associates each environment with its base URL.
  const ListManagerApiEnv(this.url);
}

/// The API environment for the Payload server.
enum PayloadApiEnv {
  /// The production API environment.
  prod('https://payload.adadapted.com'),

  /// The development (sandbox) API environment.
  dev('https://sandpayload.adadapted.com'),

  /// Used only for unit testing/mock data.
  mock('MOCK_DATA');

  /// The base URL requests are made against.
  final String url;

  /// Associates each environment with its base URL.
  const PayloadApiEnv(this.url);
}
