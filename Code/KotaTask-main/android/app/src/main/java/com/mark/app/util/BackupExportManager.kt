package com.mark.app.util

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import com.mark.app.KotaTaskApp
import com.mark.app.data.AppDatabase
import com.mark.app.data.Task
import com.mark.app.data.Project
import com.mark.app.data.Location
import com.mark.app.data.TaskType
import androidx.room.withTransaction
import androidx.annotation.RequiresApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.OutputStreamWriter

/**
 * Локальный бэкап поверх Android Auto Backup.
 *
 * Проблема: Auto Backup работает максимум 1 раз в сутки и только при зарядке + WiFi + idle.
 * Если пользователь изменил настройки между двумя бэкапами и удалил приложение,
 * изменения теряются. Этот менеджер пишет снимок настроек + задач в файл
 * Downloads/kotatask_backup.json при каждом уходе приложения в фон.
 * Downloads не очищается при удалении приложения, поэтому файл доступен при переустановке.
 *
 * Стратегия восстановления:
 *  • Настройки — всегда из локального бэкапа (он свежее Auto Backup).
 *  • Задачи    — из Room (Auto Backup), локальный бэкап применяется только если
 *                БД пуста (Auto Backup не отработал или данных не было).
 *
 * Работает только на API 29+. На API 26–28 приложение полностью полагается на Auto Backup.
 */
object BackupExportManager {

    private const val FILENAME = "kotatask_backup.json"
    private const val FORMAT_VERSION = 3

    // ─────────────────────────── EXPORT ───────────────────────────

