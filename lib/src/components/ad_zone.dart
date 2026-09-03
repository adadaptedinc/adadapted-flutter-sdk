/// The [AdZone] widget.
///
/// This is a port of the Android SDK's `AdZonePresenter`. Each instance owns one
/// zone: its own ad request, its own refresh countdown and its own impression
/// pairing, all independent of every other zone on screen. Nothing here is
/// shared statically, which is what allows several zones to coexist.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../ad_request_context.dart';
import '../api/adadapted_api_types.dart';
import 'report_ad_button.dart';

/// How long an ad is displayed for when the API supplies no usable refresh time.
///
/// Matches `Config.DEFAULT_AD_REFRESH_SECONDS` on Android.
const int defaultAdRefreshSeconds = 60;

/// The shortest refresh time that will be honored, so an unexpectedly small
/// value cannot put the zone into a tight request loop.
///
/// Matches `Ad.MINIMUM_REFRESH_TIME_SECONDS` on Android.
const int minimumAdRefreshSeconds = 15;

/// The default touch drag distance, in logical pixels, below which a touch on a
/// zone counts as a tap rather than a scroll.
const double defaultXyDragDistanceAllowed = 25;

/// Injected into the creative once it has rendered and is on screen, immediately
/// before the impression is reported. The creative is expected to define this
/// function; it loads the advertiser's measurement pixels.
///
/// Matches `PIXEL_TRACKING_JS` in the Android SDK's `AdZonePresenter`.
const String pixelTrackingJs = 'loadTrackingPixels()';

/// Resolves how long an ad should be displayed for.
///
/// Mirrors `Ad.refreshTimeOrDefault` on Android.
/// @param refreshTime - The refresh time served for the ad.
/// @returns the refresh time in seconds.
int resolveRefreshSeconds(num? refreshTime) {
  if (refreshTime == null || !refreshTime.isFinite || refreshTime <= 0) {
    return defaultAdRefreshSeconds;
  }

  return refreshTime.round() < minimumAdRefreshSeconds
      ? minimumAdRefreshSeconds
      : refreshTime.round();
}

/// A single ad zone.
///
/// The host app places one per zone it has been allocated, the way an
/// `AaZoneView` is placed in an Android layout. The zone declares only its own
/// ID: app ID, session, device info and environment all come from the SDK.
class AdZone extends StatefulWidget {
  /// The ad zone ID to serve ads for. Supplied by the host app, which is the
  /// only party that knows which zones it has been allocated.
  final String zoneId;

  /// Whether the zone is currently on screen.
  ///
  /// Leave this null — the default — and the zone measures its own visibility,
  /// which is what a host wants in almost every case. Supply it to take manual
  /// control, for a layout whose real visibility the measurement cannot see (a
  /// zone drawn into a custom compositing layer, or one deliberately kept live
  /// behind a transparent overlay).
  ///
  /// While the zone is not on screen it neither refreshes nor records
  /// impressions. React Native's SDK requires this value, because it has no way
  /// to measure; Flutter does, so the default here is measurement rather than a
  /// prop a host can silently forget.
  final bool? isVisible;

  /// The recipe context this zone is currently showing, if any.
  ///
  /// Equivalent to `AaZoneView.setAdZoneContextId`.
  final String? contextId;

  /// The touch sensitivity of the ad zone in both the X and Y directions.
  ///
  /// If the amount of touch "drag" distance in either direction is less than
  /// this value, the action is treated as a tap on the zone. Falls back to the
  /// value given to `initialize()`, then to [defaultXyDragDistanceAllowed].
  final double? xyDragDistanceAllowed;

  /// The width the zone occupies while it has an ad. Null lets it take whatever
  /// width its parent gives it.
  final double? width;

  /// The height the zone occupies while it has an ad. Null lets it take whatever
  /// height its parent gives it.
  final double? height;

  /// Called when "add to list" items are clicked in this zone.
  ///
  /// A zone without one falls back to the handler given to `initialize()`.
  final void Function(List<DetailedListItem> items)? onAddToListTriggered;

  /// Called whenever the zone's fill state changes, so the host can collapse or
  /// reveal the space around it.
  ///
  /// Mirrors `AaZoneView.Listener.onZoneHasAds`.
  final void Function(bool hasAds)? onZoneHasAds;

  /// Called when an ad has been retrieved and displayed.
  ///
  /// Mirrors `AaZoneView.Listener.onAdLoaded`.
  final VoidCallback? onAdLoaded;

  /// Called when an ad could not be retrieved or displayed.
  ///
  /// Mirrors `AaZoneView.Listener.onAdLoadFailed`.
  final VoidCallback? onAdLoadFailed;

  /// Creates an ad zone.
  const AdZone({
    required this.zoneId,
    this.isVisible,
    this.contextId,
    this.xyDragDistanceAllowed,
    this.width,
    this.height,
    this.onAddToListTriggered,
    this.onZoneHasAds,
    this.onAdLoaded,
    this.onAdLoadFailed,
    super.key,
  });

