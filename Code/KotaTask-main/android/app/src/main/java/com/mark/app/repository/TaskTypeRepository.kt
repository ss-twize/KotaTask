package com.mark.app.repository

import androidx.lifecycle.LiveData
import com.mark.app.data.AppDatabase
import com.mark.app.data.TaskType
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class TaskTypeRepository(db: AppDatabase) {
    private val dao = db.taskTypeDao()

    val all: LiveData<List<TaskType>> = dao.getAll()

    suspend fun insert(t: TaskType) = withContext(Dispatchers.IO) { dao.insert(t) }
    suspend fun update(t: TaskType) = withContext(Dispatchers.IO) { dao.update(t) }
    suspend fun getById(id: String): TaskType? = withContext(Dispatchers.IO) { dao.getById(id) }

    suspend fun delete(id: String) = withContext(Dispatchers.IO) {
        dao.unlinkFromTasks(id)
        dao.deleteById(id)
    }
}
