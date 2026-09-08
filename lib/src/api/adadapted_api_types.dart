/// Every request, response and model the AdAdapted API exchanges.
///
/// The JSON keys here are the wire contract, shared with the Android, iOS,
/// React Native and web SDKs. Field names in Dart follow Dart conventions; the
/// snake_case names they map to live in the `toJson`/`fromJson` bodies and must
/// not be renamed.
library;

// =============================================================================
// ENUMS
// =============================================================================

/// Why an ad zone went unfilled.
enum ZoneUnfilledReason {
  /// The API answered normally but had no ad to serve.
  noAd('no_ad'),

  /// The ad request failed outright and never returned a usable response.
  requestFailed('request_failed'),

  /// An ad was served and the web view could not display it.
  renderFailed('render_failed');

  /// The value sent on the wire.
  final String value;

  /// Associates each reason with its wire value.
  const ZoneUnfilledReason(this.value);
}

/// The SDK level event names that get reported.
///
/// These match the native SDKs on the wire, so reporting can treat every
/// platform the same.
enum SdkEventName {
  /// A new session ID was generated.
  sessionCreated('SESSION_CREATED'),

  /// An existing session was picked back up, because the app returned to the
  /// foreground within the session window.
  sessionResumed('SESSION_RESUMED'),

  /// The app was sent to the background.
  sessionBackgrounded('SESSION_BACKGROUNDED'),

  /// An "add to list" ad was clicked. Reported instead of an interaction,
  /// because the interaction is only earned once the host app confirms the
  /// items actually reached the user's list. See `AdadaptedFlutterSdk.acknowledge`.
  atlAdClicked('atl_ad_clicked'),

  /// A single "add to list" item was confirmed as added to the user's list.
  atlItemAddedToList('atl_item_added_to_list');

  /// The value sent on the wire.
  final String value;

  /// Associates each event with its wire value.
  const SdkEventName(this.value);
}

/// The source of a List Manager event.
enum ListManagerEventSource {
  /// The event was triggered from the app.
  app('app'),

  /// The event was triggered by the SDK itself rather than by a user action.
  /// Used for the session lifecycle events, matching SDK_EVENT_TYPE on Android.
  sdk('sdk');

  /// The value sent on the wire.
  final String value;

  /// Associates each source with its wire value.
  const ListManagerEventSource(this.value);
}

/// The List Manager event names a host app can report.
enum ListManagerEventName {
  /// The user added an item to their list.
  addedToList('user_added_to_list'),

  /// The user crossed off an item from their list.
  crossedOffList('user_crossed_off_list'),

  /// The user deleted an item from their list.
  deletedFromList('user_deleted_from_list');

  /// The value sent on the wire.
  final String value;

  /// Associates each event with its wire value.
  const ListManagerEventName(this.value);
}

/// What interacting with an ad does.
enum AdActionType {
  /// Used for Add To List.
  content('c'),

  /// Used for opening URLs in an external browser.
  external('e'),

  /// Used for opening URLs in a web view within the app.
  link('l'),

  /// Used for opening app store URLs in the app store.
  app('a'),

  /// No action.
  none('n');

  /// The value sent on the wire.
  final String value;

  /// Associates each action type with its wire value.
  const AdActionType(this.value);

  /// Resolves an action type from its wire value.
  ///
  /// Falls back to [none] for anything unrecognised, because an action type
  /// this SDK version has never heard of must leave the ad inert rather than
  /// fail to parse the response it arrived in.
  /// @param value - The wire value to resolve.
  static AdActionType fromValue(String? value) {
    for (final type in AdActionType.values) {
      if (type.value == value) {
        return type;
      }
    }

    return AdActionType.none;
  }
}

/// The different types of events that can be reported.
enum ReportedEventType {
  /// Occurs when an ad is displayed to the user.
  impression('impression'),

  /// Occurs when an ad that was displayed to the user stops being displayed,
  /// because it rotated out, the zone left the view, or the app was
  /// backgrounded. Reported at most once per ad that recorded an impression.
  impressionEnd('impression_end'),

  /// Occurs when the user interacts with an ad.
  interaction('interaction'),