  @override
  State<AdZone> createState() => _AdZoneState();
}

/// The state machine behind one ad zone.
class _AdZoneState extends State<AdZone> {
  /// The ad currently displayed, or null when the zone is unfilled.
  Ad? _currentAd;

  /// How long the current ad is displayed for.
  int _refreshSeconds = defaultAdRefreshSeconds;

  /// True once a response, filled or not, has come back for this zone.
  bool _loaded = false;

  /// Guards against overlapping ad requests.
  bool _inFlight = false;

  /// Incremented whenever what an open request would be answering changes, so a
  /// response that belongs to a previous zone can be recognised and dropped.
  int _requestGeneration = 0;

  /// Set when a targeting change arrives mid-request, so it is not lost.
  bool _refetchWhenSettled = false;

  /// The fill state last handed to [AdZone.onZoneHasAds], so the host is told
  /// when it changes rather than on every serve. Null until the first report,
  /// which distinguishes "not told yet" from "told it was false".
  bool? _reportedHasAds;

  /// When the current ad was fetched, in milliseconds since the epoch.
  int _adFetchedAt = 0;

  /// How much of the countdown is left, in milliseconds.
  int _msLeftOnRefresh = 0;

  /// When the countdown was last resumed, in milliseconds since the epoch.
  int _countdownResumedAt = 0;

  /// The running refresh countdown, if any.
  Timer? _timer;

  /// Whether the countdown is currently running.
  bool _timerRunning = false;

  /// Whether the zone is currently on screen, as measured or as the host
  /// reported.
  bool _isVisible = true;

  /// Whether the app is currently in the foreground.
  bool _isAppActive = true;

  /// Whether this state is still attached.
  ///
  /// Tracked separately from [State.mounted], which is still true throughout
  /// [dispose] and so cannot gate the work [dispose] itself must not do.
  bool _isMounted = true;

  /// Whether the zone has reported its mount and made its first request. False
  /// while it is still waiting for the SDK to finish initializing.
  bool _started = false;

  /// Whether the zone has already reported its unmount, so SDK teardown and
  /// widget disposal cannot both report one.
  bool _closed = false;

  /// Whether the creative itself has rendered in the web view.
  ///
  /// An impression is not owed for an ad the user could not actually have seen,
  /// so this gates it alongside visibility.
  bool _creativeLoaded = false;

  /// Pending timer for a load event that has not been confirmed yet. See
  /// [_onCreativeLoaded] for why a load event is not trusted immediately.
  Timer? _creativeSettleTimer;

  /// Whether an impression has been reported for the current ad.
  bool _impressionTracked = false;

  /// Whether an impression end has been reported for the current ad.
  bool _impressionEndTracked = false;

  /// Whether a click has been handled for the current ad.
  bool _clickHandled = false;

  /// Whether an unfilled reason has been reported for the current request.
  bool _unfilledReported = false;

  /// An unfilled reason waiting for the zone to be on screen.
  ZoneUnfilledReason? _pendingUnfilledReason;

  /// The context ID the zone last requested against.
  String? _previousContextId;

  /// Cancels the subscription to the SDK's request context becoming available.
  void Function()? _unsubscribeContextReady;

  /// Cancels the subscription to app foreground transitions.
  void Function()? _unsubscribeAppActive;

  /// Cancels the subscription to SDK teardown.
  void Function()? _unsubscribeTeardown;

  /// The controller for the web view the creative renders in.
  WebViewController? _webViewController;

  /// Where the user started touching the ad, used to tell a tap from a scroll.
  Offset? _touchStart;

