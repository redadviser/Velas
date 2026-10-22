package com.velas.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Widget do ecrã inicial (Birthdayly+): os próximos aniversários. O texto é
 * escrito pela app (lib/services/home_widget_sync.dart) sempre que os dados mudam;
 * tocar abre a app.
 */
class BirthdaysWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.birthdays_widget).apply {
                setTextViewText(R.id.widget_title, widgetData.getString("title", "Próximos aniversários"))
                setTextViewText(
                    R.id.widget_lines,
                    widgetData.getString("lines", "Abre a Birthdayly para veres aqui os próximos aniversários."),
                )
                setOnClickPendingIntent(R.id.widget_root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
