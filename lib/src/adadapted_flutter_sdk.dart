/// The AdAdapted Flutter SDK.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'ad_request_context.dart';
import 'api/adadapted_api_requests.dart';
import 'api/adadapted_api_types.dart';
import 'component_types/device.dart';
import 'component_types/environment.dart';
import 'device_info_channel.dart';
import 'version.dart';

/// A keyword search result.
///
/// An alias of [KeywordSearchTerm], so the interaction with the SDK can all be
/// done through this package's own names.
typedef KeywordSearchResult = KeywordSearchTerm;

/// Observes the app lifecycle on the SDK's behalf.
///
/// A dedicated observer rather than making the SDK itself a
/// [WidgetsBindingObserver], because the SDK is a plain object a host can hold
/// anywhere and mixing the binding into it would tie its lifetime to the widget
/// tree.
class _AppLifecycleObserver extends WidgetsBindingObserver {
  /// Called with each lifecycle state the binding reports.
  final void Function(AppLifecycleState state) _onChanged;

  /// Creates an observer that forwards lifecycle changes.
  /// @param onChanged - Called with each state change.
  _AppLifecycleObserver(this._onChanged);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _onChanged(state);
  }
}

/// The AdAdapted SDK for Flutter.
///
/// A host creates one, calls [initialize] once, places [AdZone] widgets for the
/// zones it has been allocated, and calls [unmount] when it is finished.
class AdadaptedFlutterSdk {
  /// How long a session survives being backgrounded before a new one is minted.
  ///
  /// Matches `THIRTY_MINUTES_IN_SECONDS` in Android's `SessionClient`.
  static const int sessionLifetimeSeconds = 30 * 60;

  /// The prefix identifying a session as having come from this SDK.
  ///
  /// Reporting distinguishes platforms by this prefix, so it must not collide
  /// with the other SDKs ("RN" on React Native, "JS" on web, "ANDROID" on
  /// Android, "IOS" on iOS).
  static const String sessionIdPrefix = 'FL';

  /// The number of random characters that follow the session ID prefix.
  static const int sessionIdLength = 32;

  /// The alphabet a session ID's random characters are drawn from.
  static const String sessionIdCharacters =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  /// The shortest search term that will be matched against keyword intercepts.
  ///
  /// The API no longer serves a minimum, so the SDK applies its own, matching
  /// `MIN_MATCH_LENGTH` in Android's `KeywordInterceptMatcher`.
  static const int minKeywordMatchLength = 3;

  /// The HTTP client a host injected, if any. Kept so every initialize() after
  /// an unmount() reuses it rather than falling back to a real one.
  final http.Client? _httpClient;

  /// The channel device info is gathered over.
  final DeviceInfoChannel _deviceInfoChannel;

  /// The source of randomness session IDs are drawn from.
  final Random _random;

  /// The API client, built at initialize() and released at unmount().
  AdadaptedApiRequests? _api;

  /// The client app ID used to send to API endpoints.
  String _appId = '';

  /// The API environment to use when making API calls.
  ApiEnv _apiEnv = ApiEnv.prod;

  /// The API environment to use when making API calls for List Manager.
  ListManagerApiEnv _listManagerApiEnv = ListManagerApiEnv.prod;

  /// The API environment to use when making API calls for the Payload server.
  PayloadApiEnv _payloadApiEnv = PayloadApiEnv.prod;

  /// The device operating system.
  DeviceOS? _deviceOs;

  /// The session ID used for the API to properly identify a user.
  String? _sessionId;

  /// All device data gathered when [initialize] is called.
  DeviceInfo? _deviceInfo;

  /// The time at which the app was last sent to the background, in seconds. The
  /// session window is measured from this.
  int _backgroundTime;

  /// Whether the app has been backgrounded since the session was last resolved.
  ///
  /// Android guards its first `onStart` instead, because `ProcessLifecycleOwner`
  /// replays the current state to a newly registered observer and would
  /// otherwise report the session `start()` just resolved. Flutter's binding has
  /// no such replay, so copying that guard would swallow the first real return
  /// from the background, and with it the rotation of a session that had expired
  /// while away. Tracking the background instead also absorbs the
  /// inactive -> resumed transition iOS raises during the launch animation,
  /// which would otherwise report a resume for a session that never left.
  bool _hasBeenBackgrounded = false;

  /// The store to target ads for, or an empty string.
  String _storeId = '';

  /// The most recently clicked "add to list" ad per zone, held until the host
  /// app confirms its items reached the user's list.
  ///
  /// Keyed by zone because several zones can be on screen at once, each with its
  /// own ATL ad. A single slot meant a click in one zone discarded another
  /// zone's pending content and lost its interaction. Android keeps them apart
  /// the same way, publishing an `AdContent` per zone.
  final Map<String, PendingAtlContent> _pendingAtlContent =
      <String, PendingAtlContent>{};

  /// The touch sensitivity of an ad zone in both the X and Y directions.
  double? _xyAdZoneDragDistanceAllowed;

