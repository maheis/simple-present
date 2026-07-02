package be.heister.simplepresent

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.os.Build
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import org.json.JSONObject
import java.io.File

class TodayWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return TodayWidgetFactory(applicationContext)
    }
}

private data class WidgetTask(
    val id: String,
    val text: String,
    val done: Boolean,
    val inProgress: Boolean,
)

private class TodayWidgetFactory(
    private val context: Context,
) : RemoteViewsService.RemoteViewsFactory {

    private val items = mutableListOf<WidgetTask>()

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
            return RemoteViews(context.packageName, R.layout.today_widget_item)
        }
        val task = items[position]
        val views = RemoteViews(context.packageName, R.layout.today_widget_item)
        val text = if (task.inProgress) {
            "▶ ${task.text}"
        } else {
            task.text
        }
        views.setTextViewText(R.id.widget_task_text, text)

        val openIntent = Intent().apply {
            action = "be.heister.simplepresent.ACTION_OPEN_FROM_WIDGET"
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
        val todayDir = File(File(appFlutter, folderName), "today")
        if (!todayDir.exists() || !todayDir.isDirectory) return

        val files = todayDir.listFiles()?.sortedBy { it.name } ?: return
        for (file in files) {
            if (!file.isFile || !file.name.endsWith(".json")) continue
            try {
                val obj = JSONObject(file.readText())
                val id = obj.optString("id", "").trim()
                val text = obj.optString("text", "").trim()
                if (id.isEmpty() || text.isEmpty()) continue
                val done = obj.optBoolean("done", false)
                if (done) continue
                val inProgress = obj.optBoolean("inProgress", false)
                items.add(WidgetTask(id = id, text = text, done = done, inProgress = inProgress))
            } catch (_: Exception) {
            }
            if (items.size >= 25) break
        }
    }
}
