package com.mark.app.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "tasks")
data class Task(
    @PrimaryKey val id: String,
    val title: String,
    val deadline: String = "",
    /** Начало диапазона дедлайна. Если пусто — задача отображается начиная с даты создания. */
    val deadlineStart: String = "",
    val parent: String = "",           // legacy free-text "project name" — оставлен для совместимости
    val purpose: String = "",
    val duration: Int = 30,
    val importance: String = "Средняя",
    val status: String = "Стек",
    val assignee: String = "",
    val created: Long = System.currentTimeMillis(),
    val completed: Long = 0L,

    // ─── Новая категоризация (nullable, добавлены в schema v2) ───
    @ColumnInfo(name = "projectId")   val projectId: String? = null,
    @ColumnInfo(name = "locationId")  val locationId: String? = null,
    @ColumnInfo(name = "taskTypeId")  val taskTypeId: String? = null,

    /**
     * Отложенное планирование (schema v4). ISO-дата (YYYY-MM-DD), на которую задача
     * запланирована к автоматическому переносу в «Сегодня». Пусто — задача не отложена.
     * Задача остаётся в статусе «Стек», пока в 00:00 нужного дня воркер не переведёт
     * её в «Сегодня» и не очистит это поле.
     */
    @ColumnInfo(name = "deferredDate") val deferredDate: String = "",
    /** Быстрый захват: полную форму ещё нужно заполнить. */
    val needsDetails: Boolean = false,
    /** Порядок внутри проектной колонки, независимо от статуса Сегодня/Стек. */
    val sortIndex: Double = 0.0
)
