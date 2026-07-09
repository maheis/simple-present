package be.heister.simplepresent

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
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
            // create a short-lived flag file to indicate refreshing state
            try {
                val flag = java.io.File(context.filesDir, "widget_refreshing")
                flag.writeText(System.currentTimeMillis().toString())
            } catch (_: Exception) {}
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val ids = appWidgetManager.getAppWidgetIds(
                ComponentName(context, TodayWidgetProvider::class.java)
            )
            for (id in ids) {
                updateWidget(context, appWidgetManager, id)
            }
            appWidgetManager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)

            // Clear the flag after a short delay and refresh widgets again so
            // the UI shows the transient refreshing state briefly.
            try {
                Thread {
                    try {
                        Thread.sleep(1800)
                        val flag = java.io.File(context.filesDir, "widget_refreshing")
                        if (flag.exists()) flag.delete()
                        val mgr = AppWidgetManager.getInstance(context)
                        val ids2 = mgr.getAppWidgetIds(
                            ComponentName(context, TodayWidgetProvider::class.java)
                        )
                        for (id2 in ids2) updateWidget(context, mgr, id2)
                        mgr.notifyAppWidgetViewDataChanged(ids2, R.id.widget_list)
                    } catch (_: Exception) {}
                }.start()
            } catch (_: Exception) {}
        }
    }

    companion object {
        const val ACTION_REFRESH_WIDGET = "be.heister.simplepresent.ACTION_REFRESH_WIDGET"
        const val EXTRA_ITEM_LAYOUT = "widget_item_layout"
        const val EXTRA_WIDGET_TEXT_WIDTH_PX = "widget_text_width_px"
        const val EXTRA_WIDGET_FONT_FAMILY = "widget_font_family"

        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int,
        ) {
            val family = readConfiguredFontFamily(context)
            val widgetOptions = appWidgetManager.getAppWidgetOptions(appWidgetId)
            val minWidthDp = widgetOptions.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 180)
            val metrics = context.resources.displayMetrics
            val totalWidthPx = (minWidthDp * metrics.density).toInt().coerceAtLeast(120)
            val textWidthPx = (totalWidthPx - (48 * metrics.density).toInt()).coerceAtLeast(96)
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
            views.setImageViewBitmap(
                R.id.widget_header_text,
                WidgetTextRenderer.renderTextBitmap(
                    context = context,
                    text = "today",
                    fontResId = fontResIdForFamily(family, bold = true),
                    textSizeSp = 16f,
                    textColor = Color.parseColor("#E6F5F0"),
                    maxWidthPx = textWidthPx,
                    bold = true,
                )
            )
            views.setImageViewBitmap(
                R.id.widget_empty,
                WidgetTextRenderer.renderTextBitmap(
                    context = context,
                    text = "no tasks",
                    fontResId = fontResIdForFamily(family, bold = false),
                    textSizeSp = 12f,
                    textColor = Color.parseColor("#A9C6BF"),
                    maxWidthPx = textWidthPx,
                    bold = false,
                )
            )

            val serviceIntent = Intent(context, TodayWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                putExtra(EXTRA_ITEM_LAYOUT, itemLayout)
                putExtra(EXTRA_WIDGET_FONT_FAMILY, family)
                putExtra(EXTRA_WIDGET_TEXT_WIDTH_PX, textWidthPx)
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
                action = "be.heister.simplepresent.ACTION_OPEN_FROM_WIDGET"
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val templatePendingIntent = PendingIntent.getActivity(
                context,
                appWidgetId + 10000,
                templateIntent,
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            views.setPendingIntentTemplate(R.id.widget_list, templatePendingIntent)
            views.setOnClickPendingIntent(R.id.widget_header, openAppPending)

            // Refresh button: send broadcast to this provider to trigger update
            try {
                val refreshIntent = Intent(ACTION_REFRESH_WIDGET).apply {
                    `package` = context.packageName
                }
                val refreshPending = PendingIntent.getBroadcast(
                    context,
                    appWidgetId + 20000,
                    refreshIntent,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                views.setOnClickPendingIntent(R.id.widget_refresh, refreshPending)
            } catch (_: Exception) {}

            // Widget refresh uses local files only; do not start MainActivity
            // or trigger cloud sync.

            appWidgetManager.updateAppWidget(appWidgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_list)
            // render a compact refresh glyph into the header refresh ImageView
            try {
                val refreshText = if (isRefreshing(context)) "refreshing..." else "⟳"
                val refreshBitmap = WidgetTextRenderer.renderTextBitmap(
                    context = context,
                    text = refreshText,
                    fontResId = fontResIdForFamily(family, bold = false),
                    textSizeSp = if (isRefreshing(context)) 12f else 16f,
                    textColor = Color.parseColor("#E6F5F0"),
                    maxWidthPx = (36 * metrics.density).toInt(),
                    bold = false,
                )
                views.setImageViewBitmap(R.id.widget_refresh, refreshBitmap)
            } catch (_: Exception) {}
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

        private fun fontResIdForFamily(family: String, bold: Boolean): Int {
            return when (family) {
                "NotoSans" -> if (bold) R.font.noto_sans_bold else R.font.noto_sans_regular
                "CourierPrime" -> if (bold) R.font.courier_prime_bold else R.font.courier_prime_regular
                else -> if (bold) R.font.open_dyslexic_bold else R.font.open_dyslexic_regular
            }
        }
    }

        private fun isRefreshing(context: Context): Boolean {
            return try {
                val flag = java.io.File(context.filesDir, "widget_refreshing")
                if (!flag.exists()) return false
                val age = System.currentTimeMillis() - flag.lastModified()
                age < 5000 // treat as refreshing if flag is younger than 5s
            } catch (_: Exception) {
                false
            }
        }
}