  /// Occurs when an ad zone is first placed. Reported for every zone, whether
  /// it ever receives an ad or not.
  zoneMounted('zone_mounted'),

  /// Occurs when an ad zone is removed.
  zoneUnmounted('zone_unmounted'),

  /// Occurs when an ad was requested for a zone but none could be displayed.
  /// Always accompanied by a [ZoneUnfilledReason] event name.
  zoneUnfilled('zone_unfilled'),

  /// Occurs when the user's search term did not match an available keyword
  /// intercept term.
  notMatched('not_matched'),

  /// Occurs when the user's search term has matched a keyword intercept term.
  matched('matched'),

  /// Occurs when the user was presented a keyword intercept term.
  presented('presented'),

  /// Occurs when the user has selected a keyword intercept term.
  selected('selected');

  /// The value sent on the wire.
  final String value;

  /// Associates each event type with its wire value.
  const ReportedEventType(this.value);
}

/// The possible payload acknowledgment status values.
enum PayloadStatus {
  /// The delivered status.
  delivered('delivered'),

  /// The rejected status.
  rejected('rejected');

  /// The value sent on the wire.
  final String value;

  /// Associates each status with its wire value.
  const PayloadStatus(this.value);
}

// =============================================================================
// MODELS
// =============================================================================

/// Reads a number that may have arrived as a numeric string.
/// @param value - The decoded JSON value.
/// @returns the number, or 0 when there is not one.
num _toNum(Object? value) {
  if (value is num) {
    return value;
  }

  if (value is String) {
    return num.tryParse(value) ?? 0;
  }

  return 0;
}

/// A single item that can be added to a user's list.
class DetailedListItem {
  /// The barcode of the product.
  final String productBarcode;

  /// The brand of the product.
  final String productBrand;

  /// The category of the product.
  final String productCategory;

  /// The discount given for the product.
  final String productDiscount;

  /// The image used for display of the product.
  final String productImage;

  /// The SKU of the product.
  final String productSku;

  /// The name/title of the product.
  final String productTitle;

  /// The tracking ID, when the API supplied one.
  final String? trackingId;

  /// Creates a detailed list item from its individual fields.
  const DetailedListItem({
    required this.productBarcode,
    required this.productBrand,
    required this.productCategory,
    required this.productDiscount,
    required this.productImage,
    required this.productSku,
    required this.productTitle,
    this.trackingId,
  });

  /// Builds a detailed list item from its JSON representation.
  /// @param json - The decoded JSON object.
  factory DetailedListItem.fromJson(Map<String, dynamic> json) {
    return DetailedListItem(
      productBarcode: json['product_barcode']?.toString() ?? '',
      productBrand: json['product_brand']?.toString() ?? '',
      productCategory: json['product_category']?.toString() ?? '',
      productDiscount: json['product_discount']?.toString() ?? '',
      productImage: json['product_image']?.toString() ?? '',
      productSku: json['product_sku']?.toString() ?? '',
      productTitle: json['product_title']?.toString() ?? '',
      trackingId: json['tracking_id']?.toString(),
    );
  }

  /// The JSON representation of this item.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'product_barcode': productBarcode,
      'product_brand': productBrand,
      'product_category': productCategory,
      'product_discount': productDiscount,
      'product_image': productImage,
      'product_sku': productSku,
      'product_title': productTitle,
      if (trackingId != null) 'tracking_id': trackingId,
    };
  }
}

/// The items an ad offers to add to a list.
class AdPayload {
  /// The list items, or null when the API substituted an empty payload object
  /// for an ad that carries no items.
  final List<DetailedListItem>? detailedListItems;

  /// Creates an ad payload.
  const AdPayload({this.detailedListItems});

  /// Builds an ad payload from its JSON representation.
  /// @param json - The decoded JSON object.
  factory AdPayload.fromJson(Map<String, dynamic> json) {
    final items = json['detailed_list_items'];

    return AdPayload(
      detailedListItems: items is List
          ? items
                .whereType<Map<String, dynamic>>()
                .map(DetailedListItem.fromJson)
                .toList()
          : null,
    );
  }
}

/// A single ad served for a zone.
class Ad {
  /// The ad ID. An empty string means the API had no ad to serve.
  final String id;

