package com.mark.app.ui

import android.content.Context
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.appcompat.app.AlertDialog
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import androidx.recyclerview.widget.LinearLayoutManager
import com.mark.app.KotaTaskApp
import com.mark.app.R
import com.mark.app.adapter.FolderAdapter
import com.mark.app.adapter.FolderItem
import com.mark.app.databinding.FragmentFoldersBinding
import com.mark.app.ui.dialog.showQuickAddDialog
import com.mark.app.viewmodel.TaskViewModel

/**
 * Главный экран "Папки" — заменяет вкладку Архив в bottom-nav.
 * Показывает секции (Проекты, и опционально Локации/Типы при включённой категоризации),
 * каждая с системной папкой "Без X" внизу.
 */
class FoldersFragment : Fragment() {

    private var _binding: FragmentFoldersBinding? = null
    private val binding get() = _binding!!
    private val vm: TaskViewModel by activityViewModels()

    private lateinit var projectsAdapter: FolderAdapter
    private lateinit var locationsAdapter: FolderAdapter
    private lateinit var typesAdapter: FolderAdapter

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentFoldersBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        projectsAdapter  = FolderAdapter(
            onClick = { item -> openCategory(CategoryKind.PROJECT, item) },
            onDelete = { item -> confirmDelete(item) { vm.deleteProject(it) } }
        )
        locationsAdapter = FolderAdapter(
            onClick = { item -> openCategory(CategoryKind.LOCATION, item) },
            onDelete = { item -> confirmDelete(item) { vm.deleteLocation(it) } }
        )
        typesAdapter = FolderAdapter(
            onClick = { item -> openCategory(CategoryKind.TASK_TYPE, item) },
            onDelete = { item -> confirmDelete(item) { vm.deleteTaskType(it) } }
        )

        binding.rvProjects.layoutManager  = LinearLayoutManager(requireContext())
        binding.rvLocations.layoutManager = LinearLayoutManager(requireContext())
        binding.rvTypes.layoutManager     = LinearLayoutManager(requireContext())
        binding.rvProjects.adapter  = projectsAdapter
        binding.rvLocations.adapter = locationsAdapter
        binding.rvTypes.adapter     = typesAdapter
        binding.btnAddProjectFolder.setOnClickListener { showAddFolderDialog(CategoryKind.PROJECT) }
        binding.btnAddLocationFolder.setOnClickListener { showAddFolderDialog(CategoryKind.LOCATION) }
        binding.btnAddTypeFolder.setOnClickListener { showAddFolderDialog(CategoryKind.TASK_TYPE) }

        applyCategoriesVisibility()

        // Любое изменение в задачах/категориях → пересчитываем счётчики
        vm.allTasks.observe(viewLifecycleOwner) { rebuild() }
        vm.allProjects.observe(viewLifecycleOwner) { rebuild() }
        vm.allLocations.observe(viewLifecycleOwner) { rebuild() }
        vm.allTaskTypes.observe(viewLifecycleOwner) { rebuild() }
    }

    private fun applyCategoriesVisibility() {
        val prefs = requireContext().getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
        val projectsEnabled  = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_PROJECTS,   true)
        val locationsEnabled = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_LOCATIONS,  true)
        val typesEnabled     = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_TASK_TYPES, true)
        binding.sectionProjectsHeader.isVisible  = projectsEnabled
        binding.rvProjects.isVisible             = projectsEnabled
        binding.sectionLocationsHeader.isVisible = locationsEnabled
        binding.rvLocations.isVisible            = locationsEnabled
        binding.sectionTypesHeader.isVisible     = typesEnabled
        binding.rvTypes.isVisible                = typesEnabled
    }

    private fun confirmDelete(item: FolderItem, doDelete: (String) -> Unit) {
        val id = item.id ?: return
        AlertDialog.Builder(requireContext())
            .setTitle(getString(R.string.folder_delete_title, item.name))
            .setMessage(R.string.folder_delete_message)
            .setPositiveButton(R.string.action_delete) { _, _ -> doDelete(id) }
            .setNegativeButton(R.string.btn_cancel, null)
            .show()
    }

    private fun rebuild() {
        val allTasks = vm.allTasks.value ?: emptyList()
        val active = vm.activeTasks(allTasks)

        // Projects
        val projectItems = (vm.allProjects.value ?: emptyList()).map { p ->
            FolderItem(p.id, p.name, active.count { it.projectId == p.id })
        }
        val withoutProject = FolderItem(
            id = null,
            name = getString(R.string.folders_none_project),
            count = active.count { it.projectId == null }
        )
        projectsAdapter.submitList(projectItems + withoutProject)

        // Locations
        val locationItems = (vm.allLocations.value ?: emptyList()).map { l ->
            FolderItem(l.id, l.name, active.count { it.locationId == l.id })
        }
        val withoutLocation = FolderItem(
            id = null,
            name = getString(R.string.folders_none_location),
            count = active.count { it.locationId == null }
        )
        locationsAdapter.submitList(locationItems + withoutLocation)

        // Types
        val typeItems = (vm.allTaskTypes.value ?: emptyList()).map { t ->
            FolderItem(t.id, t.name, active.count { it.taskTypeId == t.id })
        }
        val withoutType = FolderItem(
            id = null,
            name = getString(R.string.folders_none_type),
            count = active.count { it.taskTypeId == null }
        )
        typesAdapter.submitList(typeItems + withoutType)
    }

    private fun showAddFolderDialog(kind: CategoryKind) {
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

    private fun openCategory(kind: CategoryKind, item: FolderItem) {
        val activity = activity as? MainActivity ?: return
        activity.openModal(
            CategoryTasksFragment.newInstance(kind, item.id, item.name),
            item.name
        )
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}
