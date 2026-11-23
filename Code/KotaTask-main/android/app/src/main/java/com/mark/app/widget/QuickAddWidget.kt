package com.mark.app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import com.mark.app.R
import com.mark.app.ui.QuickCaptureActivity

/** Статичный виджет не читает базу и не запускает фоновые задачи. */
class QuickAddWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val action = PendingIntent.getActivity(
            context, 0, Intent(context, QuickCaptureActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        ids.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.widget_quick_add)
            views.setOnClickPendingIntent(R.id.widgetQuickAdd, action)
            manager.updateAppWidget(id, views)
        }
    }
}
