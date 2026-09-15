package com.mark.app.ui

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.core.view.isVisible
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import androidx.recyclerview.widget.LinearLayoutManager
import com.mark.app.R
import com.mark.app.adapter.TabMode
import com.mark.app.adapter.TaskAdapter
import com.mark.app.databinding.FragmentArchiveBinding
import com.mark.app.viewmodel.TaskViewModel

class ArchiveFragment : Fragment() {

    private var _binding: FragmentArchiveBinding? = null
    private val binding get() = _binding!!
    private val vm: TaskViewModel by activityViewModels()
    private lateinit var adapter: TaskAdapter
    private var totalArchiveCount = 0

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentArchiveBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        setupAdapter()
        setupButtons()

        vm.allTasks.observe(viewLifecycleOwner) { all ->
            val tasks = vm.getSortedTasks(all, "Архив")
            totalArchiveCount = tasks.size
            adapter.submitList(tasks)
            updateHeader(adapter.getSelectedIds().size)
            binding.emptyArchive.isVisible = tasks.isEmpty()
            binding.rvArchive.isVisible = tasks.isNotEmpty()
            binding.btnStartSelect.isVisible = tasks.isNotEmpty() && !adapter.isSelectionMode()
        }
    }

    private fun setupAdapter() {
        adapter = TaskAdapter(
            mode = TabMode.ARCHIVE,
            onAction1 = {},
            onAction2 = {},
            onCardClick = { task -> (activity as? MainActivity)?.openEditTask(task.id) }
        )
        adapter.onSelectionChanged = { selected ->
            if (_binding != null) {
                updateHeader(selected.size)
                binding.btnDeleteSelected.isEnabled = selected.isNotEmpty()
            }
        }
        binding.rvArchive.layoutManager = LinearLayoutManager(requireContext())
        binding.rvArchive.adapter = adapter
    }

    private fun setupButtons() {
        binding.btnStartSelect.setOnClickListener { enterSelectionMode() }
        binding.btnCancelSelect.setOnClickListener { exitSelectionMode() }

        binding.btnDeleteSelected.setOnClickListener {
            if (!isAdded) return@setOnClickListener
            val ids = adapter.getSelectedIds().toList()
            if (ids.isEmpty()) return@setOnClickListener
            MaterialAlertDialogBuilder(requireContext())
                .setTitle(getString(R.string.archive_confirm_selected_title))
                .setMessage("Будет удалено ${ids.size} ${taskWord(ids.size)}.\n${getString(R.string.archive_confirm_msg)}")
                .setPositiveButton(getString(R.string.btn_delete)) { _, _ ->
                    vm.deleteArchiveTasks(ids)
                    if (_binding != null) exitSelectionMode()
                }
                .setNegativeButton(getString(R.string.btn_cancel), null)
                .show()
        }

        binding.btnDeleteAll.setOnClickListener {
            if (!isAdded) return@setOnClickListener
            MaterialAlertDialogBuilder(requireContext())
                .setTitle(getString(R.string.archive_confirm_all_title))
                .setMessage("Будет удалено $totalArchiveCount ${taskWord(totalArchiveCount)}.\n${getString(R.string.archive_confirm_msg)}")
                .setPositiveButton(getString(R.string.btn_delete)) { _, _ ->
                    vm.deleteAllArchive()
                    if (_binding != null) exitSelectionMode()
                }
                .setNegativeButton(getString(R.string.btn_cancel), null)
                .show()
        }
    }

    private fun enterSelectionMode() {
        adapter.setSelectionMode(true)
        binding.btnStartSelect.isVisible = false
        binding.btnCancelSelect.isVisible = true
        binding.bottomActionBar.isVisible = true
        binding.btnDeleteSelected.isEnabled = false
        updateHeader(0)
    }

    private fun exitSelectionMode() {
        adapter.setSelectionMode(false)
        binding.btnCancelSelect.isVisible = false
        binding.bottomActionBar.isVisible = false
        binding.btnStartSelect.isVisible = totalArchiveCount > 0
        updateHeader(0)
    }

    private fun updateHeader(selectedCount: Int) {
        binding.tvArchiveInfo.text = if (adapter.isSelectionMode()) {
            if (selectedCount == 0) "Выберите задачи"
            else "Выбрано: $selectedCount"
        } else {
            if (totalArchiveCount > 0) "В архиве: $totalArchiveCount ${taskWord(totalArchiveCount)}"
            else ""
        }
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
