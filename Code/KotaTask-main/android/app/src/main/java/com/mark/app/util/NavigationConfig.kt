package com.mark.app.util

enum class MainDestination(val key: String) {
    TODAY("today"), STACK("stack"), BOARD("board"), CALENDAR("calendar"),
    FOLDERS("folders"), ARCHIVE("archive"), SETTINGS("settings")
}

object NavigationConfig {
    const val KEY = "bottom_navigation_order"
    const val MAX_ITEMS = 5
    val defaults = listOf(MainDestination.TODAY, MainDestination.STACK, MainDestination.BOARD,
        MainDestination.CALENDAR, MainDestination.SETTINGS)

    fun decode(value: String?): List<MainDestination> = value?.split(",")
        ?.mapNotNull { key -> MainDestination.entries.firstOrNull { it.key == key } }
        ?.distinct()?.take(MAX_ITEMS)?.takeIf { it.isNotEmpty() } ?: defaults

    fun encode(items: List<MainDestination>): String = items.distinct().take(MAX_ITEMS).joinToString(",") { it.key }

    /** Временно выключенная функция не стирается из сохранённого выбора. */
    fun visible(value: String?, available: Set<MainDestination>): List<MainDestination> =
        decode(value).filter { it in available }.ifEmpty { listOf(MainDestination.STACK, MainDestination.SETTINGS).filter { it in available } }
}
