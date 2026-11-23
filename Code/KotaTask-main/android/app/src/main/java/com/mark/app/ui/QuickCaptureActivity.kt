package com.mark.app.ui

import android.app.Application
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.viewModelScope
import com.google.android.material.button.MaterialButton
import com.google.android.material.textfield.TextInputEditText
import com.google.android.material.textfield.TextInputLayout
import com.mark.app.R
import com.mark.app.data.AppDatabase
import com.mark.app.repository.TaskRepository
import com.mark.app.util.TaskCapture
import kotlinx.coroutines.launch

class QuickCaptureViewModel(application: Application) : AndroidViewModel(application) {
    enum class State { READY, SAVING, SAVED, ERROR }
    val state = MutableLiveData(State.READY)
    fun save(title: String) {
        if (state.value == State.SAVING || state.value == State.SAVED) return
        val task = TaskCapture.create(title) ?: return
        state.value = State.SAVING
        viewModelScope.launch {
            try {
                TaskRepository(AppDatabase.getInstance(getApplication())).insert(task)
                state.value = State.SAVED
            } catch (_: Exception) { state.value = State.ERROR }
        }
    }
}

/** Один ввод, без онбординга и обязательных дополнительных полей. */
class QuickCaptureActivity : AppCompatActivity() {
    private val model: QuickCaptureViewModel by viewModels()
    private lateinit var input: TextInputEditText

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(24), dp(24), dp(24), dp(16))
            setBackgroundColor(getColor(R.color.bg_surface))
        }
        root.addView(TextView(this).apply {
            text = "Записать задачу"; textSize = 22f; setTextColor(getColor(R.color.text_primary))
        })
        root.addView(TextView(this).apply {
            text = "Сейчас — название. Остальное можно дополнить позже."
            setTextColor(getColor(R.color.text_secondary)); setPadding(0, dp(8), 0, dp(16))
        })
        val field = TextInputLayout(this).apply { hint = "Что нужно сделать?" }
        input = TextInputEditText(field.context).apply {
            id = R.id.quickCaptureTitle
            setSingleLine(true)
            imeOptions = EditorInfo.IME_ACTION_DONE
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            setText(savedInstanceState?.getString("title") ?: "")
        }
        field.addView(input)
        root.addView(field)
        val actions = LinearLayout(this).apply { gravity = Gravity.END }
        val cancel = MaterialButton(this, null, com.google.android.material.R.attr.borderlessButtonStyle).apply {
            text = "Отмена"; setOnClickListener { finish() }
        }
        val save = MaterialButton(this).apply { text = "Сохранить"; id = R.id.quickCaptureSave }
        fun submit() {
            if (input.text.toString().isBlank()) field.error = "Введите название"
            else { field.error = null; model.save(input.text.toString()) }
        }
        save.setOnClickListener { submit() }
        input.setOnEditorActionListener { _, action, _ ->
            if (action == EditorInfo.IME_ACTION_DONE) { submit(); true } else false
        }
        actions.addView(cancel); actions.addView(save)
        root.addView(actions)
        setContentView(root)
        window.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.WRAP_CONTENT)
        window.setGravity(Gravity.BOTTOM)
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE)
        input.requestFocus()
        model.state.observe(this) { state ->
            save.isEnabled = state != QuickCaptureViewModel.State.SAVING
            cancel.isEnabled = state != QuickCaptureViewModel.State.SAVING
            input.isEnabled = state != QuickCaptureViewModel.State.SAVING
            when (state) {
                QuickCaptureViewModel.State.SAVED -> {
                    Toast.makeText(this, "В стеке · нужно дополнить", Toast.LENGTH_SHORT).show()
                    finish()
                }
                QuickCaptureViewModel.State.ERROR -> field.error = "Не удалось сохранить. Попробуйте ещё раз."
                else -> Unit
            }
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putString("title", input.text.toString())
        super.onSaveInstanceState(outState)
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
}
