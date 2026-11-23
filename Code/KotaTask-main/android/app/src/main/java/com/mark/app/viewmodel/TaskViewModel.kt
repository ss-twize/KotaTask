package com.mark.app.viewmodel

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.viewModelScope
import com.mark.app.KotaTaskApp
import com.mark.app.data.AppDatabase
import com.mark.app.data.Location
import com.mark.app.data.Project
import com.mark.app.data.Task
import com.mark.app.data.TaskType
import com.mark.app.repository.LocationRepository
import com.mark.app.repository.ProjectRepository
import com.mark.app.repository.TaskRepository
import com.mark.app.repository.TaskTypeRepository
import com.mark.app.util.Coefficients
import com.mark.app.util.PriorityCalculator
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID

enum class SortMode(val label: String) {
    PRIORITY("По приоритету"),
    IMPORTANCE("Важность"),
    DEADLINE("Дедлайн"),
    AGE("Возраст задачи"),
    ALPHABETICAL("По алфавиту"),
    BY_PROJECT("По проектам"),
    DURATION("По времени")
}

class TaskViewModel(application: Application) : AndroidViewModel(application) {

    private val db = AppDatabase.getInstance(application)
    private val repo = TaskRepository(db)
    private val projectRepo = ProjectRepository(db)
    private val locationRepo = LocationRepository(db)
    private val typeRepo = TaskTypeRepository(db)

    val allTasks: LiveData<List<Task>> = repo.allTasks
    val allProjects: LiveData<List<Project>> = projectRepo.all
    val allLocations: LiveData<List<Location>> = locationRepo.all
    val allTaskTypes: LiveData<List<TaskType>> = typeRepo.all

    /**
     * Канал одноразовых ошибок для UI: Activity подписывается, показывает Toast,
     * затем вызывает [consumeError] чтобы Toast не появился повторно при ротации.
     * Раньше ошибки Room молча проглатывались try/catch — пользователь думал,
     * что задача сохранилась, хотя БД могла отказать.
     */
    private val _errors = MutableLiveData<String?>()
    val errors: LiveData<String?> = _errors
    fun consumeError() { _errors.value = null }

    /** Унифицированный helper: запускает блок на VM-scope, ловит исключение и пушит в [_errors]. */
    private fun launchTracked(errorMessage: String, block: suspend () -> Unit) {
        viewModelScope.launch {
            try { block() } catch (e: Exception) {
                _errors.postValue("$errorMessage: ${e.message ?: e.javaClass.simpleName}")
            }
        }
    }

    // ───────────────── Coefficients (приоритет/важность задач) ─────────────────

    fun getOverloadLimitMinutes(): Int {
        val prefs = getApplication<Application>().getSharedPreferences("mark_prefs", Context.MODE_PRIVATE)
        return prefs.getInt(KEY_OVERLOAD_LIMIT_MINUTES, DEFAULT_OVERLOAD_LIMIT_MINUTES)
            .coerceIn(MIN_OVERLOAD_LIMIT_MINUTES, MAX_OVERLOAD_LIMIT_MINUTES)
    }

    fun saveOverloadLimitMinutes(minutes: Int) {
        getApplication<Application>().getSharedPreferences("mark_prefs", Context.MODE_PRIVATE)
            .edit()
            .putInt(
                KEY_OVERLOAD_LIMIT_MINUTES,
                minutes.coerceIn(MIN_OVERLOAD_LIMIT_MINUTES, MAX_OVERLOAD_LIMIT_MINUTES)
            )
            .apply()
    }

    fun getLoadDurationBoost(): Float {
        val prefs = getApplication<Application>().getSharedPreferences("mark_prefs", Context.MODE_PRIVATE)
        return prefs.getFloat(KEY_LOAD_DURATION_BOOST, DEFAULT_LOAD_DURATION_BOOST)
            .coerceIn(0f, 1f)
    }

