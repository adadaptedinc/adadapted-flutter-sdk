package com.adadapted.flutter_sdk

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.telephony.TelephonyManager
import android.util.DisplayMetrics
import android.util.Log
import com.google.android.gms.ads.identifier.AdvertisingIdClient
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors

/**
 * Gathers the device info the SDK reports with every event.
 *
 * A port of the React Native SDK's AdadaptedReactNativeSdkModule. The values here have no
 * Dart-only equivalent, which is why this package ships native code at all.
 */
class AdadaptedFlutterSdkPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context

    /**
     * Off the main thread, because AdvertisingIdClient.getAdvertisingIdInfo blocks on a
     * binder call to Play Services and throws IllegalStateException outright when called
     * from the main thread. The React Native module got away with running inline only
     * because the bridge already called it from a background thread; a Flutter method call
     * arrives on the platform thread, which is the main thread.
     */
    private val executor = Executors.newSingleThreadExecutor()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "getDeviceInfo") {
            result.notImplemented()

            return
        }

        executor.execute {
            val deviceInfo = gatherDeviceInfo()

            // Results must be delivered on the main thread, which is not the thread the
            // advertising ID was gathered on.
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                result.success(deviceInfo)
            }
        }
    }

    /**
     * Collects everything the API wants to know about this device.
     */
    private fun gatherDeviceInfo(): Map<String, Any> {
        val displayMetrics: DisplayMetrics = applicationContext.resources.displayMetrics

        var gaid = ""
        var adTrackingEnabled = false
        var deviceCarrier = UNKNOWN_CARRIER
        var bundleVersion: String

        val telephonyManager =
            applicationContext.getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager

        if (telephonyManager?.networkOperatorName != null) {
            deviceCarrier = telephonyManager.networkOperatorName
        }

        try {
            val gaidInfo = AdvertisingIdClient.getAdvertisingIdInfo(applicationContext)

            gaid = gaidInfo.id ?: ""
            adTrackingEnabled = !gaidInfo.isLimitAdTrackingEnabled
        } catch (ex: Exception) {
            // Play Services missing, out of date, or unavailable on this device. The
            // identifier is left empty rather than substituted, which is the same choice
            // the iOS side makes when tracking has not been permitted.
            Log.w(TAG, "Problem retrieving Google Play Advertiser Info", ex)
        }

        bundleVersion = try {
            val packageInfo: PackageInfo =
                applicationContext.packageManager.getPackageInfo(applicationContext.packageName, 0)

            // versionName is @Nullable on newer platform SDKs, so fall back to the same
            // value the NameNotFoundException branch reports rather than letting a null
            // reach the device payload.
            packageInfo.versionName ?: UNKNOWN_VALUE
        } catch (ex: PackageManager.NameNotFoundException) {
            UNKNOWN_VALUE
        }

        return mapOf(
            "udid" to gaid,
            "deviceName" to android.os.Build.DEVICE,
            // The platform suffix is how reporting tells a Flutter integration from a
            // React Native one. It must not be changed without the API being told.
            "systemName" to "android_flutter",
            "systemVersion" to android.os.Build.VERSION.RELEASE,
            "deviceCarrier" to deviceCarrier,
            "deviceModel" to android.os.Build.MODEL,
            "deviceWidth" to displayMetrics.widthPixels.toString(),
            "deviceHeight" to displayMetrics.heightPixels.toString(),
            "deviceScreenDensity" to displayMetrics.density.toString(),
            "deviceLocale" to Locale.getDefault().toString(),
            "bundleId" to applicationContext.packageName,
            "bundleVersion" to bundleVersion,
            "deviceTimezone" to TimeZone.getDefault().id,
            "isAdTrackingEnabled" to adTrackingEnabled,
        )
    }

    private companion object {
        /** Must match the channel name the Dart side invokes. */
        const val CHANNEL_NAME = "com.adadapted.flutter_sdk/device_info"

        const val TAG = "AdadaptedFlutterSdk"
        const val UNKNOWN_VALUE = "Unknown"
        const val UNKNOWN_CARRIER = "n/a"
    }
}
