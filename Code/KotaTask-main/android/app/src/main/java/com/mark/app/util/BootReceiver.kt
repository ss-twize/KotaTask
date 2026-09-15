package com.mark.app.util

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.mark.app.KotaTaskApp
import java.util.Calendar
import java.util.concurrent.TimeUnit

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            scheduleDaily(context)
            scheduleDeferPromotion(context)
        }
    }
}

const val WORK_TAG = "daily_notif"

/**
 * Планирует ежедневное уведомление на время, выбранное пользователем.
 * Если уведомления отключены — отменяет всё запланированное.
 *
 * Используем OneTimeWorkRequest вместо Periodic, чтобы точно попадать
 * в нужный HH:MM: worker сам перепланирует себя на следующий день после
 * отправки уведомления (см. NotificationWorker.reschedule()).
 */
fun scheduleDaily(context: Context) {
    val prefs = context.getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
    val enabled = prefs.getBoolean(KotaTaskApp.KEY_NOTIF_ENABLED, false)

    if (!enabled) {
        cancelDaily(context)
        return
    }

    val hour   = prefs.getInt(KotaTaskApp.KEY_NOTIF_HOUR,   KotaTaskApp.DEFAULT_NOTIF_HOUR)
    val minute = prefs.getInt(KotaTaskApp.KEY_NOTIF_MINUTE, KotaTaskApp.DEFAULT_NOTIF_MINUTE)
    val delayMs = calculateInitialDelayMs(hour, minute)

    val request = OneTimeWorkRequestBuilder<NotificationWorker>()
        .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
        .addTag(WORK_TAG)
        .build()

    // REPLACE: при смене времени или включении сразу ставим новый запрос,
    // отменяя предыдущий — пользователь не ждёт до следующего цикла.
    WorkManager.getInstance(context).enqueueUniqueWork(
        WORK_TAG,
        ExistingWorkPolicy.REPLACE,
        request
    )
}

fun cancelDaily(context: Context) {
    WorkManager.getInstance(context).cancelUniqueWork(WORK_TAG)
}

/** Миллисекунды от now() до ближайшего targetHour:targetMinute (сегодня или завтра). */
fun calculateInitialDelayMs(
    targetHour: Int,
    targetMinute: Int = 0,
    now: Long = System.currentTimeMillis()
): Long {
    val target = Calendar.getInstance().apply {
        timeInMillis = now
        set(Calendar.HOUR_OF_DAY, targetHour)
        set(Calendar.MINUTE, targetMinute)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
        if (timeInMillis <= now) add(Calendar.DAY_OF_MONTH, 1)
    }
    return target.timeInMillis - now
}
