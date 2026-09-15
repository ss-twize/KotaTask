package com.mark.app.ui.calendar

import android.view.ViewGroup
import androidx.recyclerview.widget.RecyclerView
import com.mark.app.data.Task
import java.time.LocalDate
import java.time.YearMonth
import java.time.format.DateTimeFormatter

class MonthCalendarAdapter(
    private var yearMonth: YearMonth,
    private var tasksByDate: Map<String, List<Task>>,
    private val onDateSelected: (String) -> Unit
) : RecyclerView.Adapter<MonthCalendarAdapter.CellHolder>() {

    private val isoFmt = DateTimeFormatter.ISO_LOCAL_DATE
    private var cells: List<CalendarCell> = buildCells()
    private var selectedDateStr: String = LocalDate.now().format(isoFmt)

    inner class CellHolder(val view: CalendarCellView) : RecyclerView.ViewHolder(view)

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): CellHolder {
        val v = CalendarCellView(parent.context)
        v.layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT
        )
        return CellHolder(v)
    }

    override fun getItemCount() = cells.size

    override fun onBindViewHolder(holder: CellHolder, position: Int) {
        val cell = cells[position]
        holder.view.cell = cell
        holder.view.isDateSelected = cell.dateStr == selectedDateStr && cell.isCurrentMonth
        holder.view.setOnClickListener {
            if (cell.isCurrentMonth) {
                val prev = selectedDateStr
                selectedDateStr = cell.dateStr
                // refresh old and new selection
                val prevIdx = cells.indexOfFirst { it.dateStr == prev }
                if (prevIdx >= 0) notifyItemChanged(prevIdx)
                notifyItemChanged(position)
                onDateSelected(cell.dateStr)
            }
        }
    }

    fun update(yearMonth: YearMonth, tasksByDate: Map<String, List<Task>>, selectedDate: String) {
        this.yearMonth = yearMonth
        this.tasksByDate = tasksByDate
        this.selectedDateStr = selectedDate
        this.cells = buildCells()
        notifyDataSetChanged()
    }

    fun updateTasks(tasksByDate: Map<String, List<Task>>) {
        this.tasksByDate = tasksByDate
        this.cells = buildCells()
        notifyDataSetChanged()
    }

    private fun buildCells(): List<CalendarCell> {
        val today = LocalDate.now()
        val firstDay = yearMonth.atDay(1)
        // Monday=1 ... Sunday=7, we want Mon as column 0
        val startOffset = (firstDay.dayOfWeek.value - 1) // Mon=0, Tue=1 ... Sun=6
        val daysInMonth = yearMonth.lengthOfMonth()
        val prevMonth = yearMonth.minusMonths(1)
        val daysInPrev = prevMonth.lengthOfMonth()

        val list = mutableListOf<CalendarCell>()

        // Trailing days from previous month
        for (i in startOffset downTo 1) {
            val day = daysInPrev - i + 1
            val date = prevMonth.atDay(day)
            val dateStr = date.format(isoFmt)
            list.add(CalendarCell(day, dateStr, false, date == today, tasksByDate[dateStr] ?: emptyList()))
        }

        // Current month days
        for (day in 1..daysInMonth) {
            val date = yearMonth.atDay(day)
            val dateStr = date.format(isoFmt)
            list.add(CalendarCell(day, dateStr, true, date == today, tasksByDate[dateStr] ?: emptyList()))
        }

        // Leading days from next month to fill last row
        val nextMonth = yearMonth.plusMonths(1)
        val remaining = (7 - list.size % 7) % 7
        for (day in 1..remaining) {
            val date = nextMonth.atDay(day)
            val dateStr = date.format(isoFmt)
            list.add(CalendarCell(day, dateStr, false, date == today, tasksByDate[dateStr] ?: emptyList()))
        }

        return list
    }
}
