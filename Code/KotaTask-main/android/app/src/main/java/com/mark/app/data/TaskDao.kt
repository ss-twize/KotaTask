package com.mark.app.data

import androidx.lifecycle.LiveData
import androidx.room.*

@Dao
interface TaskDao {

    @Query("SELECT * FROM tasks ORDER BY created DESC")
    fun getAllTasks(): LiveData<List<Task>>

    @Query("SELECT * FROM tasks WHERE status = :status ORDER BY created DESC")
    fun getTasksByStatus(status: String): LiveData<List<Task>>

    @Query("SELECT * FROM tasks ORDER BY created DESC")
    suspend fun getAllTasksOnce(): List<Task>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(task: Task)

    @Update
    suspend fun update(task: Task)

    @Update
    suspend fun updateAll(tasks: List<Task>)

    @Delete
    suspend fun delete(task: Task)

    @Query("DELETE FROM tasks WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("UPDATE tasks SET status = :status WHERE id = :id")
    suspend fun updateStatus(id: String, status: String)

    /** Откладывает задачу на дату (ISO YYYY-MM-DD). Пустая строка — снять отложенность. */
    @Query("UPDATE tasks SET deferredDate = :date WHERE id = :id")
    suspend fun setDeferredDate(id: String, date: String)

    /**
     * Переносит в «Сегодня» все отложенные задачи, чья дата наступила (deferredDate <= today),
     * и очищает их deferredDate. Сравнение строк ISO-дат лексикографически корректно.
     * Затрагивает только задачи в «Стек» — отложенные, но уже архивированные/перенесённые не трогаем.
     */
    @Query("UPDATE tasks SET status = 'Сегодня', deferredDate = '' WHERE deferredDate != '' AND deferredDate <= :today AND status = 'Стек'")
    suspend fun promoteDueDeferred(today: String)

    @Query("UPDATE tasks SET status = 'Архив', completed = :completedAt WHERE id = :id")
    suspend fun archiveTask(id: String, completedAt: Long)

    @Query("DELETE FROM tasks WHERE id IN (:ids)")
    suspend fun deleteByIds(ids: List<String>)

    @Query("DELETE FROM tasks WHERE status = 'Архив'")
    suspend fun deleteAllArchived()
}