    /**
     * Экспортирует настройки и задачи в Downloads/kotatask_backup.json.
     * Вызывается из фонового потока при каждом уходе приложения в фон.
     */
    suspend fun exportAll(context: Context, db: AppDatabase) = withContext(Dispatchers.IO) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return@withContext
        try {
            val json = JSONObject()
            json.put("version",   FORMAT_VERSION)
            json.put("timestamp", System.currentTimeMillis())
            json.put("settings",  buildSettingsJson(context))
            db.withTransaction {
                json.put("tasks", buildTasksJson(db))
                json.put("projects", JSONArray().apply {
                    db.projectDao().getAllOnce().forEach { p ->
                        put(JSONObject().apply {
                            put("id", p.id); put("name", p.name); put("color", p.color)
                            put("created", p.created); put("updated", p.updated); put("sortIndex", p.sortIndex)
                        })
                    }
                })
                json.put("locations", JSONArray().apply {
                    db.locationDao().getAllOnce().forEach { p ->
                        put(JSONObject().apply {
                            put("id", p.id); put("name", p.name); put("created", p.created); put("updated", p.updated)
                        })
                    }
                })
                json.put("taskTypes", JSONArray().apply {
                    db.taskTypeDao().getAllOnce().forEach { p ->
                        put(JSONObject().apply {
                            put("id", p.id); put("name", p.name); put("created", p.created); put("updated", p.updated)
                        })
                    }
                })
            }
            writeToDownloads(context, json.toString())
        } catch (_: Exception) { }
    }

    private fun buildSettingsJson(context: Context): JSONObject {
        val prefs = context.getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
        val floats   = JSONObject()
        val ints     = JSONObject()
        val booleans = JSONObject()
        val strings  = JSONObject()

        prefs.all.forEach { (key, value) ->
            when (value) {
                is Float   -> floats.put(key, value.toDouble())
                is Int     -> ints.put(key, value)
                is Long    -> ints.put(key, value)
                is Boolean -> booleans.put(key, value)
                is String  -> strings.put(key, value)
            }
        }

        return JSONObject().apply {
            put("floats",   floats)
            put("ints",     ints)
            put("booleans", booleans)
            put("strings",  strings)
        }
    }

    private suspend fun buildTasksJson(db: AppDatabase): JSONArray {
        val array = JSONArray()
        db.taskDao().getAllTasksOnce().forEach { t ->
            array.put(JSONObject().apply {
                put("id",           t.id)
                put("title",        t.title)
                put("deadline",     t.deadline)
                put("deadlineStart",t.deadlineStart)
                put("parent",       t.parent)
                put("purpose",      t.purpose)
                put("duration",     t.duration)
                put("importance",   t.importance)
                put("status",       t.status)
                put("assignee",     t.assignee)
                put("created",      t.created)
                put("completed",    t.completed)
                put("projectId",    t.projectId  ?: "")
                put("locationId",   t.locationId ?: "")
                put("taskTypeId",   t.taskTypeId ?: "")
                put("deferredDate", t.deferredDate)
                put("needsDetails", t.needsDetails)
                put("sortIndex", t.sortIndex)
            })
        }
        return array
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun writeToDownloads(context: Context, content: String) {
        val resolver = context.contentResolver
        // Удаляем старый файл
        resolver.query(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            arrayOf(MediaStore.Downloads._ID),
            "${MediaStore.Downloads.DISPLAY_NAME} = ?",
            arrayOf(FILENAME), null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val id  = cursor.getLong(0)
                val uri = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                    .buildUpon().appendPath(id.toString()).build()
                resolver.delete(uri, null, null)
            }
        }
        // Пишем новый
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, FILENAME)
            put(MediaStore.Downloads.MIME_TYPE,    "application/json")
        }
        val uri: Uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: return
        resolver.openOutputStream(uri)?.use { stream ->
            OutputStreamWriter(stream).use { it.write(content) }
        }
    }

    // ─────────────────────────── IMPORT ───────────────────────────

    /**
     * Читает JSON из Downloads. Быстрая операция (~KB), допустима на main thread.
     * Возвращает null если файла нет или API < 29.
     */
    fun readBackup(context: Context): JSONObject? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return try {
            val resolver = context.contentResolver
            val id = resolver.query(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                arrayOf(MediaStore.Downloads._ID),
                "${MediaStore.Downloads.DISPLAY_NAME} = ?",
                arrayOf(FILENAME), null
            )?.use { c -> if (c.moveToFirst()) c.getLong(0) else null } ?: return null

            val uri = MediaStore.Downloads.EXTERNAL_CONTENT_URI
                .buildUpon().appendPath(id.toString()).build()
            val text = resolver.openInputStream(uri)
                ?.use { it.bufferedReader().readText() }
                ?: return null
            JSONObject(text)
        } catch (_: Exception) { null }
    }

    /**
     * Применяет настройки из бэкапа к SharedPreferences.
     * Использует commit() для гарантированной записи на диск.
     * Не перезаписывает KEY_ONBOARDING_DONE — им управляет OnboardingActivity.
     */
    fun applySettings(context: Context, backup: JSONObject) {
        val settings = backup.optJSONObject("settings") ?: return
        val prefs    = context.getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
        val editor   = prefs.edit()

        val skip = setOf(KotaTaskApp.KEY_ONBOARDING_DONE)

        settings.optJSONObject("floats")?.let { obj ->
            obj.keys().forEach { key ->
                if (key !in skip) editor.putFloat(key, obj.getDouble(key).toFloat())
            }
        }
        settings.optJSONObject("ints")?.let { obj ->
            obj.keys().forEach { key ->
                if (key !in skip) {
                    // JSON возвращает числа как Int или Long
                    val raw = obj.get(key)
                    if (raw is Long) editor.putLong(key, raw)
                    else             editor.putInt(key, obj.getInt(key))
                }
            }
        }
        settings.optJSONObject("booleans")?.let { obj ->
            obj.keys().forEach { key ->
                if (key !in skip) editor.putBoolean(key, obj.getBoolean(key))
            }
        }
        settings.optJSONObject("strings")?.let { obj ->
            obj.keys().forEach { key ->
                if (key !in skip) editor.putString(key, obj.getString(key))
            }
        }

        editor.commit()
    }

    /**
     * Импортирует задачи из бэкапа в Room (INSERT OR REPLACE).
     * Вызывается только когда БД пуста — Auto Backup не отработал.
     */
    suspend fun importTasks(context: Context, backup: JSONObject, db: AppDatabase) =
        withContext(Dispatchers.IO) {
            try {
                val array = backup.optJSONArray("tasks") ?: return@withContext
                db.withTransaction {
                backup.optJSONArray("projects")?.let { items ->
                    for (i in 0 until items.length()) {
                        val j = items.getJSONObject(i)
                        db.projectDao().insert(Project(j.getString("id"), j.getString("name"),
                            color = j.optString("color", "").ifEmpty { null },
                            created = j.optLong("created"), updated = j.optLong("updated"),
                            sortIndex = j.optDouble("sortIndex", i.toDouble())))
                    }
                }
                backup.optJSONArray("locations")?.let { items ->
                    for (i in 0 until items.length()) {
                        val j = items.getJSONObject(i)
                        db.locationDao().insert(Location(j.getString("id"), j.getString("name"),
                            created = j.optLong("created"), updated = j.optLong("updated")))
                    }
                }
                backup.optJSONArray("taskTypes")?.let { items ->
                    for (i in 0 until items.length()) {
                        val j = items.getJSONObject(i)
                        db.taskTypeDao().insert(TaskType(j.getString("id"), j.getString("name"),
                            created = j.optLong("created"), updated = j.optLong("updated")))
                    }
                }
                for (i in 0 until array.length()) {
                    val j = array.getJSONObject(i)
                    db.taskDao().insert(Task(
                        id           = j.getString("id"),
                        title        = j.getString("title"),
                        deadline     = j.optString("deadline",      ""),
                        deadlineStart= j.optString("deadlineStart", ""),
                        parent       = j.optString("parent",        ""),
                        purpose      = j.optString("purpose",       ""),
                        duration     = j.optInt("duration",         30),
                        importance   = j.optString("importance",    "Средняя"),
                        status       = j.optString("status",        "Стек"),
                        assignee     = j.optString("assignee",      ""),
                        created      = j.optLong("created",         System.currentTimeMillis()),
                        completed    = j.optLong("completed",       0L),
                        projectId    = j.optString("projectId",  "").ifEmpty { null },
                        locationId   = j.optString("locationId", "").ifEmpty { null },
                        taskTypeId   = j.optString("taskTypeId", "").ifEmpty { null },
                        deferredDate = j.optString("deferredDate",  ""),
                        needsDetails = j.optBoolean("needsDetails", false),
                        sortIndex = j.optDouble("sortIndex", i.toDouble())
                    ))
                }
                }
            } catch (_: Exception) { }
        }

    /** Метка времени последнего бэкапа (мс). 0 если файла нет. */
    fun backupTimestamp(context: Context): Long =
        readBackup(context)?.optLong("timestamp", 0L) ?: 0L
}