  /// The user input string provided by the client and used to return a result of
  /// keyword intercept terms. This will always be the last provided value.
  String _keywordInterceptSearchValue = '';

  /// The current available keyword intercepts that can be used when a search is
  /// provided by the user.
  KeywordIntercepts? _keywordIntercepts;

  /// Triggered when an "add to list" item is clicked in an ad zone.
  void Function(List<DetailedListItem> items)? _onAddToListTriggered;

  /// Triggered when an "add to list" occurs by means of an "out of app" data
  /// payload.
  void Function(List<OutOfAppDataPayload> payloads)?
  _onOutOfAppPayloadAvailable;

  /// The registered app lifecycle observer, while one is registered.
  _AppLifecycleObserver? _lifecycleObserver;

  /// Creates an SDK instance.
  ///
  /// @param httpClient - An HTTP client to issue every request through. Supplied
  ///      by tests; a real one is created per initialize() otherwise.
  /// @param deviceInfoChannel - The channel to gather device info over. Supplied
  ///      by tests; the plugin's own channel otherwise.
  /// @param random - The source of randomness for session IDs. Supplied by tests
  ///      that need deterministic IDs; a cryptographic source otherwise.
  AdadaptedFlutterSdk({
    http.Client? httpClient,
    DeviceInfoChannel deviceInfoChannel = const DeviceInfoChannel(),
    Random? random,
  }) // A named parameter cannot start with an underscore, so an initializing
    // formal is not available for either of the two private fields below.
    // ignore: prefer_initializing_formals
    : _httpClient = httpClient,
       // ignore: prefer_initializing_formals
       _deviceInfoChannel = deviceInfoChannel,
       _random = random ?? Random.secure(),
       _backgroundTime = _currentUnixTimestamp();

  /// The current session ID, or null before [initialize] has resolved and after
  /// [unmount].
  String? get sessionId => _sessionId;

  /// The device info gathered at [initialize], or null before it has resolved
  /// and after [unmount].
  DeviceInfo? get deviceInfo => _deviceInfo;

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  /// Initializes the session for the AdAdapted API and sets up the SDK.
  ///
  /// @param appId - The app ID provided by the client.
  /// @param apiEnv - The API environment. Defaults to production.
  /// @param advertiserId - A custom advertiser ID to replace the IDFA. iOS only,
  ///      matching the other SDKs.
  /// @param xyDragDistanceAllowed - The touch sensitivity of an ad zone in both
  ///      the X and Y directions. Used to tell a tap on a zone from a scroll: a
  ///      touch that travels less than this in both directions is a tap.
  /// @param storeId - The store to target ads for, if targeting ads by store.
  /// @param onAddToListTriggered - Called when "add to list" items are clicked
  ///      in a zone that has no handler of its own.
  /// @param onOutOfAppPayloadAvailable - Called when an "add to list" occurs by
  ///      means of an "out of app" data payload.
  Future<void> initialize({
    required String appId,
    ApiEnv? apiEnv,
    String? advertiserId,
    double? xyDragDistanceAllowed,
    String? storeId,
    void Function(List<DetailedListItem> items)? onAddToListTriggered,
    void Function(List<OutOfAppDataPayload> payloads)?
    onOutOfAppPayloadAvailable,
  }) async {
    _appId = appId;

    // All three backends follow the environment the caller asked for.
    _resolveApiEnvironments(apiEnv);

    if (xyDragDistanceAllowed != null) {
      _xyAdZoneDragDistanceAllowed = xyDragDistanceAllowed;
    }

    if (onAddToListTriggered != null) {
      _onAddToListTriggered = onAddToListTriggered;
    }

    if (onOutOfAppPayloadAvailable != null) {
      _onOutOfAppPayloadAvailable = onOutOfAppPayloadAvailable;
    }

    if (storeId != null) {
      _storeId = storeId;
    }

    // A previous cycle's client is released before a new one replaces it, so a
    // host that calls initialize() twice does not leak the connections the
    // first one opened.
    _api?.close();
    _api = AdadaptedApiRequests(client: _httpClient);

    var deviceInfo = await _deviceInfoChannel.getDeviceInfo();

    _deviceOs = deviceInfo.systemName.contains('ios')
        ? DeviceOS.ios
        : DeviceOS.android;

    // Pass custom advertiserId - iOS only, matching the other SDKs.
    if (_deviceOs == DeviceOS.ios && advertiserId != null) {
      deviceInfo = deviceInfo.copyWith(udid: advertiserId);
    }

    _deviceInfo = deviceInfo;

    // There is no session request any more. The session is minted here and
    // lives only for as long as this isolate does, exactly as Android's
    // SessionClient does, so relaunching the app always starts a new session.
    _createOrResumeSession();

    // Ad zones read their session and device info from here.
    _registerAdRequestContext();

    // Get all possible keyword intercept values. We don't need to wait for this
    // to complete prior to resolving initialization.
    unawaited(_getKeywordIntercepts());

    // Make the initial call to the Payload data server to see if the user has
    // any outstanding items to be added to list.
    unawaited(_getPayloadItemData());

    // Any observer from a previous initialize() goes first, so a second call
    // replaces it instead of stacking on top.
    _removeLifecycleObserver();

    final observer = _AppLifecycleObserver(_handleAppLifecycleChange);

    _lifecycleObserver = observer;

    WidgetsBinding.instance.addObserver(observer);
  }