    fun saveLoadDurationBoost(boost: Float) {
        getApplication<Application>().getSharedPreferences("mark_prefs", Context.MODE_PRIVATE)
            .edit()
            .putFloat(KEY_LOAD_DURATION_BOOST, boost.coerceIn(0f, 1f))
            .apply()
    }

    fun isOverloadEnabled(): Boolean {
        val prefs = getApplication<Application>().getSharedPreferences("mark_prefs", Context.MODE_PRIVATE)
        return prefs.getBoolean(KotaTaskApp.KEY_FEATURE_OVERLOAD, true)
    }

    /** Включена ли «умная сортировка» (приоритет по коэффициентам). */
    fun isSmartSortEnabled(): Boolean {
        val prefs = getApplication<Application>().getSharedPreferences("mark_prefs", Context.MODE_PRIVATE)
        return prefs.getBoolean(KotaTaskApp.KEY_FEATURE_SMART_SORT, true)
    }

    /**
     * Сортировка «по умолчанию» для списков задач.
     * Если умная сортировка включена — по приоритету, иначе — по алфавиту.
     */
    fun defaultSortMode(): SortMode =
        if (isSmartSortEnabled()) SortMode.PRIORITY else SortMode.ALPHABETICAL

    fun getCoefficients(): Coefficients {
        val prefs = getApplication<Application>().getSharedPreferences("mark_prefs", Context.MODE_PRIVATE)
        return Coefficients(
            deadline = prefs.getFloat("coeff_deadline", 0.45f),
            importance = prefs.getFloat("coeff_importance", 0.35f),
            duration = prefs.getFloat("coeff_duration", 0.10f),
            age = prefs.getFloat("coeff_age", 0.10f)
        )
    }

    fun saveCoefficients(c: Coefficients) {
        getApplication<Application>().getSharedPreferences("mark_prefs", Context.MODE_PRIVATE)
            .edit()
            .putFloat("coeff_deadline", c.deadline)
            .putFloat("coeff_importance", c.importance)
            .putFloat("coeff_duration", c.duration)
            .putFloat("coeff_age", c.age)
            .apply()
    }

    // ───────────────── Tasks CRUD ─────────────────

    fun addTask(
        title: String, deadlineStart: String = "", deadline: String, parent: String, purpose: String,
        duration: Int, importance: String,
        projectId: String? = null, locationId: String? = null, taskTypeId: String? = null
    ) {
        val task = Task(
            id = UUID.randomUUID().toString(),
            title = title,
            deadlineStart = deadlineStart,
            deadline = deadline,
            parent = parent,
            purpose = purpose,
            duration = duration,
            importance = importance,
            status = "Стек",
            projectId = projectId,
            locationId = locationId,
            taskTypeId = taskTypeId
        )
        launchTracked("Не удалось сохранить задачу") { repo.insert(task) }
    }

    fun updateTask(
        id: String, title: String, deadlineStart: String = "", deadline: String,
        parent: String, purpose: String,
        duration: Int, importance: String,
        projectId: String? = null, locationId: String? = null, taskTypeId: String? = null
    ) {
        launchTracked("Не удалось обновить задачу") {
            val current = allTasks.value?.firstOrNull { it.id == id } ?: return@launchTracked
            repo.update(
                current.copy(
                    title         = title,
                    deadlineStart = deadlineStart,
                    deadline      = deadline,
                    parent        = parent,
                    purpose       = purpose,
                    duration      = duration,
                    importance    = importance,
                    projectId     = projectId,
                    locationId    = locationId,
                    taskTypeId    = taskTypeId,
                    needsDetails  = false
                )
            )
        }
    }

    fun getTaskById(id: String): Task? =
        allTasks.value?.firstOrNull { it.id == id }

    fun placeOnBoard(id: String, projectId: String?, position: Int? = null, allProjects: Boolean = false) =
        launchTracked("Не удалось переместить задачу") { repo.place(id, projectId, position, allProjects) }

    fun moveProjectColumn(id: String, position: Int) =
        launchTracked("Не удалось переставить проект") { projectRepo.move(id, position) }

