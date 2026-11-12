package com.carlos.data_usage_tracker

import android.Manifest
import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.app.usage.NetworkStatsManager
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.widget.RemoteViews
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale
import java.util.concurrent.Executors

internal enum class WidgetNetwork(
    val provider: Class<out AppWidgetProvider>,
    val layout: Int,
) {
    mobile(UsageWidget::class.java, R.layout.usage_widget),
    wifi(WifiUsageWidget::class.java, R.layout.wifi_widget),
    both(CombinedUsageWidget::class.java, R.layout.combined_widget);

    fun component(context: Context) = ComponentName(context, provider)
}

@Suppress("DEPRECATION")
internal object UsageMonitor {
    const val networkExtra = "widget_network"
    private const val jobId = 4307
    private const val channelId = "usage_alerts"
    val worker = Executors.newSingleThreadExecutor()

    fun preferences(context: Context) = context.getSharedPreferences("usage_features", Context.MODE_PRIVATE)

    fun hasAccess(context: Context): Boolean =
        context.getSystemService(AppOpsManager::class.java)?.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName
        ) == AppOpsManager.MODE_ALLOWED

    fun needsPhonePermission(context: Context) =
        Build.VERSION.SDK_INT < 29 &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY) &&
            context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED

    fun mobileSubscribers(context: Context): List<String?>? {
        if (Build.VERSION.SDK_INT >= 29) return listOf(null)
        if (!context.packageManager.hasSystemFeature(PackageManager.FEATURE_TELEPHONY)) return emptyList()
        if (needsPhonePermission(context)) return null
        val phone = context.getSystemService(TelephonyManager::class.java) ?: return null
        return try {
            val ids = mutableSetOf<String>()
            phone.subscriberId?.let(ids::add)
            context.getSystemService(SubscriptionManager::class.java)?.activeSubscriptionInfoList
                .orEmpty().forEach { subscription ->
                    phone.createForSubscriptionId(subscription.subscriptionId).subscriberId?.let(ids::add)
                }
            ids.toList().takeIf { it.isNotEmpty() }
        } catch (error: SecurityException) {
            null
        }
    }

    fun mobileTotal(context: Context, start: Long, end: Long, wholeDay: Boolean = false): Long? {
        val now = System.currentTimeMillis()
        val cutoff = if (wholeDay && start < now) end else minOf(end, now)
        val subscribers = mobileSubscribers(context) ?: return null
        if (cutoff <= start) return 0
        val manager = checkNotNull(context.getSystemService(NetworkStatsManager::class.java))
        return subscribers.sumOf {
            val bucket = checkNotNull(manager.querySummaryForDevice(
                ConnectivityManager.TYPE_MOBILE, it, start, cutoff
            ))
            bucket.rxBytes + bucket.txBytes
        }
    }

    fun widgetIds(context: Context): List<Int> {
        val manager = AppWidgetManager.getInstance(context)
        return WidgetNetwork.entries.flatMap { manager.getAppWidgetIds(it.component(context)).asList() }
    }

    fun pinWidget(context: Context, selection: String?): Boolean {
        if (Build.VERSION.SDK_INT < 26) return false
        val network = WidgetNetwork.entries.firstOrNull { it.name == selection } ?: return false
        val manager = AppWidgetManager.getInstance(context)
        if (!manager.isRequestPinAppWidgetSupported) return false
        val extras = Bundle().apply {
            putParcelable(AppWidgetManager.EXTRA_APPWIDGET_PREVIEW, RemoteViews(context.packageName, network.layout))
        }
        return manager.requestPinAppWidget(network.component(context), extras, null)
    }

    private fun config(context: Context) =
        JSONObject(preferences(context).getString("monitorSettings", null) ?: "{}")

    fun schedule(context: Context) {
        val settings = config(context)
        val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
        if (widgetIds(context).isEmpty() && !settings.optBoolean("thresholds") &&
            !settings.optBoolean("spikes")) {
            scheduler.cancel(jobId)
            return
        }
        if (scheduler.getPendingJob(jobId) == null) scheduler.schedule(
            JobInfo.Builder(jobId, ComponentName(context, UsageMonitorJob::class.java))
                .setPeriodic(15 * 60 * 1000L).setPersisted(true).build()
        )
    }

    private fun startOfDay() = Calendar.getInstance().apply {
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }

    private fun cycleStart(day: Calendar, renewal: Int): Long {
        val date = (day.clone() as Calendar).apply { set(Calendar.DAY_OF_MONTH, 1) }
        val currentRenewal = minOf(renewal, date.getActualMaximum(Calendar.DAY_OF_MONTH))
        if (day.get(Calendar.DAY_OF_MONTH) < currentRenewal) date.add(Calendar.MONTH, -1)
        date.set(Calendar.DAY_OF_MONTH, minOf(renewal, date.getActualMaximum(Calendar.DAY_OF_MONTH)))
        return date.timeInMillis
    }

    fun refresh(context: Context, notify: Boolean = false) {
        val settings = config(context)
        val limit = settings.optLong("limit").coerceAtLeast(0)
        val renewal = settings.optInt("renewal", 1).coerceIn(1, 31)
        val ar = preferences(context).getString("language", null) == "ar"
        val day = startOfDay()
        val now = System.currentTimeMillis()
        val tomorrow = (day.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, 1) }.timeInMillis
        val cycle = cycleStart(day, renewal)
        val allowed = hasAccess(context)
        val manager = AppWidgetManager.getInstance(context)
        val installed = WidgetNetwork.entries.associateWith { manager.getAppWidgetIds(it.component(context)) }
            .filterValues { it.isNotEmpty() }
        val mobileNeeded = notify || installed.keys.any { it != WidgetNetwork.wifi }
        val today = if (allowed && mobileNeeded) runCatching { mobileTotal(context, day.timeInMillis, tomorrow, wholeDay = true) }.getOrNull() else null
        val used = if (allowed && notify && settings.optBoolean("thresholds") && limit > 0) runCatching { mobileTotal(context, cycle, now) }.getOrNull() else null
        val wifi = if (allowed && installed.keys.any { it != WidgetNetwork.mobile }) runCatching {
            val stats = checkNotNull(context.getSystemService(NetworkStatsManager::class.java))
            val bucket = checkNotNull(stats.querySummaryForDevice(ConnectivityManager.TYPE_WIFI, null, day.timeInMillis, tomorrow))
            bucket.rxBytes + bucket.txBytes
        }.getOrNull() else null

        for ((network, ids) in installed) {
            val views = RemoteViews(context.packageName, network.layout)
            val wifiLabel = if (ar) "الواي فاي" else "Wi-Fi"
            val mobileLabel = if (ar) "داتا الموبايل" else "Mobile data"
            when (network) {
                WidgetNetwork.both -> {
                    views.setTextViewText(R.id.widget_wifi_usage, wifi?.let(::format) ?: "—")
                    views.setTextViewText(R.id.widget_mobile_usage, today?.let(::format) ?: "—")
                    views.setTextViewText(R.id.widget_wifi_title, wifiLabel)
                    views.setTextViewText(R.id.widget_mobile_title, mobileLabel)
                }
                WidgetNetwork.mobile, WidgetNetwork.wifi -> {
                    val isWifi = network == WidgetNetwork.wifi
                    val bytes = if (isWifi) wifi else today
                    views.setTextViewText(R.id.widget_today, bytes?.let(::format) ?: "—")
                    views.setTextViewText(R.id.widget_title, if (isWifi) wifiLabel else mobileLabel)
                }
            }
            views.setOnClickPendingIntent(R.id.widget_container, appIntent(context, network))
            manager.updateAppWidget(ids, views)
        }
        if (!notify || !allowed || !canNotify(context)) return
        val prefs = preferences(context)
        if (settings.optBoolean("thresholds") && used != null) {
            val percent = listOf(100, 80, 50).firstOrNull { used >= limit * it / 100 }
            if (percent != null) {
                val key = "threshold:$cycle:$limit:$renewal"
                val last = if (prefs.getString("thresholdKey", "") == key)
                    prefs.getInt("thresholdLevel", 0) else 0
                if (percent > last) {
                    val message = if (ar) "استهلكت ${percent}٪ من باقة الموبايل." else "You reached $percent% of your mobile data plan."
                    send(context, 4311, message, ar)
                    prefs.edit().putString("thresholdKey", key).putInt("thresholdLevel", percent).apply()
                }
            }
        }
        if (settings.optBoolean("spikes") && today != null &&
            prefs.getLong("spikeDay", 0) != day.timeInMillis) {
            val prior = (day.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, -7) }
            val baseline = mobileTotal(context, prior.timeInMillis, day.timeInMillis)?.div(7)
            if (baseline != null && today >= 100_000_000 && today > baseline * 2) {
                val message = if (ar) "استهلاك الداتا اليوم ${format(today)}، أعلى من المعتاد."
                    else "Today's mobile data use is above your usual level (${format(today)})."
                send(context, 4312, message, ar)
                prefs.edit().putLong("spikeDay", day.timeInMillis).apply()
            }
        }
    }

    private fun canNotify(context: Context) =
        (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED) &&
            context.getSystemService(NotificationManager::class.java)?.areNotificationsEnabled() == true

    private fun appIntent(context: Context, network: WidgetNetwork? = null) = PendingIntent.getActivity(
        context, (network?.ordinal ?: -1) + 1, Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            network?.let { putExtra(networkExtra, it.name) }
        }, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )

    private fun send(context: Context, id: Int, message: String, ar: Boolean) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val label = if (ar) "تنبيهات استهلاك الداتا" else "Data usage alerts"
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(channelId, label, NotificationManager.IMPORTANCE_DEFAULT))
            Notification.Builder(context, channelId)
        } else Notification.Builder(context)
        manager.notify(id, builder.setSmallIcon(android.R.drawable.stat_notify_sync_noanim)
            .setContentTitle(label).setContentText(message).setContentIntent(appIntent(context))
            .setAutoCancel(true).build())
    }

    private fun format(bytes: Long) = when {
        bytes >= 1_000_000_000 -> String.format(Locale.ROOT, "%.2f GB", bytes / 1e9)
        bytes >= 1_000_000 -> String.format(Locale.ROOT, "%.1f MB", bytes / 1e6)
        bytes >= 1000 -> String.format(Locale.ROOT, "%.0f KB", bytes / 1e3)
        else -> "$bytes B"
    }
}

open class UsageWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        UsageMonitor.schedule(context)
        val pending = goAsync()
        UsageMonitor.worker.execute {
            try { UsageMonitor.refresh(context) } finally { pending.finish() }
        }
    }

    override fun onDisabled(context: Context) = UsageMonitor.schedule(context)
}

class WifiUsageWidget : UsageWidget()

class CombinedUsageWidget : UsageWidget()

class UsageMonitorJob : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        UsageMonitor.worker.execute {
            try {
                UsageMonitor.refresh(this, notify = true)
            } catch (_: Exception) {
                // A permission or subscriber can change while the background job is running.
            } finally {
                jobFinished(params, false)
            }
        }
        return true
    }

    override fun onStopJob(params: JobParameters) = false
}
