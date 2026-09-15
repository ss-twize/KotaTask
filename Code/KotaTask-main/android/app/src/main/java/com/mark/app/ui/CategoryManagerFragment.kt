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
import com.mark.app.adapter.CategoryRow
import com.mark.app.adapter.CategoryRowAdapter
import com.mark.app.databinding.FragmentCategoryManagerBinding
import com.mark.app.ui.dialog.showQuickAddDialog
import com.mark.app.viewmodel.TaskViewModel

/**
 * Универсальный CRUD-экран для одного типа категорий.
 * Аргумент KIND решает, с какой LiveData/VM-методом работать.
 *
 * Открывается из настроек.
 */
class CategoryManagerFragment : Fragment() {

    companion object {
        private const val ARG_KIND = "kind"
        fun newInstance(kind: CategoryKind) = CategoryManagerFragment().apply {
            arguments = Bundle().apply { putString(ARG_KIND, kind.name) }
        }
    }

    private var _binding: FragmentCategoryManagerBinding? = null
    private val binding get() = _binding!!
    private val vm: TaskViewModel by activityViewModels()
    private lateinit var adapter: CategoryRowAdapter
    private lateinit var kind: CategoryKind

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentCategoryManagerBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        kind = CategoryKind.valueOf(arguments?.getString(ARG_KIND) ?: CategoryKind.PROJECT.name)

        adapter = CategoryRowAdapter(
            onRename = { showRenameDialog(it) },
            onDelete = { showDeleteDialog(it) }
        )
        binding.rvCategoryList.layoutManager = LinearLayoutManager(requireContext())
        binding.rvCategoryList.adapter = adapter

        binding.btnAddCategory.setOnClickListener { showAddDialog() }

        observeCategories()
    }

    private fun observeCategories() {
        when (kind) {
            CategoryKind.PROJECT -> vm.allProjects.observe(viewLifecycleOwner) { list ->
                renderList(list.map { CategoryRow(it.id, it.name) })
            }
            CategoryKind.LOCATION -> vm.allLocations.observe(viewLifecycleOwner) { list ->
                renderList(list.map { CategoryRow(it.id, it.name) })
            }
            CategoryKind.TASK_TYPE -> vm.allTaskTypes.observe(viewLifecycleOwner) { list ->
                renderList(list.map { CategoryRow(it.id, it.name) })
            }
        }
    }

    private fun renderList(rows: List<CategoryRow>) {
        adapter.submitList(rows)
        binding.tvCategoryEmpty.isVisible = rows.isEmpty()
        binding.rvCategoryList.isVisible = rows.isNotEmpty()
    }

    private fun showAddDialog() {
        if (!isAdded) return
        showQuickAddDialog(
            requireContext(),
            titleRes = R.string.cat_add_btn,
            positiveRes = R.string.cat_add_btn,
            onSubmit = { name ->
                when (kind) {
                    CategoryKind.PROJECT   -> vm.addProject(name)
                    CategoryKind.LOCATION  -> vm.addLocation(name)
                    CategoryKind.TASK_TYPE -> vm.addTaskType(name)
                }
            }
        )
    }

    private fun showRenameDialog(row: CategoryRow) {
        if (!isAdded) return
        showQuickAddDialog(
            requireContext(),
            initial = row.name,
            titleRes = R.string.cat_rename,
            positiveRes = R.string.btn_ok,
            onSubmit = { newName ->
                if (newName == row.name) return@showQuickAddDialog
                when (kind) {
                    CategoryKind.PROJECT   -> vm.renameProject(row.id, newName)
                    CategoryKind.LOCATION  -> vm.renameLocation(row.id, newName)
                    CategoryKind.TASK_TYPE -> vm.renameTaskType(row.id, newName)
                }
            }
        )
    }

    private fun showDeleteDialog(row: CategoryRow) {
        if (!isAdded) return
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.cat_delete_confirm_title)
            .setMessage("\"${row.name}\"\n\n${getString(R.string.cat_delete_confirm_msg)}")
            .setPositiveButton(R.string.cat_delete) { _, _ ->
                when (kind) {
                    CategoryKind.PROJECT   -> vm.deleteProject(row.id)
                    CategoryKind.LOCATION  -> vm.deleteLocation(row.id)
                    CategoryKind.TASK_TYPE -> vm.deleteTaskType(row.id)
                }
            }
            .setNegativeButton(R.string.btn_cancel, null)
            .show()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