    fun quickCapture(title: String, projectId: String? = null) {
        val task = com.mark.app.util.TaskCapture.create(title, projectId) ?: return
        launchTracked("Не удалось сохранить задачу") { repo.insert(task) }
    }

    fun completeTask(id: String) =
        launchTracked("Не удалось завершить задачу") { repo.archiveTask(id) }

    fun moveToToday(id: String) =
        launchTracked("Не удалось перенести в Сегодня") { repo.updateStatus(id, "Сегодня") }

    fun moveToStack(id: String) =
        launchTracked("Не удалось перенести в Стек") { repo.updateStatus(id, "Стек") }

    /**
     * Доступно ли отложенное планирование. Требует И включённой опции «Отложенное
     * планирование», И включённого разделения «Сегодня»/«Стек» — без раздельных
     * вкладок откладывать некуда.
     */
    fun isDeferEnabled(): Boolean {
        val prefs = getApplication<Application>().getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean(KotaTaskApp.KEY_FEATURE_DEFER, false) &&
               prefs.getBoolean(KotaTaskApp.KEY_FEATURE_SPLIT_TODAY, true)
    }

    /** Откладывает задачу на дату (ISO YYYY-MM-DD). */
    fun deferTask(id: String, dateStr: String) =
        launchTracked("Не удалось отложить задачу") { repo.setDeferredDate(id, dateStr) }

    /** Снимает отложенность (задача снова обычная в стеке). */
    fun undeferTask(id: String) =
        launchTracked("Не удалось снять отложенность") { repo.setDeferredDate(id, "") }

    /** Catch-up: переносит в «Сегодня» все отложенные задачи, чья дата уже наступила. */
    fun promoteDueDeferred() =
        launchTracked("Не удалось обновить отложенные задачи") {
            repo.promoteDueDeferred(LocalDate.now().toString())
        }

    fun deleteTask(id: String) =
        launchTracked("Не удалось удалить задачу") { repo.deleteById(id) }

    // ───────────────── Category CRUD ─────────────────

    fun addProject(name: String, onCreated: ((Project) -> Unit)? = null) {
        val p = Project(id = UUID.randomUUID().toString(), name = name.trim())
        launchTracked("Не удалось создать проект") {
            projectRepo.insert(p); onCreated?.invoke(p)
        }
    }
    fun renameProject(id: String, newName: String) =
        launchTracked("Не удалось переименовать проект") {
            val cur = projectRepo.getById(id) ?: return@launchTracked
            projectRepo.update(cur.copy(name = newName.trim(), updated = System.currentTimeMillis()))
        }
    fun deleteProject(id: String) =
        launchTracked("Не удалось удалить проект") { projectRepo.delete(id) }

    fun addLocation(name: String, onCreated: ((Location) -> Unit)? = null) {
        val l = Location(id = UUID.randomUUID().toString(), name = name.trim())
        launchTracked("Не удалось создать локацию") {
            locationRepo.insert(l); onCreated?.invoke(l)
        }
    }
    fun renameLocation(id: String, newName: String) =
        launchTracked("Не удалось переименовать локацию") {
            val cur = locationRepo.getById(id) ?: return@launchTracked
            locationRepo.update(cur.copy(name = newName.trim(), updated = System.currentTimeMillis()))
        }
    fun deleteLocation(id: String) =
        launchTracked("Не удалось удалить локацию") { locationRepo.delete(id) }

    fun addTaskType(name: String, onCreated: ((TaskType) -> Unit)? = null) {
        val t = TaskType(id = UUID.randomUUID().toString(), name = name.trim())
        launchTracked("Не удалось создать тип") {
            typeRepo.insert(t); onCreated?.invoke(t)
        }
    }
    fun renameTaskType(id: String, newName: String) =
        launchTracked("Не удалось переименовать тип") {
            val cur = typeRepo.getById(id) ?: return@launchTracked
            typeRepo.update(cur.copy(name = newName.trim(), updated = System.currentTimeMillis()))
        }
    fun deleteTaskType(id: String) =
        launchTracked("Не удалось удалить тип") { typeRepo.delete(id) }

