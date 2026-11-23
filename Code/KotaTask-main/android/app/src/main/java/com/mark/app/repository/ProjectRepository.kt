package com.mark.app.repository

import androidx.lifecycle.LiveData
import androidx.room.withTransaction
import com.mark.app.data.AppDatabase
import com.mark.app.data.Project
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class ProjectRepository(private val db: AppDatabase) {
    private val dao = db.projectDao()

    val all: LiveData<List<Project>> = dao.getAll()

    suspend fun insert(p: Project) = withContext(Dispatchers.IO) {
        db.withTransaction {
            dao.insert(p.copy(sortIndex = (dao.getAllOnce().maxOfOrNull { it.sortIndex } ?: -1.0) + 1))
        }
    }
    suspend fun move(id: String, position: Int) = withContext(Dispatchers.IO) {
        db.withTransaction {
            val all = dao.getAllOnce().toMutableList()
            val project = all.firstOrNull { it.id == id } ?: return@withTransaction
            all.removeAll { it.id == id }
            all.add(position.coerceIn(0, all.size), project)
            dao.updateAll(all.mapIndexed { i, p -> p.copy(sortIndex = i.toDouble()) })
        }
    }
    suspend fun update(p: Project) = withContext(Dispatchers.IO) { dao.update(p) }
    suspend fun getById(id: String): Project? = withContext(Dispatchers.IO) { dao.getById(id) }

    /** Удаляет проект и обнуляет ссылку у всех задач. */
    suspend fun delete(id: String) = withContext(Dispatchers.IO) {
        db.withTransaction {
            dao.unlinkFromTasks(id)
            dao.deleteById(id)
        }
    }
}
