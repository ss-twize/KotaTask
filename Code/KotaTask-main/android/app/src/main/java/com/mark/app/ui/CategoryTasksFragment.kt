package com.mark.app.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.mark.app.R
import com.mark.app.adapter.TabMode
import com.mark.app.adapter.TaskAdapter
import com.mark.app.data.Task
import com.mark.app.databinding.FragmentCategoryTasksBinding
import com.mark.app.viewmodel.TaskViewModel

/**
 * Универсальный экран показа активных задач, отфильтрованных по одной категории.
 * Открывается из FoldersFragment по клику на папку.
 *
 * Аргументы:
 *   KIND  — тип категории (PROJECT / LOCATION / TASK_TYPE)
 *   ID    — id категории, или null если открыта системная папка "Без X"
 *   NAME  — имя для заголовка (используется во вспомогательной строке)
 */
class CategoryTasksFragment : Fragment() {

    companion object {
        private const val ARG_KIND = "kind"
        private const val ARG_ID   = "id"
        private const val ARG_NAME = "name"

        fun newInstance(kind: CategoryKind, id: String?, name: String): CategoryTasksFragment =
            CategoryTasksFragment().apply {
                arguments = Bundle().apply {
                    putString(ARG_KIND, kind.name)
                    putString(ARG_ID, id)
                    putString(ARG_NAME, name)
                }
            }
    }

    private var _binding: FragmentCategoryTasksBinding? = null
    private val binding get() = _binding!!
    private val vm: TaskViewModel by activityViewModels()
    private lateinit var adapter: TaskAdapter

    private lateinit var kind: CategoryKind
    private var categoryId: String? = null
    private var categoryName: String = ""

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentCategoryTasksBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        kind = CategoryKind.valueOf(arguments?.getString(ARG_KIND) ?: CategoryKind.PROJECT.name)
        categoryId = arguments?.getString(ARG_ID)
        categoryName = arguments?.getString(ARG_NAME) ?: ""

        // Внутри папки проекта метка проекта избыточна — показываем только в папках локаций/типов.
        val projectLabel: ((Task) -> String?)? =
            if (kind == CategoryKind.PROJECT) null
            else { task -> task.projectId?.let { id -> vm.allProjects.value?.find { it.id == id }?.name } }

        adapter = TaskAdapter(
            mode = TabMode.STACK,
            scoreProvider = { task -> vm.allTasks.value?.let { vm.calcScore(task, it) } ?: 0f },
            projectProvider = projectLabel,
            onAction1 = { task -> vm.moveToToday(task.id) },
            onAction2 = { task ->
                if (!isAdded) return@TaskAdapter
                // Подтверждение удаления — на этом экране нет undo, как в архиве,
                // а случайно тапнуть на "Удалить" слишком легко.
                MaterialAlertDialogBuilder(requireContext())
                    .setTitle(R.string.confirm_delete_task_title)
                    .setMessage("\"${task.title}\"\n\n${getString(R.string.confirm_delete_task_msg)}")
                    .setPositiveButton(R.string.btn_delete) { _, _ -> vm.deleteTask(task.id) }
                    .setNegativeButton(R.string.btn_cancel, null)
                    .show()
            },
            onCardClick = { task -> (activity as? MainActivity)?.openEditTask(task.id) }
        )
        binding.rvCategoryTasks.layoutManager = LinearLayoutManager(requireContext())
        binding.rvCategoryTasks.adapter = adapter
        binding.btnAddTaskInCategory.setOnClickListener {
            (activity as? MainActivity)?.openAddTask(kind, categoryId)
        }

        vm.allTasks.observe(viewLifecycleOwner) { refresh(it) }
    }

    private fun refresh(all: List<Task>) {
        if (_binding == null) return
        val active = vm.activeTasks(all)

        val filtered = active.filter { t ->
            when (kind) {
                CategoryKind.PROJECT   -> t.projectId   == categoryId
                CategoryKind.LOCATION  -> t.locationId  == categoryId
                CategoryKind.TASK_TYPE -> t.taskTypeId  == categoryId
            }
        }

        adapter.submitList(filtered)
        binding.tvCategoryEmpty.isVisible = filtered.isEmpty()
        binding.rvCategoryTasks.isVisible = filtered.isNotEmpty()

        val label = when (kind) {
            CategoryKind.PROJECT   -> "Проект: $categoryName"
            CategoryKind.LOCATION  -> "Локация: $categoryName"
            CategoryKind.TASK_TYPE -> "Тип: $categoryName"
        }
        binding.tvCategoryHeader.text = "$label · ${filtered.size}"
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
