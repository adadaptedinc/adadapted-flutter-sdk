/// The AdAdapted Flutter SDK.
///
/// A host creates one [AdadaptedFlutterSdk], calls
/// [AdadaptedFlutterSdk.initialize] once, places an [AdZone] for each zone it
/// has been allocated, and calls [AdadaptedFlutterSdk.unmount] when it is
/// finished.
library;

export 'src/adadapted_flutter_sdk.dart'
    show AdadaptedFlutterSdk, KeywordSearchResult;
export 'src/api/adadapted_api_types.dart'
    show
        Ad,
        AdActionType,
        AdPayload,
        DetailedListItem,
        KeywordIntercepts,
        KeywordSearchTerm,
        ListManagerEventName,
        OutOfAppDataPayload,
        PayloadStatus,
        ReportedEventType,
        SdkEventName,
        Zone,
        ZoneUnfilledReason;
export 'src/component_types/device.dart' show DeviceInfo, DeviceOS;
export 'src/component_types/environment.dart'
    show ApiEnv, ListManagerApiEnv, PayloadApiEnv;
export 'src/components/ad_zone.dart'
    show
        AdZone,
        defaultAdRefreshSeconds,
        defaultXyDragDistanceAllowed,
        minimumAdRefreshSeconds;
