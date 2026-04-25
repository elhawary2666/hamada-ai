package com.hamada.hamada_ai

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

class HamadaWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val prefs = context.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE)

            val topTask = prefs.getString("flutter.widget_top_task",
                "لا توجد مهام اليوم") ?: "لا توجد مهام اليوم"
            val balance = prefs.getString("flutter.widget_balance", "0") ?: "0"
            val message = prefs.getString("flutter.widget_message",
                "حماده في انتظارك") ?: "حماده في انتظارك"
            val hasKey  = prefs.getBoolean("flutter.widget_has_key", false)

            val views = RemoteViews(context.packageName, R.layout.hamada_widget)
            views.setTextViewText(R.id.widget_message, message)
            views.setTextViewText(R.id.widget_task, topTask)
            views.setTextViewText(R.id.widget_balance, "$balance ج.م")
            views.setTextViewText(
                R.id.widget_status,
                if (hasKey) "● نشط" else "● يحتاج API Key"
            )

            // Open app on tap
            val intent = Intent(context, MainActivity::class.java)
            val pi = PendingIntent.getActivity(
                context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root, pi)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
