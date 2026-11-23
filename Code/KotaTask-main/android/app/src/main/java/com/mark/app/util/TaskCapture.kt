package com.mark.app.util

import com.mark.app.data.Task
import java.util.UUID

object TaskCapture {
    fun create(title: String, projectId: String? = null, now: Long = System.currentTimeMillis()): Task? {
        val trimmed = title.trim()
        if (trimmed.isEmpty()) return null
        return Task(
            id = UUID.randomUUID().toString(), title = trimmed, projectId = projectId,
            created = now, needsDetails = true
        )
    }
}
