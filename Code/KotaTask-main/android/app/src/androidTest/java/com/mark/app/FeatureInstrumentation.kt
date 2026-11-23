package com.mark.app

import android.app.Activity
import android.app.Instrumentation
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.os.Bundle
import android.os.SystemClock
import android.widget.EditText
import androidx.room.Room
import com.mark.app.data.AppDatabase
import com.mark.app.data.Project
import com.mark.app.repository.TaskRepository
import com.mark.app.ui.QuickCaptureActivity
import com.mark.app.ui.MainActivity
import com.mark.app.ui.TaskExportActivity
import com.mark.app.data.Task
import android.view.View
import android.view.ViewGroup
import android.view.MotionEvent
import android.widget.TextView
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.mark.app.util.BackupExportManager
import com.mark.app.util.TaskCapture
import com.mark.app.widget.QuickAddWidget
import kotlinx.coroutines.runBlocking

/** Проверяет реальную Room-миграцию и ввод из виджета без внешних test-runner зависимостей. */
class FeatureInstrumentation : Instrumentation() {
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }

    override fun onStart() {
        val tests = listOf(
            "migrationPreservesV4Tasks" to { migrationAndPersistence() },
            "widgetCapturesOnlyTitle" to { widgetCapture() },
            "navigationBoardAndExport" to { appNavigationAndExport() }
        )
        var failures = 0
        tests.forEachIndexed { index, (name, body) ->
            val status = Bundle().apply {
                putString("class", this@FeatureInstrumentation.javaClass.name); putString("test", name)
                putInt("numtests", tests.size); putInt("current", index + 1)
            }
            sendStatus(1, status)
            try {
                body()
                sendStatus(0, status)
            } catch (failure: Throwable) {
                failures++
                status.putString("stack", failure.stackTraceToString())
                sendStatus(-2, status)
            }
        }
        finish(Activity.RESULT_OK, Bundle().apply {
            putString("stream", if (failures == 0) "\nOK (${tests.size} tests)\n" else "\nFAILURES: $failures\n")
        })
    }

    private fun migrationAndPersistence() = runBlocking {
        val name = "feature-migration-test.db"
        val restoredName = "feature-backup-test.db"
        targetContext.deleteDatabase(name); targetContext.deleteDatabase(restoredName)
        val file = targetContext.getDatabasePath(name).apply { parentFile?.mkdirs() }
        SQLiteDatabase.openOrCreateDatabase(file, null).use { old ->
            old.execSQL("""CREATE TABLE tasks (
                id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, deadline TEXT NOT NULL,
                deadlineStart TEXT NOT NULL, parent TEXT NOT NULL, purpose TEXT NOT NULL,
                duration INTEGER NOT NULL, importance TEXT NOT NULL, status TEXT NOT NULL,
                assignee TEXT NOT NULL, created INTEGER NOT NULL, completed INTEGER NOT NULL,
                projectId TEXT, locationId TEXT, taskTypeId TEXT, deferredDate TEXT NOT NULL
            )""")
            old.execSQL("CREATE TABLE projects (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, color TEXT, created INTEGER NOT NULL, updated INTEGER NOT NULL)")
            old.execSQL("CREATE TABLE locations (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, created INTEGER NOT NULL, updated INTEGER NOT NULL)")
            old.execSQL("CREATE TABLE task_types (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, created INTEGER NOT NULL, updated INTEGER NOT NULL)")
            old.execSQL("INSERT INTO projects VALUES ('p', 'Проект', NULL, 1, 1)")
            old.execSQL("INSERT INTO tasks VALUES ('old', 'Старая задача', '2026-12-01', '', '', 'Контекст', 45, 'Высокая', 'Сегодня', '', 1, 0, 'p', NULL, NULL, '')")
            old.version = 4
        }
        val db = Room.databaseBuilder(targetContext, AppDatabase::class.java, name)
            .addMigrations(AppDatabase.MIGRATION_4_5).build()
        val restored = Room.databaseBuilder(targetContext, AppDatabase::class.java, restoredName).build()
        try {
            val old = db.taskDao().getAllTasksOnce().single()
            check(old.title == "Старая задача" && old.projectId == "p" && old.duration == 45)
            check(!old.needsDetails && old.status == "Сегодня")
            check(db.openHelper.writableDatabase.version == 5)
            db.projectDao().insert(Project("b", "Другой", sortIndex = 1.0))
            val repo = TaskRepository(db)
            val quick = checkNotNull(TaskCapture.create("Быстро", "p"))
            repo.insert(quick)
            repo.place("old", "b", 0)
            check(db.taskDao().getAllTasksOnce().first { it.id == "old" }.let { it.status == "Сегодня" && it.projectId == "b" })
            check(db.taskDao().getAllTasksOnce().first { it.id == quick.id }.needsDetails)
            BackupExportManager.exportAll(targetContext, db)
            val backup = checkNotNull(BackupExportManager.readBackup(targetContext))
            check(backup.getJSONArray("projects").length() == 2)
            BackupExportManager.importTasks(targetContext, backup, restored)
            check(restored.taskDao().getAllTasksOnce().toSet() == db.taskDao().getAllTasksOnce().toSet())
            check(restored.projectDao().getAllOnce() == db.projectDao().getAllOnce())
        } finally {
            db.close(); restored.close()
            targetContext.deleteDatabase(name); targetContext.deleteDatabase(restoredName)
        }
    }

    private fun widgetCapture() {
        val provider = AppWidgetManager.getInstance(targetContext).installedProviders
            .first { it.provider.className == QuickAddWidget::class.java.name }
        if (android.os.Build.VERSION.SDK_INT >= 31) {
            check(provider.targetCellWidth == 4 && provider.targetCellHeight == 1)
        }
        val activity = startActivitySync(Intent(targetContext, QuickCaptureActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        val title = "Проверка виджета ${SystemClock.uptimeMillis()}"
        runOnMainSync {
            activity.findViewById<EditText>(R.id.quickCaptureTitle).setText(title)
            activity.findViewById<android.view.View>(R.id.quickCaptureSave).performClick()
        }
        val deadline = SystemClock.uptimeMillis() + 10_000
        while (!activity.isFinishing && SystemClock.uptimeMillis() < deadline) SystemClock.sleep(50)
        check(activity.isFinishing) { "Экран не закрылся после сохранения" }
        runBlocking {
            val saved = AppDatabase.getInstance(targetContext).taskDao().getAllTasksOnce().single { it.title == title }
            check(saved.needsDetails && saved.status == "Стек" && saved.deadline.isEmpty())
        }
    }

    private fun appNavigationAndExport() {
        targetContext.getSharedPreferences(KotaTaskApp.PREFS_NAME, 0).edit()
            .putBoolean(KotaTaskApp.KEY_ONBOARDING_DONE, true)
            .putBoolean(KotaTaskApp.KEY_NOTIF_ENABLED, false)
            .putString("bottom_navigation_order", "board,stack,settings").commit()
        targetContext.getSharedPreferences(KotaTaskApp.LOCAL_PREFS_NAME, 0).edit()
            .putBoolean(KotaTaskApp.KEY_INSTALL_INITIALIZED, true).commit()
        val db = AppDatabase.getInstance(targetContext)
        runBlocking {
            db.projectDao().insert(Project("demo-work", "Работа", sortIndex = 0.0))
            db.projectDao().insert(Project("demo-home", "Личное", sortIndex = 1.0))
            db.taskDao().insert(Task(id = "demo-move", title = "Записано на бегу", status = "Сегодня", needsDetails = true))
            db.taskDao().insert(Task(id = "demo-work-task", title = "Подготовить предложение", projectId = "demo-work", duration = 45))
        }
        val main = startActivitySync(Intent(targetContext, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        waitForIdleSync()
        runOnMainSync {
            val nav = main.findViewById<BottomNavigationView>(R.id.bottomNav)
            check(nav.menu.size() == 3 && nav.menu.getItem(0).itemId == R.id.nav_board)
            check(nav.selectedItemId == R.id.nav_board)
            check(findView(main.window.decorView) { it is TextView && it.text.toString().startsWith("Без проекта") } != null)
        }
        // Нативный long press → DragEvent → Room-транзакция.
        var source: View? = null
        runOnMainSync { source = findView(main.window.decorView) { it.contentDescription?.toString()?.startsWith("Записано на бегу.") == true } }
        val card = checkNotNull(source)
        val location = IntArray(2)
        runOnMainSync { card.getLocationOnScreen(location) }
        val fromX = location[0] + card.width / 2f
        val fromY = location[1] + card.height / 2f
        val toX = main.resources.displayMetrics.widthPixels - 70f
        drag(fromX, fromY, toX, fromY)
        val timeout = SystemClock.uptimeMillis() + 5_000
        var moved = false
        while (!moved && SystemClock.uptimeMillis() < timeout) {
            moved = runBlocking { db.taskDao().getAllTasksOnce().first { it.id == "demo-move" }.projectId == "demo-work" }
            if (!moved) SystemClock.sleep(50)
        }
        check(moved) { "Перетаскивание не сменило проект" }
        check(runBlocking { db.taskDao().getAllTasksOnce().first { it.id == "demo-move" }.status } == "Сегодня")

        // Полная форма снимает пометку только после успешного сохранения.
        runOnMainSync { main.openEditTask("demo-move") }
        waitForIdleSync()
        runOnMainSync {
            main.findViewById<EditText>(R.id.editDeadline).setText("2026-12-01")
            main.findViewById<View>(R.id.btnAddTask).performClick()
        }
        val detailsTimeout = SystemClock.uptimeMillis() + 5_000
        var completed = false
        while (!completed && SystemClock.uptimeMillis() < detailsTimeout) {
            completed = runBlocking { !db.taskDao().getAllTasksOnce().first { it.id == "demo-move" }.needsDetails }
            if (!completed) SystemClock.sleep(50)
        }
        check(completed) { "Полная форма не сняла пометку черновика" }

        runOnMainSync { main.showNavigationEditor() }
        waitForIdleSync()
        val root = checkNotNull(uiAutomation.rootInActiveWindow)
        val archive = root.findAccessibilityNodeInfosByText("Архив").first { it.isCheckable }
        check(archive.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK))
        waitForIdleSync()
        val up = uiAutomation.rootInActiveWindow.findAccessibilityNodeInfosByText("Архив — левее").first()
        check(up.performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK))
        waitForIdleSync()
        check(uiAutomation.rootInActiveWindow.findAccessibilityNodeInfosByText("Сохранить").first()
            .performAction(android.view.accessibility.AccessibilityNodeInfo.ACTION_CLICK))
        waitForIdleSync()
        val savedMenu = targetContext.getSharedPreferences(KotaTaskApp.PREFS_NAME, 0).getString("bottom_navigation_order", "")
        check(savedMenu == "board,stack,archive,settings") { "Состав и порядок меню не сохранены: $savedMenu" }
        runOnMainSync {
            val nav = main.findViewById<BottomNavigationView>(R.id.bottomNav)
            check(nav.menu.size() == 4 && nav.menu.getItem(2).itemId == R.id.nav_archive)
            check(nav.selectedItemId == R.id.nav_board)
        }
        runOnMainSync { main.openTaskExport() }
        val exportMonitor = addMonitor(TaskExportActivity::class.java.name, null, false)
        // Экран может уже открыться до регистрации монитора; содержание проверяем через accessibility.
        val exportTimeout = SystemClock.uptimeMillis() + 5_000
        var exported = false
        while (!exported && SystemClock.uptimeMillis() < exportTimeout) {
            val root = uiAutomation.rootInActiveWindow
            exported = root?.findAccessibilityNodeInfosByText("Пояснения столбцов")?.isNotEmpty() == true
            if (!exported) SystemClock.sleep(100)
        }
        removeMonitor(exportMonitor)
        check(exported) { "Предпросмотр экспорта не появился" }
        sendKeyDownUpSync(android.view.KeyEvent.KEYCODE_BACK)
    }

    private fun drag(x: Float, y: Float, targetX: Float, targetY: Float) {
        val down = SystemClock.uptimeMillis()
        fun event(action: Int, px: Float, py: Float) {
            val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, px, py, 0).apply {
                source = android.view.InputDevice.SOURCE_TOUCHSCREEN
            }
            // При native drag окно ввода принадлежит системе, а не Activity.
            check(uiAutomation.injectInputEvent(event, true))
            event.recycle()
        }
        event(MotionEvent.ACTION_DOWN, x, y)
        SystemClock.sleep(750)
        for (i in 1..20) {
            event(MotionEvent.ACTION_MOVE, x + (targetX - x) * i / 20, y + (targetY - y) * i / 20)
            SystemClock.sleep(25)
        }
        SystemClock.sleep(350)
        event(MotionEvent.ACTION_UP, targetX, targetY)
        waitForIdleSync()
    }

    private fun findView(root: View, matches: (View) -> Boolean): View? {
        if (matches(root)) return root
        if (root is ViewGroup) for (i in 0 until root.childCount) {
            findView(root.getChildAt(i), matches)?.let { return it }
        }
        return null
    }
}
