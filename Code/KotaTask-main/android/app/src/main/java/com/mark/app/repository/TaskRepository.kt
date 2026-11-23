package com.mark.app.repository

import androidx.lifecycle.LiveData
import androidx.room.withTransaction
import com.mark.app.data.AppDatabase
import com.mark.app.data.Task
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class TaskRepository(private val db: AppDatabase) {
    private val dao = db.taskDao()

    val allTasks: LiveData<List<Task>> = dao.getAllTasks()

    suspend fun insert(task: Task) = withContext(Dispatchers.IO) {
        db.withTransaction {
            val last = dao.getAllTasksOnce().filter { it.projectId == task.projectId }.maxOfOrNull { it.sortIndex } ?: -1.0
            dao.insert(task.copy(sortIndex = last + 1))
        }
    }

    suspend fun place(id: String, projectId: String?, position: Int?, allProjects: Boolean = false) = withContext(Dispatchers.IO) {
        db.withTransaction {
            require(allProjects || projectId == null || db.projectDao().getById(projectId) != null) { "Проект удалён" }
            val all = dao.getAllTasksOnce()
            dao.updateAll(com.mark.app.util.BoardOrder.place(all, id, projectId, position, allProjects))
        }
    }
    suspend fun update(task: Task) = withContext(Dispatchers.IO) {
        db.withTransaction {
            val all = dao.getAllTasksOnce()
            val current = all.firstOrNull { it.id == task.id } ?: return@withTransaction
            val order = if (current.projectId != task.projectId)
                (all.filter { it.projectId == task.projectId }.maxOfOrNull { it.sortIndex } ?: -1.0) + 1
                else current.sortIndex
            dao.update(task.copy(sortIndex = order))
        }
    }
    suspend fun delete(task: Task) = withContext(Dispatchers.IO) { dao.delete(task) }
    suspend fun deleteById(id: String) = withContext(Dispatchers.IO) { dao.deleteById(id) }
    suspend fun updateStatus(id: String, status: String) = withContext(Dispatchers.IO) {
        db.withTransaction {
            dao.updateStatus(id, status)
            if (status == "Сегодня") dao.setDeferredDate(id, "")
        }
    }
    suspend fun setDeferredDate(id: String, date: String) = withContext(Dispatchers.IO) { dao.setDeferredDate(id, date) }
    suspend fun promoteDueDeferred(today: String) = withContext(Dispatchers.IO) { dao.promoteDueDeferred(today) }
    suspend fun archiveTask(id: String) = withContext(Dispatchers.IO) { dao.archiveTask(id, System.currentTimeMillis()) }
    suspend fun getAllTasksOnce(): List<Task> = withContext(Dispatchers.IO) { dao.getAllTasksOnce() }
    suspend fun deleteByIds(ids: List<String>) = withContext(Dispatchers.IO) { dao.deleteByIds(ids) }
    suspend fun deleteAllArchived() = withContext(Dispatchers.IO) { dao.deleteAllArchived() }
}
