package com.mark.app.util

import com.mark.app.data.Task
import java.time.LocalDate
import java.time.temporal.ChronoUnit

data class Coefficients(
    val deadline: Float = 0.50f,
    val importance: Float = 0.30f,
    val duration: Float = 0.15f,
    val age: Float = 0.05f
)

object PriorityCalculator {

    fun calcPriority(
        task: Task,
        coeffs: Coefficients,
        dayLoadMinutes: Int = 0,
        overloadLimitMinutes: Int = 180,
        loadDurationBoost: Float = 0.2f
    ): Float {
        val dlScore = calcDeadlineScore(task.deadline)
        val impScore = calcImportanceScore(task.importance)
        val durScore = calcDurationScore(task.duration, dayLoadMinutes, overloadLimitMinutes, loadDurationBoost)
        val ageScore = calcAgeScore(task.created)

        return (dlScore * coeffs.deadline +
                impScore * coeffs.importance +
                durScore * coeffs.duration +
                ageScore * coeffs.age)
    }

    private fun calcDeadlineScore(deadline: String): Float {
        if (deadline.isBlank()) return 0.3f
        return try {
            val dl = LocalDate.parse(deadline)
            val today = LocalDate.now()
            val daysUntil = ChronoUnit.DAYS.between(today, dl)
            when {
                daysUntil < 0 -> 1.0f
                daysUntil == 0L -> 0.9f
                daysUntil <= 3 -> 0.7f
                daysUntil <= 7 -> 0.5f
                else -> 0.2f
            }
        } catch (e: Exception) {
            0.3f
        }
    }

    private fun calcImportanceScore(importance: String): Float = when (importance) {
        "Высокая" -> 1.0f
        "Средняя" -> 0.6f
        "Низкая" -> 0.2f
        else -> 0.6f
    }

    private fun calcDurationScore(
        minutes: Int,
        dayLoad: Int,
        overloadLimitMinutes: Int,
        loadDurationBoost: Float
    ): Float {
        val base = when {
            minutes <= 15 -> 1.0f
            minutes <= 30 -> 0.8f
            minutes <= 60 -> 0.6f
            minutes <= 120 -> 0.4f
            else -> 0.2f
        }
        val boostThreshold = overloadLimitMinutes.coerceAtLeast(1) / 2
        val boost = if (dayLoad > boostThreshold) loadDurationBoost.coerceIn(0f, 1f) else 0f
        return (base + boost).coerceAtMost(1.0f)
    }

    private fun calcAgeScore(createdAt: Long): Float {
        val daysOld = (System.currentTimeMillis() - createdAt) / (1000 * 60 * 60 * 24)
        return when {
            daysOld >= 5 -> 1.0f
            else -> (daysOld / 5.0f).coerceIn(0f, 1f)
        }
    }

    fun sortByPriority(tasks: List<Task>, coeffs: Coefficients): List<Task> {
        val todayLoad = tasks.filter { it.status == "Сегодня" }.sumOf { it.duration }
        return tasks.sortedByDescending { calcPriority(it, coeffs, todayLoad) }
    }
}