  /// Hands the SDK a deep link the host app received.
  ///
  /// The React Native SDK subscribes to `Linking` itself. Flutter has no
  /// built-in equivalent, and a host app almost always owns its own link
  /// routing already, so the link is passed in rather than competing for the
  /// platform's link stream. Call this for every incoming link, including the
  /// one that launched the app; anything that is not an AdAdapted payload link
  /// is ignored.
  /// @param url - The deep link URL the app received.
  void handleDeepLink(String url) {
    const searchStr = 'data=';

    final dataIndex = url.indexOf(searchStr);

    if (dataIndex == -1) {
      return;
    }

    // Bounded at the next parameter. Slicing to the end of the URL puts any
    // trailing parameters inside the base64, so a link of the form
    // ...?data=<payload>&other=1 decodes to garbage.
    final dataStart = dataIndex + searchStr.length;
    final nextParam = url.indexOf('&', dataStart);
    final encodedData = nextParam == -1
        ? url.substring(dataStart)
        : url.substring(dataStart, nextParam);

    Map<String, dynamic> payloadData;

    try {
      final decoded = jsonDecode(utf8.decode(base64Decode(encodedData)));

      if (decoded is! Map<String, dynamic>) {
        return;
      }

      payloadData = decoded;
    } catch (_) {
      // A malformed link is the sender's problem, not something to crash the
      // host app for.
      return;
    }

    final payloadId = payloadData['payload_id']?.toString() ?? '';
    final itemDataList = payloadData['detailed_list_items'];

    if (itemDataList is! List || itemDataList.isEmpty) {
      return;
    }

    // One payload per item, matching the shape the other SDKs hand their hosts.
    final finalItemList = <OutOfAppDataPayload>[];

    for (final itemData in itemDataList.whereType<Map<String, dynamic>>()) {
      finalItemList.add(
        OutOfAppDataPayload(
          payloadId: payloadId,
          detailedListItems: <DetailedListItem>[
            DetailedListItem.fromJson(itemData),
          ],
        ),
      );
    }

    if (finalItemList.isNotEmpty) {
      // Send the items to the client, so they can add them to the list.
      _onOutOfAppPayloadAvailable?.call(finalItemList);
    }
  }

  /// Searches through available ad keywords based on the provided search term.
  ///
  /// Only terms that start with the search term are returned. Matching terms
  /// that merely contain it is deliberately not enabled — the other SDKs have
  /// the same restriction, and turning it on here would both widen what the host
  /// sees and start reporting "matched" for terms the product does not treat as
  /// matches.
  /// @param searchTerm - The search term used to match against available keyword
  ///      intercepts.
  /// @returns all keyword intercept terms that matched the search term.
  List<KeywordSearchResult> performKeywordSearch(String searchTerm) {
    final results = <KeywordSearchResult>[];

    _keywordInterceptSearchValue = searchTerm;

    final deviceInfo = _deviceInfo;
    final sessionId = _sessionId;
    final intercepts = _keywordIntercepts;

    if (deviceInfo == null) {
      _logError('AdAdapted SDK has not been initialized with device info.');
    } else if (sessionId == null) {
      _logError('AdAdapted SDK has not been initialized with session id.');
    } else if (intercepts == null) {
      _logError('No available keyword intercepts.');
    } else if (searchTerm.trim().length >= minKeywordMatchLength) {
      final trimmedTerm = searchTerm.trim();
      final events = <ReportedInterceptEvent>[];
      final currentTs = _currentUnixTimestamp();

      for (final termObj in intercepts.terms) {
        if (termObj.term.toLowerCase().startsWith(trimmedTerm.toLowerCase())) {
          results.add(termObj);

          events.add(
            ReportedInterceptEvent(
              termId: termObj.termId,
              searchId: intercepts.searchId,
              userInput: _keywordInterceptSearchValue,
              term: termObj.term,
              eventType: ReportedEventType.matched,
              createdAt: currentTs,
            ),
          );
        }
      }

      // Sort the final results by priority, lowest number first.
      results.sort((a, b) => a.priority.compareTo(b.priority));

      // If there are no events to report at this point, we need to report the
      // "not_matched" event.
      if (events.isEmpty) {
        events.add(
          ReportedInterceptEvent(
            termId: '',
            searchId: 'NA',
            userInput: _keywordInterceptSearchValue,
            term: 'NA',
            eventType: ReportedEventType.notMatched,
            createdAt: currentTs,
          ),
        );
      }

      _reportInterceptEvents(events);
    }

    return results;
  }

