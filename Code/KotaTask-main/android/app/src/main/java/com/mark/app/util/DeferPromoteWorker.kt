package com.mark.app.util

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.mark.app.data.AppDatabase
import java.time.LocalDate
import java.util.concurrent.TimeUnit

/**
 * Воркер отложенного планирования. Запускается в 00:00 и переносит в «Сегодня»
 * все отложенные задачи, чья дата наступила, после чего перепланирует себя на
 * следующую полночь (self-rescheduling — тот же приём, что у NotificationWorker).
 */
class DeferPromoteWorker(ctx: Context, params: WorkerParameters) : CoroutineWorker(ctx, params) {

    override suspend fun doWork(): Result {
        val ctx = applicationContext
        try {
            AppDatabase.getInstance(ctx).taskDao().promoteDueDeferred(LocalDate.now().toString())
        } catch (_: Exception) {
            // Перенос — не критичная операция; ошибку проглатываем, чтобы не было retry-шторма.
            // На следующий старт приложения сработает catch-up через VM.promoteDueDeferred().
        }
        // Планируем следующий запуск на ближайшую полночь.
        scheduleDeferPromotion(ctx)
        return Result.success()
    }
}

const val DEFER_WORK_TAG = "defer_promote"

/**
 * Планирует перенос отложенных задач на ближайшую полночь (00:00).
 * Использует OneTimeWorkRequest, который сам себя перепланирует — так мы точно
 * попадаем в 00:00 каждый день, не завися от неточности PeriodicWork.
 */
fun scheduleDeferPromotion(context: Context) {
    val delayMs = calculateInitialDelayMs(targetHour = 0, targetMinute = 0)
    val request = OneTimeWorkRequestBuilder<DeferPromoteWorker>()
        .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
        .addTag(DEFER_WORK_TAG)
        .build()
    WorkManager.getInstance(context).enqueueUniqueWork(
        DEFER_WORK_TAG,
        ExistingWorkPolicy.REPLACE,
        request
    )
}
