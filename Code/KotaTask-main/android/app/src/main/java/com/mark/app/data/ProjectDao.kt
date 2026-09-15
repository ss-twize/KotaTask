package com.mark.app.data

import androidx.lifecycle.LiveData
import androidx.room.*

@Dao
interface ProjectDao {

    @Query("SELECT * FROM projects ORDER BY name COLLATE NOCASE ASC")
    fun getAll(): LiveData<List<Project>>

    @Query("SELECT * FROM projects WHERE id = :id")
    suspend fun getById(id: String): Project?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(p: Project)

    @Update
    suspend fun update(p: Project)

    @Query("DELETE FROM projects WHERE id = :id")
    suspend fun deleteById(id: String)

    /** При удалении проекта обнуляем ссылку у всех задач. */
    @Query("UPDATE tasks SET projectId = NULL WHERE projectId = :id")
    suspend fun unlinkFromTasks(id: String)
}
