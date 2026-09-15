package com.mark.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Большая смысловая группа задач: "Сайт для клиента", "Личный бренд" и т.п.
 * Задача может быть привязана не более чем к одному проекту.
 */
@Entity(tableName = "projects")
data class Project(
    @PrimaryKey val id: String,
    val name: String,
    val color: String? = null,
    val created: Long = System.currentTimeMillis(),
    val updated: Long = System.currentTimeMillis()
)
