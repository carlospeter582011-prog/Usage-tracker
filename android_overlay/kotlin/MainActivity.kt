package com.carlos.data_usage_tracker

import android.Manifest
import android.app.AppOpsManager
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.util.LruCache
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

@Suppress("DEPRECATION")
class MainActivity : FlutterActivity() {
    private var phonePermissionResult: MethodChannel.Result? = null
    private val phonePermissionCode = 107
    private val worker = Executors.newSingleThreadExecutor()
    private val icons = object : LruCache<String, ByteArray>(2 * 1024 * 1024) {
        override fun sizeOf(key: String, value: ByteArray) = value.size
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "data_usage_tracker/usage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAccess" -> result.success(hasAccess())
                    "needsPhonePermission" -> result.success(needsPhonePermission())
                    "requestPhonePermission" -> requestPhonePermission(result)
                    "openSettings" -> {
                        try {
                            startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("settings", "Could not open Usage access settings.", null)
                        }
                    }
                    "daily", "weekly" -> {
                        val bounds = call.argument<List<Number>>("bounds")
                            ?.map { it.toLong() }
                        val expected = if (call.method == "daily") 2 else 8
                        if (bounds == null || bounds.size != expected ||
                            bounds.zipWithNext().any { (start, end) -> end <= start }
                        ) {
                            result.error("range", "Invalid date range.", null)
                        } else {
                            inBackground(result) {
                                if (!hasAccess()) throw SecurityException()
                                if (expected == 2) daily(bounds[0], bounds[1])
                                else weekly(bounds)
                            }
                        }
                    }
                    "icon" -> {
                        val name = call.argument<String>("package")
                        if (name.isNullOrBlank()) result.success(null)
                        else inBackground(result) { appIcon(name) }
                    }
                    "goal" -> result.success(
                        getPreferences(MODE_PRIVATE).getLong("mobileGoal", 0L)
                    )
                    "saveGoal" -> {
                        val bytes = call.argument<Number>("bytes")?.toLong() ?: -1L
                        if (bytes < 0L) result.error("goal", "Invalid weekly limit.", null)
                        else inBackground(result) {
                            check(getPreferences(MODE_PRIVATE).edit().putLong("mobileGoal", bytes).commit())
                            null
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun inBackground(result: MethodChannel.Result, action: () -> Any?) {
        worker.execute {
            try {
                val data = action()
                runOnUiThread { result.success(data) }
            } catch (error: SecurityException) {
                runOnUiThread { result.error("permission", "Enable Usage access to read network statistics.", null) }
            } catch (error: Exception) {
                runOnUiThread { result.error("unavailable", "Android could not load this information. Try again.", null) }
            }
        }
    }

    private fun hasAccess(): Boolean {
        val ops = checkNotNull(getSystemService(AppOpsManager::class.java))
        return ops.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName
        ) == AppOpsManager.MODE_ALLOWED
    }

    private fun needsPhonePermission(): Boolean =
        Build.VERSION.SDK_INT < 29 &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY) &&
            checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED

    private fun requestPhonePermission(result: MethodChannel.Result) {
        if (!needsPhonePermission() || phonePermissionResult != null) {
            result.success(null)
            return
        }
        val permission = Manifest.permission.READ_PHONE_STATE
        val prefs = getPreferences(MODE_PRIVATE)
        if (prefs.getBoolean("askedForPhonePermission", false) &&
            !shouldShowRequestPermissionRationale(permission)
        ) {
            try {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", packageName, null)))
                result.success(null)
            } catch (error: Exception) {
                result.error("settings", "Could not open app permission settings.", null)
            }
            return
        }
        prefs.edit().putBoolean("askedForPhonePermission", true).apply()
        phonePermissionResult = result
        requestPermissions(arrayOf(permission), phonePermissionCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == phonePermissionCode) {
            phonePermissionResult?.success(null)
            phonePermissionResult = null
        }
    }

    // Android 10+ accepts null for all mobile networks. Older versions require
    // the identifiers of the SIMs whose usage is being queried.
    private fun mobileSubscribers(): List<String?>? {
        if (Build.VERSION.SDK_INT >= 29) return listOf(null)
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)) return emptyList()
        if (needsPhonePermission()) return null
        val phone = getSystemService(TelephonyManager::class.java) ?: return null
        return try {
            val ids = mutableSetOf<String>()
            phone.subscriberId?.let(ids::add)
            if (Build.VERSION.SDK_INT >= 24) {
                val subscriptions = getSystemService(SubscriptionManager::class.java)
                subscriptions?.activeSubscriptionInfoList.orEmpty().forEach { subscription ->
                    phone.createForSubscriptionId(subscription.subscriptionId).subscriberId
                        ?.let(ids::add)
                }
            }
            ids.toList().takeIf { it.isNotEmpty() }
        } catch (error: SecurityException) {
            null
        }
    }

    private fun daily(start: Long, end: Long): Map<String, Any?> {
        val manager = checkNotNull(getSystemService(NetworkStatsManager::class.java))
        val cutoff = minOf(end, System.currentTimeMillis())
        val packages = mutableMapOf<Int, Pair<String, String?>>()
        val mobile = mobileSubscribers()?.let { subscribers ->
            dayNetwork(manager, ConnectivityManager.TYPE_MOBILE, subscribers, start, cutoff, packages)
        }
        return mapOf(
            "mobile" to mobile,
            "wifi" to dayNetwork(manager, ConnectivityManager.TYPE_WIFI, listOf(null), start, cutoff, packages)
        )
    }

    private fun weekly(bounds: List<Long>): List<Map<String, Long?>?> {
        val manager = checkNotNull(getSystemService(NetworkStatsManager::class.java))
        val now = System.currentTimeMillis()
        val subscribers = mobileSubscribers()
        return bounds.zipWithNext { start, end ->
            val cutoff = minOf(end, now)
            if (start >= now) null
            else mapOf(
                "mobile" to subscribers?.sumOf { total(manager, ConnectivityManager.TYPE_MOBILE, it, start, cutoff) },
                "wifi" to total(manager, ConnectivityManager.TYPE_WIFI, null, start, cutoff)
            )
        }
    }

    private fun total(
        manager: NetworkStatsManager, type: Int, subscriber: String?, start: Long, end: Long
    ): Long {
        if (end <= start) return 0
        val bucket = checkNotNull(manager.querySummaryForDevice(type, subscriber, start, end))
        return bucket.rxBytes + bucket.txBytes
    }

    private fun dayNetwork(
        manager: NetworkStatsManager,
        type: Int,
        subscribers: List<String?>,
        start: Long,
        end: Long,
        packages: MutableMap<Int, Pair<String, String?>>
    ): Map<String, Any> {
        val deviceTotal = subscribers.sumOf { total(manager, type, it, start, end) }
        val bytesByUid = mutableMapOf<Int, Long>()
        if (end > start) for (subscriber in subscribers) {
            checkNotNull(manager.querySummary(type, subscriber, start, end)).use { stats ->
                val bucket = NetworkStats.Bucket()
                while (stats.hasNextBucket() && stats.getNextBucket(bucket)) {
                    val bytes = bucket.rxBytes + bucket.txBytes
                    if (bytes > 0L) bytesByUid[bucket.uid] = (bytesByUid[bucket.uid] ?: 0L) + bytes
                }
            }
        }
        val apps = bytesByUid.entries
            .sortedWith(compareByDescending<Map.Entry<Int, Long>> { it.value }.thenBy { it.key })
            .map { (uid, bytes) ->
                val (name, packageNames) = packages.getOrPut(uid) { appDetails(uid) }
                mapOf("name" to name, "package" to packageNames, "bytes" to bytes)
            }
        return mapOf("total" to deviceTotal, "apps" to apps)
    }

    private fun appDetails(uid: Int): Pair<String, String?> {
        val names = packageManager.getPackagesForUid(uid).orEmpty().sorted()
        if (names.size > 1) return "Shared Android UID" to names.joinToString(", ")
        val name = names.singleOrNull()
        if (name == null) return when (uid) {
            -4 -> "Removed apps" to null
            -5 -> "Tethering" to null
            1000 -> "Android system" to null
            else -> "Android UID $uid" to null
        }
        val label = try {
            packageManager.getApplicationInfo(name, 0).loadLabel(packageManager).toString()
        } catch (error: PackageManager.NameNotFoundException) {
            name
        }
        return label to name
    }

    private fun appIcon(name: String): ByteArray? {
        icons.get(name)?.let { return it }
        val icon = try {
            packageManager.getApplicationIcon(name)
        } catch (error: PackageManager.NameNotFoundException) {
            return null
        }
        val bitmap = Bitmap.createBitmap(72, 72, Bitmap.Config.ARGB_8888)
        return try {
            icon.setBounds(0, 0, bitmap.width, bitmap.height)
            icon.draw(Canvas(bitmap))
            ByteArrayOutputStream().use { output ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                output.toByteArray().also { icons.put(name, it) }
            }
        } finally {
            bitmap.recycle()
        }
    }

    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }
}
