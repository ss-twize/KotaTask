package com.mark.app.ui

import android.app.DatePickerDialog
import android.content.Context
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.content.res.ResourcesCompat
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import com.google.android.material.button.MaterialButton
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.mark.app.KotaTaskApp
import com.mark.app.R
import com.mark.app.data.Task
import com.mark.app.databinding.FragmentAddTaskBinding
import com.mark.app.ui.dialog.showQuickAddDialog
import com.mark.app.viewmodel.TaskViewModel
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Calendar

/**
 * Dual-mode fragment: создание или редактирование задачи.
 *
 * Категоризация (projectId / locationId / taskTypeId) — необязательные поля,
 * выбираются через диалог с радио-списком. Внутри диалога есть опция
 * "+ Добавить новый …", которая открывает второй диалог с inline вводом
 * имени, создаёт сущность и сразу выбирает её для текущей задачи.
 */
class AddTaskFragment : Fragment() {

    companion object {
        private const val ARG_TASK_ID = "task_id"
        private const val ARG_CATEGORY_KIND = "category_kind"
        private const val ARG_CATEGORY_ID = "category_id"

        // Допустимый диапазон длительности задачи (минуты). Валидируется в submitTask().
        // Верхняя граница 600 мин = 10 ч — за пределами этого уже не задача, а проект.
        const val MIN_DURATION = 1
        const val MAX_DURATION = 600

        fun forEdit(taskId: String): AddTaskFragment = AddTaskFragment().apply {
            arguments = Bundle().apply { putString(ARG_TASK_ID, taskId) }
        }

        fun forCategory(kind: CategoryKind, id: String?): AddTaskFragment = AddTaskFragment().apply {
            arguments = Bundle().apply {
                putString(ARG_CATEGORY_KIND, kind.name)
                putString(ARG_CATEGORY_ID, id)
            }
        }
    }

    private var _binding: FragmentAddTaskBinding? = null
    private val binding get() = _binding!!
    private val vm: TaskViewModel by activityViewModels()

    private var importance: String = "Средняя"
    private var editingTaskId: String? = null

    /**
     * Уровень помощи из онбординга (см. SettingsFragment → KEY_ASSISTANCE_LEVEL).
     * Считывается в onViewCreated и фиксируется на время жизни фрагмента — если
     * пользователь зашёл в настройки и поменял уровень, новое значение применится
     * к следующему открытию формы.
     */
    private var assistanceLevel: String = KotaTaskApp.DEFAULT_ASSISTANCE_LEVEL
    private val prefs by lazy {
        requireContext().getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
    }

    /** True, пока edit-mode ещё не нашёл и не заполнил форму. */
    private var awaitingPrefill: Boolean = false

    // Категоризация — храним выбранные id и человекочитаемые имена
    private var selectedProjectId:  String? = null
    private var selectedLocationId: String? = null
    private var selectedTaskTypeId: String? = null

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentAddTaskBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        editingTaskId = arguments?.getString(ARG_TASK_ID)
        if (editingTaskId == null) {
            preselectCategoryFromArguments()
        }

        // Применяем выбор пользователя из онбординга/настроек ДО setup-методов,
        // чтобы setupCategoryRows() не вешал listener'ы на скрытые row'ы.
        loadUserPreferences()
        applyFieldVisibility()

        setupImportancePills()
        setupDatePicker()
        setupCategoryRows()
        applyModeChrome()

        binding.btnAddTask.setOnClickListener { submitTask() }

        // Перерисовка лейблов категорий, если их список обновился (например, после quick-add)
        vm.allProjects.observe(viewLifecycleOwner)  { refreshCategoryLabels() }
        vm.allLocations.observe(viewLifecycleOwner) { refreshCategoryLabels() }
        vm.allTaskTypes.observe(viewLifecycleOwner) { refreshCategoryLabels() }

