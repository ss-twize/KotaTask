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
        // FAB живёт в центральном слоте bottom-nav и доступен на любой вкладке,
        // включая «Настройки». Прячем только внутри модальных экранов
        // (AddTask/Архив/Папки), где он перекрывал бы их собственные действия.
        binding.fabAdd.isVisible = !inModal
        // Restore title to the currently-selected main destination on back
        if (!inModal) {
            binding.tvTopBarTitle.text = titleForId(binding.bottomNav.selectedItemId)
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

        setupBottomNav()
        setupFab()
        setupDonateButton()
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

        if (savedInstanceState == null) {
            if (featureSplit) {
                // nav_today — дефолтно выбранный пункт меню, поэтому фрагмент
                // нужно показать вручную: программное присвоение того же
                // selectedItemId не триггерит listener.
                showFragment(TodayFragment())
            } else {
                // nav_today скрыт — стартуем сразу на объединённой вкладке.
                // Присвоение нового selectedItemId триггерит listener, который
                // сам инфлейтит StackFragment.newMerged().
                binding.bottomNav.selectedItemId = R.id.nav_stack
            }
        }
    }

    /**
     * Применяет текущие feature-флаги к bottom-nav: видимость вкладок «Сегодня»
     * и «Календарь», а также заголовок «Стек» / «Задачи». Идемпотентно — можно
     * вызывать после каждого изменения настроек.
     */
    fun applyFeatureFlagsToNav() {
        val menu = binding.bottomNav.menu
        menu.findItem(R.id.nav_today)?.isVisible    = featureSplit
        menu.findItem(R.id.nav_calendar)?.isVisible = featureCalendar
        menu.findItem(R.id.nav_stack)?.setTitle(
            if (featureSplit) R.string.nav_stack else R.string.nav_tasks
        )
        // Состав вкладок изменился — центральный слот уехал, двигаем за ним FAB.
        alignFabToCenterSlot()
    }

    /**
     * Ставит FAB ровно по центру пустого слота nav_placeholder.
     *
     * Constraint-разметка центрирует FAB по всей ширине bottom-nav, но при
     * скрытых вкладках «Сегодня»/«Календарь» пустой слот перестаёт совпадать
     * с геометрическим центром панели (BottomNavigationView раскладывает
     * только видимые пункты). Поэтому после каждого layout'а сдвигаем FAB
     * через translationX на разницу между центром слота и центром FAB.
     */
    private fun alignFabToCenterSlot() {
        binding.bottomNav.post {
            val slot = binding.bottomNav.findViewById<View>(R.id.nav_placeholder) ?: return@post
            if (slot.width == 0 || binding.fabAdd.width == 0) return@post
            val slotCenter = binding.bottomNav.left + slot.left + slot.width / 2f
            val fabCenter  = binding.fabAdd.left + binding.fabAdd.width / 2f
            binding.fabAdd.translationX = slotCenter - fabCenter
        }
    }

    private fun setupBottomNav() {
        // Применяем выбор пользователя из онбординга/настроек.
        applyFeatureFlagsToNav()

        binding.bottomNav.setOnItemSelectedListener { item ->
            val fragment = when (item.itemId) {
                R.id.nav_today    -> TodayFragment()
                R.id.nav_stack    -> if (featureSplit) StackFragment() else StackFragment.newMerged()
                R.id.nav_calendar -> CalendarFragment()
                R.id.nav_settings -> SettingsFragment()
                else -> return@setOnItemSelectedListener false
            }
            // If a modal is open (AddTask/Settings), pop it before switching tabs
            if (supportFragmentManager.backStackEntryCount > 0) {
                supportFragmentManager.popBackStackImmediate(null, FragmentManager.POP_BACK_STACK_INCLUSIVE)
            }
            showFragment(fragment)
            binding.tvTopBarTitle.text = titleForId(item.itemId)
            binding.fabAdd.isVisible = true
            true
        }

        // If a modal is open and the user taps the same tab, close the modal
        binding.bottomNav.setOnItemReselectedListener {
            if (supportFragmentManager.backStackEntryCount > 0) {
                supportFragmentManager.popBackStack(null, FragmentManager.POP_BACK_STACK_INCLUSIVE)
            }
        }
    }

    private fun setupFab() {
        binding.fabAdd.setOnClickListener {
            openModalFragment(AddTaskFragment(), getString(R.string.screen_title_add))
        }
    }

    private fun setupDonateButton() {
        binding.btnDonate.setOnClickListener {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://pay.cloudtips.ru/p/e0ddf2ed")))
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
    }

    private fun titleForId(id: Int): String = when (id) {
        R.id.nav_today    -> getString(R.string.screen_title_today)
        R.id.nav_stack    -> getString(
            if (featureSplit) R.string.screen_title_stack else R.string.nav_tasks
        )
        R.id.nav_calendar -> getString(R.string.screen_title_calendar)
        R.id.nav_settings -> getString(R.string.screen_title_settings)
        else              -> getString(R.string.app_name)
    }

    /** Открывает модальный фрагмент с заданным заголовком — публичный API для других фрагментов. */
    fun openModal(fragment: Fragment, title: String) {
        openModalFragment(fragment, title)
    }

    /**
     * Закрывает модальный экран и переключает нижнюю навигацию на вкладку «Стек».
     * Вызывается из AddTaskFragment после успешного создания новой задачи (не редактирования).
     */
    fun navigateToStack() {
        if (supportFragmentManager.backStackEntryCount > 0) {
            supportFragmentManager.popBackStackImmediate(null, FragmentManager.POP_BACK_STACK_INCLUSIVE)
        }
        binding.bottomNav.selectedItemId = R.id.nav_stack
    }

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
     * setOnItemSelectedListener не стреляет при восстановлении selectedItemId
     * через onRestoreInstanceState() (BottomNavigationView восстанавливает
     * выделение напрямую, минуя слушателя), поэтому после recreate() (смена
     * темы) видимость FAB и его позицию в центральном слоте пересчитываем здесь.
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
            alignFabToCenterSlot()
        }
    }

    override fun onDestroy() {
        supportFragmentManager.removeOnBackStackChangedListener(backStackListener)
        super.onDestroy()
    }
}
