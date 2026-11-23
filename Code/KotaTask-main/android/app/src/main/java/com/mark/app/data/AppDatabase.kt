package com.mark.app.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [
        Task::class,
        Project::class,
        Location::class,
        TaskType::class
    ],
    version = 5,
    exportSchema = false
)
abstract class AppDatabase : RoomDatabase() {

    abstract fun taskDao(): TaskDao
    abstract fun projectDao(): ProjectDao
    abstract fun locationDao(): LocationDao
    abstract fun taskTypeDao(): TaskTypeDao

    companion object {
        @Volatile private var INSTANCE: AppDatabase? = null

        /**
         * v1 → v2 миграция:
         *   • Tasks: 3 новых nullable-колонки (projectId, locationId, taskTypeId).
         *   • 3 новые таблицы для категорий.
         * Существующие задачи сохраняются. Поля категорий становятся NULL.
         */
        private val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                // 1) расширяем tasks
                db.execSQL("ALTER TABLE tasks ADD COLUMN projectId TEXT DEFAULT NULL")
                db.execSQL("ALTER TABLE tasks ADD COLUMN locationId TEXT DEFAULT NULL")
                db.execSQL("ALTER TABLE tasks ADD COLUMN taskTypeId TEXT DEFAULT NULL")

                // 2) projects
                db.execSQL("""
                    CREATE TABLE IF NOT EXISTS `projects` (
                        `id` TEXT NOT NULL,
                        `name` TEXT NOT NULL,
                        `color` TEXT,
                        `created` INTEGER NOT NULL,
                        `updated` INTEGER NOT NULL,
                        PRIMARY KEY(`id`)
                    )
                """.trimIndent())

                // 3) locations
                db.execSQL("""
                    CREATE TABLE IF NOT EXISTS `locations` (
                        `id` TEXT NOT NULL,
                        `name` TEXT NOT NULL,
                        `created` INTEGER NOT NULL,
                        `updated` INTEGER NOT NULL,
                        PRIMARY KEY(`id`)
                    )
                """.trimIndent())

                // 4) task_types
                db.execSQL("""
                    CREATE TABLE IF NOT EXISTS `task_types` (
                        `id` TEXT NOT NULL,
                        `name` TEXT NOT NULL,
                        `created` INTEGER NOT NULL,
                        `updated` INTEGER NOT NULL,
                        PRIMARY KEY(`id`)
                    )
                """.trimIndent())
            }
        }

        /**
         * v2 → v3 миграция:
         *   • Tasks: добавляем deadlineStart — начало диапазона дедлайна.
         *     NOT NULL DEFAULT '' → существующие задачи получат пустую строку,
         *     что означает «начало = дата создания задачи».
         */
        private val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE tasks ADD COLUMN deadlineStart TEXT NOT NULL DEFAULT ''")
            }
        }

        /**
         * v3 → v4 миграция:
         *   • Tasks: добавляем deferredDate — ISO-дата отложенного планирования.
         *     NOT NULL DEFAULT '' → существующие задачи не отложены.
         */
        private val MIGRATION_3_4 = object : Migration(3, 4) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE tasks ADD COLUMN deferredDate TEXT NOT NULL DEFAULT ''")
            }
        }

        val MIGRATION_4_5 = object : Migration(4, 5) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE tasks ADD COLUMN needsDetails INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE tasks ADD COLUMN sortIndex REAL NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE projects ADD COLUMN sortIndex REAL NOT NULL DEFAULT 0")
                // ISO-даты и существующие поля не меняются. Начальный порядок — новые сверху.
                db.execSQL("""UPDATE tasks SET sortIndex = (
                    SELECT COUNT(*) FROM tasks AS other
                    WHERE other.projectId IS tasks.projectId AND
                    (other.created > tasks.created OR (other.created = tasks.created AND other.id < tasks.id))
                )""")
                db.execSQL("""UPDATE projects SET sortIndex = (
                    SELECT COUNT(*) FROM projects AS other
                    WHERE other.name < projects.name COLLATE NOCASE OR
                    (other.name = projects.name COLLATE NOCASE AND other.id < projects.id)
                )""")
            }
        }

        fun getInstance(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                // Намеренно НЕ используем fallbackToDestructiveMigration:
                // потеря всех задач при ошибке миграции — худший возможный сценарий
                // для таск-менеджера. Любая будущая версия схемы ОБЯЗАНА иметь
                // явную Migration(N-1, N), иначе приложение упадёт при старте,
                // а данные останутся целыми.
                //
                // JournalMode.TRUNCATE: каждая запись фиксируется прямо в mark_db,
                // WAL-файл не создаётся. Auto Backup всегда видит актуальное состояние
                // базы без необходимости делать wal_checkpoint перед резервным копированием.
                // При первом открытии существующей WAL-базы Room автоматически переключит
                // режим и сбросит текущий WAL в основной файл.
                Room.databaseBuilder(context.applicationContext, AppDatabase::class.java, "mark_db")
                    .addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5)
                    .setJournalMode(RoomDatabase.JournalMode.TRUNCATE)
                    .build()
                    .also { INSTANCE = it }
            }
        }
    }
}