        // Если edit-mode не нашёл задачу при первом вызове applyModeChrome (LiveData ещё
        // не загрузилась), ждём первое обновление и повторно пытаемся применить prefill.
        // Без этого пользователь ловит баг "редактирование превращается в создание новой".
        if (awaitingPrefill) {
            vm.allTasks.observe(viewLifecycleOwner) {
                if (awaitingPrefill) {
                    awaitingPrefill = false
                    applyModeChrome()
                }
            }
        }
    }

    /**
     * Кешируем настройки в локальные поля — submitTask() обращается к ним
     * многократно при валидации, а доставать prefs из контекста каждый раз
     * не нужно.
     */
    private fun loadUserPreferences() {
        assistanceLevel = prefs.getString(
            KotaTaskApp.KEY_ASSISTANCE_LEVEL,
            KotaTaskApp.DEFAULT_ASSISTANCE_LEVEL
        ) ?: KotaTaskApp.DEFAULT_ASSISTANCE_LEVEL
    }

    /**
     * Прячет необязательные поля формы согласно выбору пользователя в онбординге:
     *   - KEY_FIELD_DURATION  → durationLayout
     *   - KEY_FIELD_PURPOSE   → purposeLayout
     *   - KEY_FIELD_PROJECT   → rowProject
     *   - KEY_FEATURE_CATEGORIES → rowLocation + rowTaskType
     *
     * Заголовок «Категоризация» скрываем, если все три row'а ушли в GONE.
     * Поле «Ответственный» (KEY_FIELD_ASSIGNEE) пока не реализовано в разметке —
     * флаг сохраняется в prefs, но визуально ни на что не влияет.
     */
    private fun applyFieldVisibility() {
        val showDuration   = prefs.getBoolean(KotaTaskApp.KEY_FIELD_DURATION, true)
        val showPurpose    = prefs.getBoolean(KotaTaskApp.KEY_FIELD_PURPOSE,  true)
        val showProject    = prefs.getBoolean(KotaTaskApp.KEY_FIELD_PROJECT,  true) &&
                             prefs.getBoolean(KotaTaskApp.KEY_FEATURE_PROJECTS, true)
        val showLocations = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_LOCATIONS, true) &&
                            prefs.getBoolean(KotaTaskApp.KEY_FIELD_LOCATION,    true)
        val showTaskTypes = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_TASK_TYPES, true) &&
                            prefs.getBoolean(KotaTaskApp.KEY_FIELD_TASK_TYPE,    true)

        binding.tvDurationLabel.isVisible = showDuration
        binding.durationLayout.isVisible  = showDuration
        binding.tvPurposeLabel.isVisible  = showPurpose
        binding.purposeLayout.isVisible   = showPurpose
        binding.rowProject.isVisible      = showProject
        binding.rowLocation.isVisible     = showLocations
        binding.rowTaskType.isVisible     = showTaskTypes

        // Если все три категоризационные строки скрыты — прячем и подзаголовок.
        binding.tvCategoriesHeading.isVisible = showProject || showLocations || showTaskTypes
    }

    private fun preselectCategoryFromArguments() {
        val kindName = arguments?.getString(ARG_CATEGORY_KIND) ?: return
        val id = arguments?.getString(ARG_CATEGORY_ID)
        when (CategoryKind.valueOf(kindName)) {
            CategoryKind.PROJECT   -> selectedProjectId = id
            CategoryKind.LOCATION  -> selectedLocationId = id
            CategoryKind.TASK_TYPE -> selectedTaskTypeId = id
        }
    }

    private fun applyModeChrome() {
        val id = editingTaskId ?: run {
            binding.btnAddTask.setText(R.string.btn_add_task)
            binding.btnAddTask.setIconResource(R.drawable.ic_add)
            return
        }

        val task = vm.getTaskById(id)
        if (task == null) {
            // LiveData ещё не пришла. НЕ сбрасываем editingTaskId в null,
            // иначе forEdit() превратится в createTask. Помечаем флагом и
            // подписываемся в onViewCreated на первое обновление allTasks.
            awaitingPrefill = true
            // Покажем "Сохранить изменения" как только пользователь поймёт что это edit-mode —
            // когда задача найдётся. До тех пор оставляем дефолтный текст создания.
            binding.btnAddTask.setText(R.string.btn_add_task)
            binding.btnAddTask.setIconResource(R.drawable.ic_add)
            return
        }

        prefillForm(task)
        binding.btnAddTask.setText(R.string.btn_save_task)
        binding.btnAddTask.setIconResource(R.drawable.ic_check)
    }

    private fun prefillForm(task: Task) {
        binding.editTitle.setText(task.title)
        binding.editDeadlineStart.setText(task.deadlineStart)
        binding.editDeadline.setText(task.deadline)
        binding.editPurpose.setText(task.purpose)
        binding.editDuration.setText(task.duration.toString())
        selectImportance(task.importance.ifBlank { "Средняя" })

        selectedProjectId  = task.projectId
        selectedLocationId = task.locationId
        selectedTaskTypeId = task.taskTypeId
        refreshCategoryLabels()
    }

    // ─────────────────────────── Importance pills ───────────────────────────

    private fun setupImportancePills() {
        binding.pillImportanceLow.setOnClickListener { selectImportance("Низкая") }
        binding.pillImportanceMedium.setOnClickListener { selectImportance("Средняя") }
        binding.pillImportanceHigh.setOnClickListener { selectImportance("Высокая") }
        selectImportance("Средняя")
    }

    private fun selectImportance(value: String) {
        importance = value
        applyPillState(binding.pillImportanceLow, selected = false, R.drawable.bg_pill_low)
        applyPillState(binding.pillImportanceMedium, selected = false, R.drawable.bg_pill_medium)
        applyPillState(binding.pillImportanceHigh, selected = false, R.drawable.bg_pill_high)
        when (value) {
            "Низкая" -> applyPillState(binding.pillImportanceLow, selected = true, R.drawable.bg_pill_low)
            "Средняя" -> applyPillState(binding.pillImportanceMedium, selected = true, R.drawable.bg_pill_medium)
            "Высокая" -> applyPillState(binding.pillImportanceHigh, selected = true, R.drawable.bg_pill_high)
        }
    }

    private fun applyPillState(pill: MaterialButton, selected: Boolean, selectedBg: Int) {
        val ctx = requireContext()
        val density = resources.displayMetrics.density
        if (selected) {
            pill.background = ResourcesCompat.getDrawable(resources, selectedBg, ctx.theme)
            pill.setTextColor(ctx.getColor(R.color.text_primary))
            pill.typeface = ResourcesCompat.getFont(ctx, R.font.manrope_bold)
            pill.iconSize = (13 * density).toInt()
        } else {
            pill.background = ResourcesCompat.getDrawable(resources, R.drawable.bg_pill_unselected, ctx.theme)
            pill.setTextColor(ctx.getColor(R.color.text_secondary))
            pill.typeface = ResourcesCompat.getFont(ctx, R.font.manrope_semibold)
            pill.iconSize = (8 * density).toInt()
        }
    }

    // ─────────────────────────── Date picker ───────────────────────────

    private fun setupDatePicker() {
        // Helper: открывает DatePickerDialog и возвращает выбранную дату через callback
        fun openPicker(initialText: String, allowPast: Boolean, onPicked: (String) -> Unit) {
            val cal = Calendar.getInstance()
            if (initialText.isNotBlank()) {
                try {
                    val d = LocalDate.parse(initialText)
                    cal.set(d.year, d.monthValue - 1, d.dayOfMonth)
                } catch (_: Exception) { /* fall through to today */ }
            }
            val dialog = DatePickerDialog(requireContext(), { _, y, m, d ->
                onPicked(LocalDate.of(y, m + 1, d).format(DateTimeFormatter.ISO_LOCAL_DATE))
            }, cal.get(Calendar.YEAR), cal.get(Calendar.MONTH), cal.get(Calendar.DAY_OF_MONTH))
            if (!allowPast) {
                dialog.datePicker.minDate = System.currentTimeMillis() - 1000
            }
            dialog.show()
        }

        // Deadline start picker
        val openStartPicker = {
            openPicker(
                initialText = binding.editDeadlineStart.text?.toString()?.trim().orEmpty(),
                allowPast = false
            ) { picked ->
                binding.editDeadlineStart.setText(picked)
            }
        }
        binding.editDeadlineStart.setOnClickListener { openStartPicker() }
        binding.deadlineStartLayout.setEndIconOnClickListener { openStartPicker() }

        // Deadline end picker
        val openEndPicker = {
            openPicker(
                initialText = binding.editDeadline.text?.toString()?.trim().orEmpty(),
                allowPast = editingTaskId != null   // при редактировании прошедшие даты разрешены
            ) { picked ->
                binding.editDeadline.setText(picked)
            }
        }
        binding.editDeadline.setOnClickListener { openEndPicker() }
        binding.deadlineLayout.setEndIconOnClickListener { openEndPicker() }
    }

    // ─────────────────────────── Category pickers ───────────────────────────

    private fun setupCategoryRows() {
        binding.rowProject.setOnClickListener   { showCategoryPicker(CategoryKind.PROJECT) }
        binding.rowLocation.setOnClickListener  { showCategoryPicker(CategoryKind.LOCATION) }
        binding.rowTaskType.setOnClickListener  { showCategoryPicker(CategoryKind.TASK_TYPE) }
        refreshCategoryLabels()
    }

    /**
     * Подтягивает текущие имена выбранных категорий из LiveData ВМ.
     * Вызывается при каждом обновлении списков (на случай переименования из настроек).
     */
    private fun refreshCategoryLabels() {
        if (_binding == null) return
        binding.tvProjectValue.text = selectedProjectId
            ?.let { id -> vm.allProjects.value?.firstOrNull { it.id == id }?.name }
            ?: getString(R.string.hint_project)
        binding.tvLocationValue.text = selectedLocationId
            ?.let { id -> vm.allLocations.value?.firstOrNull { it.id == id }?.name }
            ?: getString(R.string.hint_location)
        binding.tvTaskTypeValue.text = selectedTaskTypeId
            ?.let { id -> vm.allTaskTypes.value?.firstOrNull { it.id == id }?.name }
            ?: getString(R.string.hint_task_type)
    }

    /**
     * Универсальный picker — показывает список существующих категорий +
     * "Очистить" + "Добавить новый". Все 3 поля используют один путь.
     */
    private fun showCategoryPicker(kind: CategoryKind) {
        if (!isAdded) return

        val items: List<Pair<String, String>> = when (kind) {     // (id, name)
            CategoryKind.PROJECT   -> vm.allProjects.value.orEmpty().map { it.id to it.name }
            CategoryKind.LOCATION  -> vm.allLocations.value.orEmpty().map { it.id to it.name }
            CategoryKind.TASK_TYPE -> vm.allTaskTypes.value.orEmpty().map { it.id to it.name }
        }

        val labels = items.map { it.second }.toMutableList()
        labels.add(getString(R.string.action_clear))
        labels.add(when (kind) {
            CategoryKind.PROJECT   -> getString(R.string.action_add_project)
            CategoryKind.LOCATION  -> getString(R.string.action_add_location)
            CategoryKind.TASK_TYPE -> getString(R.string.action_add_task_type)
        })

        MaterialAlertDialogBuilder(requireContext())
            .setTitle(when (kind) {
                CategoryKind.PROJECT   -> R.string.label_project
                CategoryKind.LOCATION  -> R.string.label_location
                CategoryKind.TASK_TYPE -> R.string.label_task_type
            })
            .setItems(labels.toTypedArray()) { _, which ->
                when {
                    which == labels.size - 1 -> showQuickAddDialog(kind)       // последний — Добавить новый
                    which == labels.size - 2 -> setCategory(kind, null)        // предпоследний — Очистить
                    else -> setCategory(kind, items[which].first)              // конкретный id
                }
            }
            .show()
    }

    private fun showQuickAddDialog(kind: CategoryKind) {
        if (!isAdded) return
        showQuickAddDialog(
            requireContext(),
            initial = "",
            onSubmit = { name ->
                when (kind) {
                    CategoryKind.PROJECT   -> vm.addProject(name)   { created -> setCategory(CategoryKind.PROJECT, created.id) }
                    CategoryKind.LOCATION  -> vm.addLocation(name)  { created -> setCategory(CategoryKind.LOCATION, created.id) }
                    CategoryKind.TASK_TYPE -> vm.addTaskType(name)  { created -> setCategory(CategoryKind.TASK_TYPE, created.id) }
                }
            }
        )
    }

    private fun setCategory(kind: CategoryKind, id: String?) {
        when (kind) {
            CategoryKind.PROJECT   -> selectedProjectId  = id
            CategoryKind.LOCATION  -> selectedLocationId = id
            CategoryKind.TASK_TYPE -> selectedTaskTypeId = id
        }
        refreshCategoryLabels()
    }

    // ─────────────────────────── Submit ───────────────────────────

    private fun submitTask() {
        val title = binding.editTitle.text?.toString()?.trim().orEmpty()
        val deadlineStart = binding.editDeadlineStart.text?.toString()?.trim().orEmpty()
        val deadline = binding.editDeadline.text?.toString()?.trim().orEmpty()
        val parent = ""
        val purpose  = binding.editPurpose.text?.toString()?.trim().orEmpty()

        // Сбрасываем предыдущие ошибки перед новой валидацией.
        binding.titleLayout.error = null
        binding.deadlineStartLayout.error = null
        binding.deadlineLayout.error = null
        binding.durationLayout.error = null
        binding.purposeLayout.error = null
        binding.tvProjectError.isVisible = false
        binding.tvLocationError.isVisible = false
        binding.tvTaskTypeError.isVisible = false

        // ─── Title (требуется на всех уровнях, включая minimal) ───
        if (title.isBlank()) {
            binding.titleLayout.error = getString(R.string.error_empty_title)
            return
        }

        // ─── Деадлайн: обязателен на standard/advanced, и опционально на custom ───
        val deadlineRequired = assistanceLevel == KotaTaskApp.ASSISTANCE_STANDARD ||
                               assistanceLevel == KotaTaskApp.ASSISTANCE_ADVANCED ||
                               (assistanceLevel == KotaTaskApp.ASSISTANCE_CUSTOM &&
                                prefs.getBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_DEADLINE, false))
        if (deadlineRequired && deadline.isBlank()) {
            binding.deadlineLayout.error = getString(R.string.error_required_deadline)
            return
        }

        // Валидация продолжительности: 1..600 минут (до 10 часов).
        // Раньше принимали любое число (или null → 30 мин по умолчанию).
        // Это приводило к мусорным значениям: 0 ломал расчёт приоритета,
        // 999999 искажал график дневной нагрузки.
        // На advanced уровне поле обязательно (если оно вообще показывается).
        val rawDuration = binding.editDuration.text?.toString()?.toIntOrNull()
        val duration: Int = when {
            rawDuration == null -> {
                val durationRequired = binding.durationLayout.isVisible && (
                    assistanceLevel == KotaTaskApp.ASSISTANCE_ADVANCED ||
                    (assistanceLevel == KotaTaskApp.ASSISTANCE_CUSTOM &&
                     prefs.getBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_DURATION, false)))
                if (durationRequired) {
                    binding.durationLayout.error = getString(R.string.error_required_duration)
                    return
                }
                30                                          // поле пусто → дефолт
            }
            rawDuration !in MIN_DURATION..MAX_DURATION -> {
                binding.durationLayout.error = getString(R.string.error_duration_range)
                return
            }
            else -> rawDuration
        }

        // ─── Purpose: требуется на advanced и опционально на custom ───
        val purposeRequired = binding.purposeLayout.isVisible && (
            assistanceLevel == KotaTaskApp.ASSISTANCE_ADVANCED ||
            (assistanceLevel == KotaTaskApp.ASSISTANCE_CUSTOM &&
             prefs.getBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_PURPOSE, false)))
        if (purposeRequired && purpose.isBlank()) {
            binding.purposeLayout.error = getString(R.string.error_required_purpose)
            return
        }

        // ─── Поля, обязательные только на custom-уровне ───

        val deadlineStartRequired = assistanceLevel == KotaTaskApp.ASSISTANCE_CUSTOM &&
            prefs.getBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_DEADLINE_START, false)
        if (deadlineStartRequired && deadlineStart.isBlank()) {
            binding.deadlineStartLayout.error = getString(R.string.error_required_deadline_start)
            return
        }

        val projectRequired = binding.rowProject.isVisible &&
            assistanceLevel == KotaTaskApp.ASSISTANCE_CUSTOM &&
            prefs.getBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_PROJECT, false)
        if (projectRequired && selectedProjectId == null) {
            binding.tvProjectError.isVisible = true
            binding.tvProjectError.text = getString(R.string.error_required_project)
            return
        }

        val locationRequired = binding.rowLocation.isVisible &&
            assistanceLevel == KotaTaskApp.ASSISTANCE_CUSTOM &&
            prefs.getBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_LOCATION, false)
        if (locationRequired && selectedLocationId == null) {
            binding.tvLocationError.isVisible = true
            binding.tvLocationError.text = getString(R.string.error_required_location)
            return
        }

        val taskTypeRequired = binding.rowTaskType.isVisible &&
            assistanceLevel == KotaTaskApp.ASSISTANCE_CUSTOM &&
            prefs.getBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_TASK_TYPE, false)
        if (taskTypeRequired && selectedTaskTypeId == null) {
            binding.tvTaskTypeError.isVisible = true
            binding.tvTaskTypeError.text = getString(R.string.error_required_task_type)
            return
        }

        val id = editingTaskId
        if (id == null) {
            vm.addTask(
                title, deadlineStart, deadline, parent, purpose, duration, importance,
                projectId = selectedProjectId,
                locationId = selectedLocationId,
                taskTypeId = selectedTaskTypeId
            )
        } else {
            vm.updateTask(
                id, title, deadlineStart, deadline, parent, purpose, duration, importance,
                projectId = selectedProjectId,
                locationId = selectedLocationId,
                taskTypeId = selectedTaskTypeId
            )
        }

        val isFromFolder = arguments?.getString(ARG_CATEGORY_KIND) != null
        val isEditMode   = editingTaskId != null
        when {
            // Создание новой задачи из FAB (вне папки) → отправить на вкладку «Стек»
            !isFromFolder && !isEditMode -> (activity as? MainActivity)?.navigateToStack()
            // Создание внутри папки или редактирование → просто закрыть модальный экран
            parentFragmentManager.backStackEntryCount > 0 -> parentFragmentManager.popBackStack()
            else -> clearForm()
        }
    }

    private fun clearForm() {
        binding.editTitle.setText("")
        binding.editDeadlineStart.setText("")
        binding.editDeadline.setText("")
        binding.editPurpose.setText("")
        binding.editDuration.setText("")
        selectImportance("Средняя")
        selectedProjectId = null
        selectedLocationId = null
        selectedTaskTypeId = null
        refreshCategoryLabels()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
