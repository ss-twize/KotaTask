package com.mark.app.ui

import android.content.ClipData
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.os.Bundle
import android.view.DragEvent
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.PopupMenu
import android.widget.TextView
import androidx.core.widget.addTextChangedListener
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.button.MaterialButton
import com.google.android.material.card.MaterialCardView
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.textfield.TextInputEditText
import com.mark.app.KotaTaskApp
import com.mark.app.R
import com.mark.app.data.Project
import com.mark.app.data.Task
import com.mark.app.util.BoardOrder
import com.mark.app.viewmodel.TaskViewModel

/** Проектные колонки, как на Mac. Перетаскивание не меняет статус задачи. */
class KanbanFragment : Fragment() {
    private val vm: TaskViewModel by activityViewModels()
    private var horizontal: HorizontalScrollView? = null
    private var row: LinearLayout? = null
    private var query = ""
    private var scrollPosition = 0
    private var columnKeys = emptyList<String>()
    private val columns = linkedMapOf<String, Column>()
    private var scrollSpeed = 0
    private var dragging = false
    private val autoScroll = object : Runnable {
        override fun run() {
            val scroll = horizontal ?: return
            if (!dragging) return
            scroll.scrollBy(scrollSpeed, 0)
            scroll.postOnAnimation(this)
        }
    }
    private data class TaskDrag(val id: String, val projectId: String?)
    private data class Column(
        val view: MaterialCardView, val title: TextView, val list: RecyclerView,
        val adapter: Cards, val marker: DropMarker, val projectId: String?, val allProjects: Boolean
    )

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        val ctx = requireContext()
        val projectsEnabled = ctx.getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KotaTaskApp.KEY_FEATURE_PROJECTS, true)
        val root = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(ctx.getColor(R.color.bg_canvas))
        }
        val bar = LinearLayout(ctx).apply {
            gravity = Gravity.CENTER_VERTICAL; setPadding(dp(16), 0, dp(16), dp(6))
        }
        val search = TextInputEditText(ctx).apply {
            hint = "Поиск по задачам"; setSingleLine(true)
            setText(query)
            addTextChangedListener { query = it.toString().trim(); render() }
        }
        bar.addView(search, LinearLayout.LayoutParams(0, dp(52), 1f))
        bar.addView(MaterialButton(ctx, null, com.google.android.material.R.attr.borderlessButtonStyle).apply {
            text = "+ Проект"; contentDescription = "Создать проект"
            visibility = if (projectsEnabled) View.VISIBLE else View.GONE
            setOnClickListener { editProject(null) }
        })
        root.addView(bar)
        root.addView(TextView(ctx).apply {
            text = if (projectsEnabled) "Удерживайте карточку и перенесите. «Сегодня» остаётся в своём проекте."
                else "Удерживайте карточку, чтобы изменить порядок задач."
            textSize = 12f; setTextColor(ctx.getColor(R.color.text_secondary))
            setPadding(dp(16), 0, dp(16), dp(10))
        })
        row = LinearLayout(ctx).apply { orientation = LinearLayout.HORIZONTAL; setPadding(dp(12), 0, dp(12), dp(80)) }
        horizontal = HorizontalScrollView(ctx).apply {
            isFillViewport = true; addView(row, ViewGroup.LayoutParams(-2, -1))
        }
        root.addView(horizontal, LinearLayout.LayoutParams(-1, 0, 1f))
        return root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        vm.allTasks.observe(viewLifecycleOwner) { render() }
        vm.allProjects.observe(viewLifecycleOwner) { render() }
    }

    private fun render() {
        val host = row ?: return
        val all = vm.allTasks.value ?: return
        val projects = vm.allProjects.value ?: return
        val projectsEnabled = requireContext().getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KotaTaskApp.KEY_FEATURE_PROJECTS, true)
        val scopes = if (projectsEnabled) listOf(null) + projects.map { it.id } else listOf(null)
        val keys = scopes.map { it ?: if (projectsEnabled) "none" else "all" }
        if (keys != columnKeys) {
            val offset = horizontal?.scrollX?.takeIf { it > 0 } ?: scrollPosition
            host.removeAllViews(); columns.clear()
            keys.forEachIndexed { index, key ->
                val projectId = scopes[index]
                val column = makeColumn(projectId, allProjects = !projectsEnabled)
                columns[key] = column
                host.addView(column.view, LinearLayout.LayoutParams(
                    minOf(dp(300), resources.displayMetrics.widthPixels - dp(48)), -1
                ).apply { marginEnd = dp(12) })
            }
            columnKeys = keys
            horizontal?.post { horizontal?.scrollTo(offset, 0) }
        }
        columns.values.forEach { column ->
            val tasks = BoardOrder.column(all, column.projectId, column.allProjects).filter {
                query.isEmpty() || it.title.contains(query, true) || it.purpose.contains(query, true)
            }
            val name = if (column.allProjects) "Задачи" else
                projects.firstOrNull { it.id == column.projectId }?.name ?: "Без проекта"
            column.title.text = "$name · ${tasks.size}"
            column.adapter.submitList(tasks)
        }
    }

    private fun makeColumn(projectId: String?, allProjects: Boolean): Column {
        val ctx = requireContext()
        val card = MaterialCardView(ctx).apply {
            radius = dp(18).toFloat(); cardElevation = 0f
            setCardBackgroundColor(ctx.getColor(R.color.bg_surface))
            strokeColor = ctx.getColor(R.color.border_subtle); strokeWidth = dp(1)
        }
        val body = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(10), dp(8), dp(10), dp(8)) }
        val header = LinearLayout(ctx).apply { gravity = Gravity.CENTER_VERTICAL }
        val title = TextView(ctx).apply {
            textSize = 16f; setTextColor(ctx.getColor(R.color.text_primary))
            gravity = Gravity.CENTER_VERTICAL
            setTypeface(typeface, android.graphics.Typeface.BOLD); maxLines = 2
        }
        header.addView(title, LinearLayout.LayoutParams(0, dp(56), 1f))
        header.addView(MaterialButton(ctx, null, com.google.android.material.R.attr.borderlessButtonStyle).apply {
            text = "⋮"; contentDescription = "Действия с колонкой"
            setOnClickListener { columnMenu(it, projectId) }
        }, LinearLayout.LayoutParams(dp(48), dp(48)))
        body.addView(header)
        val adapter = Cards { task, anchor, menu ->
            if (menu) taskMenu(task, anchor) else (activity as? MainActivity)?.openEditTask(task.id)
        }
        val list = RecyclerView(ctx).apply {
            layoutManager = LinearLayoutManager(ctx)
            this.adapter = adapter
            setPadding(0, dp(4), 0, dp(8)); clipToPadding = false
        }
        val marker = DropMarker(ctx.getColor(R.color.primary), dp(3).toFloat())
        list.addItemDecoration(marker)
        body.addView(list, LinearLayout.LayoutParams(-1, 0, 1f))
        body.addView(MaterialButton(ctx, null, com.google.android.material.R.attr.borderlessButtonStyle).apply {
            text = "+ Задача"; setOnClickListener { quickAdd(projectId) }
        }, LinearLayout.LayoutParams(-1, dp(52)))
        card.addView(body)
        val column = Column(card, title, list, adapter, marker, projectId, allProjects)
        card.setOnDragListener { _, event -> handleDrag(column, event) }
        return column
    }

    private fun handleDrag(column: Column, event: DragEvent): Boolean {
        val drag = event.localState as? TaskDrag ?: return false
        when (event.action) {
            DragEvent.ACTION_DRAG_STARTED -> {
                if (!dragging) { dragging = true; horizontal?.postOnAnimation(autoScroll) }
                return true
            }
            DragEvent.ACTION_DRAG_ENTERED, DragEvent.ACTION_DRAG_LOCATION -> {
                val allowed = query.isEmpty() || (!column.allProjects && drag.projectId != column.projectId)
                column.view.strokeColor = requireContext().getColor(if (allowed) R.color.primary else R.color.border_subtle)
                val listPosition = IntArray(2); column.list.getLocationOnScreen(listPosition)
                val cardPosition = IntArray(2); column.view.getLocationOnScreen(cardPosition)
                val localY = event.y + cardPosition[1] - listPosition[1]
                column.marker.position = if (allowed) insertionPosition(column.list, localY) else null
                column.list.invalidateItemDecorations()
                val viewport = IntArray(2); horizontal?.getLocationOnScreen(viewport)
                val x = event.x + cardPosition[0] - viewport[0]
                scrollSpeed = when {
                    x < dp(40) -> -dp(8)
                    x > (horizontal?.width ?: 0) - dp(40) -> dp(8)
                    else -> 0
                }
                return true
            }
            DragEvent.ACTION_DROP -> {
                val sameColumn = column.allProjects || drag.projectId == column.projectId
                if (query.isNotEmpty() && sameColumn) return false
                // Быстрый бросок может прийти до последнего LOCATION: вычисляем
                // место по DROP, а не по состоянию визуального указателя.
                val listPosition = IntArray(2); column.list.getLocationOnScreen(listPosition)
                val cardPosition = IntArray(2); column.view.getLocationOnScreen(cardPosition)
                val rawPosition = insertionPosition(column.list, event.y + cardPosition[1] - listPosition[1])
                val oldIndex = column.adapter.currentList.indexOfFirst { it.id == drag.id }
                val position = if (query.isNotEmpty()) null
                    else rawPosition - if (oldIndex >= 0 && oldIndex < rawPosition) 1 else 0
                vm.placeOnBoard(drag.id, column.projectId, position, column.allProjects)
                column.view.performHapticFeedback(if (android.os.Build.VERSION.SDK_INT >= 30)
                    HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.KEYBOARD_TAP)
                return true
            }
            DragEvent.ACTION_DRAG_EXITED -> clearDrop(column)
            DragEvent.ACTION_DRAG_ENDED -> {
                clearDrop(column)
                dragging = false; scrollSpeed = 0; horizontal?.removeCallbacks(autoScroll)
            }
        }
        return true
    }

    private fun clearDrop(column: Column) {
        column.view.strokeColor = requireContext().getColor(R.color.border_subtle)
        column.marker.position = null; column.list.invalidateItemDecorations()
    }

    private fun insertionPosition(list: RecyclerView, y: Float): Int {
        val manager = list.layoutManager ?: return 0
        for (i in 0 until manager.childCount) {
            val child = manager.getChildAt(i) ?: continue
            if (y < (child.top + child.bottom) / 2f) return list.getChildAdapterPosition(child).coerceAtLeast(0)
        }
        val last = manager.getChildAt(manager.childCount - 1)
        return if (last == null) 0 else (list.getChildAdapterPosition(last) + 1).coerceAtMost(list.adapter?.itemCount ?: 0)
    }

    private fun taskMenu(task: Task, anchor: View) {
        PopupMenu(requireContext(), anchor).apply {
            menu.add("Дополнить / редактировать").setOnMenuItemClickListener { (activity as? MainActivity)?.openEditTask(task.id); true }
            menu.add(if (task.status == "Сегодня") "В стек" else "В сегодня").setOnMenuItemClickListener {
                if (task.status == "Сегодня") vm.moveToStack(task.id) else vm.moveToToday(task.id); true
            }
            menu.add("Выполнить").setOnMenuItemClickListener { vm.completeTask(task.id); true }
            val move = menu.addSubMenu("Переместить в проект")
            move.add("Без проекта").setOnMenuItemClickListener { vm.placeOnBoard(task.id, null); true }
            vm.allProjects.value.orEmpty().forEach { project ->
                move.add(project.name).setOnMenuItemClickListener { vm.placeOnBoard(task.id, project.id); true }
            }
            menu.add("Удалить…").setOnMenuItemClickListener {
                MaterialAlertDialogBuilder(requireContext()).setTitle("Удалить задачу?").setMessage(task.title)
                    .setNegativeButton("Отмена", null).setPositiveButton("Удалить") { _, _ -> vm.deleteTask(task.id) }.show()
                true
            }
            show()
        }
    }

    private fun columnMenu(anchor: View, projectId: String?) {
        val projects = vm.allProjects.value.orEmpty()
        val project = projects.firstOrNull { it.id == projectId }
        PopupMenu(requireContext(), anchor).apply {
            menu.add("Новая задача").setOnMenuItemClickListener { quickAdd(projectId); true }
            if (project != null) {
                menu.add("Переименовать…").setOnMenuItemClickListener { editProject(project); true }
                val position = projects.indexOf(project)
                menu.add("Колонку левее").apply {
                    isEnabled = position > 0
                    setOnMenuItemClickListener { vm.moveProjectColumn(project.id, position - 1); true }
                }
                menu.add("Колонку правее").apply {
                    isEnabled = position < projects.lastIndex
                    setOnMenuItemClickListener { vm.moveProjectColumn(project.id, position + 1); true }
                }
                menu.add("Удалить проект…").setOnMenuItemClickListener {
                    MaterialAlertDialogBuilder(requireContext()).setTitle("Удалить «${project.name}»?")
                        .setMessage("Задачи останутся в колонке «Без проекта».")
                        .setNegativeButton("Отмена", null)
                        .setPositiveButton("Удалить") { _, _ -> vm.deleteProject(project.id) }.show()
                    true
                }
            }
            show()
        }
    }

    private fun quickAdd(projectId: String?) {
        titleDialog("Быстрая задача", "") { vm.quickCapture(it, projectId) }
    }
    private fun editProject(project: Project?) {
        titleDialog(if (project == null) "Новый проект" else "Переименовать проект", project?.name ?: "") {
            if (project == null) vm.addProject(it) else vm.renameProject(project.id, it)
        }
    }
    private fun titleDialog(title: String, initial: String, onSave: (String) -> Unit) {
        val input = TextInputEditText(requireContext()).apply {
            hint = "Название"; setSingleLine(true); setText(initial); selectAll()
            setPadding(dp(24), dp(16), dp(24), dp(16))
        }
        val dialog = MaterialAlertDialogBuilder(requireContext()).setTitle(title).setView(input)
            .setNegativeButton("Отмена", null).setPositiveButton("Сохранить", null).create()
        dialog.setOnShowListener {
            dialog.getButton(android.content.DialogInterface.BUTTON_POSITIVE).setOnClickListener {
                if (input.text.toString().isBlank()) input.error = "Введите название"
                else { onSave(input.text.toString().trim()); dialog.dismiss() }
            }
            input.requestFocus()
            dialog.window?.setSoftInputMode(android.view.WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
        }
        dialog.show()
    }

    override fun onDestroyView() {
        scrollPosition = horizontal?.scrollX ?: scrollPosition
        dragging = false; horizontal?.removeCallbacks(autoScroll)
        horizontal = null; row = null; columns.clear(); columnKeys = emptyList()
        super.onDestroyView()
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    private class DropMarker(private val color: Int, private val thickness: Float) : RecyclerView.ItemDecoration() {
        var position: Int? = null
        override fun onDrawOver(canvas: Canvas, parent: RecyclerView, state: RecyclerView.State) {
            val position = position ?: return
            val manager = parent.layoutManager ?: return
            val child = manager.findViewByPosition(position)
            val last = manager.getChildAt(manager.childCount - 1)
            val y = child?.top?.toFloat() ?: last?.bottom?.toFloat() ?: 4f
            canvas.drawRect(4f, y, parent.width - 4f, y + thickness, Paint().apply { this.color = this@DropMarker.color })
        }
    }

    private class Cards(val action: (Task, View, Boolean) -> Unit) : ListAdapter<Task, Cards.Holder>(
        object : DiffUtil.ItemCallback<Task>() {
            override fun areItemsTheSame(a: Task, b: Task) = a.id == b.id
            override fun areContentsTheSame(a: Task, b: Task) = a == b
        }
    ) {
        class Holder(val card: MaterialCardView, val title: TextView, val meta: TextView, val menu: MaterialButton) :
            RecyclerView.ViewHolder(card)

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): Holder {
            val ctx = parent.context
            fun dp(v: Int) = (v * ctx.resources.displayMetrics.density).toInt()
            val card = MaterialCardView(ctx).apply {
                radius = dp(12).toFloat(); cardElevation = 0f
                strokeWidth = dp(1); strokeColor = ctx.getColor(R.color.border_default)
                setCardBackgroundColor(ctx.getColor(R.color.bg_surface))
                layoutParams = RecyclerView.LayoutParams(-1, -2).apply { bottomMargin = dp(10) }
            }
            val body = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL; setPadding(dp(12), dp(8), dp(8), dp(12)) }
            val top = LinearLayout(ctx).apply { gravity = Gravity.CENTER_VERTICAL }
            val title = TextView(ctx).apply {
                textSize = 15f; setTextColor(ctx.getColor(R.color.text_primary))
                setTypeface(typeface, android.graphics.Typeface.BOLD)
            }
            val menu = MaterialButton(ctx, null, com.google.android.material.R.attr.borderlessButtonStyle).apply {
                text = "⋮"; contentDescription = "Действия с задачей"
            }
            top.addView(title, LinearLayout.LayoutParams(0, -2, 1f))
            top.addView(menu, LinearLayout.LayoutParams(dp(48), dp(48)))
            val meta = TextView(ctx).apply { textSize = 12f; setTextColor(ctx.getColor(R.color.text_secondary)) }
            body.addView(top); body.addView(meta); card.addView(body)
            return Holder(card, title, meta, menu)
        }
        override fun onBindViewHolder(holder: Holder, position: Int) {
            val task = getItem(position)
            holder.title.text = task.title
            holder.meta.text = listOfNotNull(
                if (task.needsDetails) "✎ Дополнить" else null,
                if (task.status == "Сегодня") "☀ Сегодня" else null,
                "${task.duration} мин · ${task.importance}",
                task.deadline.takeIf { it.isNotBlank() }?.let { "Срок: $it" },
                task.deferredDate.takeIf { it.isNotBlank() }?.let { "Отложена до $it" }
            ).joinToString("\n")
            holder.card.contentDescription = "${task.title}. ${holder.meta.text}"
            holder.card.setOnClickListener { action(task, it, false) }
            holder.menu.setOnClickListener { action(task, it, true) }
            holder.card.setOnLongClickListener { view ->
                view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                view.startDragAndDrop(ClipData.newPlainText("Задача KotaTask", task.id),
                    View.DragShadowBuilder(view), TaskDrag(task.id, task.projectId), 0)
            }
        }
    }
}