  /// Reports that a keyword intercept term has been selected by the user.
  ///
  /// This ensures the event is properly recorded and enables accuracy in the
  /// reports we provide to clients.
  /// @param termId - The term ID to trigger the event for.
  void reportKeywordInterceptTermSelected(String termId) {
    final termObj = _getKeywordInterceptTerm(termId);
    final intercepts = _keywordIntercepts;

    if (_deviceInfo == null) {
      _logError('AdAdapted SDK has not been initialized with device info.');
    } else if (_sessionId == null) {
      _logError('AdAdapted SDK has not been initialized with session id.');
    } else if (intercepts == null) {
      _logError('No available keyword intercepts.');
    } else if (termId.isEmpty || termObj == null) {
      _logError('Invalid term ID provided.');
    } else {
      _reportInterceptEvents(<ReportedInterceptEvent>[
        ReportedInterceptEvent(
          termId: termObj.termId,
          searchId: intercepts.searchId,
          userInput: _keywordInterceptSearchValue,
          term: termObj.term,
          eventType: ReportedEventType.selected,
          createdAt: _currentUnixTimestamp(),
        ),
      ]);
    }
  }

  /// Reports that keyword intercept terms have been presented to the user.
  ///
  /// All terms that satisfy a search do not have to be presented, so only
  /// provide term IDs for the terms that ultimately get presented to the user.
  /// @param termIds - The term IDs to trigger the event for.
  void reportKeywordInterceptTermsPresented(List<String> termIds) {
    final termObjs = <KeywordSearchTerm>[];

    for (final termId in termIds) {
      final termObj = _getKeywordInterceptTerm(termId);

      if (termObj != null) {
        termObjs.add(termObj);
      }
    }

    final intercepts = _keywordIntercepts;

    if (_deviceInfo == null) {
      _logError('AdAdapted SDK has not been initialized with device info.');
    } else if (_sessionId == null) {
      _logError('AdAdapted SDK has not been initialized with session id.');
    } else if (intercepts == null) {
      _logError('No available keyword intercepts.');
    } else if (termIds.isEmpty || termObjs.isEmpty) {
      _logError('Invalid or empty terms ID list provided.');
    } else {
      final currentTs = _currentUnixTimestamp();

      _reportInterceptEvents(
        termObjs
            .map(
              (termObj) => ReportedInterceptEvent(
                termId: termObj.termId,
                searchId: intercepts.searchId,
                userInput: _keywordInterceptSearchValue,
                term: termObj.term,
                eventType: ReportedEventType.presented,
                createdAt: currentTs,
              ),
            )
            .toList(),
      );
    }
  }

  /// Acknowledges that an "add to list" item reached the user's list.
  ///
  /// This is what earns an ATL ad its interaction. Clicking the ad only offers
  /// the items; the host app is the only party that knows whether they were
  /// actually added, so the interaction is reported here rather than on the
  /// click. Ported from `AdContent.itemAcknowledge` in the Android SDK,
  /// including its guard against a second item reporting a second interaction
  /// for one click.
  ///
  /// Item names that belong to no recently clicked ad are ignored, so a host can
  /// safely call this for every item a user adds, ad-sourced or not.
  /// @param itemName - The product title of the item that was added.
  void acknowledge(String itemName) {
    // Newest first: with several zones showing ATL ads, the most recent click is
    // the one the host is most likely acknowledging. A flat item name is all
    // this API carries, so matching on it is the closest this can get to
    // Android, where the host holds the AdContent object for a specific zone.
    PendingAtlContent? content;

    for (final candidate in _pendingAtlContent.values.toList().reversed) {
      if (candidate.items.any((item) => item.productTitle == itemName)) {
        content = candidate;

        break;
      }
    }

    if (content == null) {
      return;
    }

    if (!content.isHandled) {
      content.isHandled = true;

      _reportAdEvent(
        AdEventReport(
          adId: content.adId,
          zoneId: content.zoneId,
          impressionId: content.impressionId,
          eventType: ReportedEventType.interaction,
        ),
      );
    }

    _reportSdkEvent(SdkEventName.atlItemAddedToList, <String, String>{
      'ad_id': content.adId,
      'item_name': itemName,
    });
  }

  /// Reports items added to a list, for the reports we provide to clients.
  /// @param itemNames - The items to report.
  /// @param listName - The list to associate the items with, if any.
  void reportItemsAddedToList(List<String> itemNames, [String? listName]) {
    _reportListManagerEvents(
      'reportItemsAddedToList',
      ListManagerEventName.addedToList,
      itemNames,
      listName,
    );
  }

  /// Reports items crossed off a list, for the reports we provide to clients.
  /// @param itemNames - The items to report.
  /// @param listName - The list the items are associated with, if any.
  void reportItemsCrossedOffList(List<String> itemNames, [String? listName]) {
    _reportListManagerEvents(
      'reportItemsCrossedOffList',
      ListManagerEventName.crossedOffList,
      itemNames,
      listName,
    );
  }

