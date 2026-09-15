package com.mark.app.ui

import android.app.TimePickerDialog
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.view.isVisible
import androidx.fragment.app.Fragment
import androidx.fragment.app.activityViewModels
import com.mark.app.KotaTaskApp
import com.mark.app.R
import com.mark.app.databinding.FragmentSettingsBinding
import com.mark.app.util.Coefficients
import com.mark.app.util.cancelDaily
import com.mark.app.util.scheduleDaily
import com.mark.app.viewmodel.TaskViewModel
import java.util.Locale

class SettingsFragment : Fragment() {

    private var _binding: FragmentSettingsBinding? = null
    private val binding get() = _binding!!
    private val vm: TaskViewModel by activityViewModels()

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View {
        _binding = FragmentSettingsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        setupThemeSelector()
        setupFeatureToggles()
        setupCalendarModeSelector()
        setupAssistanceSelector()
        setupFieldToggles()
        setupNotificationSettings()
        setupPrioritySliders()
        setupArchiveButton()
        setupFoldersButton()
        setupContacts()
    }

    /**
     * Тогглы из онбординга, сохраняющиеся мгновенно. После каждого изменения
     * просим MainActivity перерисовать bottom-nav, чтобы пользователь сразу
     * видел эффект (исчезла/появилась вкладка «Сегодня»/«Календарь»).
     */
    private fun setupFeatureToggles() {
        val prefs = requireContext().getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)