  /// The impression ID.
  final String impressionId;

  /// How long, in seconds, this ad is displayed for before the next ad is
  /// requested for the zone. On a response carrying no ad, this is instead the
  /// backoff to wait before asking again.
  final num refreshTime;

  /// The URL of the ad creative to display.
  final String creativeUrl;

  /// The URL the ad navigates to when interacted with. An empty string when the
  /// action type does not navigate anywhere.
  final String actionPath;

  /// What interacting with the ad does.
  final AdActionType actionType;

  /// The items to add to a list, for add-to-list ads.
  final AdPayload payload;

  /// The ID of the zone this ad was served for.
  ///
  /// Set by the SDK rather than the API, so every reported event can name its
  /// zone without parsing it back out of the impression ID.
  final String? zoneId;

  /// Creates an ad from its individual fields.
  const Ad({
    required this.id,
    required this.impressionId,
    required this.refreshTime,
    required this.creativeUrl,
    required this.actionPath,
    required this.actionType,
    required this.payload,
    this.zoneId,
  });

  /// Builds an ad from its JSON representation.
  /// @param json - The decoded JSON object.
  factory Ad.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'];

    return Ad(
      id: json['id']?.toString() ?? '',
      impressionId: json['impression_id']?.toString() ?? '',
      // Coerced rather than cast. The other SDKs run this through JavaScript's
      // Number(), so a refresh_time delivered as a string is honored there; a
      // hard type check here would quietly drop it to the 60 second default.
      refreshTime: _toNum(json['refresh_time']),
      creativeUrl: json['creative_url']?.toString() ?? '',
      actionPath: json['action_path']?.toString() ?? '',
      actionType: AdActionType.fromValue(json['action_type']?.toString()),
      payload: payload is Map<String, dynamic>
          ? AdPayload.fromJson(payload)
          : const AdPayload(),
      zoneId: json['zone_id']?.toString(),
    );
  }

  /// A copy of this ad with the given fields replaced.
  /// @param zoneId - The zone the ad was served into.
  Ad copyWith({String? zoneId}) {
    return Ad(
      id: id,
      impressionId: impressionId,
      refreshTime: refreshTime,
      creativeUrl: creativeUrl,
      actionPath: actionPath,
      actionType: actionType,
      payload: payload,
      zoneId: zoneId ?? this.zoneId,
    );
  }
}

/// A zone, carrying the single ad the API chose for it.
class Zone {
  /// The single ad to display within the zone. An ad whose [Ad.id] is empty
  /// means the API had nothing to serve, and only its refresh time is
  /// meaningful.
  final Ad ad;

  /// The optimized height of the zone.
  final num portHeight;

  /// The optimized width of the zone.
  final num portWidth;

  /// Creates a zone from its individual fields.
  const Zone({
    required this.ad,
    required this.portHeight,
    required this.portWidth,
  });

  /// Builds a zone from its JSON representation.
  /// @param json - The decoded JSON object.
  factory Zone.fromJson(Map<String, dynamic> json) {
    final ad = json['ad'];

    return Zone(
      ad: ad is Map<String, dynamic>
          ? Ad.fromJson(ad)
          : const Ad(
              id: '',
              impressionId: '',
              refreshTime: 0,
              creativeUrl: '',
              actionPath: '',
              actionType: AdActionType.none,
              payload: AdPayload(),
            ),
      portHeight: json['port_height'] is num ? json['port_height'] as num : 0,
      portWidth: json['port_width'] is num ? json['port_width'] as num : 0,
    );
  }
}

/// An "out of app" data payload.
class OutOfAppDataPayload {
  /// The payload ID associated to the provided list items.
  final String payloadId;

  /// The payload message.
  final String? payloadMessage;

  /// The payload image.
  final String? payloadImage;

  /// The campaign ID.
  final String? campaignId;

  /// The app ID.
  final String? appId;

  /// Expiration time in seconds.
  final num? expireSeconds;

  /// The list items the payload carries.
  final List<DetailedListItem> detailedListItems;

  /// Creates an out of app payload from its individual fields.
  const OutOfAppDataPayload({
    required this.payloadId,
    required this.detailedListItems,
    this.payloadMessage,
    this.payloadImage,
    this.campaignId,
    this.appId,
    this.expireSeconds,
  });

