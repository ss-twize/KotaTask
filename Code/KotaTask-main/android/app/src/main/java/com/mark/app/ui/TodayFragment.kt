package com.mark.app.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.ArrayAdapter
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import androidx.recyclerview.widget.LinearLayoutManager
import com.mark.app.R
import com.mark.app.adapter.TabMode
import com.mark.app.adapter.TaskAdapter
import com.mark.app.data.Task
import com.mark.app.databinding.FragmentTodayBinding
import com.mark.app.viewmodel.SortMode
import com.mark.app.viewmodel.TaskViewModel

class TodayFragment : Fragment() {

    private var _binding: FragmentTodayBinding? = null
    private val binding get() = _binding!!
    private val vm: TaskViewModel by activityViewModels()
    private lateinit var adapter: TaskAdapter
    private var currentSort = SortMode.PRIORITY

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentTodayBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        setupSortSpinner()
        adapter = TaskAdapter(
            mode = TabMode.TODAY,
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
            onAction1 = { task -> vm.completeTask(task.id) },
            onAction2 = { task -> vm.moveToStack(task.id) },
            onCardClick = { task -> (activity as? MainActivity)?.openEditTask(task.id) }
        )
        binding.rvToday.layoutManager = LinearLayoutManager(requireContext())
        binding.rvToday.adapter = adapter

        vm.allTasks.observe(viewLifecycleOwner) { all -> refresh(all) }
        // Reload when locations finish loading so context labels appear correctly
        vm.allLocations.observe(viewLifecycleOwner) { vm.allTasks.value?.let { refresh(it) } }
        // Same for projects — so the project label on cards stays in sync
        vm.allProjects.observe(viewLifecycleOwner) { vm.allTasks.value?.let { refresh(it) } }
    }

    private fun setupSortSpinner() {
        val labels = SortMode.entries.map { it.label }
        val a = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, labels)
        a.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        binding.spinnerSortToday.adapter = a
        // Стартовая сортировка зависит от «умной сортировки»: вкл → приоритет, выкл → алфавит.
        currentSort = vm.defaultSortMode()
        binding.spinnerSortToday.setSelection(SortMode.entries.indexOf(currentSort), false)
        binding.spinnerSortToday.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, v: View?, pos: Int, id: Long) {
                currentSort = SortMode.entries[pos]
                vm.allTasks.value?.let { refresh(it) }
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
    }

    private fun refresh(all: List<Task>) {
        if (_binding == null) return   // spinner onItemSelected can fire after onDestroyView
        val tasks = vm.getSortedTasks(all, "Сегодня", currentSort)
        adapter.submitList(tasks)
        binding.emptyToday.isVisible = tasks.isEmpty()
        binding.rvToday.isVisible = tasks.isNotEmpty()

        // ═══ Hero day-load update ═══
        val loadMin = tasks.sumOf { it.duration }
        binding.tvLoadMinutes.text = loadMin.toString()
        binding.tvLoadCount.text = "${tasks.size} ${taskWord(tasks.size)}"

        val loadMax = vm.getOverloadLimitMinutes()
        val warnThreshold = loadMax / 2
        binding.progressLoad.max = loadMax
        binding.progressLoad.progress = loadMin.coerceAtMost(loadMax)
        binding.tvLoadHalfMark.text = "$warnThreshold мин"
        binding.tvLoadMaxMark.text = "$loadMax мин"

        // Status pill copy + progress drawable tint based on load level
        val ctx = requireContext()
        val (label, progressColor) = when {
            loadMin <  warnThreshold -> getString(R.string.today_load_ok) to R.color.load_ok
            loadMin <  loadMax -> getString(R.string.today_load_warn) to R.color.load_warn
            else                      -> getString(R.string.today_load_over) to R.color.load_over
        }
        binding.tvLoadStatus.text = label

        // Re-tint the progress drawable layer
        (binding.progressLoad.progressDrawable as? android.graphics.drawable.LayerDrawable)
            ?.findDrawableByLayerId(android.R.id.progress)
            ?.setTint(ctx.getColor(progressColor))
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
