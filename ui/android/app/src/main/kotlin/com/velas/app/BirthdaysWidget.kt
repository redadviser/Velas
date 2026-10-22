package com.velas.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Shader
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File
import java.util.Calendar
import kotlin.math.min

/**
 * Widget do ecrã inicial (Birthdayly+): o próximo aniversário com a fotografia
 * (ou as iniciais) e os dois seguintes. A app guarda as datas, as iniciais, o
 * caminho da fotografia e a língua (lib/services/home_widget_sync.dart); é aqui
 * que se conta quanto falta, por isso "Hoje", "Amanhã" e "Em 5 dias" continuam
 * certos mesmo sem abrir a app (o sistema volta a desenhá-lo a cada 6 h).
 */
class BirthdaysWidget : HomeWidgetProvider() {
    private data class Next(
        val name: String,
        val initials: String,
        val photo: String?,
        val days: Int,
        val date: Calendar,
        val age: Int?,
    )

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val t = Texts.of(widgetData.getString("lang", "pt"))
        val plus = widgetData.getBoolean("plus", false)
        val upcoming = parse(widgetData.getString("people", null).orEmpty())
        val first = upcoming.firstOrNull()
        val avatar = first?.photo?.let { circle(it) }
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.birthdays_widget)
            views.setTextViewText(R.id.widget_label, t.label)
            when {
                !plus -> show(views, "Birthdayly+", t.activate, emptyList(), "+", null)
                first == null -> show(views, t.empty, t.add, emptyList(), "🎂", null)
                else -> {
                    val rest = upcoming.drop(1).take(ROWS.size).map { it.name to t.short(it.date) }
                    show(views, first.name, t.whenText(first.days, first.date, first.age), rest, first.initials, avatar)
                }
            }
            views.setOnClickPendingIntent(R.id.widget_root, HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /** O próximo em destaque; os seguintes ([rest]: nome e dia) em linhas simples. */
    private fun show(views: RemoteViews, name: String, detail: String, rest: List<Pair<String, String>>, initials: String, photo: Bitmap?) {
        views.setTextViewText(R.id.widget_name, name)
        views.setTextViewText(R.id.widget_when, detail)
        views.setTextViewText(R.id.widget_initials, initials)
        if (photo != null) {
            views.setImageViewBitmap(R.id.widget_photo, photo)
            views.setViewVisibility(R.id.widget_photo, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_photo, View.GONE)
        }
        views.setViewVisibility(R.id.widget_next_group, if (rest.isEmpty()) View.GONE else View.VISIBLE)
        for ((i, row) in ROWS.withIndex()) {
            val person = rest.getOrNull(i)
            views.setViewVisibility(row.first, if (person == null) View.GONE else View.VISIBLE)
            if (person != null) {
                views.setTextViewText(row.second, person.first)
                views.setTextViewText(row.third, person.second)
            }
        }
    }

    /** A fotografia recortada em círculo, pequena (os widgets têm pouca memória para imagens). */
    private fun circle(path: String): Bitmap? {
        val file = File(path)
        if (!file.exists()) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (min(bounds.outWidth, bounds.outHeight) / (sample * 2) >= SIZE) sample *= 2
        val src = BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        val side = min(src.width, src.height)
        val square = Bitmap.createBitmap(src, (src.width - side) / 2, (src.height - side) / 2, side, side)
        val scaled = Bitmap.createScaledBitmap(square, SIZE, SIZE, true)
        val out = Bitmap.createBitmap(SIZE, SIZE, Bitmap.Config.ARGB_8888)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = BitmapShader(scaled, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP) }
        Canvas(out).drawCircle(SIZE / 2f, SIZE / 2f, SIZE / 2f, paint)
        return out
    }

    /** Uma pessoa por linha: "nome|dia|mês|ano|iniciais|fotografia" (vazios quando não há). */
    private fun parse(raw: String): List<Next> {
        val today = noon(Calendar.getInstance())
        return raw.lines().mapNotNull { line ->
            val parts = line.split('|')
            if (parts.size < 3) return@mapNotNull null
            val day = parts[1].toIntOrNull() ?: return@mapNotNull null
            val month = parts[2].toIntOrNull() ?: return@mapNotNull null
            val year = parts.getOrNull(3)?.toIntOrNull()
            var date = occurrence(today.get(Calendar.YEAR), day, month)
            if (date.before(today)) date = occurrence(today.get(Calendar.YEAR) + 1, day, month)
            val days = ((date.timeInMillis - today.timeInMillis + 43_200_000L) / 86_400_000L).toInt()
            Next(
                name = parts[0],
                initials = parts.getOrNull(4).orEmpty().ifEmpty { parts[0].take(1).uppercase() },
                photo = parts.getOrNull(5)?.ifEmpty { null },
                days = days,
                date = date,
                age = year?.let { date.get(Calendar.YEAR) - it },
            )
        }.sortedBy { it.days }
    }

    /** Como na app: o 29 de fevereiro passa a 28 nos anos não bissextos. */
    private fun occurrence(year: Int, day: Int, month: Int): Calendar {
        val leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        val d = if (month == 2 && day == 29 && !leap) 28 else day
        return noon(Calendar.getInstance().apply { set(year, month - 1, d) })
    }

    private fun noon(c: Calendar) = c.apply {
        set(Calendar.HOUR_OF_DAY, 12)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }

    /** Os textos do widget na língua da app. */
    private class Texts(
        val label: String,
        val empty: String,
        val add: String,
        val activate: String,
        private val today: String,
        private val turns: String,
        private val tomorrow: String,
        private val inDays: String,
        private val months: List<String>,
        private val weekdays: List<String>,
    ) {
        fun short(c: Calendar) = "${c.get(Calendar.DAY_OF_MONTH)} ${months[c.get(Calendar.MONTH)]}"

        private fun weekday(c: Calendar) = weekdays[c.get(Calendar.DAY_OF_WEEK) - 1]

        /** Duas linhas curtas, para caberem ao lado da fotografia. */
        fun whenText(days: Int, date: Calendar, age: Int?): String = when (days) {
            0 -> if (age != null) "$today 🎂\n${turns.replace("{n}", "$age")}" else "$today 🎂"
            1 -> "$tomorrow\n${weekday(date)}"
            in 2..6 -> "${weekday(date).replaceFirstChar { it.uppercase() }}\n${inDays.replace("{n}", "$days")}"
            else -> "${inDays.replace("{n}", "$days").replaceFirstChar { it.uppercase() }}\n${short(date)}"
        }

        companion object {
            fun of(lang: String?): Texts = when (lang) {
                "en" -> Texts(
                    "Birthdays", "No birthdays", "Tap to add one", "Get Birthdayly+ in the app",
                    "Today", "turns {n}", "Tomorrow", "in {n} days",
                    listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"),
                    listOf("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"),
                )
                "es" -> Texts(
                    "Cumpleaños", "Sin cumpleaños", "Toca para añadir", "Activa Birthdayly+ en la app",
                    "Hoy", "cumple {n}", "Mañana", "en {n} días",
                    listOf("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"),
                    listOf("domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"),
                )
                "fr" -> Texts(
                    "Anniversaires", "Aucun anniversaire", "Touchez pour ajouter", "Activez Birthdayly+ dans l'app",
                    "Aujourd'hui", "{n} ans", "Demain", "dans {n} jours",
                    listOf("janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."),
                    listOf("dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"),
                )
                else -> Texts(
                    "Aniversários", "Sem aniversários", "Toca para acrescentar", "Ativa o Birthdayly+ na app",
                    "Hoje", "faz {n} anos", "Amanhã", "em {n} dias",
                    listOf("jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"),
                    listOf("domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"),
                )
            }
        }
    }

    private companion object {
        /** Lado da fotografia em px (o círculo tem 46 dp). */
        const val SIZE = 160

        /** As linhas dos seguintes: (linha, nome, dia). */
        val ROWS = listOf(
            Triple(R.id.widget_row1, R.id.widget_row1_name, R.id.widget_row1_date),
            Triple(R.id.widget_row2, R.id.widget_row2_name, R.id.widget_row2_date),
        )
    }
}