    // ───────────────── Sorting / filtering ─────────────────

    fun getSortedTasks(tasks: List<Task>, status: String, mode: SortMode = SortMode.PRIORITY): List<Task> {
        val filtered = tasks.filter { it.status == status }
        if (status == "Архив") return filtered.sortedByDescending { it.completed }
        return applySortMode(filtered, tasks, mode)
    }

    fun applySortMode(tasks: List<Task>, allTasks: List<Task>, mode: SortMode): List<Task> {
        val coeffs = getCoefficients()
        val todayLoad = allTasks.filter { it.status == "Сегодня" }.sumOf { it.duration }
        val overloadLimit = if (isOverloadEnabled()) getOverloadLimitMinutes() else Int.MAX_VALUE / 2
        val loadDurationBoost = if (isOverloadEnabled()) getLoadDurationBoost() else 0f
        val impOrder = mapOf("Высокая" to 0, "Средняя" to 1, "Низкая" to 2)
        return when (mode) {
            SortMode.PRIORITY ->
                tasks.sortedByDescending {
                    PriorityCalculator.calcPriority(it, coeffs, todayLoad, overloadLimit, loadDurationBoost)
                }
            SortMode.IMPORTANCE ->
                tasks.sortedWith(compareBy({ impOrder[it.importance] ?: 1 }, { it.title }))
            SortMode.DEADLINE ->
                tasks.sortedWith(compareBy(
                    { if (it.deadline.isBlank()) 1 else 0 },
                    { it.deadline }
                ))
            SortMode.AGE ->
                tasks.sortedBy { it.created }
            SortMode.ALPHABETICAL ->
                tasks.sortedBy { it.title }
            SortMode.BY_PROJECT -> {
                // Группируем по имени проекта (резолвим projectId → name).
                // Раньше сортировка шла по legacy-полю parent, которое всегда
                // пустое, поэтому «По проектам» фактически не работала.
                // Задачи без проекта уезжают в конец (sentinel "￿").
                val projectNames = allProjects.value.orEmpty().associate { it.id to it.name }
                tasks.sortedWith(compareBy(
                    { task -> task.projectId?.let { projectNames[it] } ?: "￿" },
                    { task -> impOrder[task.importance] ?: 1 },
                    { task -> task.title }
                ))
            }
            SortMode.DURATION ->
                tasks.sortedBy { it.duration }
        }
    }

    fun calcScore(task: Task, tasks: List<Task>): Float {
        val coeffs = getCoefficients()
        val todayLoad = tasks.filter { it.status == "Сегодня" }.sumOf { it.duration }
        return PriorityCalculator.calcPriority(
            task,
            coeffs,
            todayLoad,
            getOverloadLimitMinutes(),
            getLoadDurationBoost()
        )
    }

    fun getProjectSuggestions(tasks: List<Task>): List<String> {
        val now = System.currentTimeMillis()
        val threeDaysMs = 3L * 24 * 60 * 60 * 1000
        return tasks
            .filter { t ->
                t.parent.isNotBlank() && (
                    t.status == "Стек" || t.status == "Сегодня" ||
                    (t.status == "Архив" && t.completed > 0 && (now - t.completed) <= threeDaysMs)
                )
            }
            .map { it.parent }
            .distinct()
            .sorted()
    }

    // ───────────────── Calendar display mode ─────────────────

    /**
     * Возвращает текущий режим отображения дедлайнов в календаре:
     *   "range" — задача видна весь период [deadlineStart, deadline]
     *   "point" — задача видна только в день окончания дедлайна
     */
    fun getCalendarMode(): String {
        val prefs = getApplication<Application>()
            .getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(KotaTaskApp.KEY_CALENDAR_MODE, "range") ?: "range"
    }

