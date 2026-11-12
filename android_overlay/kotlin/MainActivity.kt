package com.carlos.data_usage_tracker

import android.Manifest
import android.app.Activity
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.LruCache
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

@Suppress("DEPRECATION")
class MainActivity : FlutterActivity() {
    companion object {
        private var launchClaimed = false
    }

    private var csvExport: Pair<String, MethodChannel.Result>? = null
    private var notificationPermission: MethodChannel.Result? = null
    private var phonePermissionResult: MethodChannel.Result? = null
    private val phonePermissionCode = 107
    private val worker = Executors.newSingleThreadExecutor()
    private val icons = object : LruCache<String, ByteArray>(2 * 1024 * 1024) {
        override fun sizeOf(key: String, value: ByteArray) = value.size
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "data_usage_tracker/usage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAccess" -> result.success(UsageMonitor.hasAccess(this))
                    "language", "monitorSettings" -> result.success(
                        UsageMonitor.preferences(this).getString(call.method, null)
                    )
                    "saveLanguage", "saveMonitorSettings" -> {
                        val key = if (call.method == "saveLanguage") "language" else "monitorSettings"
                        val value = call.argument<String>("value")
                        inBackground(result) {
                            check(UsageMonitor.preferences(this).edit().putString(key, value).commit())
                            if (key == "monitorSettings") UsageMonitor.schedule(this)
                            if (UsageMonitor.widgetIds(this).isNotEmpty()) UsageMonitor.refresh(this)
                            null
                        }
                    }
                    "pinWidget" -> result.success(UsageMonitor.pinWidget(this, call.argument<String>("network")))
                    "widgetNetwork" -> {
                        val network = intent.getStringExtra(UsageMonitor.networkExtra)
                        intent.removeExtra(UsageMonitor.networkExtra)
                        result.success(network)
                    }
                    "widgetInstalled" -> result.success(UsageMonitor.widgetIds(this).isNotEmpty())
                    "notificationPermission" -> {
                        if (Build.VERSION.SDK_INT < 33 ||
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                            PackageManager.PERMISSION_GRANTED
                        ) result.success(true)
                        else if (notificationPermission != null) result.success(false)
                        else {
                            notificationPermission = result
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 108)
                        }
                    }
                    "exportCsv" -> {
                        val csv = call.argument<String>("csv")
                        if (csv == null || csvExport != null) result.success(false)
                        else {
                            csvExport = csv to result
                            try {
                                startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                    type = "text/csv"
                                    addCategory(Intent.CATEGORY_OPENABLE)
                                    putExtra(Intent.EXTRA_TITLE, "data-usage.csv")
                                }, 109)
                            } catch (error: Exception) {
                                csvExport = null
                                result.error("export", "Could not open the file picker.", null)
                            }
                        }
                    }
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
                    "daily", "weekly", "monthly", "appHistory", "mobileTotal" -> {
                        val bounds = call.argument<List<Number>>("bounds")
                            ?.map { it.toLong() }
                        val expected = when (call.method) {
                            "daily", "mobileTotal" -> 2..2
                            "appHistory" -> 2..32
                            "weekly" -> 8..8
                            else -> 29..32
                        }
                        if (bounds == null || bounds.size !in expected ||
                            bounds.zipWithNext().any { (start, end) -> end <= start }
                        ) {
                            result.error("range", "Invalid date range.", null)
                        } else {
                            inBackground(result) {
                                if (!UsageMonitor.hasAccess(this)) throw SecurityException()
                                when (call.method) {
                                    "daily" -> daily(bounds[0], bounds[1])
                                    "mobileTotal" -> UsageMonitor.mobileTotal(this, bounds[0], bounds[1])
                                    "appHistory" -> appHistory(bounds, checkNotNull(call.argument<Number>("uid")).toInt())
                                    else -> series(bounds)
                                }
                            }
                        }
                    }
                    "icon" -> {
                        val name = call.argument<String>("package")
                        if (name.isNullOrBlank()) result.success(null)
                        else inBackground(result) { appIcon(name) }
                    }
                    "returningLaunch" -> {
                        val preferences = getPreferences(MODE_PRIVATE)
                        val returning = !launchClaimed &&
                            preferences.getBoolean("launchedBefore", false)
                        launchClaimed = true
                        preferences.edit().putBoolean("launchedBefore", true).apply()
                        result.success(returning && UsageMonitor.hasAccess(this))
                    }
                    "appearance" -> result.success(
                        getPreferences(MODE_PRIVATE).getString("appearance", "system")
                    )
                    "saveAppearance" -> {
                        val mode = call.argument<String>("mode")
                        if (mode !in listOf("system", "light", "dark")) {
                            result.error("appearance", "Invalid appearance mode.", null)
                        } else inBackground(result) {
                            check(getPreferences(MODE_PRIVATE).edit().putString("appearance", mode).commit())
                            null
                        }
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

    private fun needsPhonePermission(): Boolean = UsageMonitor.needsPhonePermission(this)

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
        if (requestCode == 108) {
            notificationPermission?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            notificationPermission = null
        }
        if (requestCode == phonePermissionCode) {
            phonePermissionResult?.success(null)
            phonePermissionResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 109) return
        val (csv, result) = csvExport ?: return
        csvExport = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) result.success(false)
        else inBackground(result) {
            checkNotNull(contentResolver.openOutputStream(uri, "wt")).use { stream ->
                stream.write(csv.toByteArray(Charsets.UTF_8))
            }
            true
        }
    }

    private fun mobileSubscribers() = UsageMonitor.mobileSubscribers(this)

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

    private fun series(bounds: List<Long>): List<Map<String, Long?>?> {
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
        val apps = traffic(manager, type, subscribers, start, end).entries
            .sortedWith(compareByDescending<Map.Entry<Int, Traffic>> { it.value.total }.thenBy { it.key })
            .map { (uid, bytes) ->
                val (name, packageName) = packages.getOrPut(uid) { appDetails(uid) }
                val system = packageName?.let {
                    try {
                        val flags = packageManager.getApplicationInfo(it, 0).flags
                        flags and (android.content.pm.ApplicationInfo.FLAG_SYSTEM or
                            android.content.pm.ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
                    } catch (error: PackageManager.NameNotFoundException) {
                        false
                    }
                }
                mapOf("name" to name, "package" to packageName, "uid" to uid, "system" to system,
                    "bytes" to bytes.total, "rx" to bytes.rx, "tx" to bytes.tx)
            }
        return mapOf("total" to deviceTotal, "apps" to apps)
    }

    private data class Traffic(var rx: Long = 0, var tx: Long = 0) {
        val total get() = rx + tx
        fun asMap() = mapOf("rx" to rx, "tx" to tx)
    }

    private fun traffic(
        manager: NetworkStatsManager, type: Int, subscribers: List<String?>,
        start: Long, end: Long, onlyUid: Int? = null
    ): Map<Int, Traffic> {
        val totals = mutableMapOf<Int, Traffic>()
        if (end <= start) return totals
        for (subscriber in subscribers) {
            checkNotNull(manager.querySummary(type, subscriber, start, end)).use { stats ->
                val bucket = NetworkStats.Bucket()
                while (stats.hasNextBucket() && stats.getNextBucket(bucket)) {
                    if ((onlyUid == null || bucket.uid == onlyUid) && bucket.rxBytes + bucket.txBytes > 0) {
                        val count = totals.getOrPut(bucket.uid) { Traffic() }
                        count.rx += bucket.rxBytes
                        count.tx += bucket.txBytes
                    }
                }
            }
        }
        return totals
    }

    private fun appHistory(bounds: List<Long>, uid: Int): List<Map<String, Any?>> {
        val manager = checkNotNull(getSystemService(NetworkStatsManager::class.java))
        val now = System.currentTimeMillis()
        val mobile = mobileSubscribers()
        return bounds.zipWithNext { start, end ->
            val cutoff = minOf(end, now)
            val wifiTraffic = traffic(manager, ConnectivityManager.TYPE_WIFI, listOf(null), start, cutoff, uid)[uid]
            val mobileTraffic = mobile?.let {
                traffic(manager, ConnectivityManager.TYPE_MOBILE, it, start, cutoff, uid)[uid] ?: Traffic()
            }
            mapOf("wifi" to (wifiTraffic ?: Traffic()).asMap(), "mobile" to mobileTraffic?.asMap())
        }
    }

    private fun appDetails(uid: Int): Pair<String, String?> {
        val names = packageManager.getPackagesForUid(uid).orEmpty().sorted()
        if (names.size > 1) {
            val representative = names.firstOrNull { packageManager.getLaunchIntentForPackage(it) != null }
                ?: names.first()
            return "Shared Android UID" to representative
        }
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
