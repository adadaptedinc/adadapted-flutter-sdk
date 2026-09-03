import AdSupport
import AppTrackingTransparency
import CoreTelephony
import Flutter
import UIKit

/// Gathers the device info the SDK reports with every event.
///
/// A port of the React Native SDK's `AdadaptedReactNativeSdk` module. The values here have
/// no Dart-only equivalent, which is why this package ships native code at all.
public class AdadaptedFlutterSdkPlugin: NSObject, FlutterPlugin {
    /// Must match the channel name the Dart side invokes.
    private static let channelName = "com.adadapted.flutter_sdk/device_info"

    /// The carrier reported when the device has none.
    private static let unknownCarrier = "n/a"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )

        registrar.addMethodCallDelegate(AdadaptedFlutterSdkPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "getDeviceInfo" else {
            result(FlutterMethodNotImplemented)

            return
        }

        result(gatherDeviceInfo())
    }

    /// Collects everything the API wants to know about this device.
    private func gatherDeviceInfo() -> [String: Any] {
        let screenBounds = UIScreen.main.bounds
        let screenScale = UIScreen.main.scale
        let screenWidth = screenBounds.size.width * screenScale
        let screenHeight = screenBounds.size.height * screenScale

        let device = UIDevice.current
        let bundle = Bundle.main

        return [
            "udid": identifierForAdvertising(),
            "deviceName": device.model,
            // The platform suffix is how reporting tells a Flutter integration from a
            // React Native one. It must not be changed without the API being told.
            "systemName": "ios_flutter",
            "systemVersion": device.systemVersion,
            "deviceCarrier": carrierName(),
            "deviceModel": device.model,
            "deviceWidth": String(format: "%1.0f", screenWidth),
            "deviceHeight": String(format: "%1.0f", screenHeight),
            "deviceScreenDensity": String(format: "%0.0f", screenScale),
            "deviceLocale": Locale.preferredLanguages.first ?? "",
            "bundleId": bundle.bundleIdentifier ?? "",
            "bundleVersion": bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "deviceTimezone": TimeZone.current.identifier,
            "isAdTrackingEnabled": isAdTrackingEnabled(),
        ]
    }

    /// The device's cellular carrier, or `n/a` when there is none.
    ///
    /// `serviceSubscriberCellularProviders` is deprecated from iOS 16 and Apple has said
    /// it will return `--` rather than a real name, so a missing or empty value is normal
    /// and is reported as `n/a`. Whatever it does return is forwarded as-is, placeholder
    /// included, because the native iOS and React Native SDKs do the same and reporting
    /// has to be able to compare iOS traffic across all three.
    private func carrierName() -> String {
        let networkInfo = CTTelephonyNetworkInfo()

        guard
            let carrier = networkInfo.serviceSubscriberCellularProviders?.values.first(where: {
                !($0.carrierName ?? "").isEmpty
            }),
            let name = carrier.carrierName,
            !name.isEmpty
        else {
            return Self.unknownCarrier
        }

        return name
    }

    /// Whether the user has permitted ad tracking.
    ///
    /// Via App Tracking Transparency, not `ASIdentifierManager` directly: Apple made
    /// `isAdvertisingTrackingEnabled` always return false from iOS 14, so reading it
    /// reports every user as having refused tracking, including those who granted it. This
    /// is the same signal that decides whether an advertising identifier is reported, so
    /// the two must agree.
    private func isAdTrackingEnabled() -> Bool {
        if #available(iOS 14, *) {
            return ATTrackingManager.trackingAuthorizationStatus == .authorized
        }

        return ASIdentifierManager.shared().isAdvertisingTrackingEnabled
    }

    /// The advertising identifier, or an empty string when tracking is not permitted.
    ///
    /// Nothing is substituted when the user has not permitted tracking. This matches the
    /// Android side, which leaves the identifier empty when the advertising ID is
    /// unavailable rather than reporting something else. `identifierForVendor` in
    /// particular is deliberately not used: it is stable and needs no prompt, but it is
    /// shared across this vendor's apps, and sending it to an ad service after tracking
    /// was denied is the sort of linkage App Tracking Transparency exists to prevent.
    private func identifierForAdvertising() -> String {
        guard isAdTrackingEnabled() else {
            return ""
        }

        return ASIdentifierManager.shared().advertisingIdentifier.uuidString
    }
}