    fun saveCalendarMode(mode: String) {
        getApplication<Application>()
            .getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(KotaTaskApp.KEY_CALENDAR_MODE, mode).apply()
    }

    /**
     * Возвращает активные задачи для заданной даты.
     *
     * [rangeMode] = true  → «Диапазон»: задача включается если дата попадает в [deadlineStart, deadline].
     *                        Если deadlineStart не задан — начало считается от даты создания задачи.
     * [rangeMode] = false → «Точка»:    задача включается только если deadline == dateStr (старое поведение).
     */
    fun getTasksByDeadline(tasks: List<Task>, dateStr: String, rangeMode: Boolean = true): List<Task> {
        val date = try { LocalDate.parse(dateStr) } catch (e: Exception) { return emptyList() }
        return tasks
            .filter { task ->
                (task.status == "Стек" || task.status == "Сегодня") &&
                task.deadline.isNotBlank() &&
                if (rangeMode) {
                    val endDate = try { LocalDate.parse(task.deadline) } catch (e: Exception) { return@filter false }
                    val startDate = if (task.deadlineStart.isNotBlank()) {
                        try { LocalDate.parse(task.deadlineStart) } catch (e: Exception) { endDate }
                    } else {
                        Instant.ofEpochMilli(task.created).atZone(ZoneId.systemDefault()).toLocalDate()
                    }
                    !date.isBefore(startDate) && !date.isAfter(endDate)
                } else {
                    // Режим «Точка»: только в день дедлайна
                    task.deadline == dateStr
                }
            }
            .sortedWith(compareBy({ if (it.status == "Сегодня") 0 else 1 }, { it.title }))
    }

    fun deleteArchiveTasks(ids: List<String>) =
        launchTracked("Не удалось удалить выбранные задачи") { repo.deleteByIds(ids) }

    fun deleteAllArchive() =
        launchTracked("Не удалось очистить архив") { repo.deleteAllArchived() }

    // ───────────────── Category-based filtering for Folders + Stack ─────────────────

    /**
     * Sentinel-значения для фильтров "Без X" (в отличие от null = "Все").
     */
    companion object {
        const val FILTER_ANY = ""             // "Все" — не фильтровать
        const val FILTER_NONE = "__none__"    // "Без X" — задачи с null
        const val MIN_OVERLOAD_LIMIT_MINUTES = 120
        const val MAX_OVERLOAD_LIMIT_MINUTES = 960
        const val DEFAULT_OVERLOAD_LIMIT_MINUTES = 180
        const val DEFAULT_LOAD_DURATION_BOOST = 0.2f
        private const val KEY_OVERLOAD_LIMIT_MINUTES = "overload_limit_minutes"
        private const val KEY_LOAD_DURATION_BOOST = "load_duration_boost"
    }

    /**
     * Фильтрует список задач по комбинации категорий.
     * Каждый фильтр:
     *   null или FILTER_ANY → не применять
     *   FILTER_NONE         → только задачи с null в этом поле
     *   конкретный id       → только задачи с этим id
     */
    fun applyCategoryFilters(
        tasks: List<Task>,
        projectFilter: String?,
        locationFilter: String?,
        typeFilter: String?
    ): List<Task> {
        return tasks.filter { t ->
            val pOk = when (projectFilter) {
                null, FILTER_ANY -> true
                FILTER_NONE      -> t.projectId == null
                else             -> t.projectId == projectFilter
            }
            val lOk = when (locationFilter) {
                null, FILTER_ANY -> true
                FILTER_NONE      -> t.locationId == null
                else             -> t.locationId == locationFilter
            }
            val tOk = when (typeFilter) {
                null, FILTER_ANY -> true
                FILTER_NONE      -> t.taskTypeId == null
                else             -> t.taskTypeId == typeFilter
            }
            pOk && lOk && tOk
        }
    }

    /** Активные задачи: Стек + Сегодня (исключает архив). */
    fun activeTasks(all: List<Task>): List<Task> =
        all.filter { it.status == "Стек" || it.status == "Сегодня" }
}
