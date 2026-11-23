package com.mark.app

import com.mark.app.data.Task
import com.mark.app.util.BoardOrder
import com.mark.app.util.MainDestination
import com.mark.app.util.NavigationConfig
import com.mark.app.util.TaskCapture
import com.mark.app.util.TaskTextExport
import org.junit.Assert.*
import org.junit.Test

class NewFeaturesTest {
    private fun task(id: String, project: String? = null, index: Double = 0.0, status: String = "Стек") =
        Task(id = id, title = id, projectId = project, sortIndex = index, status = status, created = 0)

    @Test fun quickCaptureOnlyNeedsTitleAndMarksIncomplete() {
        assertNull(TaskCapture.create(" \n "))
        val captured = TaskCapture.create("  Позвонить врачу  ", now = 123)!!
        assertEquals("Позвонить врачу", captured.title)
        assertTrue(captured.needsDetails)
        assertEquals("Стек", captured.status)
        assertEquals("", captured.deadline)
        assertEquals(123L, captured.created)
    }

    @Test fun boardIncludesTodayAndExcludesArchive() {
        assertEquals(listOf("today", "stack"), BoardOrder.column(listOf(
            task("stack", "A", 2.0), task("today", "A", 1.0, "Сегодня"),
            task("done", "A", 0.0, "Архив"), task("other", "B")
        ), "A").map { it.id })
    }

    @Test fun crossProjectPlacementKeepsStatusAndFields() {
        val moving = task("moving", "A", status = "Сегодня").copy(needsDetails = true, purpose = "Контекст")
        val all = listOf(moving, task("b1", "B", 0.0), task("b2", "B", 1.0))
        val updates = BoardOrder.place(all, "moving", "B", 1)
        val after = all.map { original -> updates.find { it.id == original.id } ?: original }
        assertEquals(listOf("b1", "moving", "b2"), BoardOrder.column(after, "B").map { it.id })
        val placed = after.first { it.id == "moving" }
        assertEquals("Сегодня", placed.status)
        assertTrue(placed.needsDetails)
        assertEquals("Контекст", placed.purpose)
        assertTrue(BoardOrder.column(after, "A").isEmpty())
    }

    @Test fun droppingAtEndAndReorderingDoesNotDuplicate() {
        val all = listOf(task("a", "A", 0.0), task("b", "A", 1.0), task("c", "A", 2.0))
        val changes = BoardOrder.place(all, "a", "A", null)
        val after = all.map { original -> changes.find { it.id == original.id } ?: original }
        assertEquals(listOf("b", "c", "a"), BoardOrder.column(after, "A").map { it.id })
        assertEquals(3, after.map { it.id }.distinct().size)
        assertTrue(BoardOrder.place(all, "missing", null, 0).isEmpty())
        assertTrue(BoardOrder.place(listOf(task("done", status = "Архив")), "done", null, 0).isEmpty())
    }

    @Test fun disabledProjectsKeepAssignmentsDuringManualReorder() {
        val all = listOf(task("a", "A", 0.0), task("b", "B", 1.0))
        val updates = BoardOrder.place(all, "b", null, 0, allProjects = true)
        assertEquals("B", updates.first { it.id == "b" }.projectId)
        val after = all.map { t -> updates.find { it.id == t.id } ?: t }
        assertEquals(listOf("b", "a"), BoardOrder.column(after, null, true).map { it.id })
    }

    @Test fun navigationRestoresOrderAndHandlesInvalidOrDisabledChoices() {
        assertEquals(listOf(MainDestination.BOARD, MainDestination.ARCHIVE),
            NavigationConfig.decode("board,bad,board,archive"))
        assertEquals(NavigationConfig.defaults, NavigationConfig.decode("bad"))
        val available = MainDestination.entries.toSet() - MainDestination.TODAY - MainDestination.CALENDAR
        assertEquals(listOf(MainDestination.BOARD), NavigationConfig.visible("today,board,calendar", available))
        assertEquals(listOf(MainDestination.STACK, MainDestination.SETTINGS),
            NavigationConfig.visible("today,calendar", available))
        val encoded = NavigationConfig.encode(listOf(MainDestination.ARCHIVE, MainDestination.BOARD))
        assertEquals(listOf(MainDestination.ARCHIVE, MainDestination.BOARD), NavigationConfig.decode(encoded))
    }

    @Test fun exportContainsBothActiveStatusesAllFieldsAndLegendBeforeData() {
        val captured = task("draft", "p", status = "Сегодня").copy(
            title = "Название", purpose = "Описание", deadlineStart = "2026-11-21",
            deadline = "2026-11-23", locationId = "l", taskTypeId = "t",
            deferredDate = "2026-11-22", needsDetails = true
        )
        val text = TaskTextExport.render(listOf(captured, task("stack"), task("archived", status = "Архив")),
            mapOf("p" to "Проект"), mapOf("l" to "Дом"), mapOf("t" to "Звонок"))
        listOf("Название", "Описание", "2026-11-21", "2026-11-23", "Проект", "Дом", "Звонок",
            "2026-11-22", "Да", "| stack |", "| draft |").forEach { assertTrue(it, text.contains(it)) }
        assertFalse(text.contains("| archived |"))
        assertTrue(text.indexOf("Пояснения столбцов") < text.indexOf("| draft |"))
        assertTrue(text.contains("Всего: 2."))
    }

    @Test fun exportEscapesCellsAndDoesNotTruncateLargeLists() {
        val tasks = (0..2499).map { task("task-$it").copy(title = "Строка | $it\nпродолжение\\", purpose = "а\tб") }
        val text = TaskTextExport.render(tasks, emptyMap(), emptyMap(), emptyMap())
        assertTrue(text.contains("Строка \\| 2499\\nпродолжение\\\\"))
        assertTrue(text.contains("а\\tб"))
        assertEquals(2500, text.lineSequence().count { it.startsWith("| task-") })
        assertTrue(text.contains("Всего: 2500."))
    }
}