  /// Builds an out of app payload from its JSON representation.
  /// @param json - The decoded JSON object.
  factory OutOfAppDataPayload.fromJson(Map<String, dynamic> json) {
    final items = json['detailed_list_items'];

    return OutOfAppDataPayload(
      payloadId: json['payload_id']?.toString() ?? '',
      payloadMessage: json['payload_message']?.toString(),
      payloadImage: json['payload_image']?.toString(),
      campaignId: json['campaign_id']?.toString(),
      appId: json['app_id']?.toString(),
      expireSeconds: json['expire_seconds'] is num
          ? json['expire_seconds'] as num
          : null,
      detailedListItems: items is List
          ? items
                .whereType<Map<String, dynamic>>()
                .map(DetailedListItem.fromJson)
                .toList()
          : <DetailedListItem>[],
    );
  }
}

/// A keyword search term the SDK matches user input against.
class KeywordSearchTerm {
  /// The search term ID.
  final String termId;

  /// The search term to validate a search string against.
  final String term;

  /// The display string a client can use to display in a list.
  final String replacement;

  /// The display priority of this item. The lower the number, the higher the
  /// priority.
  final num priority;

  /// Creates a keyword search term from its individual fields.
  const KeywordSearchTerm({
    required this.termId,
    required this.term,
    required this.replacement,
    required this.priority,
  });

  /// Builds a keyword search term from its JSON representation.
  /// @param json - The decoded JSON object.
  factory KeywordSearchTerm.fromJson(Map<String, dynamic> json) {
    return KeywordSearchTerm(
      termId: json['term_id']?.toString() ?? '',
      term: json['term']?.toString() ?? '',
      replacement: json['replacement']?.toString() ?? '',
      priority: json['priority'] is num ? json['priority'] as num : 0,
    );
  }
}

/// The keyword intercepts available to a session.
class KeywordIntercepts {
  /// The search ID, automatically assigned by the API. Minted with the
  /// intercepts and reported on every intercept event.
  final String searchId;

  /// All available search terms.
  final List<KeywordSearchTerm> terms;

  /// Creates keyword intercepts from their individual fields.
  const KeywordIntercepts({required this.searchId, required this.terms});

  /// Builds keyword intercepts from their JSON representation.
  /// @param json - The decoded JSON object.
  factory KeywordIntercepts.fromJson(Map<String, dynamic> json) {
    final terms = json['terms'];

    return KeywordIntercepts(
      searchId: json['search_id']?.toString() ?? '',
      terms: terms is List
          ? terms
                .whereType<Map<String, dynamic>>()
                .map(KeywordSearchTerm.fromJson)
                .toList()
          : <KeywordSearchTerm>[],
    );
  }
}

/// An ad or zone level event to report.
class ReportedAdEvent {
  /// The ad ID. An empty string on the zone level events, which describe the
  /// zone itself rather than any ad within it.
  final String adId;

  /// The ad zone the event is for.
  final String zoneId;

  /// The impression ID. An empty string on the zone level events.
  final String impressionId;

  /// The event type to report.
  final ReportedEventType eventType;

  /// Additional detail for event types that carry one, currently only the
  /// reason a zone went unfilled.
  final ZoneUnfilledReason? eventName;

  /// The timestamp at which the event occurred.
  final int createdAt;

  /// Creates a reported ad event from its individual fields.
  const ReportedAdEvent({
    required this.adId,
    required this.zoneId,
    required this.impressionId,
    required this.eventType,
    required this.createdAt,
    this.eventName,
  });

  /// The JSON representation of this event.
  ///
  /// `event_name` is left off the payload entirely rather than sent as null
  /// when there is no name for this event type.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'ad_id': adId,
      'zone_id': zoneId,
      'impression_id': impressionId,
      'event_type': eventType.value,
      if (eventName != null) 'event_name': eventName!.value,
      'created_at': createdAt,
    };
  }
}

/// A keyword intercept event to report.
class ReportedInterceptEvent {
  /// The intercept search ID.
  final String searchId;

  /// The term ID.
  final String termId;

  /// The term.
  final String term;

