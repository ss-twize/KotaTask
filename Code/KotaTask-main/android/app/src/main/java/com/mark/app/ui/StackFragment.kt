package com.mark.app.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Spinner
import androidx.core.view.isVisible
import androidx.core.widget.addTextChangedListener
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.datepicker.CalendarConstraints
import com.google.android.material.datepicker.DateValidatorPointForward
import com.google.android.material.datepicker.MaterialDatePicker
import com.mark.app.R
import com.mark.app.adapter.TabMode
import com.mark.app.adapter.TaskAdapter
import com.mark.app.data.Task
import com.mark.app.databinding.FragmentStackBinding
import com.mark.app.viewmodel.SortMode
import com.mark.app.viewmodel.TaskViewModel
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

class StackFragment : Fragment() {

    private var _binding: FragmentStackBinding? = null
    private val binding get() = _binding!!
    private val vm: TaskViewModel by activityViewModels()
    private lateinit var adapter: TaskAdapter
    private var currentSort = SortMode.PRIORITY

    /**
     * «Объединённый» режим: один список и для «Сегодня», и для «Стека». Активен,
     * когда в онбординге выключена опция «Раздельные Сегодня и Стек».
     */
    private var mergedMode = false

    // Filter state. null = ANY (показывать все), TaskViewModel.FILTER_NONE = только без категории.
    private var locationFilter: String? = null
    private var typeFilter:     String? = null
    private var searchQuery: String = ""

    // Параллельные списки: позиция в spinner → значение фильтра ("", FILTER_NONE, или id)
    private var locationFilterValues: List<String> = emptyList()
    private var typeFilterValues:     List<String> = emptyList()

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentStackBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        mergedMode = arguments?.getBoolean(ARG_MERGED, false) ?: false
        if (mergedMode) {
            binding.tvStackHeading.setText(R.string.stack_heading_merged)
            binding.tvEmptyTitle.setText(R.string.empty_title_merged)
            binding.tvEmptySubtitle.setText(R.string.empty_subtitle_merged)
            binding.statsDivider.isVisible = false
            binding.statsLoadColumn.isVisible = false
        }
        setupSortSpinner()
        setupFilterSpinners()
        binding.editSearch.addTextChangedListener { editable ->
            searchQuery = editable?.toString() ?: ""
            refreshList()
        }

        // Отложенное планирование доступно только в раздельном режиме (не merged).
        val deferEnabled = !mergedMode && vm.isDeferEnabled()

        adapter = TaskAdapter(
            mode = if (mergedMode) TabMode.MERGED else TabMode.STACK,
            scoreProvider = { task -> vm.allTasks.value?.let { vm.calcScore(task, it) } ?: 0f },
            contextProvider = { task ->
                task.locationId?.let { id ->
                    vm.allLocations.value?.find { it.id == id }?.name
                }
            },
            projectProvider = { task ->
                task.projectId?.let { id ->
                    vm.allProjects.value?.find { it.id == id }?.name
                }
            },
            onAction1 = { task ->
                if (mergedMode) vm.completeTask(task.id)
                else {
                    // Перенос в «Сегодня» вручную снимает отложенность, если она была.
                    if (task.deferredDate.isNotBlank()) vm.undeferTask(task.id)
                    vm.moveToToday(task.id)
                }
            },
            onAction2 = { task ->
                if (!isAdded) return@TaskAdapter
                MaterialAlertDialogBuilder(requireContext())
                    .setTitle("Удалить задачу?")
                    .setMessage("\"${task.title}\"\n\nЭто действие нельзя отменить")
                    .setPositiveButton("Удалить") { _, _ -> vm.deleteTask(task.id) }
                    .setNegativeButton("Отмена", null)
                    .show()
            },
            onAction3 = { task -> if (isAdded) showDeferPicker(task) },
            deferEnabled = deferEnabled,
            onCardClick = { task -> (activity as? MainActivity)?.openEditTask(task.id) }
        )
        binding.rvStack.layoutManager = LinearLayoutManager(requireContext())
        binding.rvStack.adapter = adapter

