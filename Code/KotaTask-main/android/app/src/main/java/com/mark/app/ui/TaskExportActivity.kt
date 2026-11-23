package com.mark.app.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import androidx.lifecycle.lifecycleScope
import androidx.room.withTransaction
import com.google.android.material.button.MaterialButton
import com.mark.app.R
import com.mark.app.data.AppDatabase
import com.mark.app.util.TaskTextExport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class TaskExportActivity : AppCompatActivity() {
    private var exportText: String? = null
    private val saveDocument = registerForActivityResult(ActivityResultContracts.CreateDocument("text/plain")) { uri ->
        val text = exportText
        if (uri != null && text != null) lifecycleScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    checkNotNull(contentResolver.openOutputStream(uri)).bufferedWriter().use { it.write(text) }
                }
                toast("Файл сохранён")
            } catch (_: Exception) { toast("Не удалось сохранить файл. Попробуйте другую папку.") }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(16), dp(20), dp(16))
            setBackgroundColor(getColor(R.color.bg_canvas))
        }
        root.addView(TextView(this).apply {
            text = "Экспорт задач"; textSize = 24f; setTextColor(getColor(R.color.text_primary))
        })
        root.addView(TextView(this).apply {
            text = "Весь стек и план на сегодня — для чата или нейросети."
            setTextColor(getColor(R.color.text_secondary)); setPadding(0, dp(8), 0, dp(12))
        })
        val preview = TextView(this).apply {
            text = "Подготавливаем список…"; textSize = 12f
            setTextColor(getColor(R.color.text_primary)); setTextIsSelectable(true)
        }
        root.addView(ScrollView(this).apply { addView(preview) }, LinearLayout.LayoutParams(-1, 0, 1f))
        val actions = LinearLayout(this).apply { gravity = Gravity.CENTER; orientation = LinearLayout.VERTICAL }
        fun button(label: String, action: () -> Unit): MaterialButton =
            MaterialButton(this).apply {
                text = label; isEnabled = false; setOnClickListener { action() }
                actions.addView(this, LinearLayout.LayoutParams(-1, dp(52)))
            }
        val shareButton = button("Поделиться текстом") { exportText?.let(::share) }
        val copyButton = button("Копировать") {
            exportText?.let {
                try {
                    (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                        .setPrimaryClip(ClipData.newPlainText("Задачи KotaTask", it))
                    toast("Скопировано")
                } catch (_: Exception) { toast("Список слишком большой для буфера. Сохраните файл.") }
            }
        }
        val saveButton = button("Сохранить .txt") { saveDocument.launch("KotaTask-задачи.txt") }
        root.addView(actions)
        root.addView(MaterialButton(this, null, com.google.android.material.R.attr.borderlessButtonStyle).apply {
            text = "Закрыть"; setOnClickListener { finish() }
        })
        setContentView(root)
        lifecycleScope.launch {
            try {
                val text = withContext(Dispatchers.IO) {
                    val db = AppDatabase.getInstance(applicationContext)
                    db.withTransaction {
                        TaskTextExport.render(
                            db.taskDao().getAllTasksOnce(),
                            db.projectDao().getAllOnce().associate { it.id to it.name },
                            db.locationDao().getAllOnce().associate { it.id to it.name },
                            db.taskTypeDao().getAllOnce().associate { it.id to it.name }
                        )
                    }
                }
                exportText = text
                preview.text = text
                shareButton.isEnabled = true; copyButton.isEnabled = true; saveButton.isEnabled = true
                if (text.toByteArray(Charsets.UTF_8).size > 180_000) shareButton.text = "Поделиться файлом .txt"
            } catch (_: Exception) {
                preview.text = "Не удалось прочитать задачи. Закройте экран и попробуйте ещё раз."
            }
        }
    }

    private fun share(text: String) {
        lifecycleScope.launch {
            try {
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_SUBJECT, "Задачи KotaTask")
                }
                if (text.toByteArray(Charsets.UTF_8).size <= 180_000) {
                    send.putExtra(Intent.EXTRA_TEXT, text)
                } else {
                    val file = withContext(Dispatchers.IO) {
                        File(cacheDir, "exports").apply { mkdirs() }
                            .resolve("KotaTask-задачи.txt").apply { writeText(text) }
                    }
                    val uri = FileProvider.getUriForFile(this@TaskExportActivity, "$packageName.exports", file)
                    send.putExtra(Intent.EXTRA_STREAM, uri)
                    send.clipData = ClipData.newRawUri("Задачи KotaTask", uri)
                    send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(send, "Отправить задачи"))
            } catch (_: Exception) { toast("Не удалось открыть отправку. Используйте «Сохранить .txt».") }
        }
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun toast(message: String) = Toast.makeText(this, message, Toast.LENGTH_LONG).show()
}