  /// The user input provided that ultimately resulted in the event triggering.
  final String userInput;

  /// The event type to report.
  final ReportedEventType eventType;

  /// The timestamp at which the event occurred.
  final int createdAt;

  /// Creates a reported intercept event from its individual fields.
  const ReportedInterceptEvent({
    required this.searchId,
    required this.termId,
    required this.term,
    required this.userInput,
    required this.eventType,
    required this.createdAt,
  });

  /// The JSON representation of this event.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'search_id': searchId,
      'term_id': termId,
      'term': term,
      'user_input': userInput,
      'event_type': eventType.value,
      'created_at': createdAt,
    };
  }
}

/// A single List Manager event.
class ListManagerEvent {
  /// The source of the event.
  final ListManagerEventSource eventSource;

  /// The timestamp this event occurred (unix time).
  final int eventTimestamp;

  /// The event name. Either a [ListManagerEventName] or an [SdkEventName].
  final String eventName;

  /// The parameters the event is triggered for. Null values are dropped rather
  /// than sent, matching what `JSON.stringify` does for an undefined field in
  /// the other SDKs.
  final Map<String, String?> eventParams;

  /// Creates a List Manager event from its individual fields.
  const ListManagerEvent({
    required this.eventSource,
    required this.eventTimestamp,
    required this.eventName,
    required this.eventParams,
  });

  /// The JSON representation of this event.
  Map<String, dynamic> toJson() {
    final params = <String, dynamic>{};

    eventParams.forEach((key, value) {
      if (value != null) {
        params[key] = value;
      }
    });

    return <String, dynamic>{
      'event_source': eventSource.value,
      'event_name': eventName,
      'event_timestamp': eventTimestamp,
      'event_params': params,
    };
  }
}

/// A payload tracking event.
class PayloadTrackingEvent {
  /// The payload being tracked.
  final String payloadId;

  /// The status to report.
  final PayloadStatus status;

  /// The timestamp this event occurred (unix time).
  final int eventTimestamp;

  /// Creates a payload tracking event from its individual fields.
  const PayloadTrackingEvent({
    required this.payloadId,
    required this.status,
    required this.eventTimestamp,
  });

  /// The JSON representation of this event.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'payload_id': payloadId,
      'status': status.value,
      'event_timestamp': eventTimestamp,
    };
  }
}

// =============================================================================
// REQUESTS
// =============================================================================

/// The request for a single ad for one zone.
class AdRetrieveRequest {
  /// The SDK version. Named `sdkId` on the wire, matching the native SDKs.
  final String sdkId;

  /// The bundle ID of the host app.
  final String bundleId;

  /// The unique device ID of the user.
  final String userId;

  /// The zone to retrieve an ad for. One ad is returned per request.
  final String zoneId;

  /// The store to target ads for, or an empty string.
  final String storeId;

  /// The recipe context this zone is showing, or an empty string.
  final String contextId;

  /// The current session ID.
  final String sessionId;

  /// Reserved for additional targeting params. Currently always an empty string.
  final String extra;

  /// Creates an ad retrieve request from its individual fields.
  const AdRetrieveRequest({
    required this.sdkId,
    required this.bundleId,
    required this.userId,
    required this.zoneId,
    required this.storeId,
    required this.contextId,
    required this.sessionId,
    required this.extra,
  });

  /// The JSON representation of this request.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sdkId': sdkId,
      'bundleId': bundleId,
      'userId': userId,
      'zoneId': zoneId,
      'storeId': storeId,
      'contextId': contextId,
      'sessionId': sessionId,
      'extra': extra,
    };
  }
}

/// The request for the keyword intercepts available to a session.
class InterceptRetrieveRequest {
  /// The SDK version.
  final String sdkId;

  /// The bundle ID of the host app.
  final String bundleId;

  /// The unique device ID of the user.
  final String userId;

  /// Always an empty string for intercepts, which are not zone scoped.
  final String zoneId;

  /// The current session ID.
  final String sessionId;

  /// Reserved for additional params.
  final String extra;

  /// Creates an intercept retrieve request from its individual fields.
  const InterceptRetrieveRequest({
    required this.sdkId,
    required this.bundleId,
    required this.userId,
    required this.zoneId,
    required this.sessionId,
    required this.extra,
  });

