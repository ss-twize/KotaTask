package com.mark.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Характер действия задачи: "Звонок", "Создание", "Тренировка".
 * НЕ путать с importance/priority — это про *что* делать, а не *насколько важно*.
 * Задача может быть привязана не более чем к одному типу.
 */
@Entity(tableName = "task_types")
data class TaskType(
    @PrimaryKey val id: String,
    val name: String,
    val created: Long = System.currentTimeMillis(),
    val updated: Long = System.currentTimeMillis()
)
