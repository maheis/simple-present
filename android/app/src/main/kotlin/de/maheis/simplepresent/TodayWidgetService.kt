package be.heister.simplepresent

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.graphics.Color
import android.os.Build
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONObject
import java.io.File

class TodayWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return TodayWidgetFactory(applicationContext, intent)
    }
}

private data class WidgetTask(
    val id: String,
    val text: String,
    val done: Boolean,
    val inProgress: Boolean,
    val important: Boolean,
    val scheduledAtMs: Long?,
    val inProgressAtMs: Long?,
    val loadIndex: Int,
)

private class TodayWidgetFactory(
    private val context: Context,
    intent: Intent,
) : RemoteViewsService.RemoteViewsFactory {

    private val items = mutableListOf<WidgetTask>()
    private val itemLayoutRes = intent.getIntExtra(TodayWidgetProvider.EXTRA_ITEM_LAYOUT, R.layout.today_widget_item)
    private var fontFamily = intent.getStringExtra(TodayWidgetProvider.EXTRA_WIDGET_FONT_FAMILY) ?: "OpenDyslexic"
    private val textWidthPx = intent.getIntExtra(TodayWidgetProvider.EXTRA_WIDGET_TEXT_WIDTH_PX, 240)

    override fun onCreate() {
        loadData()
    }

    override fun onDataSetChanged() {
        loadData()
    }

    override fun onDestroy() {
        items.clear()
    }

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
        if (position < 0 || position >= items.size) {
            return RemoteViews(context.packageName, itemLayoutRes)
        }
        val task = items[position]
        val views = RemoteViews(context.packageName, itemLayoutRes)
        val text = if (task.inProgress) {
            "▶ ${task.text}"
        } else {
            task.text
        }
        views.setImageViewBitmap(
            R.id.widget_task_text,
            WidgetTextRenderer.renderTextBitmap(
                context = context,
                text = text,
                fontResId = fontResIdForFamily(fontFamily, bold = false),
                textSizeSp = 13f,
                textColor = Color.parseColor("#E6F5F0"),
                maxWidthPx = textWidthPx,
                bold = false,
            )
        )

        val openIntent = Intent().apply {
            putExtra("task_id", task.id)
        }
        views.setOnClickFillInIntent(R.id.widget_item_root, openIntent)
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long =
        items.getOrNull(position)?.id?.hashCode()?.toLong() ?: position.toLong()

    override fun hasStableIds(): Boolean = true

    private fun loadData() {
        items.clear()
        val appFlutter = File(context.filesDir.parentFile, "app_flutter")
        val folderName = if ((context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            "simplepresent-debug"
        } else {
            "simplepresent"
        }
        // Only use aggregated widget file for data (legacy per-task folder removed).
        val widgetFile = File(File(appFlutter, folderName), "simplepresent_widget.json")
        if (!widgetFile.exists() || !widgetFile.isFile) {
            // No data available for widget
            return
        }
        try {
            val root = JSONObject(widgetFile.readText())
            val font = root.optString("fontFamily", "").trim()
            if (font.isNotEmpty()) fontFamily = font
            val arr = root.optJSONArray("tasks")
            if (arr != null) {
                var idx = 0
                for (i in 0 until arr.length()) {
                    try {
                        val obj = arr.optJSONObject(i) ?: continue
                        val id = obj.optString("id", "").trim()
                        val text = obj.optString("text", "").trim()
                        if (id.isEmpty() || text.isEmpty()) continue
                        val done = obj.optBoolean("done", false)
                        if (done) continue
                        val inProgress = obj.optBoolean("inProgress", false)
                        val important = obj.optBoolean("important", false)
                        val scheduledRaw = obj.optString("scheduled_at", obj.optString("scheduledAt", ""))
                        val inProgressAtRaw = obj.optString("in_progress_at", obj.optString("inProgressAt", ""))
                        val scheduledAtMs = parseIsoMillis(scheduledRaw)
                        val inProgressAtMs = parseIsoMillis(inProgressAtRaw)
                        items.add(
                            WidgetTask(
                                id = id,
                                text = text,
                                done = done,
                                inProgress = inProgress,
                                important = important,
                                scheduledAtMs = scheduledAtMs,
                                inProgressAtMs = inProgressAtMs,
                                loadIndex = idx,
                            )
                        )
                        idx++
                    } catch (_: Exception) {
                    }
                }
            }
        } catch (_: Exception) {
        }
        // proceed to sort later

        sortLikeApp(items)
        if (items.size > 25) {
            items.subList(25, items.size).clear()
        }
    }

    private fun parseIsoMillis(raw: String?): Long? {
        val text = raw?.trim().orEmpty()
        if (text.isEmpty()) return null
        return try {
            java.time.Instant.parse(text).toEpochMilli()
        } catch (_: Exception) {
            try {
                java.time.OffsetDateTime.parse(text).toInstant().toEpochMilli()
            } catch (_: Exception) {
                try {
                    java.time.LocalDateTime.parse(text)
                        .atZone(java.time.ZoneId.systemDefault())
                        .toInstant()
                        .toEpochMilli()
                } catch (_: Exception) {
                    null
                }
            }
        }
    }

    private fun fontResIdForFamily(family: String, bold: Boolean): Int {
        return when (family) {
            "NotoSans" -> if (bold) R.font.noto_sans_bold else R.font.noto_sans_regular
            "CourierPrime" -> if (bold) R.font.courier_prime_bold else R.font.courier_prime_regular
            else -> if (bold) R.font.open_dyslexic_bold else R.font.open_dyslexic_regular
        }
    }

    private fun sortLikeApp(list: MutableList<WidgetTask>) {
        val now = System.currentTimeMillis()

        val bucketImportantInProgress = mutableListOf<WidgetTask>()
        val bucketInProgressScheduledPast = mutableListOf<WidgetTask>()
        val bucketInProgressNoSchedule = mutableListOf<WidgetTask>()
        val bucketInProgressScheduledFuture = mutableListOf<WidgetTask>()
        val bucketImportant = mutableListOf<WidgetTask>()
        val bucketScheduledPast = mutableListOf<WidgetTask>()
        val bucketDueIn1h = mutableListOf<WidgetTask>()
        val bucketRest = mutableListOf<WidgetTask>()
        val bucketScheduledFuture = mutableListOf<WidgetTask>()

        for (t in list) {
            val sched = t.scheduledAtMs
            val hasSchedule = sched != null
            val diff = if (sched != null) sched - now else null
            val isOverdue = hasSchedule && diff!! < 0
            val dueWithin1h = hasSchedule && diff!! >= 0 && diff <= 60L * 60L * 1000L
            val isScheduledFuture = hasSchedule && !isOverdue && !dueWithin1h

            if (t.inProgress) {
                if (t.important) {
                    bucketImportantInProgress.add(t)
                } else if (isOverdue) {
                    bucketInProgressScheduledPast.add(t)
                } else if (isScheduledFuture) {
                    bucketInProgressScheduledFuture.add(t)
                } else {
                    bucketInProgressNoSchedule.add(t)
                }
                continue
            }

            if (t.important) {
                bucketImportant.add(t)
                continue
            }
            if (isOverdue) {
                bucketScheduledPast.add(t)
                continue
            }
            if (dueWithin1h) {
                bucketDueIn1h.add(t)
                continue
            }
            if (isScheduledFuture) {
                bucketScheduledFuture.add(t)
                continue
            }
            bucketRest.add(t)
        }

        fun inProgressKey(t: WidgetTask): Long = t.inProgressAtMs ?: 0L
        bucketImportantInProgress.sortWith(compareByDescending<WidgetTask> { inProgressKey(it) }.thenBy { it.loadIndex })
        bucketInProgressScheduledPast.sortWith(compareByDescending<WidgetTask> { inProgressKey(it) }.thenBy { it.loadIndex })
        bucketInProgressNoSchedule.sortWith(compareByDescending<WidgetTask> { inProgressKey(it) }.thenBy { it.loadIndex })
        bucketInProgressScheduledFuture.sortWith(compareByDescending<WidgetTask> { inProgressKey(it) }.thenBy { it.loadIndex })

        bucketScheduledPast.sortWith(compareByDescending<WidgetTask> { it.scheduledAtMs ?: 0L }.thenBy { it.loadIndex })
        bucketDueIn1h.sortWith(compareBy<WidgetTask> { it.scheduledAtMs ?: 0L }.thenBy { it.loadIndex })
        bucketScheduledFuture.sortWith(compareBy<WidgetTask> { it.scheduledAtMs ?: 0L }.thenBy { it.loadIndex })

        val ordered = mutableListOf<WidgetTask>()
        ordered.addAll(bucketImportantInProgress)
        ordered.addAll(bucketInProgressScheduledPast)
        ordered.addAll(bucketInProgressNoSchedule)
        ordered.addAll(bucketInProgressScheduledFuture)
        ordered.addAll(bucketImportant)
        ordered.addAll(bucketScheduledPast)
        ordered.addAll(bucketDueIn1h)
        ordered.addAll(bucketRest)
        ordered.addAll(bucketScheduledFuture)

        val inProgressFirst = ordered.filter { it.inProgress && !it.done }
        val restFinal = ordered.filter { !(it.inProgress && !it.done) }
        list.clear()
        list.addAll(inProgressFirst)
        list.addAll(restFinal)
    }
}
