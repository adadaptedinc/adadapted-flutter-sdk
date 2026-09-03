/// The context an [AdZone] needs in order to request ads and report events.
///
/// This exists as its own library to break what would otherwise be a circular
/// import: the SDK class renders nothing but owns the session and device info,
/// while the AdZone widget owns its ad but needs both.
///
/// The active context is held statically, which mirrors the native SDKs where
/// the equivalents (Android's `SessionClient` and `AdClient`) are singletons. An
/// AdZone therefore needs only a zone ID, exactly as `AaZoneView` does.
library;

import 'api/adadapted_api_requests.dart';
import 'api/adadapted_api_types.dart';
import 'component_types/environment.dart';

/// An "add to list" ad whose items have been handed to the host app, but which
/// has not yet earned its interaction.
///
/// Clicking an ATL ad is not itself the interaction: the items still have to
/// reach the user's list, which only the host app can confirm. This mirrors the
/// `AdContent` object Android publishes to the app and waits to have
/// acknowledged.
class PendingAtlContent {
  /// The ad the items came from.
  final String adId;

  /// The zone the ad was served into.
  final String zoneId;

  /// The impression the click belongs to.
  final String impressionId;

  /// The items handed to the host app.
  final List<DetailedListItem> items;

  /// Whether the interaction has already been reported. Guards against a second
  /// acknowledgement reporting a second interaction for one click, the way
  /// `AdContent.isHandled` does.
  bool isHandled;

  /// Creates pending ATL content from its individual fields.
  PendingAtlContent({
    required this.adId,
    required this.zoneId,
    required this.impressionId,
    required this.items,
    this.isHandled = false,
  });
}

/// An ad or zone level event to report.
class AdEventReport {
  /// The ad the event describes, or an empty string for zone level events.
  final String adId;

  /// The zone the event describes.
  final String zoneId;

  /// The impression the event belongs to, or an empty string for zone level
  /// events.
  final String impressionId;

  /// What happened.
  final ReportedEventType eventType;

  /// Why a zone went unfilled. Omitted for every other event type.
  final ZoneUnfilledReason? eventName;

  /// Creates an ad event report from its individual fields.
  const AdEventReport({
    required this.adId,
    required this.zoneId,
    required this.impressionId,
    required this.eventType,
    this.eventName,
  });
}

/// Everything an ad zone needs from the SDK in order to do its work.
class AdRequestContext {
  /// The client's app ID, sent as the API key header.
  final String appId;

  /// The API environment to make requests against.
  final ApiEnv apiEnv;

  /// The unique device ID of the user.
  final String udid;

  /// The bundle ID of the host app.
  final String bundleId;

  /// The SDK version.
  final String sdkVersion;

  /// The store to target ads for, or an empty string.
  final String storeId;

  /// The touch drag distance configured on initialize(), if any. A zone without
  /// its own `xyDragDistanceAllowed` falls back to this, so the value a host set
  /// once at initialize() is not silently ignored.
  final double? xyDragDistanceAllowed;

  /// The API client every zone issues its ad requests through. Shared with the
  /// SDK so a host that injected a client for testing gets one SDK, one client,
  /// and one place to assert against.
  final AdadaptedApiRequests api;

  /// Reads the current session ID.
  ///
  /// NOTE: A function rather than a value, because the session rotates when the
  ///       app is foregrounded after the session window has elapsed. Capturing
  ///       the ID once would attribute later requests to a session that has
  ///       ended.
  final String Function() getSessionId;

  /// Reports an ad or zone level event.
  final void Function(AdEventReport event) reportAdEvent;

  /// Reports an SDK level event.
  final void Function(SdkEventName eventName, Map<String, String>? extraParams)
  reportSdkEvent;

  /// Hands an "add to list" ad's items to the SDK so a later acknowledgement can
  /// be attributed back to the ad that produced them.
  final void Function(PendingAtlContent content) setPendingAtlContent;

  /// Forwards "add to list" items to the callback the host gave initialize().
  ///
  /// Used only when a zone was created without its own `onAddToListTriggered`.
  /// The callback was global before zones became widgets, and a host with one
  /// handler for every zone should not have to pass it to each one.
  final void Function(List<DetailedListItem> items) forwardAddToList;

