package com.mark.app.repository

import androidx.lifecycle.LiveData
import com.mark.app.data.AppDatabase
import com.mark.app.data.Project
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class ProjectRepository(db: AppDatabase) {
    private val dao = db.projectDao()

    val all: LiveData<List<Project>> = dao.getAll()

    suspend fun insert(p: Project) = withContext(Dispatchers.IO) { dao.insert(p) }
    suspend fun update(p: Project) = withContext(Dispatchers.IO) { dao.update(p) }
    suspend fun getById(id: String): Project? = withContext(Dispatchers.IO) { dao.getById(id) }

    /** Удаляет проект и обнуляет ссылку у всех задач. */
    suspend fun delete(id: String) = withContext(Dispatchers.IO) {
        dao.unlinkFromTasks(id)
        dao.deleteById(id)
    }
}
