package com.mark.app

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import androidx.appcompat.app.AppCompatDelegate
import com.mark.app.data.AppDatabase
import com.mark.app.util.BackupExportManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class KotaTaskApp : Application() {

    private var startedActivities = 0

    override fun onCreate() {
        super.onCreate()
        applyTheme(this)
        registerBackgroundExport()
    }

    /**
     * При уходе приложения в фон записывает снимок настроек и задач в
     * Downloads/kotatask_backup.json. Этот файл НЕ удаляется при удалении
     * приложения, поэтому на переустановке мы считаем его и восстанавливаем
     * актуальное состояние — в отличие от Auto Backup, который запускается
     * максимум раз в сутки и может быть устаревшим.
     */
    private fun registerBackgroundExport() {
        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityStarted(activity: Activity)  { startedActivities++ }
            override fun onActivityStopped(activity: Activity)  {
                if (--startedActivities <= 0) {
                    CoroutineScope(Dispatchers.IO).launch {
                        BackupExportManager.exportAll(
                            applicationContext,
                            AppDatabase.getInstance(applicationContext)
                        )
                    }
                }
            }
            override fun onActivityCreated(a: Activity, b: Bundle?) {}
            override fun onActivityResumed(a: Activity)  {}
            override fun onActivityPaused(a: Activity)   {}
            override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
            override fun onActivityDestroyed(a: Activity) {}
        })
    }

    companion object {
        const val PREFS_NAME = "mark_prefs"
        const val KEY_THEME = "theme_mode"
        /** "range" — задача видна весь диапазон; "point" — только в день дедлайна */
        const val KEY_CALENDAR_MODE = "calendar_mode"

        // Ежедневные напоминания
        const val KEY_NOTIF_ENABLED = "notif_enabled"
        const val KEY_NOTIF_HOUR    = "notif_hour"
        const val KEY_NOTIF_MINUTE  = "notif_minute"
        const val DEFAULT_NOTIF_HOUR   = 8
        const val DEFAULT_NOTIF_MINUTE = 0

        // Onboarding
        const val KEY_ONBOARDING_DONE = "onboarding_done"

        /**
         * Локальные настройки, НЕ попадающие в Auto Backup (в backup-правилах
         * включается только mark_prefs.xml, поэтому mark_local.xml автоматически
         * исключён). Используется, чтобы отличить «чистую установку» от
         * «переустановки с восстановленными из бэкапа данными».
         */
        const val LOCAL_PREFS_NAME = "mark_local"
        /** Был ли уже первый запуск на ЭТОЙ установке (флаг живёт только локально). */
        const val KEY_INSTALL_INITIALIZED = "install_initialized"

        /** Intent-extra для OnboardingActivity: разрешить кнопку «Пропустить». */
        const val EXTRA_ALLOW_SKIP = "allow_skip"

        // Включённые возможности (выбираются в онбординге, дублируются в настройках)
        const val KEY_FEATURE_SPLIT_TODAY = "feat_split_today"
        const val KEY_FEATURE_CALENDAR    = "feat_calendar"
        const val KEY_FEATURE_PROJECTS    = "feat_projects"
        const val KEY_FEATURE_CATEGORIES  = "feat_categories"  // legacy — kept for onboarding compat
        const val KEY_FEATURE_LOCATIONS   = "feat_locations"
        const val KEY_FEATURE_TASK_TYPES  = "feat_task_types"
        const val KEY_FEATURE_SMART_SORT  = "feat_smart_sort"
        const val KEY_FEATURE_OVERLOAD    = "feat_overload"
        /** Отложенное планирование — кнопка «Отложить» в стеке. Работает только при включённом разделении Сегодня/Стек. */
        const val KEY_FEATURE_DEFER       = "feat_defer"

        // Какие поля задачи показывать в форме создания
        const val KEY_FIELD_DURATION   = "field_duration"
        const val KEY_FIELD_PURPOSE    = "field_purpose"
        const val KEY_FIELD_ASSIGNEE   = "field_assignee"
        const val KEY_FIELD_PROJECT    = "field_project"
        const val KEY_FIELD_TASK_TYPE  = "field_task_type"
        const val KEY_FIELD_LOCATION   = "field_location"

        // Уровень помощи (валидация AddTask): "minimal" | "standard" | "advanced"
        const val KEY_ASSISTANCE_LEVEL = "assistance_level"
        const val ASSISTANCE_MINIMAL  = "minimal"
        const val ASSISTANCE_STANDARD = "standard"
        const val ASSISTANCE_ADVANCED = "advanced"
        const val ASSISTANCE_CUSTOM   = "custom"
        const val DEFAULT_ASSISTANCE_LEVEL = ASSISTANCE_STANDARD

        // Какие поля обязательны при custom-уровне помощи
        const val KEY_CUSTOM_REQUIRE_DEADLINE_START = "custom_req_deadline_start"
        const val KEY_CUSTOM_REQUIRE_DEADLINE       = "custom_req_deadline"
        const val KEY_CUSTOM_REQUIRE_IMPORTANCE     = "custom_req_importance"
        const val KEY_CUSTOM_REQUIRE_DURATION       = "custom_req_duration"
        const val KEY_CUSTOM_REQUIRE_PURPOSE        = "custom_req_purpose"
        const val KEY_CUSTOM_REQUIRE_PROJECT        = "custom_req_project"
        const val KEY_CUSTOM_REQUIRE_LOCATION       = "custom_req_location"
        const val KEY_CUSTOM_REQUIRE_TASK_TYPE      = "custom_req_task_type"

        fun applyTheme(context: Context) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val mode = when (prefs.getString(KEY_THEME, "system")) {
                "light"  -> AppCompatDelegate.MODE_NIGHT_NO
                "dark"   -> AppCompatDelegate.MODE_NIGHT_YES
                else     -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
            }
            AppCompatDelegate.setDefaultNightMode(mode)
        }
    }
}
