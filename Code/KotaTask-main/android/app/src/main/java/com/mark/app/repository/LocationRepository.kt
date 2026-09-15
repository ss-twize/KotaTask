package com.mark.app.repository

import androidx.lifecycle.LiveData
import com.mark.app.data.AppDatabase
import com.mark.app.data.Location
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class LocationRepository(db: AppDatabase) {
    private val dao = db.locationDao()

    val all: LiveData<List<Location>> = dao.getAll()

    suspend fun insert(l: Location) = withContext(Dispatchers.IO) { dao.insert(l) }
    suspend fun update(l: Location) = withContext(Dispatchers.IO) { dao.update(l) }
    suspend fun getById(id: String): Location? = withContext(Dispatchers.IO) { dao.getById(id) }

    suspend fun delete(id: String) = withContext(Dispatchers.IO) {
        dao.unlinkFromTasks(id)
        dao.deleteById(id)
    }
}
