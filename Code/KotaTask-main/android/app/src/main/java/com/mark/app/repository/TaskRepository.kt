package com.mark.app.repository

import androidx.lifecycle.LiveData
import com.mark.app.data.AppDatabase
import com.mark.app.data.Task
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class TaskRepository(db: AppDatabase) {
    private val dao = db.taskDao()

    val allTasks: LiveData<List<Task>> = dao.getAllTasks()

    suspend fun insert(task: Task) = withContext(Dispatchers.IO) { dao.insert(task) }
    suspend fun update(task: Task) = withContext(Dispatchers.IO) { dao.update(task) }
    suspend fun delete(task: Task) = withContext(Dispatchers.IO) { dao.delete(task) }
    suspend fun deleteById(id: String) = withContext(Dispatchers.IO) { dao.deleteById(id) }
    suspend fun updateStatus(id: String, status: String) = withContext(Dispatchers.IO) { dao.updateStatus(id, status) }
    suspend fun setDeferredDate(id: String, date: String) = withContext(Dispatchers.IO) { dao.setDeferredDate(id, date) }
    suspend fun promoteDueDeferred(today: String) = withContext(Dispatchers.IO) { dao.promoteDueDeferred(today) }
    suspend fun archiveTask(id: String) = withContext(Dispatchers.IO) { dao.archiveTask(id, System.currentTimeMillis()) }
    suspend fun getAllTasksOnce(): List<Task> = withContext(Dispatchers.IO) { dao.getAllTasksOnce() }
    suspend fun deleteByIds(ids: List<String>) = withContext(Dispatchers.IO) { dao.deleteByIds(ids) }
    suspend fun deleteAllArchived() = withContext(Dispatchers.IO) { dao.deleteAllArchived() }
}