        vm.allTasks.observe(viewLifecycleOwner) { all -> refreshList(all) }
        vm.allLocations.observe(viewLifecycleOwner) {
            rebuildFilterSpinner(
                binding.spinnerFilterLocation, it.map { l -> l.id to l.name },
                "Локация", { v -> locationFilterValues = v }, { locationFilter = it; refreshList() }
            )
            // Re-render cards so context labels pick up newly loaded location names
            refreshList()
        }
        vm.allTaskTypes.observe(viewLifecycleOwner) { rebuildFilterSpinner(
            binding.spinnerFilterType, it.map { t -> t.id to t.name },
            "Тип", { v -> typeFilterValues = v }, { typeFilter = it; refreshList() }
        ) }
        // Перерисовываем карточки при изменении списка проектов, чтобы метка
        // проекта появлялась/обновлялась (загрузка после задач, переименование).
        vm.allProjects.observe(viewLifecycleOwner) { refreshList() }
    }

    private fun setupSortSpinner() {
        val labels = SortMode.entries.map { it.label }
        val spinnerAdapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, labels)
        spinnerAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        binding.spinnerSortStack.adapter = spinnerAdapter
        // Стартовая сортировка зависит от «умной сортировки»: вкл → приоритет, выкл → алфавит.
        currentSort = vm.defaultSortMode()
        binding.spinnerSortStack.setSelection(SortMode.entries.indexOf(currentSort), false)
        binding.spinnerSortStack.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, v: View?, pos: Int, id: Long) {
                currentSort = SortMode.entries[pos]
                vm.allTasks.value?.let { refreshList(it) }
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
    }

    private fun setupFilterSpinners() {
        // Изначально только "Все" / "Без X" в каждом spinner (категорий ещё нет)
        rebuildFilterSpinner(binding.spinnerFilterLocation, emptyList(),
            "Локация", { locationFilterValues = it }, { locationFilter = it; refreshList() })
        rebuildFilterSpinner(binding.spinnerFilterType, emptyList(),
            "Тип", { typeFilterValues = it }, { typeFilter = it; refreshList() })
    }

    /**
     * Перестраивает spinner фильтра: первый элемент "<label>: все",
     * затем категории, последним — "Без <label>".
     * Сохраняет выбранную пользователем позицию по value (если она ещё валидна).
     */
    private fun rebuildFilterSpinner(
        spinner: Spinner,
        categories: List<Pair<String, String>>,   // (id, name)
        label: String,
        valuesSink: (List<String>) -> Unit,
        onChange: (String?) -> Unit
    ) {
        if (_binding == null) return
        val labels = mutableListOf("$label: все").apply {
            addAll(categories.map { it.second })
            add("Без ${label.lowercase()}")
        }
        val values = mutableListOf(TaskViewModel.FILTER_ANY).apply {
            addAll(categories.map { it.first })
            add(TaskViewModel.FILTER_NONE)
        }
        valuesSink(values)

        // запомним текущий выбор по значению, чтобы попытаться его восстановить
        val currentValue = when (spinner.id) {
            binding.spinnerFilterLocation.id -> locationFilter
            binding.spinnerFilterType.id     -> typeFilter
            else -> null
        }

        val a = ArrayAdapter(requireContext(), R.layout.item_spinner_filter, labels)
        a.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        spinner.adapter = a

        val restoreIdx = values.indexOf(currentValue ?: TaskViewModel.FILTER_ANY).let { if (it < 0) 0 else it }
        spinner.setSelection(restoreIdx, false)

        spinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, v: View?, pos: Int, id: Long) {
                val v2 = values[pos]
                onChange(if (v2 == TaskViewModel.FILTER_ANY) null else v2)
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
    }

    private fun refreshList(all: List<com.mark.app.data.Task>? = vm.allTasks.value) {
        if (_binding == null || all == null) return
        val byStatus = if (mergedMode) {
            val active = all.filter { it.status == "Сегодня" || it.status == "Стек" }
            vm.applySortMode(active, all, currentSort)
        } else {
            vm.getSortedTasks(all, "Стек", currentSort)
        }
        val byCategory = vm.applyCategoryFilters(byStatus, null, locationFilter, typeFilter)
        val tasks = if (searchQuery.isBlank()) byCategory
                    else byCategory.filter {
                        it.title.contains(searchQuery, ignoreCase = true) ||
                        it.purpose.contains(searchQuery, ignoreCase = true)
                    }

        adapter.submitList(tasks)
        binding.tvStackCount.text = tasks.size.toString()
        binding.tvStackCountLabel.text = "${taskWord(tasks.size)} в очереди"
        binding.emptyStack.isVisible = tasks.isEmpty()
        binding.rvStack.isVisible = tasks.isNotEmpty()

        val todayMin = all.filter { it.status == "Сегодня" }.sumOf { it.duration }
        val overloadLimit = vm.getOverloadLimitMinutes()
        val warnThreshold = overloadLimit / 2
        binding.tvTodayLoad.text = todayMin.toString()
        binding.tvTodayLoad.setTextColor(requireContext().getColor(when {
            todayMin < warnThreshold -> R.color.success
            todayMin < overloadLimit -> R.color.warning
            else -> R.color.error
        }))
    }

    /**
     * Открывает календарь выбора даты для откладывания задачи.
     * Выбрать можно только дату ПОСЛЕ сегодняшнего дня (минимум — завтра).
     * MaterialDatePicker оперирует UTC-миллисекундами, поэтому конвертируем
     * через ZoneOffset.UTC, чтобы выбранный день не «уехал» из-за часового пояса.
     */
    private fun showDeferPicker(task: Task) {
        val today = LocalDate.now()
        val tomorrowUtcMs = today.plusDays(1)
            .atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()

        // Предвыбор: текущая дата откладывания (если уже отложена и она в будущем) или завтра.
        val preselectMs = task.deferredDate
            .takeIf { it.isNotBlank() }
            ?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
            ?.takeIf { it.isAfter(today) }
            ?.atStartOfDay(ZoneOffset.UTC)?.toInstant()?.toEpochMilli()
            ?: tomorrowUtcMs

        val constraints = CalendarConstraints.Builder()
            .setStart(tomorrowUtcMs)
            .setValidator(DateValidatorPointForward.from(tomorrowUtcMs))
            .build()

        val picker = MaterialDatePicker.Builder.datePicker()
            .setTitleText(R.string.defer_picker_title)
            .setSelection(preselectMs)
            .setCalendarConstraints(constraints)
            .build()

        picker.addOnPositiveButtonClickListener { utcMs ->
            val date = Instant.ofEpochMilli(utcMs).atZone(ZoneOffset.UTC).toLocalDate()
            vm.deferTask(task.id, date.toString())
        }
        picker.show(childFragmentManager, "defer_date_picker")
    }

    /** Склонение слова «задача» по числу: 1 задача, 2 задачи, 5 задач. */
    private fun taskWord(n: Int): String = when {
        n % 10 == 1 && n % 100 != 11 -> "задача"
        n % 10 in 2..4 && n % 100 !in 12..14 -> "задачи"
        else -> "задач"
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    companion object {
        private const val ARG_MERGED = "merged_mode"

        /** Конструктор для объединённого режима «Сегодня + Стек» в одной вкладке. */
        fun newMerged(): StackFragment = StackFragment().apply {
            arguments = Bundle().apply { putBoolean(ARG_MERGED, true) }
        }
    }
}
