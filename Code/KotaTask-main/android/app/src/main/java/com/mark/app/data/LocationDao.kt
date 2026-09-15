package com.mark.app.data

import androidx.lifecycle.LiveData
import androidx.room.*

@Dao
interface LocationDao {

    @Query("SELECT * FROM locations ORDER BY name COLLATE NOCASE ASC")
    fun getAll(): LiveData<List<Location>>

    @Query("SELECT * FROM locations WHERE id = :id")
    suspend fun getById(id: String): Location?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(l: Location)

    @Update
    suspend fun update(l: Location)

    @Query("DELETE FROM locations WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("UPDATE tasks SET locationId = NULL WHERE locationId = :id")
    suspend fun unlinkFromTasks(id: String)
}