        binding.switchFeatSplitToday.isChecked  = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_SPLIT_TODAY, true)
        binding.switchFeatCalendar.isChecked    = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_CALENDAR,    true)
        binding.switchFeatProjects.isChecked    = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_PROJECTS,    true)
        binding.switchFeatLocations.isChecked   = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_LOCATIONS,   true)
        binding.switchFeatTaskTypes.isChecked   = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_TASK_TYPES,  true)
        binding.switchFeatSmartSort.isChecked   = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_SMART_SORT,  true)
        binding.switchFeatDefer.isChecked       = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_DEFER,       false)

        // Отложенное планирование работает только при включённом разделении Сегодня/Стек.
        // При выключенном разделении строка становится серой и неактивной.
        updateDeferToggleEnabled(binding.switchFeatSplitToday.isChecked)

        binding.switchFeatSplitToday.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FEATURE_SPLIT_TODAY, v).apply()
            updateDeferToggleEnabled(v)
            (activity as? MainActivity)?.applyFeatureFlagsToNav()
        }
        binding.switchFeatDefer.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FEATURE_DEFER, v).apply()
        }
        binding.switchFeatCalendar.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FEATURE_CALENDAR, v).apply()
            (activity as? MainActivity)?.applyFeatureFlagsToNav()
        }
        binding.switchFeatProjects.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FEATURE_PROJECTS, v).apply()
            (activity as? MainActivity)?.applyFeatureFlagsToNav()
            refreshFoldersCardVisibility()
        }
        binding.switchFeatLocations.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FEATURE_LOCATIONS, v).apply()
            (activity as? MainActivity)?.applyFeatureFlagsToNav()
            refreshFoldersCardVisibility()
        }
        binding.switchFeatTaskTypes.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FEATURE_TASK_TYPES, v).apply()
            (activity as? MainActivity)?.applyFeatureFlagsToNav()
            refreshFoldersCardVisibility()
        }
        binding.switchFeatSmartSort.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FEATURE_SMART_SORT, v).apply()
        }
    }

    /**
     * Включает/выключает строку «Отложенное планирование» в зависимости от того,
     * включено ли разделение Сегодня/Стек. При выключенном разделении строка
     * затемняется (alpha 0.4) и переключатель становится неактивным.
     */
    private fun updateDeferToggleEnabled(splitEnabled: Boolean) {
        binding.switchFeatDefer.isEnabled = splitEnabled
        binding.rowFeatDefer.alpha = if (splitEnabled) 1.0f else 0.4f
    }

    private fun setupAssistanceSelector() {
        val prefs = requireContext().getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
        val saved = prefs.getString(KotaTaskApp.KEY_ASSISTANCE_LEVEL, KotaTaskApp.DEFAULT_ASSISTANCE_LEVEL)

        binding.rgAssistance.check(when (saved) {
            KotaTaskApp.ASSISTANCE_MINIMAL  -> binding.rbAsstMinimal.id
            KotaTaskApp.ASSISTANCE_ADVANCED -> binding.rbAsstAdvanced.id
            KotaTaskApp.ASSISTANCE_CUSTOM   -> binding.rbAsstCustom.id
            else                            -> binding.rbAsstStandard.id
        })
        binding.btnConfigureCustomLevel.isVisible = (saved == KotaTaskApp.ASSISTANCE_CUSTOM)

        binding.rgAssistance.setOnCheckedChangeListener { _, checkedId ->
            val level = when (checkedId) {
                binding.rbAsstMinimal.id  -> KotaTaskApp.ASSISTANCE_MINIMAL
                binding.rbAsstAdvanced.id -> KotaTaskApp.ASSISTANCE_ADVANCED
                binding.rbAsstCustom.id   -> KotaTaskApp.ASSISTANCE_CUSTOM
                else                      -> KotaTaskApp.ASSISTANCE_STANDARD
            }
            prefs.edit().putString(KotaTaskApp.KEY_ASSISTANCE_LEVEL, level).apply()
            binding.btnConfigureCustomLevel.isVisible = (level == KotaTaskApp.ASSISTANCE_CUSTOM)
        }

        binding.btnConfigureCustomLevel.setOnClickListener { showCustomLevelDialog(prefs) }
    }

    private fun showCustomLevelDialog(prefs: android.content.SharedPreferences) {
        val isDurationVisible  = prefs.getBoolean(KotaTaskApp.KEY_FIELD_DURATION, true)
        val isPurposeVisible   = prefs.getBoolean(KotaTaskApp.KEY_FIELD_PURPOSE,  true)
        val isProjectVisible   = prefs.getBoolean(KotaTaskApp.KEY_FIELD_PROJECT,  true) &&
                                 prefs.getBoolean(KotaTaskApp.KEY_FEATURE_PROJECTS, true)
        val isLocationVisible  = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_LOCATIONS, true) &&
                                 prefs.getBoolean(KotaTaskApp.KEY_FIELD_LOCATION,     true)
        val isTaskTypeVisible  = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_TASK_TYPES, true) &&
                                 prefs.getBoolean(KotaTaskApp.KEY_FIELD_TASK_TYPE,    true)

        data class FieldEntry(val labelRes: Int, val key: String, val isEnabled: Boolean)
        val fields = listOf(
            FieldEntry(R.string.custom_req_deadline_start, KotaTaskApp.KEY_CUSTOM_REQUIRE_DEADLINE_START, true),
            FieldEntry(R.string.custom_req_deadline,       KotaTaskApp.KEY_CUSTOM_REQUIRE_DEADLINE,       true),
            FieldEntry(R.string.custom_req_importance,     KotaTaskApp.KEY_CUSTOM_REQUIRE_IMPORTANCE,     true),
            FieldEntry(R.string.custom_req_duration,       KotaTaskApp.KEY_CUSTOM_REQUIRE_DURATION,       isDurationVisible),
            FieldEntry(R.string.custom_req_purpose,        KotaTaskApp.KEY_CUSTOM_REQUIRE_PURPOSE,        isPurposeVisible),
            FieldEntry(R.string.custom_req_project,        KotaTaskApp.KEY_CUSTOM_REQUIRE_PROJECT,        isProjectVisible),
            FieldEntry(R.string.custom_req_location,       KotaTaskApp.KEY_CUSTOM_REQUIRE_LOCATION,       isLocationVisible),
            FieldEntry(R.string.custom_req_task_type,      KotaTaskApp.KEY_CUSTOM_REQUIRE_TASK_TYPE,      isTaskTypeVisible)
        )

        val ctx = requireContext()
        val density = ctx.resources.displayMetrics.density
        val dp8  = (8  * density).toInt()
        val dp16 = (16 * density).toInt()

        val container = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp8, dp8, dp8, dp8)
        }
        val checkBoxes = fields.map { entry ->
            CheckBox(ctx).apply {
                text = getString(entry.labelRes)
                isChecked = prefs.getBoolean(entry.key, false)
                isEnabled = entry.isEnabled
                alpha = if (entry.isEnabled) 1.0f else 0.38f
                setPadding(dp16, dp8, dp16, dp8)
                textSize = 16f
                container.addView(this)
            }
        }
        val scrollView = ScrollView(ctx).apply { addView(container) }

        AlertDialog.Builder(ctx)
            .setTitle(R.string.custom_level_dialog_title)
            .setView(scrollView)
            .setPositiveButton(android.R.string.ok) { _, _ ->
                val editor = prefs.edit()
                fields.forEachIndexed { i, entry ->
                    editor.putBoolean(entry.key, checkBoxes[i].isChecked && entry.isEnabled)
                }
                editor.apply()
            }
            .setNegativeButton(R.string.btn_cancel, null)
            .show()
    }

    private fun setupFieldToggles() {
        val prefs = requireContext().getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
        binding.switchFieldDuration.isChecked  = prefs.getBoolean(KotaTaskApp.KEY_FIELD_DURATION,  true)
        binding.switchFieldPurpose.isChecked   = prefs.getBoolean(KotaTaskApp.KEY_FIELD_PURPOSE,   true)
        binding.switchFieldProject.isChecked   = prefs.getBoolean(KotaTaskApp.KEY_FIELD_PROJECT,   true)
        binding.switchFieldTaskType.isChecked  = prefs.getBoolean(KotaTaskApp.KEY_FIELD_TASK_TYPE, true)
        binding.switchFieldLocation.isChecked  = prefs.getBoolean(KotaTaskApp.KEY_FIELD_LOCATION,  true)

        binding.switchFieldDuration.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FIELD_DURATION, v).apply()
        }
        binding.switchFieldPurpose.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FIELD_PURPOSE, v).apply()
        }
        binding.switchFieldProject.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FIELD_PROJECT, v).apply()
        }
        binding.switchFieldTaskType.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FIELD_TASK_TYPE, v).apply()
        }
        binding.switchFieldLocation.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FIELD_LOCATION, v).apply()
        }
    }

    private fun setupNotificationSettings() {
        val prefs = requireContext().getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)

        val enabled = prefs.getBoolean(KotaTaskApp.KEY_NOTIF_ENABLED, false)
        val hour    = prefs.getInt(KotaTaskApp.KEY_NOTIF_HOUR,   KotaTaskApp.DEFAULT_NOTIF_HOUR)
        val minute  = prefs.getInt(KotaTaskApp.KEY_NOTIF_MINUTE, KotaTaskApp.DEFAULT_NOTIF_MINUTE)

        binding.switchNotif.isChecked = enabled
        binding.rowNotifTime.isVisible = enabled
        binding.tvNotifTime.text = formatTime(hour, minute)

        binding.switchNotif.setOnCheckedChangeListener { _, isChecked ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_NOTIF_ENABLED, isChecked).apply()
            binding.rowNotifTime.isVisible = isChecked
            if (isChecked) scheduleDaily(requireContext())
            else cancelDaily(requireContext())
        }

        binding.rowNotifTime.setOnClickListener {
            val h = prefs.getInt(KotaTaskApp.KEY_NOTIF_HOUR,   KotaTaskApp.DEFAULT_NOTIF_HOUR)
            val m = prefs.getInt(KotaTaskApp.KEY_NOTIF_MINUTE, KotaTaskApp.DEFAULT_NOTIF_MINUTE)
            TimePickerDialog(requireContext(), { _, pickedH, pickedM ->
                prefs.edit()
                    .putInt(KotaTaskApp.KEY_NOTIF_HOUR,   pickedH)
                    .putInt(KotaTaskApp.KEY_NOTIF_MINUTE, pickedM)
                    .apply()
                binding.tvNotifTime.text = formatTime(pickedH, pickedM)
                // Перепланировать с новым временем немедленно
                scheduleDaily(requireContext())
            }, h, m, true).show()
        }
    }

    private fun setupContacts() {
        binding.rowContactEmail.setOnClickListener {
            startActivity(Intent(Intent.ACTION_SENDTO).apply {
                data = Uri.parse("mailto:supportkotatask@gmail.com")
            })
        }
        binding.rowContactTelegram.setOnClickListener {
            openUrl("https://t.me/+j6uyk2SS80liNDNi")
        }
        binding.rowContactSuggest.setOnClickListener {
            openUrl("https://t.me/+dbGPeyjrZsk1Yjgy")
        }
    }

    private fun openUrl(url: String) {
        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    }

    private fun formatTime(hour: Int, minute: Int): String =
        String.format(Locale.US, "%02d:%02d", hour, minute)

    /**
     * «Папки» живут в настройках, а не в bottom-nav: панель отдала центральный
     * слот кнопке добавления задачи. Карточка скрыта, если все три вида
     * категорий (проекты/локации/типы) выключены — тогда открывать нечего.
     */
    private fun setupFoldersButton() {
        val act = activity as? MainActivity ?: return
        binding.cardFolders.isVisible = act.featureFolders
        binding.btnOpenFolders.setOnClickListener {
            act.openModal(FoldersFragment(), getString(R.string.screen_title_folders))
        }
    }

    /** Пересчитывает видимость карточки «Папки» после смены тогглов категорий. */
    private fun refreshFoldersCardVisibility() {
        binding.cardFolders.isVisible = (activity as? MainActivity)?.featureFolders ?: false
    }

    private fun setupArchiveButton() {
        val act = activity as? MainActivity ?: return
        binding.btnOpenArchive.setOnClickListener {
            act.openModal(ArchiveFragment(), getString(R.string.screen_title_archive))
        }
    }

    private fun setupThemeSelector() {
        val prefs = requireContext().getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
        val saved = prefs.getString(KotaTaskApp.KEY_THEME, "system")

        binding.rgTheme.check(when (saved) {
            "light"  -> binding.rbThemeLight.id
            "dark"   -> binding.rbThemeDark.id
            else     -> binding.rbThemeSystem.id
        })

        binding.rgTheme.setOnCheckedChangeListener { _, checkedId ->
            val mode = when (checkedId) {
                binding.rbThemeLight.id  -> "light"
                binding.rbThemeDark.id   -> "dark"
                else                     -> "system"
            }
            prefs.edit().putString(KotaTaskApp.KEY_THEME, mode).apply()
            val nightMode = when (mode) {
                "light"  -> AppCompatDelegate.MODE_NIGHT_NO
                "dark"   -> AppCompatDelegate.MODE_NIGHT_YES
                else     -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
            }
            AppCompatDelegate.setDefaultNightMode(nightMode)
        }
    }

    private fun setupCalendarModeSelector() {
        val prefs = requireContext().getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)
        val saved = prefs.getString(KotaTaskApp.KEY_CALENDAR_MODE, "range")

        binding.rgCalendarMode.check(when (saved) {
            "point" -> binding.rbCalendarPoint.id
            else    -> binding.rbCalendarRange.id
        })

        // Сохраняем мгновенно при смене — не требует кнопки «Сохранить»
        binding.rgCalendarMode.setOnCheckedChangeListener { _, checkedId ->
            val mode = if (checkedId == binding.rbCalendarPoint.id) "point" else "range"
            prefs.edit().putString(KotaTaskApp.KEY_CALENDAR_MODE, mode).apply()
        }
    }

    private fun setupPrioritySliders() {
        val c = vm.getCoefficients()
        binding.seekDeadline.progress = (c.deadline * 100).toInt()
        binding.seekImportance.progress = (c.importance * 100).toInt()
        binding.seekDuration.progress = (c.duration * 100).toInt()
        binding.seekAge.progress = (c.age * 100).toInt()
        binding.seekOverloadLimit.max =
            (TaskViewModel.MAX_OVERLOAD_LIMIT_MINUTES - TaskViewModel.MIN_OVERLOAD_LIMIT_MINUTES) / OVERLOAD_STEP
        binding.seekOverloadLimit.progress =
            (vm.getOverloadLimitMinutes() - TaskViewModel.MIN_OVERLOAD_LIMIT_MINUTES) / OVERLOAD_STEP
        binding.seekLoadDurationBoost.progress = (vm.getLoadDurationBoost() * 100).toInt()

        updateLabels()

        val listener = object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(s: SeekBar?, progress: Int, fromUser: Boolean) = updateLabels()
            override fun onStartTrackingTouch(s: SeekBar?) {}
            override fun onStopTrackingTouch(s: SeekBar?) {}
        }
        binding.seekDeadline.setOnSeekBarChangeListener(listener)
        binding.seekImportance.setOnSeekBarChangeListener(listener)
        binding.seekDuration.setOnSeekBarChangeListener(listener)
        binding.seekAge.setOnSeekBarChangeListener(listener)
        binding.seekOverloadLimit.setOnSeekBarChangeListener(listener)
        binding.seekLoadDurationBoost.setOnSeekBarChangeListener(listener)

        binding.btnResetAlgorithmDefaults.setOnClickListener {
            binding.seekDeadline.progress = DEFAULT_DEADLINE_PROGRESS
            binding.seekImportance.progress = DEFAULT_IMPORTANCE_PROGRESS
            binding.seekDuration.progress = DEFAULT_DURATION_PROGRESS
            binding.seekAge.progress = DEFAULT_AGE_PROGRESS
            updateLabels()
        }

        binding.btnResetLoadDefaults.setOnClickListener {
            binding.seekOverloadLimit.progress =
                (TaskViewModel.DEFAULT_OVERLOAD_LIMIT_MINUTES - TaskViewModel.MIN_OVERLOAD_LIMIT_MINUTES) / OVERLOAD_STEP
            binding.seekLoadDurationBoost.progress =
                (TaskViewModel.DEFAULT_LOAD_DURATION_BOOST * 100).toInt()
            updateLabels()
        }

        binding.btnSaveSettings.setOnClickListener {
            vm.saveCoefficients(Coefficients(
                deadline = binding.seekDeadline.progress / 100f,
                importance = binding.seekImportance.progress / 100f,
                duration = binding.seekDuration.progress / 100f,
                age = binding.seekAge.progress / 100f
            ))
            vm.saveOverloadLimitMinutes(currentOverloadLimitMinutes())
            vm.saveLoadDurationBoost(binding.seekLoadDurationBoost.progress / 100f)
            Toast.makeText(requireContext(), R.string.settings_saved, Toast.LENGTH_SHORT).show()
        }
    }

    private fun updateLabels() {
        binding.tvDeadlineVal.text = String.format(Locale.US, "%.2f", binding.seekDeadline.progress / 100f)
        binding.tvImportanceVal.text = String.format(Locale.US, "%.2f", binding.seekImportance.progress / 100f)
        binding.tvDurationVal.text = String.format(Locale.US, "%.2f", binding.seekDuration.progress / 100f)
        binding.tvAgeVal.text = String.format(Locale.US, "%.2f", binding.seekAge.progress / 100f)
        val overloadLimit = currentOverloadLimitMinutes()
        binding.tvOverloadLimitVal.text = "$overloadLimit мин"
        binding.tvLoadDurationBoostVal.text =
            String.format(Locale.US, "%.2f", binding.seekLoadDurationBoost.progress / 100f)
    }

    private fun currentOverloadLimitMinutes(): Int =
        (TaskViewModel.MIN_OVERLOAD_LIMIT_MINUTES + binding.seekOverloadLimit.progress * OVERLOAD_STEP)
            .coerceIn(
                TaskViewModel.MIN_OVERLOAD_LIMIT_MINUTES,
                TaskViewModel.MAX_OVERLOAD_LIMIT_MINUTES
            )

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private companion object {
        const val DEFAULT_DEADLINE_PROGRESS = 45
        const val DEFAULT_IMPORTANCE_PROGRESS = 35
        const val DEFAULT_DURATION_PROGRESS = 10
        const val DEFAULT_AGE_PROGRESS = 10
        const val OVERLOAD_STEP = 10  // шаг слайдера нагрузки в минутах
    }
}
