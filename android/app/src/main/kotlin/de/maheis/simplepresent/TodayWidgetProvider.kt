package be.heister.simplepresent

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

class TodayWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == ACTION_REFRESH_WIDGET) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(
                ComponentName(context, TodayWidgetProvider::class.java)
            )
            for (id in ids) {
                updateWidget(context, appWidgetManager, id)
            }
            appWidgetManager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
        }
    }

    companion object {
        const val ACTION_REFRESH_WIDGET = "be.heister.simplepresent.ACTION_REFRESH_WIDGET"
        const val EXTRA_ITEM_LAYOUT = "widget_item_layout"

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val family = readConfiguredFontFamily(context)
            val rootLayout = when (family) {
                "NotoSans" -> R.layout.today_widget_noto_sans
                "CourierPrime" -> R.layout.today_widget_courier_prime
                else -> R.layout.today_widget
            }
            val itemLayout = when (family) {
                "NotoSans" -> R.layout.today_widget_item_noto_sans
                "CourierPrime" -> R.layout.today_widget_item_courier_prime
                else -> R.layout.today_widget_item
            }

            val views = RemoteViews(context.packageName, rootLayout)

            val serviceIntent = Intent(context, TodayWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                putExtra(EXTRA_ITEM_LAYOUT, itemLayout)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.widget_list, serviceIntent)
            views.setEmptyView(R.id.widget_list, R.id.widget_empty)

            val openAppIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val openAppPending = PendingIntent.getActivity(
                context,
                appWidgetId,
                openAppIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            views.setOnClickPendingIntent(R.id.widget_header, openAppPending)

            val templateIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val templatePendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId + 10000,
                templateIntent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            views.setPendingIntentTemplate(R.id.widget_list, templatePendingIntent)
            views.setOnClickPendingIntent(R.id.widget_header, openAppPending)

            appWidgetManager.updateAppWidget(appWidgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_list)
        }

        private fun readConfiguredFontFamily(context: Context): String {
            return try {
                val appFlutter = java.io.File(context.filesDir.parentFile, "app_flutter")
                val debugMode = (context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
                val folderName = if (debugMode) "simplepresent-debug" else "simplepresent"
                val prefix = if (debugMode) "debug_" else ""
                val settingsFile = java.io.File(
                    java.io.File(appFlutter, folderName),
                    "${prefix}simplepresent_settings.json"
                )
                if (!settingsFile.exists()) return "OpenDyslexic"
                val text = settingsFile.readText()
                val obj = org.json.JSONObject(text)
                obj.optString("fontFamily", "OpenDyslexic")
            } catch (_: Exception) {
                "OpenDyslexic"
            }
        }
    }
}
