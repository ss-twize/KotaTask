package com.mark.app.ui

import android.content.Context
import android.content.SharedPreferences
import android.view.Gravity
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.mark.app.util.MainDestination
import com.mark.app.util.NavigationConfig

object NavigationEditor {
    fun show(
        context: Context, prefs: SharedPreferences, available: Set<MainDestination>,
        title: (MainDestination) -> String, onSaved: () -> Unit
    ) {
        val saved = NavigationConfig.decode(prefs.getString(NavigationConfig.KEY, null))
        val selected = saved.filter { it in available }.toMutableSet()
        val order = (saved + MainDestination.entries.filter { it !in saved }).toMutableList()
        val root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(20, 12, 20, 12)
        }
        fun redraw() {
            val grouped = order.filter { it in selected } + order.filter { it !in selected }
            order.clear(); order.addAll(grouped)
            root.removeAllViews()
            root.addView(TextView(context).apply {
                text = "Выберите 2–5 разделов. Стрелки меняют порядок. Все разделы всегда доступны через ⋮."
                setPadding(8, 8, 8, 16)
            })
            order.forEachIndexed { index, destination ->
                val row = LinearLayout(context).apply { gravity = Gravity.CENTER_VERTICAL }
                val check = CheckBox(context).apply {
                    text = title(destination) + if (destination !in available) " · выключено" else ""
                    isChecked = destination in selected
                    isEnabled = destination in available
                    minHeight = (48 * resources.displayMetrics.density).toInt()
                    setOnCheckedChangeListener { button, enabled ->
                        if (enabled && selected.count { it in available } >= NavigationConfig.MAX_ITEMS) {
                            button.isChecked = false
                            Toast.makeText(context, "На панели не больше пяти разделов", Toast.LENGTH_SHORT).show()
                        } else {
                            if (enabled) selected.add(destination) else selected.remove(destination)
                            redraw()
                        }
                    }
                }
                row.addView(check, LinearLayout.LayoutParams(0, -2, 1f))
                fun arrow(label: String, offset: Int) {
                    row.addView(android.widget.Button(context).apply {
                        text = label
                        contentDescription = title(destination) + if (offset < 0) " — левее" else " — правее"
                        visibility = if (destination in selected) android.view.View.VISIBLE else android.view.View.GONE
                        isEnabled = index + offset in order.indices && order[index + offset] in selected
                        setOnClickListener {
                            java.util.Collections.swap(order, index, index + offset)
                            redraw()
                        }
                    }, LinearLayout.LayoutParams((48 * context.resources.displayMetrics.density).toInt(), -2))
                }
                arrow("↑", -1); arrow("↓", 1)
                root.addView(row)
            }
        }
        redraw()
        val dialog = MaterialAlertDialogBuilder(context)
            .setTitle("Нижнее меню")
            .setView(ScrollView(context).apply { addView(root) })
            .setNegativeButton("Отмена", null)
            .setNeutralButton("По умолчанию", null)
            .setPositiveButton("Сохранить", null).create()
        dialog.setOnShowListener {
            dialog.getButton(android.content.DialogInterface.BUTTON_NEUTRAL).setOnClickListener {
                prefs.edit().remove(NavigationConfig.KEY).apply(); onSaved(); dialog.dismiss()
            }
            dialog.getButton(android.content.DialogInterface.BUTTON_POSITIVE).setOnClickListener {
                if (selected.count { it in available } < 2) {
                    Toast.makeText(context, "Выберите хотя бы два доступных раздела", Toast.LENGTH_SHORT).show()
                } else {
                    prefs.edit().putString(NavigationConfig.KEY, NavigationConfig.encode(order.filter { it in selected })).apply()
                    onSaved(); dialog.dismiss()
                }
            }
        }
        dialog.show()
    }
}
