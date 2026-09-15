package com.mark.app.data

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Место/контекст выполнения задачи: "Дом", "Зал", "Компьютер".
 * Задача может быть привязана не более чем к одной локации.
 */
@Entity(tableName = "locations")
data class Location(
    @PrimaryKey val id: String,
    val name: String,
    val created: Long = System.currentTimeMillis(),
    val updated: Long = System.currentTimeMillis()
)