  /// The JSON representation of this request.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sdkId': sdkId,
      'bundleId': bundleId,
      'userId': userId,
      'zoneId': zoneId,
      'sessionId': sessionId,
      'extra': extra,
    };
  }
}

/// The request that reports ad events.
class ReportAdEventRequest {
  /// The app ID provided by the client using the API.
  final String appId;

  /// The unique device ID.
  final String udid;

  /// The current session ID.
  final String sessionId;

  /// The events to report.
  final List<ReportedAdEvent> events;

  /// Creates an ad event report request from its individual fields.
  const ReportAdEventRequest({
    required this.appId,
    required this.udid,
    required this.sessionId,
    required this.events,
  });

  /// The JSON representation of this request.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'app_id': appId,
      'udid': udid,
      'session_id': sessionId,
      'events': events.map((event) => event.toJson()).toList(),
    };
  }
}

/// The request that reports keyword intercept events.
class ReportInterceptEventRequest {
  /// The app ID provided by the client using the API.
  final String appId;

  /// The unique device ID.
  final String udid;

  /// The current session ID.
  final String sessionId;

  /// The events to report.
  final List<ReportedInterceptEvent> events;

  /// Creates an intercept event report request from its individual fields.
  const ReportInterceptEventRequest({
    required this.appId,
    required this.udid,
    required this.sessionId,
    required this.events,
  });

  /// The JSON representation of this request.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'app_id': appId,
      'udid': udid,
      'session_id': sessionId,
      'events': events.map((event) => event.toJson()).toList(),
    };
  }
}

/// The request that reports List Manager data.
///
/// NOTE: `locale` and `allow_retargeting` used to travel on the session
///       initialize body. With that request gone this is the only channel left
///       for them, and it is the one the native SDKs already use, so a user's
///       retargeting decision is still honored rather than silently dropped.
///       The remaining device fields are here for the same reason, and their
///       names match Android's `EventRequest` exactly, because that is the wire
///       contract.
class ReportListManagerDataRequest {
  /// The app ID provided by the client using the API.
  final String appId;

  /// The unique device ID.
  final String udid;

  /// The current session ID.
  final String sessionId;

  /// The events to report.
  final List<ListManagerEvent> events;

  /// The SDK version.
  final String sdkVersion;

  /// The bundle ID of the host app.
  final String bundleId;

  /// The bundle version of the host app.
  final String bundleVersion;

  /// The device locale.
  final String locale;

  /// Whether the user permits ad retargeting, as 1 or 0.
  final int allowRetargeting;

  /// The device name. Android calls this field "device" on this request.
  final String device;

  /// The device operating system.
  final String os;

  /// The device operating system version.
  final String osv;

  /// The device's timezone.
  final String timezone;

  /// The device's cellular carrier.
  final String carrier;

  /// The device width in pixels.
  final int dw;

  /// The device height in pixels.
  final int dh;

  /// The device screen density.
  final String density;

  /// Creates a List Manager report request from its individual fields.
  const ReportListManagerDataRequest({
    required this.appId,
    required this.udid,
    required this.sessionId,
    required this.events,
    required this.sdkVersion,
    required this.bundleId,
    required this.bundleVersion,
    required this.locale,
    required this.allowRetargeting,
    required this.device,
    required this.os,
    required this.osv,
    required this.timezone,
    required this.carrier,
    required this.dw,
    required this.dh,
    required this.density,
  });

  /// A copy of this request carrying a different set of events.
  ///
  /// The device and session fields are the same on every event request, so they
  /// are assembled once and the events swapped in per report.
  /// @param events - The events the copy should carry.
  ReportListManagerDataRequest withEvents(List<ListManagerEvent> events) {
    return ReportListManagerDataRequest(
      appId: appId,
      udid: udid,
      sessionId: sessionId,
      events: events,
      sdkVersion: sdkVersion,
      bundleId: bundleId,
      bundleVersion: bundleVersion,
      locale: locale,
      allowRetargeting: allowRetargeting,
      device: device,
      os: os,
      osv: osv,
      timezone: timezone,
      carrier: carrier,
      dw: dw,
      dh: dh,
      density: density,
    );
  }