  /// Creates an ad request context from its individual fields.
  const AdRequestContext({
    required this.appId,
    required this.apiEnv,
    required this.udid,
    required this.bundleId,
    required this.sdkVersion,
    required this.storeId,
    required this.xyDragDistanceAllowed,
    required this.api,
    required this.getSessionId,
    required this.reportAdEvent,
    required this.reportSdkEvent,
    required this.setPendingAtlContent,
    required this.forwardAddToList,
  });
}

/// Holds the context registered by the most recent initialize() call, and the
/// notifications the SDK sends its zones.
///
/// Every member is static because there is one SDK per app, exactly as there is
/// one `SessionClient` per app on Android.
abstract final class AdRequestContextRegistry {
  /// The context registered by the most recent initialize() call.
  static AdRequestContext? _activeContext;

  /// Zones waiting for a context to become available.
  static final Set<void Function()> _waitingForContext = <void Function()>{};

  /// Zones waiting to be told the app moved between the foreground and
  /// background.
  static final Set<void Function(bool isActive)> _appActiveListeners =
      <void Function(bool isActive)>{};

  /// Zones waiting to be told the SDK is being torn down.
  static final Set<void Function()> _teardownListeners = <void Function()>{};

  /// The context ad zones should use, or null when the SDK has not been
  /// initialized.
  static AdRequestContext? get context => _activeContext;

  /// Registers the context ad zones should use. Called by the SDK during
  /// initialize().
  /// @param context - The context to make active, or null to clear it.
  static void setContext(AdRequestContext? context) {
    final hadNoContext = _activeContext == null;

    _activeContext = context;

    if (context != null && hadNoContext) {
      // A zone typically builds before initialize() resolves, since the host
      // renders its layout straight away and device info is gathered over the
      // platform channel. Without this the zone would find no context on mount
      // and sit empty for the rest of the session.
      //
      // Iterated over a copy, because a listener that starts its zone can
      // cancel its own registration and mutate the set mid-iteration.
      for (final listener in _waitingForContext.toList()) {
        listener();
      }
    }
  }

  /// Registers interest in a context arriving, for a zone that mounted before
  /// the SDK finished initializing.
  /// @param listener - Called when a context becomes available.
  /// @returns a function that cancels the registration.
  static void Function() onContextReady(void Function() listener) {
    _waitingForContext.add(listener);

    return () {
      _waitingForContext.remove(listener);
    };
  }

  /// Subscribes a zone to foreground and background transitions.
  ///
  /// Zones are told by the SDK rather than each observing the app lifecycle
  /// themselves. A zone's own observer would be registered first, because a
  /// child's `initState` runs before its parent's and the SDK's registration
  /// waits on the platform channel call, so on returning from the background the
  /// zone would refetch before the SDK had resolved the session, requesting ads
  /// against a session it was about to end.
  /// @param listener - Called with true on foreground, false on background.
  /// @returns a function that cancels the subscription.
  static void Function() subscribeToAppActive(
    void Function(bool isActive) listener,
  ) {
    _appActiveListeners.add(listener);

    return () {
      _appActiveListeners.remove(listener);
    };
  }

  /// Tells every zone the app changed foreground state. Called by the SDK, after
  /// it has resolved the session on the way back in.
  /// @param isActive - Whether the app is now in the foreground.
  static void notifyAppActiveChanged(bool isActive) {
    for (final listener in _appActiveListeners.toList()) {
      listener(isActive);
    }
  }

  /// Subscribes a zone to the SDK being unmounted, so it can close out its
  /// events while there is still a context to report them through.
  /// @param listener - Called when unmount() begins.
  /// @returns a function that cancels the subscription.
  static void Function() subscribeToSdkTeardown(void Function() listener) {
    _teardownListeners.add(listener);

    return () {
      _teardownListeners.remove(listener);
    };
  }

  /// Tells every zone the SDK is going away. Called by unmount() before the
  /// context is released, so the closing events can still be reported.
  static void notifySdkTeardown() {
    for (final listener in _teardownListeners.toList()) {
      listener();
    }
  }

  /// Drops every registered context and listener.
  ///
  /// Only for tests: the statics here outlive an individual test's widget tree,
  /// so without this one test's zones stay subscribed and report events into the
  /// next one.
  static void resetForTesting() {
    _activeContext = null;

    _waitingForContext.clear();
    _appActiveListeners.clear();
    _teardownListeners.clear();
  }
}
