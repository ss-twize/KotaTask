package com.mark.app.data

import androidx.lifecycle.LiveData
import androidx.room.*

@Dao
interface TaskTypeDao {

    @Query("SELECT * FROM task_types ORDER BY name COLLATE NOCASE ASC")
    fun getAll(): LiveData<List<TaskType>>

    @Query("SELECT * FROM task_types ORDER BY name COLLATE NOCASE ASC")
    suspend fun getAllOnce(): List<TaskType>

    @Query("SELECT * FROM task_types WHERE id = :id")
    suspend fun getById(id: String): TaskType?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(t: TaskType)

    @Update
    suspend fun update(t: TaskType)

    @Query("DELETE FROM task_types WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("UPDATE tasks SET taskTypeId = NULL WHERE taskTypeId = :id")
    suspend fun unlinkFromTasks(id: String)
}
