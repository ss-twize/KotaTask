package com.mark.app.adapter

import android.view.LayoutInflater
import android.view.ViewGroup
import android.widget.LinearLayout
import androidx.core.view.isVisible
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.mark.app.R
import com.mark.app.data.Task
import com.mark.app.databinding.ItemTaskBinding
import java.text.SimpleDateFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.*
import kotlin.math.roundToInt

enum class TabMode { TODAY, STACK, ARCHIVE, CALENDAR,
    /** Unified list (split_today off): all active tasks, single «Выполнить» action. */
    MERGED
}

class TaskAdapter(
    private val mode: TabMode,
    private val scoreProvider: ((Task) -> Float)? = null,
    /** Resolves a task's locationId to a human-readable context string, or null/blank to hide. */
    private val contextProvider: ((Task) -> String?)? = null,
    /** Resolves a task's projectId to a project name, or null/blank to hide. */
    private val projectProvider: ((Task) -> String?)? = null,
    private val onAction1: (Task) -> Unit = {},
    private val onAction2: (Task) -> Unit = {},
    /** Третье действие («Отложить») — показывается только в STACK при [deferEnabled]. */
    private val onAction3: (Task) -> Unit = {},
    /** Включено ли отложенное планирование (третья кнопка в стеке). */
    private val deferEnabled: Boolean = false,
    /**
     * Fired when the user taps anywhere on the card body (outside the action
     * buttons / checkbox). Used to open the task in edit mode.
     * In ARCHIVE mode this is suppressed while selection mode is active —
     * a tap there toggles selection instead.
     */
    private val onCardClick: (Task) -> Unit = {}
) : ListAdapter<Task, TaskAdapter.ViewHolder>(DIFF) {

    companion object {
        val DIFF = object : DiffUtil.ItemCallback<Task>() {
            override fun areItemsTheSame(a: Task, b: Task) = a.id == b.id
            override fun areContentsTheSame(a: Task, b: Task) = a == b
        }
    }

    private var selectionMode = false
    private val selectedIds = mutableSetOf<String>()
    var onSelectionChanged: ((Set<String>) -> Unit)? = null

    fun setSelectionMode(enabled: Boolean) {
        selectionMode = enabled
        if (!enabled) selectedIds.clear()
        notifyDataSetChanged()
    }

    fun isSelectionMode() = selectionMode

    fun getSelectedIds(): Set<String> = selectedIds.toSet()

    fun selectAll() {
        currentList.forEach { selectedIds.add(it.id) }
        onSelectionChanged?.invoke(selectedIds.toSet())
        notifyDataSetChanged()
    }

    private fun toggleSelection(task: Task, position: Int) {
        if (selectedIds.contains(task.id)) selectedIds.remove(task.id)
        else selectedIds.add(task.id)
        onSelectionChanged?.invoke(selectedIds.toSet())
        notifyItemChanged(position)
    }

    inner class ViewHolder(val binding: ItemTaskBinding) : RecyclerView.ViewHolder(binding.root)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val binding = ItemTaskBinding.inflate(LayoutInflater.from(parent.context), parent, false)
        return ViewHolder(binding)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val task = getItem(position)
        val b = holder.binding
        val ctx = b.root.context

        // ═══ Title ═══
        b.tvTitle.text = task.title

        // ═══ Importance: stripe + pill ═══
        val (stripeRes, dotRes, importanceText) = when (task.importance) {
            "Высокая" -> Triple(R.drawable.stripe_high, R.drawable.circle_red, "Высокая")
            "Низкая"  -> Triple(R.drawable.stripe_low,  R.drawable.circle_green, "Низкая")
            else      -> Triple(R.drawable.stripe_medium, R.drawable.circle_yellow, "Средняя")
        }
        b.stripeImportance.setBackgroundResource(stripeRes)
        b.dotImportance.setBackgroundResource(dotRes)
        b.tvImportance.text = importanceText

        // Hidden legacy badge (kept for compatibility)
        b.tvImportanceBadge.isVisible = false

        // ═══ Deadline chip ═══
        if (task.deadline.isNotBlank()) {
            b.tvDeadlineChip.isVisible = true
            b.tvDeadlineChip.text = formatDeadlineChip(task.deadlineStart, task.deadline)
            val (bg, fg) = deadlineColors(task.deadline)
            b.tvDeadlineChip.setBackgroundResource(bg)
            b.tvDeadlineChip.setTextColor(ctx.getColor(fg))
        } else {
            b.tvDeadlineChip.isVisible = false
        }

        // ═══ Duration chip ═══
        b.tvDurationChip.text = "${task.duration} мин"

        // ═══ Score badge (today + stack + calendar) ═══
        if (mode != TabMode.ARCHIVE && scoreProvider != null) {
            val score = scoreProvider.invoke(task)
            b.scoreBadge.isVisible = true
            b.tvScoreChip.text = String.format(Locale.US, "%.2f", score)
        } else {
            b.scoreBadge.isVisible = false
        }

        // ═══ Context (location) ═══
        val contextName = contextProvider?.invoke(task)
        if (!contextName.isNullOrBlank()) {
            b.contextRow.isVisible = true
            b.tvContext.text = contextName
        } else {
            b.contextRow.isVisible = false
        }

        // ═══ Project (резолвится из projectId через projectProvider) ═══
        val projectName = projectProvider?.invoke(task)
        if (!projectName.isNullOrBlank()) {
            b.parentRow.isVisible = true
            b.tvParent.text = projectName
        } else {
            b.parentRow.isVisible = false
        }

        // ═══ Completed timestamp for archive ═══
        if (mode == TabMode.ARCHIVE && task.completed > 0) {
            b.completedRow.isVisible = true
            val fmt = SimpleDateFormat("dd MMM yyyy, HH:mm", Locale("ru"))
            b.tvCompleted.text = fmt.format(Date(task.completed))
        } else {
            b.completedRow.isVisible = false
        }

        // ═══ Card appearance ═══
        applyCardSkin(b, task)

        // ═══ Selection mode (archive only) ═══
        if (mode == TabMode.ARCHIVE) {
            b.cbSelect.isVisible = selectionMode
            if (selectionMode) {
                b.cbSelect.setOnCheckedChangeListener(null)
                b.cbSelect.isChecked = selectedIds.contains(task.id)
                b.cbSelect.setOnCheckedChangeListener { _, _ ->
                    toggleSelection(task, holder.bindingAdapterPosition)
                }
                b.cardRoot.setOnClickListener {
                    toggleSelection(task, holder.bindingAdapterPosition)
                }
            } else {
                // Not in selection mode → tapping the card opens edit
                b.cardRoot.setOnClickListener { onCardClick(task) }
            }
            b.actionsRow.isVisible = false
            return
        }

        b.cbSelect.isVisible = false
        // По умолчанию третья кнопка скрыта; включается только в STACK-ветке ниже.
        // Сбрасываем явно — ViewHolder'ы переиспользуются.
        b.btnAction3.isVisible = false

        // Tap card body → open edit (active tabs)
        b.cardRoot.setOnClickListener { onCardClick(task) }

        // ═══ Action buttons ═══
        when (mode) {
            TabMode.MERGED -> {
                // No stack/today split — single full-width "Complete" button
                b.btnAction1.text = "Выполнить"
                b.btnAction1.setBackgroundColor(ctx.getColor(R.color.success))
                b.btnAction1.setTextColor(ctx.getColor(R.color.on_success))
                b.btnAction1.setIconResource(R.drawable.ic_check)
                b.btnAction1.iconTint = android.content.res.ColorStateList.valueOf(ctx.getColor(R.color.on_success))
                // Remove end margin so the button fills the full row
                (b.btnAction1.layoutParams as LinearLayout.LayoutParams).marginEnd = 0
                b.btnAction2.isVisible = false
                b.actionsRow.isVisible = true
                b.btnAction1.setOnClickListener { onAction1(task) }
            }
            TabMode.TODAY -> {
                b.btnAction1.text = "Выполнить"
                b.btnAction1.setBackgroundColor(ctx.getColor(R.color.success))
                b.btnAction1.setTextColor(ctx.getColor(R.color.on_success))
                b.btnAction1.setIconResource(R.drawable.ic_check)
                b.btnAction1.iconTint = android.content.res.ColorStateList.valueOf(ctx.getColor(R.color.on_success))
                b.btnAction2.isVisible = true
                (b.btnAction1.layoutParams as LinearLayout.LayoutParams).marginEnd =
                    (8 * ctx.resources.displayMetrics.density).toInt()
                b.btnAction2.text = "В стек"
                b.btnAction2.setIconResource(R.drawable.ic_undo)
                b.btnAction2.iconTint = android.content.res.ColorStateList.valueOf(ctx.getColor(R.color.text_primary))
                b.actionsRow.isVisible = true
                b.btnAction1.setOnClickListener { onAction1(task) }
                b.btnAction2.setOnClickListener { onAction2(task) }
            }
            TabMode.STACK -> {
                val gap = (8 * ctx.resources.displayMetrics.density).toInt()
                b.btnAction1.text = "В сегодня"
                b.btnAction1.setBackgroundColor(ctx.getColor(R.color.primary))
                b.btnAction1.setTextColor(ctx.getColor(R.color.on_primary))
                b.btnAction1.setIconResource(R.drawable.ic_target)
                b.btnAction1.iconTint = android.content.res.ColorStateList.valueOf(ctx.getColor(R.color.on_primary))
                (b.btnAction1.layoutParams as LinearLayout.LayoutParams).marginEnd = gap
                b.btnAction2.isVisible = true
                b.btnAction2.text = "Удалить"
                b.btnAction2.setIconResource(R.drawable.ic_trash)
                b.btnAction2.iconTint = android.content.res.ColorStateList.valueOf(ctx.getColor(R.color.error))
                b.btnAction2.setTextColor(ctx.getColor(R.color.error))
                b.actionsRow.isVisible = true
                b.btnAction1.setOnClickListener { onAction1(task) }
                b.btnAction2.setOnClickListener { onAction2(task) }

                // ─── Третья кнопка «Отложить» (только при включённой функции) ───
                if (deferEnabled) {
                    // Освобождаем место для третьей кнопки — у второй появляется отступ справа.
                    (b.btnAction2.layoutParams as LinearLayout.LayoutParams).marginEnd = gap
                    b.btnAction3.isVisible = true
                    val deferred = task.deferredDate.isNotBlank()
                    // Отложенная задача → кнопка подсвечена фиолетовым и показывает дату.
                    val accent = ctx.getColor(R.color.defer_purple)
                    b.btnAction3.text = if (deferred) formatDeferChip(task.deferredDate) else "Отложить"
                    b.btnAction3.setIconResource(R.drawable.ic_clock)
                    b.btnAction3.iconTint = android.content.res.ColorStateList.valueOf(accent)
                    b.btnAction3.setTextColor(accent)
                    b.btnAction3.setStrokeColorResource(R.color.defer_purple)
                    b.btnAction3.setOnClickListener { onAction3(task) }
                } else {
                    (b.btnAction2.layoutParams as LinearLayout.LayoutParams).marginEnd = 0
                    b.btnAction3.isVisible = false
                }
            }
            TabMode.CALENDAR -> {
                if (task.status == "Сегодня") {
                    b.btnAction1.text = "Выполнить"
                    b.btnAction1.setBackgroundColor(ctx.getColor(R.color.success))
                    b.btnAction1.setTextColor(ctx.getColor(R.color.on_success))
                    b.btnAction1.setIconResource(R.drawable.ic_check)
                    b.btnAction1.iconTint = android.content.res.ColorStateList.valueOf(ctx.getColor(R.color.on_success))
                    b.btnAction2.text = "В стек"
                    b.btnAction2.setIconResource(R.drawable.ic_undo)
                } else {
                    b.btnAction1.text = "В сегодня"
                    b.btnAction1.setBackgroundColor(ctx.getColor(R.color.primary))
                    b.btnAction1.setTextColor(ctx.getColor(R.color.on_primary))
                    b.btnAction1.setIconResource(R.drawable.ic_target)
                    b.btnAction1.iconTint = android.content.res.ColorStateList.valueOf(ctx.getColor(R.color.on_primary))
                    b.btnAction2.text = "Удалить"
                    b.btnAction2.setIconResource(R.drawable.ic_trash)
                }
                b.actionsRow.isVisible = true
                b.btnAction1.setOnClickListener { onAction1(task) }
                b.btnAction2.setOnClickListener { onAction2(task) }
            }
            TabMode.ARCHIVE -> { /* handled above */ }
        }
    }

    /**
     * Applies the right card background skin based on deadline urgency and mode.
     * Uses subtle tinting on overdue and "due today" tasks for instant visual signal.
     */
    private fun applyCardSkin(b: ItemTaskBinding, task: Task) {
        val ctx = b.root.context
        // Фон карточки всегда белый. Срочность задачи передаётся цветом обводки.
        b.cardRoot.setCardBackgroundColor(ctx.getColor(R.color.bg_surface))
        b.cardRoot.strokeColor = when {
            mode == TabMode.ARCHIVE -> ctx.getColor(R.color.border_subtle)
            // Отложенная задача — фиолетовая обводка как визуальный сигнал в стеке.
            task.deferredDate.isNotBlank() && task.status == "Стек" ->
                ctx.getColor(R.color.defer_purple)
            mode == TabMode.CALENDAR && task.status == "Сегодня" ->
                ctx.getColor(R.color.primary_container)
            task.deadline.isNotBlank() && isToday(task.deadline) ->
                ctx.getColor(R.color.deadline_today)
            else -> ctx.getColor(R.color.border_subtle)
        }
    }

    /**
     * Форматирует чип дедлайна. Если задано начало — показывает диапазон «startFmt → endFmt».
     * Цвет чипа всегда отражает срочность по дате окончания (deadline).
     */
    private fun formatDeadlineChip(deadlineStart: String, deadline: String): String {
        return try {
            val endDate = LocalDate.parse(deadline)
            val today = LocalDate.now()
            val fmt = DateTimeFormatter.ofPattern("d MMM", Locale("ru"))
            val endStr = when {
                endDate.isBefore(today) -> "Просрочено · ${endDate.format(fmt)}"
                endDate.isEqual(today)  -> "Сегодня"
                else                    -> endDate.format(fmt)
            }
            if (deadlineStart.isNotBlank()) {
                val startDate = try { LocalDate.parse(deadlineStart) } catch (e: Exception) { null }
                if (startDate != null && startDate != endDate) "${startDate.format(fmt)} → $endStr"
                else endStr
            } else endStr
        } catch (e: Exception) { deadline }
    }

    /** Короткая подпись отложенной задачи на кнопке: «До 5 июн». */
    private fun formatDeferChip(deferredDate: String): String = try {
        val d = LocalDate.parse(deferredDate)
        "До ${d.format(DateTimeFormatter.ofPattern("d MMM", Locale("ru")))}"
    } catch (e: Exception) { "Отложено" }

    private fun deadlineColors(deadline: String): Pair<Int, Int> {
        return try {
            val dl = LocalDate.parse(deadline)
            val today = LocalDate.now()
            when {
                dl.isBefore(today) -> Pair(R.drawable.bg_chip_red, R.color.deadline_overdue)
                dl.isEqual(today)  -> Pair(R.drawable.bg_chip_yellow, R.color.deadline_today)
                else               -> Pair(R.drawable.bg_chip, R.color.deadline_future)
            }
        } catch (e: Exception) { Pair(R.drawable.bg_chip, R.color.deadline_future) }
    }

    private fun isOverdue(deadline: String) = try {
        LocalDate.parse(deadline).isBefore(LocalDate.now())
    } catch (e: Exception) { false }

    private fun isToday(deadline: String) = try {
        LocalDate.parse(deadline).isEqual(LocalDate.now())
    } catch (e: Exception) { false }
}
