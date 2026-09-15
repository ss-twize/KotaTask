package com.mark.app.util

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.CoroutineWorker
import com.mark.app.KotaTaskApp
import com.mark.app.R
import com.mark.app.data.AppDatabase
import java.util.concurrent.TimeUnit

class NotificationWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {

    override suspend fun doWork(): Result {
        val ctx = applicationContext
        val prefs = ctx.getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)

        // Не показываем уведомление, если пользователь отключил его пока worker ждал
        val enabled = prefs.getBoolean(KotaTaskApp.KEY_NOTIF_ENABLED, false)
        if (enabled) {
            showNotification(ctx)
        }

        // Планируем следующий запуск на завтра в то же время (self-rescheduling)
        reschedule(ctx, prefs)

        return Result.success()
    }

    private suspend fun showNotification(ctx: Context) {
        val db = AppDatabase.getInstance(ctx)
        val tasks = db.taskDao().getAllTasksOnce().filter { it.status == "Сегодня" }

        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        val channel = NotificationChannel(
            CHANNEL_ID,
            ctx.getString(R.string.notification_channel_daily),
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            lockscreenVisibility = Notification.VISIBILITY_PRIVATE
        }
        nm.createNotificationChannel(channel)

        val fullBody = if (tasks.isEmpty()) {
            ctx.getString(R.string.notif_no_tasks)
        } else {
            tasks.take(5).joinToString("\n") { "• ${it.title}" } +
                if (tasks.size > 5) "\n${ctx.getString(R.string.notif_and_more, tasks.size - 5)}" else ""
        }

        val full = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(ctx.getString(R.string.notif_title))
            .setContentText(ctx.getString(R.string.notification_morning_summary))
            .setStyle(NotificationCompat.BigTextStyle().bigText(fullBody))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(
                NotificationCompat.Builder(ctx, CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentTitle(ctx.getString(R.string.notif_title))
                    .setContentText(ctx.getString(R.string.notification_morning_summary))
                    .build()
            )
            .setAutoCancel(true)
            .build()

        nm.notify(NOTIF_ID, full)
    }

    private fun reschedule(ctx: Context, prefs: android.content.SharedPreferences) {
        val enabled = prefs.getBoolean(KotaTaskApp.KEY_NOTIF_ENABLED, false)
        if (!enabled) return

        val hour   = prefs.getInt(KotaTaskApp.KEY_NOTIF_HOUR,   KotaTaskApp.DEFAULT_NOTIF_HOUR)
        val minute = prefs.getInt(KotaTaskApp.KEY_NOTIF_MINUTE, KotaTaskApp.DEFAULT_NOTIF_MINUTE)

        // Следующий запуск завтра в то же время (от сейчас ~24 ч - прошедшие минуты)
        val delayMs = calculateInitialDelayMs(hour, minute)

        val next = OneTimeWorkRequestBuilder<NotificationWorker>()
            .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
            .addTag(WORK_TAG)
            .build()

        WorkManager.getInstance(ctx).enqueueUniqueWork(
            WORK_TAG,
            ExistingWorkPolicy.REPLACE,
            next
        )
    }

    companion object {
        private const val CHANNEL_ID = "mark_daily"
        private const val NOTIF_ID   = 1001
    }
}