  /// Reports items deleted from a list, for the reports we provide to clients.
  /// @param itemNames - The items to report.
  /// @param listName - The list the items are associated with, if any.
  void reportItemsDeletedFromList(List<String> itemNames, [String? listName]) {
    _reportListManagerEvents(
      'reportItemsDeletedFromList',
      ListManagerEventName.deletedFromList,
      itemNames,
      listName,
    );
  }

  /// Marks an "out of app" payload as delivered.
  /// @param payloadId - The payload ID to acknowledge.
  void markPayloadContentAcknowledged(String payloadId) {
    _reportPayloadStatus(
      'markPayloadContentAcknowledged',
      payloadId,
      PayloadStatus.delivered,
    );
  }

  /// Marks an "out of app" payload as rejected.
  /// @param payloadId - The payload ID to reject.
  void markPayloadContentRejected(String payloadId) {
    _reportPayloadStatus(
      'markPayloadContentRejected',
      payloadId,
      PayloadStatus.rejected,
    );
  }

  /// Performs all clean up tasks for the SDK.
  ///
  /// Call this when the widget that owns the SDK is disposed, otherwise you can
  /// experience memory leaks.
  void unmount() {
    // Nothing acknowledged after this belongs to the session that is ending.
    _pendingAtlContent.clear();

    // Zones close out first, while the context is still in place. Releasing it
    // beforehand makes reportAdEvent a no-op, which silently swallowed the
    // impression_end and zone_unmounted of every zone still mounted.
    AdRequestContextRegistry.notifySdkTeardown();

    // Only then release the context, which stops any zone still mounted from
    // issuing further requests against a torn-down SDK.
    AdRequestContextRegistry.setContext(null);

    _removeLifecycleObserver();

    _api?.close();
    _api = null;

    // The session is over, so nothing that identifies it survives. Left in
    // place, the public reporting methods carry on posting under a session the
    // SDK had declared finished — they guard on these being present, not on the
    // SDK still being mounted — and a later initialize() could resume a session
    // that its own start had already replaced.
    _sessionId = null;
    _deviceInfo = null;
    _keywordIntercepts = null;
    _keywordInterceptSearchValue = '';
    _hasBeenBackgrounded = false;
  }

  // ===========================================================================
  // SESSION
  // ===========================================================================

  /// Generates a new session ID.
  ///
  /// Format: [sessionIdPrefix] followed by [sessionIdLength] characters from
  /// `[A-Z0-9]`, mirroring `SessionClient.generateId` on Android.
  String _generateSessionId() {
    // The largest multiple of the alphabet length that fits in a byte. Rejecting
    // anything at or above it keeps every character equally likely, rather than
    // biasing towards the start of the alphabet.
    final rejectAtOrAbove = 256 - (256 % sessionIdCharacters.length);
    final buffer = StringBuffer(sessionIdPrefix);

    var written = 0;

    while (written < sessionIdLength) {
      final randomByte = _random.nextInt(256);

      if (randomByte < rejectAtOrAbove) {
        buffer.write(
          sessionIdCharacters[randomByte % sessionIdCharacters.length],
        );

        written++;
      }
    }

    return buffer.toString();
  }

  /// Mints a new session, or resumes the current one if the app has not been
  /// backgrounded for longer than the session window, and reports the matching
  /// event. A direct port of `SessionClient.createOrResumeSession`.
  ///
  /// NOTE: The session is held in memory only and is never persisted, so a cold
  ///       start always mints a new one. `SESSION_RESUMED` therefore only ever
  ///       occurs when the app is foregrounded within the same process. This is
  ///       deliberate parity with Android; the web SDK persists instead, because
  ///       reloading a browser tab is normal where relaunching an app is not.
  void _createOrResumeSession() {
    final currentTime = _currentUnixTimestamp();
    final isNewSession =
        _sessionId == null ||
        currentTime - _backgroundTime >= sessionLifetimeSeconds;

    if (isNewSession) {
      _sessionId = _generateSessionId();
    } else {
      _backgroundTime = currentTime;
    }

    _reportSdkEvent(
      isNewSession ? SdkEventName.sessionCreated : SdkEventName.sessionResumed,
      null,
    );
  }

  /// Stamps the time the app was backgrounded and reports the event.
  ///
  /// A port of `SessionClient.sessionBackgrounded`.
  void _sessionBackgrounded() {
    _backgroundTime = _currentUnixTimestamp();

    _reportSdkEvent(SdkEventName.sessionBackgrounded, null);
  }