  /// The JSON representation of this request.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'session_id': sessionId,
      'app_id': appId,
      'udid': udid,
      'sdk_version': sdkVersion,
      'bundle_id': bundleId,
      'bundle_version': bundleVersion,
      'locale': locale,
      'allow_retargeting': allowRetargeting,
      'device': device,
      'os': os,
      'osv': osv,
      'timezone': timezone,
      'carrier': carrier,
      'dw': dw,
      'dh': dh,
      'density': density,
      'events': events.map((event) => event.toJson()).toList(),
    };
  }
}

/// The request that reports payload tracking data.
class ReportPayloadDataRequest {
  /// The app ID provided by the client using the API.
  final String appId;

  /// The unique device ID.
  final String udid;

  /// The current session ID.
  final String sessionId;

  /// The payload tracking events.
  final List<PayloadTrackingEvent> tracking;

  /// Creates a payload tracking request from its individual fields.
  const ReportPayloadDataRequest({
    required this.appId,
    required this.udid,
    required this.sessionId,
    required this.tracking,
  });

  /// The JSON representation of this request.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'app_id': appId,
      'udid': udid,
      'session_id': sessionId,
      'tracking': tracking.map((event) => event.toJson()).toList(),
    };
  }
}

/// The request that gets outstanding payload server data for a user.
class RetrievePayloadItemDataRequest {
  /// The app ID provided by the client using the API.
  final String appId;

  /// The unique device ID.
  final String udid;

  /// The current session ID.
  final String sessionId;

  /// Creates a payload retrieval request from its individual fields.
  const RetrievePayloadItemDataRequest({
    required this.appId,
    required this.udid,
    required this.sessionId,
  });

  /// The JSON representation of this request.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'app_id': appId,
      'udid': udid,
      'session_id': sessionId,
    };
  }
}

// =============================================================================
// RESPONSES
// =============================================================================

/// The response to an ad retrieve request.
class AdRetrieveResponse {
  /// The zone data, carrying the single ad the API chose for the requested
  /// zone. Null when the response carried none.
  final Zone? data;

  /// False when the request was rejected.
  ///
  /// NOTE: The API returns this on a 200 for business rejections, so the status
  ///       code alone is not enough to detect failure.
  final bool success;

  /// Creates an ad retrieve response from its individual fields.
  const AdRetrieveResponse({required this.data, required this.success});

  /// Builds an ad retrieve response from its JSON representation.
  /// @param json - The decoded JSON object.
  factory AdRetrieveResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'];

    return AdRetrieveResponse(
      data: data is Map<String, dynamic> ? Zone.fromJson(data) : null,
      success: json['success'] != false,
    );
  }
}

/// The response to a keyword intercept retrieve request.
class InterceptRetrieveResponse {
  /// The available keyword intercepts, or null when the response carried none.
  final KeywordIntercepts? data;

  /// False when the request was rejected.
  final bool success;

  /// Creates an intercept retrieve response from its individual fields.
  const InterceptRetrieveResponse({required this.data, required this.success});

  /// Builds an intercept retrieve response from its JSON representation.
  /// @param json - The decoded JSON object.
  factory InterceptRetrieveResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'];

    return InterceptRetrieveResponse(
      data: data is Map<String, dynamic>
          ? KeywordIntercepts.fromJson(data)
          : null,
      success: json['success'] != false,
    );
  }
}

/// The response to a payload retrieval request.
class RetrievePayloadItemDataResponse {
  /// All current payloads for the provided user.
  final List<OutOfAppDataPayload> payloads;

  /// Creates a payload retrieval response from its individual fields.
  const RetrievePayloadItemDataResponse({required this.payloads});

  /// Builds a payload retrieval response from its JSON representation.
  /// @param json - The decoded JSON object.
  factory RetrievePayloadItemDataResponse.fromJson(Map<String, dynamic> json) {
    final payloads = json['payloads'];

    return RetrievePayloadItemDataResponse(
      payloads: payloads is List
          ? payloads
                .whereType<Map<String, dynamic>>()
                .map(OutOfAppDataPayload.fromJson)
                .toList()
          : <OutOfAppDataPayload>[],
    );
  }
}
