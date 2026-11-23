package com.mark.app.util

import com.mark.app.data.Task

/** Колонки показывают Стек + Сегодня; статус не меняется при смене проекта. */
object BoardOrder {
    fun column(all: List<Task>, projectId: String?, allProjects: Boolean = false): List<Task> =
        all.filter { (allProjects || it.projectId == projectId) && (it.status == "Стек" || it.status == "Сегодня") }
            .sortedWith(compareBy<Task> { it.sortIndex }.thenByDescending { it.created }.thenBy { it.id })

    /** Только изменённые записи; репозиторий записывает их одной транзакцией. */
    fun place(all: List<Task>, id: String, projectId: String?, position: Int?, allProjects: Boolean = false): List<Task> {
        val moving = all.firstOrNull { it.id == id && (it.status == "Стек" || it.status == "Сегодня") }
            ?: return emptyList()
        val siblings = column(all, projectId, allProjects).filter { it.id != id }.toMutableList()
        siblings.add((position ?: siblings.size).coerceIn(0, siblings.size),
            moving.copy(projectId = if (allProjects) moving.projectId else projectId))
        return siblings.mapIndexed { index, task -> task.copy(sortIndex = index.toDouble()) }
            .filter { next -> all.firstOrNull { it.id == next.id } != next }
    }
}
