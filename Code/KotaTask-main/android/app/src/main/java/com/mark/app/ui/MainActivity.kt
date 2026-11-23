package com.mark.app.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.Toast
import android.widget.PopupMenu
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import com.mark.app.util.MainDestination
import com.mark.app.util.NavigationConfig
import com.mark.app.widget.QuickAddWidget
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.fragment.app.FragmentManager
import com.mark.app.KotaTaskApp
import com.mark.app.R
import com.mark.app.data.AppDatabase
import com.mark.app.databinding.ActivityMainBinding
import com.mark.app.util.BackupExportManager
import com.mark.app.util.scheduleDaily
import com.mark.app.util.scheduleDeferPromotion
import com.mark.app.viewmodel.TaskViewModel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    private val vm: TaskViewModel by viewModels()
    private var currentDestination = MainDestination.TODAY
    private var syncingNavigation = false
    private val prefs get() = getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)

    private fun availableDestinations(): Set<MainDestination> = MainDestination.entries.filter {
        when (it) {
            MainDestination.TODAY -> featureSplit
            MainDestination.CALENDAR -> featureCalendar
            MainDestination.FOLDERS -> featureFolders
            else -> true
        }
    }.toSet()

    private fun navigationItems() = NavigationConfig.visible(prefs.getString(NavigationConfig.KEY, null), availableDestinations())

    // Прочитаем после прохождения онбординга и зафиксируем на время жизни активности.
    // Изменение флагов в настройках применится после следующего onCreate (recreate),
    // что и делает SettingsFragment, когда пользователь меняет эти переключатели.
    private val featureSplit: Boolean
        get() = getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KotaTaskApp.KEY_FEATURE_SPLIT_TODAY, true)

    private val featureCalendar: Boolean
        get() = getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KotaTaskApp.KEY_FEATURE_CALENDAR, true)

    /** Папки доступны если включён хотя бы один из: Проекты, Локации, Типы задач. */
    val featureFolders: Boolean
        get() = getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE).let { p ->
            p.getBoolean(KotaTaskApp.KEY_FEATURE_PROJECTS,   true) ||
            p.getBoolean(KotaTaskApp.KEY_FEATURE_LOCATIONS,  true) ||
            p.getBoolean(KotaTaskApp.KEY_FEATURE_TASK_TYPES, true)
        }

    private val notifPermLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) {}

    private val backStackListener = FragmentManager.OnBackStackChangedListener {
        val inModal = supportFragmentManager.backStackEntryCount > 0
        // Кнопка создания независима от выбранного состава нижней панели.
        // В модальной форме её скрываем.
        binding.fabAdd.isVisible = !inModal
        // Restore title to the currently-selected main destination on back
        if (!inModal) {
            binding.tvTopBarTitle.text = titleFor(currentDestination)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Первый запуск / переустановка: показать онбординг и завершить активность.
        // Проверка до inflate, чтобы не тратить время на разметку, которая
        // тут же будет заменена.
        //
        // KEY_INSTALL_INITIALIZED живёт в mark_local (НЕ бэкапится), поэтому:
        //   • его отсутствие = первый запуск на ДАННОЙ установке;
        //   • если при этом onboardingDone == true, значит настройки пришли
        //     из бэкапа (переустановка) → онбординг с кнопкой «Пропустить».
        //   • если onboardingDone == false → чистая установка, пропуск запрещён.
        val prefs      = getSharedPreferences(KotaTaskApp.PREFS_NAME,  Context.MODE_PRIVATE)
        val localPrefs = getSharedPreferences(KotaTaskApp.LOCAL_PREFS_NAME, Context.MODE_PRIVATE)
        val firstLaunchThisInstall = !localPrefs.getBoolean(KotaTaskApp.KEY_INSTALL_INITIALIZED, false)

        if (firstLaunchThisInstall) {
            localPrefs.edit().putBoolean(KotaTaskApp.KEY_INSTALL_INITIALIZED, true).apply()

            // Локальный бэкап (Downloads/kotatask_backup.json) не удаляется при удалении
            // приложения и всегда актуальнее Auto Backup. Читаем его синхронно — файл
            // маленький (~несколько KB) и операция занимает < 5 мс.
            val localBackup = BackupExportManager.readBackup(this)
            if (localBackup != null) {
                // Восстанавливаем настройки немедленно (commit, не apply).
                BackupExportManager.applySettings(this, localBackup)

                // Задачи: Room-БД уже восстановлена через Auto Backup. Задачи из
                // локального бэкапа добавляем только если БД пуста (Auto Backup не отработал).
                CoroutineScope(Dispatchers.IO).launch {
                    val db = AppDatabase.getInstance(applicationContext)
                    if (db.taskDao().getAllTasksOnce().isEmpty()) {
                        BackupExportManager.importTasks(applicationContext, localBackup, db)
                    }
                }
            }

            // Перечитываем флаг — он мог быть восстановлен из localBackup выше
            val onboardingDone = prefs.getBoolean(KotaTaskApp.KEY_ONBOARDING_DONE, false)
            startActivity(Intent(this, OnboardingActivity::class.java)
                .putExtra(KotaTaskApp.EXTRA_ALLOW_SKIP, onboardingDone))
            finish()
            return
        }
        val onboardingDone = prefs.getBoolean(KotaTaskApp.KEY_ONBOARDING_DONE, false)
        if (!onboardingDone) {
            startActivity(Intent(this, OnboardingActivity::class.java))
            finish()
            return
        }

        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        supportFragmentManager.addOnBackStackChangedListener(backStackListener)

        currentDestination = savedInstanceState?.getString("destination")?.let { key ->
            MainDestination.entries.firstOrNull { it.key == key }
        } ?: navigationItems().first()
        setupBottomNav()
        setupFab()
        setupAppMenu()
        requestNotifPermission()
        scheduleDaily(this)

        // Отложенное планирование: догоняем пропущенные переносы (если устройство
        // было выключено в 00:00) и планируем следующий перенос на полночь.
        vm.promoteDueDeferred()
        scheduleDeferPromotion(this)

        // Покажем Toast при любой ошибке БД. consumeError() предотвращает повторный
        // показ Toast при ротации (LiveData при подписке отдаёт последнее значение).
        vm.errors.observe(this) { msg ->
            if (!msg.isNullOrBlank()) {
                Toast.makeText(this, msg, Toast.LENGTH_LONG).show()
                vm.consumeError()
            }
        }

        if (savedInstanceState == null || currentDestination !in availableDestinations()) {
            navigateTo(navigationItems().first())
        } else {
            binding.tvTopBarTitle.text = titleFor(currentDestination)
        }
    }

    fun applyFeatureFlagsToNav() {
        if (!::binding.isInitialized) return
        setupBottomNav()
        if (currentDestination !in availableDestinations() || currentDestination !in navigationItems()) {
            navigateTo(navigationItems().first())
        }
    }

    private fun menuId(destination: MainDestination): Int = when (destination) {
        MainDestination.TODAY -> R.id.nav_today
        MainDestination.STACK -> R.id.nav_stack
        MainDestination.BOARD -> R.id.nav_board
        MainDestination.CALENDAR -> R.id.nav_calendar
        MainDestination.FOLDERS -> R.id.nav_folders
        MainDestination.ARCHIVE -> R.id.nav_archive
        MainDestination.SETTINGS -> R.id.nav_settings
    }

    private fun menuIcon(destination: MainDestination): Int = when (destination) {
        MainDestination.TODAY -> R.drawable.ic_target
        MainDestination.STACK -> R.drawable.ic_stack
        MainDestination.BOARD -> R.drawable.ic_board
        MainDestination.CALENDAR -> R.drawable.ic_calendar
        MainDestination.FOLDERS -> android.R.drawable.ic_menu_agenda
        MainDestination.ARCHIVE -> R.drawable.ic_archive
        MainDestination.SETTINGS -> R.drawable.ic_settings
    }

    private fun titleFor(destination: MainDestination): String = when (destination) {
        MainDestination.TODAY -> getString(R.string.screen_title_today)
        MainDestination.STACK -> getString(if (featureSplit) R.string.screen_title_stack else R.string.nav_tasks)
        MainDestination.BOARD -> "Канбан"
        MainDestination.CALENDAR -> getString(R.string.screen_title_calendar)
        MainDestination.FOLDERS -> "Папки"
        MainDestination.ARCHIVE -> "Архив"
        MainDestination.SETTINGS -> getString(R.string.screen_title_settings)
    }

    private fun setupBottomNav() {
        binding.bottomNav.setOnItemSelectedListener(null)
        binding.bottomNav.setOnItemReselectedListener(null)
        val menu = binding.bottomNav.menu
        menu.clear()
        navigationItems().forEachIndexed { index, destination ->
            menu.add(0, menuId(destination), index, titleFor(destination)).setIcon(menuIcon(destination)).isCheckable = true
        }
        if (currentDestination in navigationItems()) binding.bottomNav.selectedItemId = menuId(currentDestination)
        binding.bottomNav.setOnItemSelectedListener { item ->
            val destination = MainDestination.entries.firstOrNull { menuId(it) == item.itemId }
            if (destination != null && !syncingNavigation) navigateTo(destination)
            destination != null
        }
        binding.bottomNav.setOnItemReselectedListener { item ->
            if (!syncingNavigation) {
                MainDestination.entries.firstOrNull { menuId(it) == item.itemId }?.let(::navigateTo)
            }
        }
    }

    private fun navigateTo(destination: MainDestination) {
        if (destination !in availableDestinations()) return
        supportFragmentManager.popBackStackImmediate(null, FragmentManager.POP_BACK_STACK_INCLUSIVE)
        val fragment = when (destination) {
            MainDestination.TODAY -> TodayFragment()
            MainDestination.STACK -> if (featureSplit) StackFragment() else StackFragment.newMerged()
            MainDestination.BOARD -> KanbanFragment()
            MainDestination.CALENDAR -> CalendarFragment()
            MainDestination.FOLDERS -> FoldersFragment()
            MainDestination.ARCHIVE -> ArchiveFragment()
            MainDestination.SETTINGS -> SettingsFragment()
        }
        // Раздел, убранный с панели, открывается поверх текущего. «Назад» возвращает
        // в выбранный раздел, и подсветка нижней панели остаётся правдивой.
        if (destination !in navigationItems()) {
            openModalFragment(fragment, titleFor(destination))
            return
        }
        currentDestination = destination
        showFragment(fragment)
        binding.tvTopBarTitle.text = titleFor(destination)
        binding.fabAdd.isVisible = true
        syncingNavigation = true
        if (binding.bottomNav.selectedItemId != menuId(destination)) {
            binding.bottomNav.selectedItemId = menuId(destination)
        }
        syncingNavigation = false
    }

    fun showNavigationEditor() {
        NavigationEditor.show(this, prefs, availableDestinations(), ::titleFor) { applyFeatureFlagsToNav() }
    }

    fun openTaskExport() { startActivity(Intent(this, TaskExportActivity::class.java)) }

    fun openKanban() { navigateTo(MainDestination.BOARD) }

    fun addQuickCaptureWidget() {
        val manager = getSystemService(AppWidgetManager::class.java)
        if (manager.isRequestPinAppWidgetSupported) {
            manager.requestPinAppWidget(ComponentName(this, QuickAddWidget::class.java), null, null)
        } else {
            Toast.makeText(this, "На главном экране удерживайте пустое место → Виджеты → KotaTask", Toast.LENGTH_LONG).show()
        }
    }

    private fun setupAppMenu() {
        binding.btnDonate.text = "⋮"
        binding.btnDonate.contentDescription = "Все разделы и действия"
        binding.btnDonate.setOnClickListener { anchor ->
            PopupMenu(this, anchor).apply {
                availableDestinations().forEach { menu.add(0, menuId(it), 0, titleFor(it)) }
                menu.add(1, 1001, 100, "Экспорт задач")
                menu.add(1, 1002, 101, "Настроить нижнее меню")
                menu.add(1, 1003, 102, "Добавить виджет")
                menu.add(1, 1004, 103, "Поддержать проект")
                setOnMenuItemClickListener { item ->
                    when (item.itemId) {
                        1001 -> openTaskExport()
                        1002 -> showNavigationEditor()
                        1003 -> addQuickCaptureWidget()
                        1004 -> startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://pay.cloudtips.ru/p/e0ddf2ed")))
                        else -> MainDestination.entries.firstOrNull { menuId(it) == item.itemId }?.let(::navigateTo)
                    }
                    true
                }
                show()
            }
        }
    }

    private fun setupFab() {
        binding.fabAdd.setOnClickListener {
            openModalFragment(AddTaskFragment(), getString(R.string.screen_title_add))
        }
    }

    /**
     * Opens AddTaskFragment in edit mode for the given task id.
     * Called from list fragments when the user taps a task card.
     */
    fun openEditTask(taskId: String) {
        openModalFragment(
            AddTaskFragment.forEdit(taskId),
            getString(R.string.screen_title_edit)
        )
    }

    fun openAddTask(kind: CategoryKind, categoryId: String?) {
        openModalFragment(
            AddTaskFragment.forCategory(kind, categoryId),
            getString(R.string.screen_title_add)
        )
    }

    private fun showFragment(fragment: Fragment) {
        supportFragmentManager.beginTransaction()
            .setCustomAnimations(R.anim.fragment_enter, R.anim.fragment_exit)
            .replace(R.id.fragmentContainer, fragment)
            .commit()
    }

    /**
     * Opens Settings / AddTask as a modal layer that lives on the back stack.
     * Pressing back returns to the previously selected bottom-nav tab.
     */
    private fun openModalFragment(fragment: Fragment, title: String) {
        supportFragmentManager.beginTransaction()
            .setCustomAnimations(
                R.anim.slide_in_right, R.anim.fade_out_short,
                R.anim.fade_in_short, R.anim.slide_out_right
            )
            .replace(R.id.fragmentContainer, fragment, "modal")
            .addToBackStack("modal_$title")
            .commit()
        binding.tvTopBarTitle.text = title
        binding.fabAdd.isVisible = false
    }

    /** Открывает модальный фрагмент с заданным заголовком — публичный API для других фрагментов. */
    fun openModal(fragment: Fragment, title: String) {
        openModalFragment(fragment, title)
    }

    /**
     * Закрывает модальный экран и переключает нижнюю навигацию на вкладку «Стек».
     * Вызывается из AddTaskFragment после успешного создания новой задачи (не редактирования).
     */
    fun navigateToStack() { navigateTo(MainDestination.STACK) }

    private fun requestNotifPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
                notifPermLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }
    }

    /**
     * Корректируем видимость FAB после полного восстановления состояния.
     *
     * После recreate() и восстановления back stack видимость кнопки
     * зависит от того, открыта ли модальная форма.
     *
     * onResume() вызывается ПОСЛЕ onRestoreInstanceState(), поэтому состав
     * вкладок и выбранный пункт здесь уже восстановлены.
     * Проверка ::binding.isInitialized нужна, потому что в ранних выходах
     * onCreate() (онбординг) binding не инициализируется.
     */
    override fun onResume() {
        super.onResume()
        if (::binding.isInitialized) {
            val inModal = supportFragmentManager.backStackEntryCount > 0
            binding.fabAdd.isVisible = !inModal
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("destination", currentDestination.key)
        super.onSaveInstanceState(outState)
    }

    override fun onDestroy() {
        supportFragmentManager.removeOnBackStackChangedListener(backStackListener)
        super.onDestroy()
    }
}