  /// Reacts to the app moving between the foreground and background.
  ///
  /// `AppLifecycleState.inactive` and `.hidden` are transient states raised on
  /// the way to and from `.paused` — and on iOS for the app switcher, control
  /// centre and incoming calls — so acting on them would report churn the native
  /// SDKs never report. `.detached` is the app on its way out of the engine,
  /// where reporting cannot be relied upon to land.
  /// @param state - The lifecycle state the binding reported.
  void _handleAppLifecycleChange(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Only a genuine return from the background resolves the session again.
      // See _hasBeenBackgrounded for why this differs from Android.
      if (!_hasBeenBackgrounded) {
        return;
      }

      _hasBeenBackgrounded = false;

      // Before the zones are told, never after. A zone returning to an ad that
      // outlived its refresh time refetches immediately and reads the session
      // synchronously, so telling it first would send that request under the
      // session about to be replaced and split the retrieve and its impression
      // across two sessions.
      final previousSessionId = _sessionId;

      _createOrResumeSession();

      // The intercepts belong to the session that fetched them: search_id is
      // minted with them and rides on every intercept event. Fetched only at
      // initialize(), a session replaced here left the SDK reporting a search_id
      // from the session that had just ended. A resumed session keeps its own,
      // which are still the right ones.
      //
      // Compared by ID rather than done inside _createOrResumeSession, because
      // initialize() resolves the session and fetches the intercepts itself —
      // doing it there sent the request twice on every launch.
      if (_sessionId != previousSessionId) {
        unawaited(_getKeywordIntercepts());
      }

      unawaited(_getPayloadItemData());

      // Only after a real background. Zones are paused on background and
      // nowhere else, so there is nothing to wake otherwise.
      AdRequestContextRegistry.notifyAppActiveChanged(true);
    } else if (state == AppLifecycleState.paused) {
      _hasBeenBackgrounded = true;

      // Zones first here, so each closes its impression while the session it
      // belongs to is still the current one.
      AdRequestContextRegistry.notifyAppActiveChanged(false);

      _sessionBackgrounded();
    }
  }

  // ===========================================================================
  // REPORTING
  // ===========================================================================

  /// Registers the context ad zones read their session and device info from.
  void _registerAdRequestContext() {
    AdRequestContextRegistry.setContext(
      AdRequestContext(
        appId: _appId,
        apiEnv: _apiEnv,
        udid: _deviceInfo!.udid,
        bundleId: _deviceInfo!.bundleId,
        sdkVersion: sdkVersion,
        storeId: _storeId,
        xyDragDistanceAllowed: _xyAdZoneDragDistanceAllowed,
        api: _api!,
        getSessionId: () => _sessionId ?? '',
        reportAdEvent: _reportAdEvent,
        reportSdkEvent: _reportSdkEvent,
        setPendingAtlContent: (content) {
          // Removed first: re-assigning an existing key keeps its original
          // insertion position, so re-keying a zone would leave it where it was
          // and acknowledge()'s newest-first scan would pick an older zone's ad
          // instead.
          _pendingAtlContent.remove(content.zoneId);
          _pendingAtlContent[content.zoneId] = content;
        },
        forwardAddToList: (items) {
          _onAddToListTriggered?.call(items);
        },
      ),
    );
  }

  /// Reports an SDK level event, carrying the session it describes.
  /// @param eventName - The event to report.
  /// @param extraParams - Any additional params the event carries.
  void _reportSdkEvent(
    SdkEventName eventName,
    Map<String, String>? extraParams,
  ) {
    final api = _api;
    final sessionId = _sessionId;
    final deviceOs = _deviceOs;

    if (api == null ||
        sessionId == null ||
        _deviceInfo == null ||
        deviceOs == null) {
      return;
    }

    unawaited(
      api
          .reportListManagerEvents(
            _sdkEventRequestBase().withEvents(<ListManagerEvent>[
              ListManagerEvent(
                // "sdk" rather than "app": these describe the SDK's own
                // lifecycle, not a user action. Matches SDK_EVENT_TYPE in
                // Android's EventStrings.
                eventSource: ListManagerEventSource.sdk,
                eventName: eventName.value,
                eventTimestamp: _currentUnixTimestamp(),
                eventParams: <String, String?>{
                  'sessionId': sessionId,
                  ...?extraParams,
                },
              ),
            ]),
            deviceOs,
            _listManagerApiEnv,
          )
          .catchError((Object _) {
            // Reporting failures must not interrupt ad serving.
          }),
    );
  }

  /// Reports an ad or zone level event.
  ///
  /// Exposed to ad zones through the request context rather than being called
  /// directly.
  /// @param event - What the event describes and what happened.
  void _reportAdEvent(AdEventReport event) {
    final api = _api;
    final sessionId = _sessionId;
    final deviceInfo = _deviceInfo;

    if (api == null || sessionId == null || deviceInfo == null) {
      return;
    }

    unawaited(
      api
          .reportAdEvent(
            ReportAdEventRequest(
              appId: _appId,
              sessionId: sessionId,
              udid: deviceInfo.udid,
              events: <ReportedAdEvent>[
                ReportedAdEvent(
                  adId: event.adId,
                  zoneId: event.zoneId,
                  impressionId: event.impressionId,
                  eventType: event.eventType,
                  eventName: event.eventName,
                  createdAt: _currentUnixTimestamp(),
                ),
              ],
            ),
            _appId,
            _apiEnv,
          )
          .catchError((Object _) {
            // Reporting failures must not interrupt ad serving.
          }),
    );
  }

  /// Reports a batch of keyword intercept events.
  /// @param events - The events to report.
  void _reportInterceptEvents(List<ReportedInterceptEvent> events) {
    final api = _api;
    final sessionId = _sessionId;
    final deviceInfo = _deviceInfo;

    if (api == null || sessionId == null || deviceInfo == null) {
      return;
    }

    unawaited(
      api
          .reportInterceptEvent(
            ReportInterceptEventRequest(
              appId: _appId,
              udid: deviceInfo.udid,
              sessionId: sessionId,
              events: events,
            ),
            _appId,
            _apiEnv,
          )
          .catchError((Object _) {
            // Reporting failures must not interrupt keyword search.
          }),
    );
  }

  /// Reports one List Manager event per item name.
  /// @param method - The method being called, named in the log when the SDK
  ///      cannot report.
  /// @param eventName - The event name to report for each item.
  /// @param itemNames - The items to report.
  /// @param listName - The list associated with the items, if any.
  void _reportListManagerEvents(
    String method,
    ListManagerEventName eventName,
    List<String> itemNames,
    String? listName,
  ) {
    if (!_canReport(method)) {
      return;
    }

    final timestamp = _currentUnixTimestamp();

    unawaited(
      _api!
          .reportListManagerEvents(
            _sdkEventRequestBase().withEvents(
              itemNames
                  .map(
                    (itemName) => ListManagerEvent(
                      eventSource: ListManagerEventSource.app,
                      eventName: eventName.value,
                      eventTimestamp: timestamp,
                      eventParams: <String, String?>{
                        'item_name': itemName,
                        'list_name': listName,
                      },
                    ),
                  )
                  .toList(),
            ),
            _deviceOs!,
            _listManagerApiEnv,
          )
          .catchError((Object _) {
            // Reporting failures must not interrupt the host app.
          }),
    );
  }

  /// Reports the delivery status of an "out of app" payload.
  /// @param method - The method being called, named in the log when the SDK
  ///      cannot report.
  /// @param payloadId - The payload the status is for.
  /// @param status - The status to report.
  void _reportPayloadStatus(
    String method,
    String payloadId,
    PayloadStatus status,
  ) {
    if (!_canReport(method)) {
      return;
    }

    unawaited(
      _api!
          .reportPayloadContentStatus(
            ReportPayloadDataRequest(
              appId: _appId,
              sessionId: _sessionId!,
              udid: _deviceInfo!.udid,
              tracking: <PayloadTrackingEvent>[
                PayloadTrackingEvent(
                  payloadId: payloadId,
                  status: status,
                  eventTimestamp: _currentUnixTimestamp(),
                ),
              ],
            ),
            _payloadApiEnv,
          )
          .catchError((Object _) {
            // Reporting failures must not interrupt the host app.
          }),
    );
  }

  /// The fields every SDK level event request carries.
  ///
  /// NOTE: locale and allow_retargeting used to travel on the session initialize
  ///       body. With that request gone this is the only channel left for them,
  ///       and it is the one the native SDKs already use, so a user's retargeting
  ///       decision is still honored rather than silently dropped. The rest is
  ///       what the native SDKs put on this same route; field names match
  ///       Android's `EventRequest` exactly, because that is the wire contract.
  ///
  ///       Android also sends `device_udid` and an `errors` array. Neither has an
  ///       equivalent here: the platform channel exposes only one device
  ///       identifier, and this SDK does not report SDK errors yet, so inventing
  ///       values for them would be worse than omitting them.
  ReportListManagerDataRequest _sdkEventRequestBase() {
    final deviceInfo = _deviceInfo!;

    return ReportListManagerDataRequest(
      sessionId: _sessionId!,
      appId: _appId,
      udid: deviceInfo.udid,
      events: const <ListManagerEvent>[],
      sdkVersion: sdkVersion,
      bundleId: deviceInfo.bundleId,
      bundleVersion: deviceInfo.bundleVersion,
      locale: deviceInfo.deviceLocale,
      allowRetargeting: deviceInfo.isAdTrackingEnabled ? 1 : 0,
      device: deviceInfo.deviceName,
      os: deviceInfo.systemName,
      osv: deviceInfo.systemVersion,
      timezone: deviceInfo.deviceTimezone,
      carrier: deviceInfo.deviceCarrier,
      // Reported as strings over the channel but numbers on the wire.
      dw: int.tryParse(deviceInfo.deviceWidth) ?? 0,
      dh: int.tryParse(deviceInfo.deviceHeight) ?? 0,
      density: deviceInfo.deviceScreenDensity,
    );
  }

  /// Whether the SDK currently has what a reported event needs to identify
  /// itself.
  ///
  /// The reporting methods are public and the host can call them whenever it
  /// likes, including before initialize() has resolved and after unmount() has
  /// released the session. Both leave the request unbuildable, so this is
  /// checked at the entry point rather than throwing several frames down.
  /// @param method - The method being called, named in the log.
  /// @returns true when an event can be reported.
  bool _canReport(String method) {
    if (_api == null ||
        _sessionId == null ||
        _deviceInfo == null ||
        _deviceOs == null) {
      _logError(
        'AdAdapted SDK cannot report "$method" before initialize() has resolved or after unmount().',
      );

      return false;
    }

    return true;
  }

  // ===========================================================================
  // DATA
  // ===========================================================================

  /// Gets all possible keyword intercepts for the session.
  Future<void> _getKeywordIntercepts() async {
    final api = _api;
    final deviceInfo = _deviceInfo;
    final sessionId = _sessionId;

    if (api == null || deviceInfo == null || sessionId == null) {
      return;
    }

    try {
      final response = await api.getKeywordIntercepts(
        InterceptRetrieveRequest(
          sdkId: sdkVersion,
          bundleId: deviceInfo.bundleId,
          userId: deviceInfo.udid,
          zoneId: '',
          sessionId: sessionId,
          extra: '',
        ),
        _appId,
        _apiEnv,
      );

      _keywordIntercepts = response.success ? response.data : null;
    } catch (_) {
      // Keyword intercepts are optional; a failure here must not stop the rest
      // of the SDK from working.
    }
  }

  /// Gets all available Payload server item data for the user.
  Future<void> _getPayloadItemData() async {
    final api = _api;
    final deviceInfo = _deviceInfo;
    final sessionId = _sessionId;

    if (api == null || deviceInfo == null || sessionId == null) {
      return;
    }

    try {
      final response = await api.retrievePayloadContent(
        RetrievePayloadItemDataRequest(
          appId: _appId,
          sessionId: sessionId,
          udid: deviceInfo.udid,
        ),
        _payloadApiEnv,
      );

      // One payload per item, matching the shape the other SDKs hand their
      // hosts.
      final finalItemList = <OutOfAppDataPayload>[];

      for (final payload in response.payloads) {
        for (final itemData in payload.detailedListItems) {
          finalItemList.add(
            OutOfAppDataPayload(
              payloadId: payload.payloadId,
              detailedListItems: <DetailedListItem>[itemData],
            ),
          );
        }
      }

      if (finalItemList.isNotEmpty) {
        // Send the items to the client, so they can add them to the list.
        _onOutOfAppPayloadAvailable?.call(finalItemList);
      }
    } catch (_) {
      // Payload content is optional; a failure here must not stop the rest of
      // the SDK from working.
    }
  }

  /// Gets a keyword intercept term by its ID.
  /// @param termId - The term ID to get the term object for.
  /// @returns the term, or null when there is no term with that ID.
  KeywordSearchTerm? _getKeywordInterceptTerm(String termId) {
    final intercepts = _keywordIntercepts;

    if (intercepts == null || termId.isEmpty) {
      return null;
    }

    for (final termObj in intercepts.terms) {
      if (termObj.termId == termId) {
        return termObj;
      }
    }

    return null;
  }

  // ===========================================================================
  // HOUSEKEEPING
  // ===========================================================================

  /// Points the ad, list manager and payload backends at one environment.
  ///
  /// All three are separate hosts with their own production and sandbox tiers,
  /// so each has to be derived.
  /// @param apiEnv - The environment the caller asked for, if any.
  void _resolveApiEnvironments(ApiEnv? apiEnv) {
    // Production unless told otherwise, which is the long-standing default.
    _apiEnv = apiEnv ?? ApiEnv.prod;

    switch (_apiEnv) {
      case ApiEnv.dev:
        _listManagerApiEnv = ListManagerApiEnv.dev;
        _payloadApiEnv = PayloadApiEnv.dev;
      case ApiEnv.mock:
        _listManagerApiEnv = ListManagerApiEnv.mock;
        _payloadApiEnv = PayloadApiEnv.mock;
      case ApiEnv.prod:
        _listManagerApiEnv = ListManagerApiEnv.prod;
        _payloadApiEnv = PayloadApiEnv.prod;
    }
  }

  /// Removes the app lifecycle observer, if one is registered.
  ///
  /// Called before registering as well as on unmount, because only the most
  /// recent observer is tracked: initializing twice without this leaves the
  /// earlier observer attached forever, and every background then reports
  /// SESSION_BACKGROUNDED once per leaked observer. Hot reload initializes
  /// twice.
  void _removeLifecycleObserver() {
    final observer = _lifecycleObserver;

    if (observer != null) {
      WidgetsBinding.instance.removeObserver(observer);

      _lifecycleObserver = null;
    }
  }

  /// The current unix timestamp, in seconds.
  static int _currentUnixTimestamp() {
    return (clock.now().millisecondsSinceEpoch / 1000).round();
  }

  /// Logs an integration error for the host developer.
  ///
  /// Routed through `debugPrint` rather than `print`, so it is dropped from
  /// release builds along with the rest of the framework's diagnostics rather
  /// than writing to a shipped app's log.
  /// @param message - The message to log.
  static void _logError(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }
}