  // ===========================================================================
  // LIFECYCLE
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    _attachToZone();
  }

  @override
  void didUpdateWidget(AdZone oldWidget) {
    super.didUpdateWidget(oldWidget);

    // A zone change reports an unmount for the zone being left and a mount for
    // the one arriving. Without it the change is ignored outright: no events
    // either way, and the new zone displays the previous one's ad until its next
    // refresh happens to request the right one. A host can still avoid all of it
    // by keying the widget.
    if (oldWidget.zoneId != widget.zoneId) {
      _detachFromZone(oldWidget.zoneId);
      _attachToZone();

      return;
    }

    // The host took, released or changed manual control of visibility.
    if (oldWidget.isVisible != widget.isVisible && widget.isVisible != null) {
      _applyVisibility(widget.isVisible!);
    }

    if (oldWidget.contextId != widget.contextId) {
      _handleContextIdChanged();
    }
  }

  @override
  void dispose() {
    _detachFromZone(widget.zoneId);

    _isMounted = false;

    super.dispose();
  }

  /// Subscribes the zone to the SDK and starts it, if the SDK is ready.
  void _attachToZone() {
    _isMounted = true;

    // Anything already in flight was asked on behalf of whichever zone this
    // widget was serving before. Bumped here rather than inside [_start], which
    // is skipped entirely while there is no request context: a zone switch
    // between unmount() and the next initialize() then left the generation
    // untouched, and the previous zone's response landed and rendered its
    // creative under the new zone.
    _requestGeneration += 1;

    // The request this is about to make already carries the current context,
    // because it is read when the request is built. Without this a later
    // comparison would see a stale value, queue a refetch on top of a request
    // that was already targeted correctly, and throw that fill away.
    _previousContextId = widget.contextId;

    if (widget.isVisible != null) {
      _isVisible = widget.isVisible!;
    }

    // A host builds its layout immediately, while initialize() is still
    // gathering device info over the platform channel, so a zone normally mounts
    // before there is any context to request with. Android has no equivalent
    // problem: its SessionClient is an object that always exists, so the
    // presenter can call straight into it. Here the zone waits to be told.
    //
    // Subscribed for the widget's lifetime rather than just until the first
    // context, so a later initialize() reaches a zone that is still mounted.
    _unsubscribeContextReady = AdRequestContextRegistry.onContextReady(_start);

    // A backgrounded app is not showing its ads to anyone.
    //
    // The SDK owns the lifecycle observer and calls in here, rather than each
    // zone observing for itself. A zone's own observer registers first, because
    // a child's initState runs before its parent's and the SDK's registration
    // waits on the platform channel call, so on returning from the background
    // this zone would have refetched before the SDK resolved the session and
    // requested an ad against the session it was about to replace.
    _unsubscribeAppActive = AdRequestContextRegistry.subscribeToAppActive((
      isActive,
    ) {
      _isAppActive = isActive;

      _applyOnScreenChange();
    });

    // The SDK is going away. Close out while there is still a context to report
    // through, because releasing it turns every report into a no-op.
    _unsubscribeTeardown = AdRequestContextRegistry.subscribeToSdkTeardown(
      _handleSdkTeardown,
    );

    if (AdRequestContextRegistry.context != null) {
      _start();
    }
  }

  /// Starts the zone once there is a session and device info to request with.
  ///
  /// Also restarts one that SDK teardown closed out, which is what makes a host
  /// that calls unmount() and then initialize() again work: teardown cancels the
  /// countdown, so without this the zone stays on screen with no timer and never
  /// serves or reports anything again.
  void _start() {
    if (_started && !_closed) {
      return;
    }

    // Whatever was on screen belonged to the previous cycle: either to a
    // different zone, or to a session that has since ended. Either way it must
    // not stay up, or the arriving zone gets billed for it.
    _setCurrentAd(null);

    // The tracking flags go with it. Leaving them to [_displayAd] is wrong:
    // that calls [_endImpression] before resetting them, and [_endImpression]
    // reports against a current ad this has already cleared, so a creative that
    // finished loading after teardown leaves the impression flag set and the
    // next ad opens with an impression_end carrying an empty ad ID and
    // impression ID.
    _cancelCreativeSettle();

    _creativeLoaded = false;
    _impressionTracked = false;
    _impressionEndTracked = false;
    _clickHandled = false;

    _started = true;
    _closed = false;

    // The ad from before teardown is gone, so this is a fresh cycle.
    _loaded = false;

    // Reported for every zone, whether it ever receives an ad or not.
    _reportEvent(ReportedEventType.zoneMounted);

    _fetchAd();
  }

  /// Closes the zone out, reporting its unmount while a context is still around
  /// to report through.
  ///
  /// @param zoneId - The zone being left. Passed explicitly because a zone
  ///      switch closes out the previous zone, whose ID the widget no longer
  ///      carries.
  void _detachFromZone(String zoneId) {
    _unsubscribeContextReady?.call();
    _unsubscribeAppActive?.call();
    _unsubscribeTeardown?.call();

    _unsubscribeContextReady = null;
    _unsubscribeAppActive = null;
    _unsubscribeTeardown = null;

    _endImpression(zoneId: zoneId);
    _cancelTimer();

    // Otherwise it fires against a zone that is gone, calling back into a host
    // that has disposed of it.
    _cancelCreativeSettle();

    // Only if the mount was reported and the zone has not already been closed
    // out by SDK teardown, so mounts and unmounts stay paired one to one however
    // the zone goes away.
    if (_started && !_closed) {
      _closed = true;

      _reportEvent(ReportedEventType.zoneUnmounted, zoneId: zoneId);
    }
  }

  /// Handles the SDK being torn down under a zone that is still on screen.
  void _handleSdkTeardown() {
    _endImpression();
    _cancelTimer();

    // The widget is still mounted here, so [_isOnScreen] is still true: left
    // running, this settle reaches [_trackImpression] and injects the creative's
    // pixels for an impression the SDK can no longer report.
    _cancelCreativeSettle();

    if (_started && !_closed) {
      _closed = true;

      _reportEvent(ReportedEventType.zoneUnmounted);
    }

    // The ad comes down with the SDK. Reporting has just been closed out and the
    // context is about to be released, so anything left on screen is an ad
    // nothing can account for — and it stays tappable, because the touch handler
    // acts on the current ad. A tap would still hand items to the host or open
    // the advertiser's URL while the interaction went unreported. Cleared after
    // the events above, which report against it.
    _setCurrentAd(null);
  }

  // ===========================================================================
  // VISIBILITY
  // ===========================================================================

  /// Records a visibility change and reacts to it.
  /// @param isVisible - Whether the zone is now on screen.
  void _applyVisibility(bool isVisible) {
    if (_isVisible == isVisible) {
      return;
    }

    _isVisible = isVisible;

    _applyOnScreenChange();
  }

  /// Reacts to the zone arriving on or leaving the screen.
  void _applyOnScreenChange() {
    if (_isOnScreen()) {
      _flushUnfilled();
      _trackImpression();
      _resumeTimer();
    } else {
      _endImpression();
      _pauseTimer();
    }
  }

  /// Whether the zone is actually in front of the user right now.
  ///
  /// The countdown, the impression events and the unfilled report all hang off
  /// this. Mirrors `AdZonePresenter.zoneIsOnScreen`.
  bool _isOnScreen() {
    return _isMounted && _isVisible && _isAppActive;
  }

  /// Reacts to the measured visibility of the zone changing.
  ///
  /// An unfilled zone occupies no space, so the measurement it produces is not
  /// a statement about whether the user can see the slot — it is an artifact of
  /// there being nothing to see. Acting on it would freeze the countdown of
  /// every zone the moment it went unfilled, and it would never ask for another
  /// ad. The last real measurement stands instead, which is correct in both
  /// directions: a zone that went unfilled while on screen keeps refreshing, and
  /// one that went unfilled while off screen stays paused.
  /// @param info - What the detector measured.
  void _onVisibilityInfo(VisibilityInfo info) {
    if (!_isMounted || widget.isVisible != null || info.size.isEmpty) {
      return;
    }

    _applyVisibility(info.visibleFraction > 0);
  }

  // ===========================================================================
  // EVENTS
  // ===========================================================================

  /// Reports an ad or zone level event through the SDK.
  /// @param eventType - What happened.
  /// @param ad - The ad the event describes, when there is one.
  /// @param eventName - Why a zone went unfilled, for that event type only.
  /// @param zoneId - The zone the event belongs to. Defaults to this widget's.
  void _reportEvent(
    ReportedEventType eventType, {
    Ad? ad,
    ZoneUnfilledReason? eventName,
    String? zoneId,
  }) {
    AdRequestContextRegistry.context?.reportAdEvent(
      AdEventReport(
        adId: ad?.id ?? '',
        zoneId: zoneId ?? widget.zoneId,
        impressionId: ad?.impressionId ?? '',
        eventType: eventType,
        eventName: eventName,
      ),
    );
  }

  /// Reports the impression for the current ad, at most once per ad.
  void _trackImpression() {
    final ad = _currentAd;

    if (ad == null ||
        _impressionTracked ||
        // The creative has to have rendered. Reporting on the response alone
        // bills ads whose creative failed to paint, and means the tracking
        // script below never runs. Mirrors the webView.loaded condition in
        // AdZonePresenter.trackAdImpression.
        !_creativeLoaded ||
        !_isOnScreen()) {
      return;
    }

    _impressionTracked = true;

    // Before the impression, as on Android. The creative defines this function;
    // it loads the advertiser's own measurement pixels, so without it third
    // party verification sees no impressions at all however healthy our own
    // numbers look.
    //
    // Contained, because the flag above is already set: a throw from the
    // injection would otherwise lose this ad's impression permanently — the
    // guard says it was reported and the report below never runs — and escape
    // into whichever handler called this. The advertiser's pixels are the
    // creative's own code and outside our control; ours are not.
    unawaited(
      _webViewController?.runJavaScript(pixelTrackingJs).catchError((
        Object error,
      ) {
        debugPrint(
          'Unable to inject the tracking pixels for ad "${ad.id}". $error',
        );
      }),
    );

    _reportEvent(ReportedEventType.impression, ad: ad);
  }

  /// Reports the impression end for the current ad.
  ///
  /// Only fires once, and only if a real impression was recorded for that ad
  /// first. Mirrors `EventClient.trackImpressionEnd`.
  /// @param zoneId - The zone the event belongs to. Defaults to this widget's.
  void _endImpression({String? zoneId}) {
    if (!_impressionTracked || _impressionEndTracked) {
      return;
    }

    _impressionEndTracked = true;

    _reportEvent(
      ReportedEventType.impressionEnd,
      ad: _currentAd,
      zoneId: zoneId,
    );
  }

  /// Reports a queued unfilled event once the zone is on screen.
  void _flushUnfilled() {
    final reason = _pendingUnfilledReason;

    if (reason == null || _unfilledReported || !_isOnScreen()) {
      return;
    }

    _unfilledReported = true;
    _pendingUnfilledReason = null;

    _reportEvent(ReportedEventType.zoneUnfilled, eventName: reason);
  }

  /// Queues the unfilled report, and sends it if the zone is already on screen.
  ///
  /// Held rather than dropped when off screen, because a request can settle
  /// before the zone's visibility has been measured, and dropping it there would
  /// lose the report for any zone that loses that race.
  /// @param reason - Why the zone went unfilled.
  void _reportUnfilled(ZoneUnfilledReason reason) {
    if (_unfilledReported) {
      return;
    }

    _pendingUnfilledReason = reason;

    _flushUnfilled();
  }

  // ===========================================================================
  // TIMERS
  // ===========================================================================

  /// Cancels any deferred creative settle.
  ///
  /// The settle is what waits out a load event that precedes an error, so it has
  /// to be cancelled anywhere the ad it belongs to stops being the ad on screen.
  void _cancelCreativeSettle() {
    _creativeSettleTimer?.cancel();
    _creativeSettleTimer = null;
  }

  /// Stops the refresh countdown.
  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _timerRunning = false;
  }

  /// Starts the countdown with whatever time it has left.
  void _startTimer() {
    if (!_loaded || _timerRunning || !_isOnScreen()) {
      return;
    }

    _timerRunning = true;
    _countdownResumedAt = clock.now().millisecondsSinceEpoch;
    _timer = Timer(Duration(milliseconds: _msLeftOnRefresh), () {
      _timerRunning = false;

      _loadNextAd();
    });
  }

  /// Arms the countdown fresh from the current ad's refresh time.
  void _restartTimer() {
    _cancelTimer();

    _adFetchedAt = clock.now().millisecondsSinceEpoch;
    _msLeftOnRefresh = _refreshSeconds * 1000;

    _startTimer();
  }

  /// Freezes what is left of the countdown, so a zone that is off screen or in a
  /// backgrounded app neither refreshes nor fetches.
  void _pauseTimer() {
    if (!_timerRunning) {
      return;
    }

    final elapsed = clock.now().millisecondsSinceEpoch - _countdownResumedAt;

    _msLeftOnRefresh = _msLeftOnRefresh - elapsed < 0
        ? 0
        : _msLeftOnRefresh - elapsed;

    _cancelTimer();
  }

  /// Resumes the countdown.
  ///
  /// An ad that outlived its own refresh time while the countdown was frozen is
  /// replaced immediately, rather than being shown for time it never spent in
  /// front of anyone.
  void _resumeTimer() {
    if (_timerRunning || !_isOnScreen()) {
      return;
    }

    final age = clock.now().millisecondsSinceEpoch - _adFetchedAt;

    if (_loaded && age >= _refreshSeconds * 1000) {
      _loadNextAd();
    } else {
      _startTimer();
    }
  }

  // ===========================================================================
  // SERVING
  // ===========================================================================

  /// Places an ad in the zone, or clears it when there is none, and arms the
  /// countdown.
  /// @param ad - The ad to display, or null when there is no ad.
  /// @param refreshSecondsOverride - The refresh time to use when there is no
  ///      ad.
  void _displayAd(Ad? ad, {num? refreshSecondsOverride}) {
    if (!_isMounted) {
      // The zone was disposed while its request was in flight. Dropping the
      // response here keeps disposal final: no render, no impression and no
      // timer for a zone that is gone.
      return;
    }

    // Each ad gets its own impression pair, so the outgoing ad is closed out
    // before the tracking flags reset.
    _endImpression();

    // Any settle pending for the outgoing ad is void.
    _cancelCreativeSettle();

    _refreshSeconds = resolveRefreshSeconds(
      ad != null ? ad.refreshTime : refreshSecondsOverride,
    );
    _impressionTracked = false;
    _impressionEndTracked = false;
    _clickHandled = false;

    // The replacement has not rendered yet. The web view's own load callback
    // sets this and files the impression from there.
    _creativeLoaded = false;

    // Armed before anything else, so a later failure cannot leave the zone
    // without a refresh timer.
    _restartTimer();

    _setCurrentAd(ad);

    // Deliberately no impression here. It is owed when the creative has rendered
    // and the zone is on screen, whichever happens last, so it is filed from the
    // web view's load callback and re-attempted whenever visibility changes.
    // Android files it from the same place, through onAdLoadedInWebView.
    //
    // Only on a change, which is what the callback documents and what a host
    // needs: it exists so the app can collapse or reveal the space around the
    // zone, and firing it on every rotation with an unchanged value rebuilds the
    // host for nothing.
    final hasAds = ad != null;

    if (_reportedHasAds != hasAds) {
      _reportedHasAds = hasAds;

      widget.onZoneHasAds?.call(hasAds);
    }

    // A response with no ad is a fill failure, reported here. A response with an
    // ad whose creative will not render is a render failure, reported from the
    // web view's error callback.
    if (ad == null) {
      widget.onAdLoadFailed?.call();
    }
  }

  /// Requests a single ad for this zone.
  Future<void> _fetchAd() async {
    final context = AdRequestContextRegistry.context;

    if (!_isMounted || context == null) {
      return;
    }

    if (_inFlight) {
      // A targeting change arrived while a request was outstanding. Recording it
      // means the zone picks up the new value as soon as that settles, instead of
      // showing the previous one's ad until the next refresh.
      _refetchWhenSettled = true;

      return;
    }

    _inFlight = true;
    _unfilledReported = false;
    _pendingUnfilledReason = null;

    final generation = _requestGeneration;

    AdRetrieveResponse? response;
    var failed = false;

    try {
      response = await context.api.retrieveAd(
        AdRetrieveRequest(
          sdkId: context.sdkVersion,
          bundleId: context.bundleId,
          userId: context.udid,
          zoneId: widget.zoneId,
          storeId: context.storeId,
          contextId: widget.contextId ?? '',
          sessionId: context.getSessionId(),
          extra: '',
        ),
        context.appId,
        context.apiEnv,
      );
    } catch (_) {
      failed = true;
    }

    _inFlight = false;

    if (generation != _requestGeneration) {
      // Answered for a zone this widget is no longer serving. Displaying it
      // would put the previous zone's creative under the current one and bill
      // the current one for it.
      //
      // Straight back to [_fetchAd] rather than [_loadNextAd], because the
      // current zone has not loaded anything yet and [_loadNextAd] returns early
      // on that, which would strand it with no ad and no request outstanding.
      _refetchWhenSettled = false;

      unawaited(_fetchAd());

      return;
    }

    _loaded = true;

    if (failed || response == null) {
      _reportUnfilled(ZoneUnfilledReason.requestFailed);

      // The current refresh time is carried forward, so a failing zone still
      // paces its retries instead of dropping back to the default.
      _displayAd(null, refreshSecondsOverride: _refreshSeconds);
    } else {
      _handleAdResponse(response);
    }

    if (_refetchWhenSettled) {
      _refetchWhenSettled = false;

      _loadNextAd();
    }
  }

  /// Decides what a settled ad response means for the zone.
  /// @param response - The response the API answered with.
  void _handleAdResponse(AdRetrieveResponse response) {
    final zone = response.data;

    // The API returns success:false on a 200 for business rejections, so the
    // status code alone is not enough.
    if (!response.success || zone == null) {
      _reportUnfilled(ZoneUnfilledReason.requestFailed);
      _displayAd(null, refreshSecondsOverride: _refreshSeconds);

      return;
    }

    final ad = zone.ad;

    if (ad.id.isNotEmpty && ad.creativeUrl.isEmpty) {
      // An ad with an ID but nothing to render. It counts as a fill by every
      // other measure, so without this the zone reports its mount, no impression
      // and no unfilled reason, and sits blank until the next refresh.
      _reportUnfilled(ZoneUnfilledReason.renderFailed);
      _displayAd(null, refreshSecondsOverride: ad.refreshTime);

      return;
    }

    if (ad.id.isEmpty) {
      // An ad object with no ID is how the API reports that it had nothing to
      // serve. Its refresh time is the backoff.
      _reportUnfilled(ZoneUnfilledReason.noAd);
      _displayAd(null, refreshSecondsOverride: ad.refreshTime);

      return;
    }

    _displayAd(ad.copyWith(zoneId: widget.zoneId));
  }

  /// Requests the next ad, replacing whatever the zone is showing.
  void _loadNextAd() {
    // Armed before the request goes out, and deliberately so. It keeps the
    // countdown owned for the whole time that request is open, which is what
    // makes [_resumeTimer] a no-op while one is in flight. Without it any
    // visibility change during the request sees a stopped timer and an ad
    // already past its refresh time, queues a refetch, and then bills an
    // impression and an impression_end for the arriving ad in a single tick.
    //
    // This cannot leave a response arriving to an expired timer, because every
    // request is bounded by the API client's timeout, which is below
    // [minimumAdRefreshSeconds]: the response always lands first. Android arms
    // it in both places too, in getNextAd and again in handleAd.
    _restartTimer();

    if (_inFlight) {
      _refetchWhenSettled = true;

      return;
    }

    if (!_loaded) {
      return;
    }

    _endImpression();

    unawaited(_fetchAd());
  }

  /// Reacts to the recipe context changing.
  ///
  /// A changed recipe context means the ad on screen was chosen for the wrong
  /// one.
  void _handleContextIdChanged() {
    if (_previousContextId == widget.contextId) {
      return;
    }

    _previousContextId = widget.contextId;

    if (_inFlight) {
      // The open request was built with the previous context, so pick the new
      // one up as soon as it settles. Gating this on [_loaded] instead drops the
      // change entirely for the very first request, leaving the zone showing an
      // ad chosen for a context it is no longer in, with nothing to make it try
      // again.
      _refetchWhenSettled = true;

      return;
    }

    if (_loaded) {
      _loadNextAd();
    }
  }

  // ===========================================================================
  // CREATIVE
  // ===========================================================================

  /// Points the web view at an ad's creative, building a controller on first
  /// use.
  /// @param ad - The ad whose creative should be displayed.
  void _loadCreative(Ad ad) {
    final controller = _webViewController ??= _buildWebViewController();

    // Always issued, even for a creative_url the web view is already showing.
    // Two ads rotating through the same creative is routine, and the impression
    // is owed on the load event, so a navigation that was skipped as redundant
    // would cost that ad its impression entirely.
    unawaited(
      controller.loadRequest(Uri.parse(ad.creativeUrl)).catchError((Object _) {
        // A creative URL the platform cannot parse or reach never raises a load
        // event, so it is failed here rather than left to hang until the next
        // refresh.
        _onCreativeFailed();
      }),
    );
  }

  /// Builds the web view controller the creatives render in.
  WebViewController _buildWebViewController() {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _onCreativeLoaded(),
          onWebResourceError: (error) {
            // Main frame only, which is what Android's onReceivedError covers. A
            // sub-resource inside a creative that is otherwise fine must not
            // discard a real fill.
            if (error.isForMainFrame ?? true) {
              _onCreativeFailed();
            }
          },
        ),
      );
  }

  /// The creative finished rendering.
  ///
  /// This is when an impression becomes owed, so it is attempted here and again
  /// on any later visibility change. Mirrors `AaZoneView.onAdLoadedInWebView`.
  void _onCreativeLoaded() {
    final ad = _currentAd;

    if (ad == null || _creativeLoaded || _creativeSettleTimer != null) {
      return;
    }

    // A load event is not proof the creative rendered. Android's WebViewClient
    // reports a finished page for a load that failed, so acting on that first
    // event would bill an impression and fire the creative's tracking pixels for
    // an ad that had failed, and leave the real error a no-op because the flag
    // was already set. Both events arrive in one turn, so settling on a timer
    // gives an error that is coming the chance to cancel this first.
    //
    // The ad is captured, because this fires a task later and it can be replaced
    // in between: a response resolving in the same turn runs [_displayAd] first,
    // as a microtask beats a timer. Without this check the settle lands on the
    // new ad, billing an impression for a creative that has not rendered and
    // swallowing its later load and failure events alike.
    final settlingAd = ad;

    _creativeSettleTimer = Timer(Duration.zero, () {
      _creativeSettleTimer = null;

      if (_currentAd == null ||
          !identical(_currentAd, settlingAd) ||
          _creativeLoaded) {
        return;
      }

      _creativeLoaded = true;

      widget.onAdLoaded?.call();

      _trackImpression();
    });
  }

  /// The creative could not be rendered.
  ///
  /// An ad was served, so this is neither a no-fill nor a failed request:
  /// Android reports it as its own reason and drops the ad, keeping the refresh
  /// time so the zone tries again on schedule. Mirrors
  /// `AdZonePresenter.onAdDisplayFailed`.
  void _onCreativeFailed() {
    if (_currentAd == null || _creativeLoaded) {
      return;
    }

    // Cancels the load event that precedes this one, which is the whole reason
    // the settle above is deferred.
    _cancelCreativeSettle();

    // Marked handled so a later load event for the same ad cannot file an
    // impression for a creative that already failed.
    _creativeLoaded = true;

    // onAdLoadFailed is left to [_displayAd] below, which reports it for every
    // outcome leaving the zone without an ad. Calling it here as well fires it
    // twice for a single failure.
    _reportUnfilled(ZoneUnfilledReason.renderFailed);
    _displayAd(null, refreshSecondsOverride: _refreshSeconds);
  }

  /// Sets the ad on screen and rebuilds.
  /// @param ad - The ad to display, or null to clear the zone.
  void _setCurrentAd(Ad? ad) {
    if (identical(_currentAd, ad)) {
      return;
    }

    _currentAd = ad;

    if (ad != null && ad.creativeUrl.isNotEmpty) {
      _loadCreative(ad);
    }

    if (_isMounted && mounted) {
      setState(() {});
    }
  }

  // ===========================================================================
  // INTERACTION
  // ===========================================================================

  /// The touch drag distance below which a touch counts as a tap.
  double get _dragDistanceAllowed {
    return widget.xyDragDistanceAllowed ??
        AdRequestContextRegistry.context?.xyDragDistanceAllowed ??
        defaultXyDragDistanceAllowed;
  }

  /// Handles the user selecting the ad zone.
  /// @param selectedAd - The ad that was selected.
  void _onAdZoneSelected(Ad selectedAd) {
    // The zone keeps showing this ad until its replacement arrives, so the touch
    // target stays live and a second tap would report a second click against the
    // same impression.
    if (_clickHandled) {
      return;
    }

    final context = AdRequestContextRegistry.context;

    var wasHandled = false;

    if (selectedAd.actionType == AdActionType.external &&
        selectedAd.actionPath.isNotEmpty) {
      wasHandled = true;

      _reportEvent(ReportedEventType.interaction, ad: selectedAd);

      // Fails when the platform has no handler for the URL, which is the ad's
      // content rather than anything the SDK controls. The interaction above is
      // already reported, so this only needs to not surface as an unhandled
      // error.
      unawaited(
        launchUrl(
          Uri.parse(selectedAd.actionPath),
          mode: LaunchMode.externalApplication,
        ).catchError((Object error) {
          debugPrint(
            'Unable to open the URL for ad "${selectedAd.id}". $error',
          );

          return false;
        }),
      );
    } else if (selectedAd.actionType == AdActionType.content &&
        selectedAd.payload.detailedListItems != null) {
      wasHandled = true;

      final items = selectedAd.payload.detailedListItems!;

      // An "add to list" click reports no interaction yet. The items have only
      // been offered at this point, and the interaction is earned when the host
      // app confirms they reached the list, through
      // AdadaptedFlutterSdk.acknowledge. Android splits it the same way:
      // atl_ad_clicked here, trackInteraction in AdContent.acknowledge.
      context?.reportSdkEvent(SdkEventName.atlAdClicked, <String, String>{
        'id': selectedAd.id,
      });

      context?.setPendingAtlContent(
        PendingAtlContent(
          adId: selectedAd.id,
          zoneId: widget.zoneId,
          impressionId: selectedAd.impressionId,
          items: items,
        ),
      );

      if (widget.onAddToListTriggered != null) {
        widget.onAddToListTriggered!(items);
      } else {
        // No handler on this zone, so fall back to the one the host gave
        // initialize().
        context?.forwardAddToList(items);
      }
    }

    if (!wasHandled) {
      // An action type this SDK cannot handle must not cost the zone its ad.
      return;
    }

    _clickHandled = true;

    _loadNextAd();
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final ad = _currentAd;
    final controller = _webViewController;

    // With no ad to display the zone takes up no space.
    if (ad == null || ad.creativeUrl.isEmpty || controller == null) {
      return _wrapWithVisibilityDetector(const SizedBox.shrink());
    }

    return _wrapWithVisibilityDetector(
      SizedBox(
        width: widget.width,
        height: widget.height,
        // Expanded, because every child below is positioned. A stack with no
        // unpositioned child sizes itself as small as its constraints allow, so
        // under the loose constraints of a Column or a Center the whole zone
        // would collapse to nothing and render an ad no one can see.
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Positioned.fill(
              child: Listener(
                // Opaque, so the zone registers the touch itself rather than
                // relying on the creative to be hit-testable. A transparent
                // creative, or a platform view that has not attached yet, would
                // otherwise leave the whole zone untappable.
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  _touchStart = event.position;
                },
                onPointerUp: (event) {
                  final touchStart = _touchStart;

                  _touchStart = null;

                  if (touchStart == null) {
                    return;
                  }

                  if ((touchStart.dx - event.position.dx).abs() <
                          _dragDistanceAllowed &&
                      (touchStart.dy - event.position.dy).abs() <
                          _dragDistanceAllowed) {
                    _onAdZoneSelected(ad);
                  }
                },
                onPointerCancel: (_) {
                  _touchStart = null;
                },
                child: WebViewWidget(controller: controller),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: ReportAdButton(
                adId: ad.id,
                udid: AdRequestContextRegistry.context?.udid ?? '',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Wraps the zone in the detector that measures its visibility, unless the
  /// host is driving visibility itself.
  /// @param child - The zone's content.
  Widget _wrapWithVisibilityDetector(Widget child) {
    if (widget.isVisible != null) {
      return child;
    }

    return VisibilityDetector(
      // Unique per state object, which is what the detector requires. The zone
      // ID alone is not enough: a host may legitimately place two widgets for
      // one zone, and identical keys make the detector drop one of them.
      key: ValueKey<String>(
        'adadapted-ad-zone-${widget.zoneId}-${identityHashCode(this)}',
      ),
      onVisibilityChanged: _onVisibilityInfo,
      child: child,
    );
  }
}
