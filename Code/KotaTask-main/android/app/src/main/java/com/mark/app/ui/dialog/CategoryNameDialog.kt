package com.mark.app.ui.dialog

import android.content.Context
import android.view.LayoutInflater
import androidx.appcompat.app.AlertDialog
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout
import com.mark.app.R

/**
 * Общий диалог ввода названия категории.
 *
 * Особенности:
 *   • inline-валидация (пустая строка → ошибка под полем, диалог НЕ закрывается);
 *   • локализованные кнопки (берутся из R.string, не из android.R);
 *   • переиспользуется в AddTaskFragment (quick-add при создании задачи) и
 *     в CategoryManagerFragment (добавление/переименование).
 *
 * Стандартный setPositiveButton() закрывает диалог автоматически. Чтобы
 * провалидировать ввод И оставить диалог открытым при ошибке, используем
 * setOnShowListener + ручной setOnClickListener на positive-кнопке.
 */
fun showQuickAddDialog(
    ctx: Context,
    initial: String = "",
    titleRes: Int = R.string.cat_add_btn,
    positiveRes: Int = R.string.cat_add_btn,
    onSubmit: (String) -> Unit
) {
    val dialog = MaterialAlertDialogBuilder(ctx)
        .setTitle(titleRes)
        .setPositiveButton(positiveRes, null)  // null — закрытие переопределим
        .setNegativeButton(R.string.btn_cancel, null)
        .create()

    // Inflate the view with the dialog's themed context to ensure correct style resolution
    val view = LayoutInflater.from(dialog.context)
        .inflate(R.layout.dialog_category_input, null, false)
    val til   = view.findViewById<TextInputLayout>(R.id.tilCategoryName)
    val input = view.findViewById<TextInputEditText>(R.id.etCategoryName)

    input.setText(initial)
    input.setSelection(input.text?.length ?: 0)

    dialog.setView(view)

    dialog.setOnShowListener {
        // Request focus and show keyboard
        input.requestFocus()

        val positive = dialog.getButton(AlertDialog.BUTTON_POSITIVE)
        positive.setOnClickListener {
            val name = input.text?.toString()?.trim().orEmpty()
            if (name.isEmpty()) {
                til.error = ctx.getString(R.string.error_empty_category_name)
                return@setOnClickListener
            }
            til.error = null
            onSubmit(name)
            dialog.dismiss()
        }
        // Очищаем ошибку при изменении текста после ошибки
        input.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                if (!til.error.isNullOrEmpty()) til.error = null
            }
            override fun afterTextChanged(s: android.text.Editable?) {}
        })
    }
    dialog.show()
}
