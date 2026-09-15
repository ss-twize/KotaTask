package com.mark.app.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.LinearLayoutManager
import com.mark.app.adapter.TabMode
import com.mark.app.adapter.TaskAdapter
import com.mark.app.data.Task
import com.mark.app.databinding.FragmentCalendarBinding
import com.mark.app.ui.calendar.MonthCalendarAdapter
import com.mark.app.viewmodel.TaskViewModel
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

class CalendarFragment : Fragment() {

    private var _binding: FragmentCalendarBinding? = null
    private val binding get() = _binding!!
    private val vm: TaskViewModel by activityViewModels()

    private lateinit var taskAdapter: TaskAdapter
    private lateinit var monthAdapter: MonthCalendarAdapter

    private var currentYearMonth: YearMonth = YearMonth.now()
    private var selectedDateStr: String = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentCalendarBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        setupTaskList()
        setupMonthGrid()
        setupNavButtons()

        vm.allTasks.observe(viewLifecycleOwner) { all ->
            val rangeMode = vm.getCalendarMode() == "range"
            val byDate = groupTasksByDate(all, rangeMode)
            monthAdapter.updateTasks(byDate)
            showTasksForDate(all, rangeMode)
        }
    }

    private fun setupTaskList() {
        taskAdapter = TaskAdapter(
            mode = TabMode.CALENDAR,
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
                if (task.status == "Сегодня") vm.completeTask(task.id)
                else vm.moveToToday(task.id)
            },
            onAction2 = { task ->
                if (!isAdded) return@TaskAdapter
                if (task.status == "Сегодня") {
                    vm.moveToStack(task.id)
                } else {
                    MaterialAlertDialogBuilder(requireContext())
                        .setTitle("Удалить задачу?")
                        .setMessage("\"${task.title}\"\n\nЭто действие нельзя отменить")
                        .setPositiveButton("Удалить") { _, _ -> vm.deleteTask(task.id) }
                        .setNegativeButton("Отмена", null)
                        .show()
                }
            },
            onCardClick = { task -> (activity as? MainActivity)?.openEditTask(task.id) }
        )
        binding.rvCalTasks.layoutManager = LinearLayoutManager(requireContext())
        binding.rvCalTasks.adapter = taskAdapter
    }

    private fun setupMonthGrid() {
        val allTasks = vm.allTasks.value ?: emptyList()
        monthAdapter = MonthCalendarAdapter(
            yearMonth = currentYearMonth,
            tasksByDate = groupTasksByDate(allTasks, vm.getCalendarMode() == "range"),
            onDateSelected = { dateStr ->
                selectedDateStr = dateStr
                val rangeMode = vm.getCalendarMode() == "range"
                vm.allTasks.value?.let { showTasksForDate(it, rangeMode) }
            }
        )
        binding.rvMonthGrid.layoutManager = GridLayoutManager(requireContext(), 7)
        binding.rvMonthGrid.adapter = monthAdapter
        binding.rvMonthGrid.itemAnimator = null
        updateMonthTitle()
    }

    private fun setupNavButtons() {
        binding.btnPrevMonth.setOnClickListener {
            currentYearMonth = currentYearMonth.minusMonths(1)
            refreshMonth()
        }
        binding.btnNextMonth.setOnClickListener {
            currentYearMonth = currentYearMonth.plusMonths(1)
            refreshMonth()
        }
        // Тап по названию месяца — быстрый возврат к текущему месяцу и выбор сегодня.
        binding.tvMonthYear.setOnClickListener {
            currentYearMonth = YearMonth.now()
            selectedDateStr = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
            refreshMonth()
            vm.allTasks.value?.let { showTasksForDate(it, vm.getCalendarMode() == "range") }
        }
    }

    private fun refreshMonth() {
        updateMonthTitle()
        val allTasks = vm.allTasks.value ?: emptyList()
        monthAdapter.update(currentYearMonth, groupTasksByDate(allTasks, vm.getCalendarMode() == "range"), selectedDateStr)
    }

    private fun updateMonthTitle() {
        val fmt = DateTimeFormatter.ofPattern("LLLL yyyy", Locale("ru"))
        binding.tvMonthYear.text = currentYearMonth.format(fmt)
            .replaceFirstChar { it.uppercase() }
    }

    /**
     * Строит карту дата → задачи для раскраски ячеек месяца.
     *
     * [rangeMode] = true  — задача попадает в каждый день диапазона [deadlineStart, deadline].
     *                        Если deadlineStart не задан — начало считается с даты создания задачи.
     * [rangeMode] = false — задача попадает только в день deadline (старое поведение).
     */
    private fun groupTasksByDate(tasks: List<Task>, rangeMode: Boolean): Map<String, List<Task>> {
        val active = tasks.filter { it.status == "Стек" || it.status == "Сегодня" }
        val result = mutableMapOf<String, MutableList<Task>>()

        // ─── Дедлайны ───
        val withDeadline = active.filter { it.deadline.isNotBlank() }
        if (!rangeMode) {
            // Режим «Точка»: задача только в день дедлайна
            withDeadline.forEach { task ->
                result.getOrPut(task.deadline) { mutableListOf() }.add(task)
            }
        } else {
            // Режим «Диапазон»: разворачиваем задачу на каждый день [start, end]
            withDeadline.forEach { task ->
                val endDate = try { LocalDate.parse(task.deadline) } catch (e: Exception) { return@forEach }
                val startDate = if (task.deadlineStart.isNotBlank()) {
                    try { LocalDate.parse(task.deadlineStart) } catch (e: Exception) { endDate }
                } else {
                    Instant.ofEpochMilli(task.created).atZone(ZoneId.systemDefault()).toLocalDate()
                }
                var current = startDate
                while (!current.isAfter(endDate)) {
                    result.getOrPut(current.format(DateTimeFormatter.ISO_LOCAL_DATE)) { mutableListOf() }.add(task)
                    current = current.plusDays(1)
                }
            }
        }

        // ─── Отложенные задачи ───
        // Показываем отложенную задачу на дате её откладывания (фиолетовым — раскраска
        // в CalendarCellView). Дедупликация: если задача уже попала в этот день через дедлайн —
        // не добавляем повторно.
        active.filter { it.deferredDate.isNotBlank() && it.status == "Стек" }.forEach { task ->
            val bucket = result.getOrPut(task.deferredDate) { mutableListOf() }
            if (!bucket.contains(task)) bucket.add(task)
        }

        return result
    }

    private fun showTasksForDate(all: List<Task>, rangeMode: Boolean = true) {
        if (_binding == null) return   // guard against stale callbacks after onDestroyView
        val tasks = vm.getTasksByDeadline(all, selectedDateStr, rangeMode)
        taskAdapter.submitList(tasks)

        val date = LocalDate.parse(selectedDateStr)
        // FormatStyle.LONG без явной локали брал системный default и для emulator-образа
        // выходил MAY 22, 2026. Жёстко прибиваем русскую локаль — приложение по UX
        // только русскоязычное, и любая системная локаль не должна это ломать.
        val label = date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG).withLocale(RU))
        binding.tvCalSelectedDate.text = if (tasks.isEmpty())
            "$label — нет задач"
        else
            "$label — ${tasks.size} ${taskWord(tasks.size)}"

        binding.rvCalTasks.isVisible = tasks.isNotEmpty()
    }

    private companion object {
        private val RU = java.util.Locale("ru")
    }

    private fun taskWord(n: Int): String = when {
        n % 10 == 1 && n % 100 != 11 -> "задача"
        n % 10 in 2..4 && n % 100 !in 12..14 -> "задачи"
        else -> "задач"
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
