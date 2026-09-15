package com.mark.app.ui

import android.app.TimePickerDialog
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Bundle
import android.widget.CheckBox
import android.widget.SeekBar
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.view.isInvisible
import androidx.core.view.isVisible
import com.mark.app.KotaTaskApp
import com.mark.app.R
import com.mark.app.databinding.ActivityOnboardingBinding
import com.mark.app.util.scheduleDaily
import java.util.Locale

/**
 * Первый запуск приложения: 7 экранов мастера настройки. По завершении
 * выставляет KEY_ONBOARDING_DONE и стартует MainActivity. Все настройки
 * дублируются в SettingsFragment, и пользователь может изменить их позже.
 */
class OnboardingActivity : AppCompatActivity() {

    private lateinit var binding: ActivityOnboardingBinding
    private lateinit var prefs: SharedPreferences
    private var currentStep = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityOnboardingBinding.inflate(layoutInflater)
        setContentView(binding.root)

        prefs = getSharedPreferences(KotaTaskApp.PREFS_NAME, Context.MODE_PRIVATE)

        bindSystemStep()
        bindFeaturesStep()
        bindCoeffsStep()
        bindCalendarStep()
        bindAssistanceStep()
        bindFieldsStep()

        // Кнопка «Пропустить» доступна только при переустановке с восстановленными
        // настройками (см. MainActivity). При чистой установке её нет — пройти
        // первичную настройку обязательно.
        val allowSkip = intent.getBooleanExtra(KotaTaskApp.EXTRA_ALLOW_SKIP, false)
        binding.onbBtnSkip.isVisible = allowSkip
        binding.onbBtnSkip.setOnClickListener { finishOnboarding() }

        binding.onbBtnBack.setOnClickListener {
            var prev = currentStep - 1
            if (prev == STEP_FIELDS && !isCustomAssistance()) prev--
            if (prev == STEP_COEFFS && !isSmartSortEnabled()) prev--
            goToStep(prev)
        }
        binding.onbBtnNext.setOnClickListener {
            val next = computeNext(currentStep)
            if (next >= STEP_COUNT) finishOnboarding()
            else goToStep(next)
        }

        // Восстанавливаем шаг после пересоздания Activity. Смена темы на шаге
        // «Системные настройки» вызывает recreate(), и без этого пользователя
        // отбрасывало на первый экран (баг: сброс онбординга при выборе темы).
        goToStep(savedInstanceState?.getInt(KEY_CURRENT_STEP, 0) ?: 0)
    }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putInt(KEY_CURRENT_STEP, currentStep)
    }

    /** Returns the next visible step index from [from], skipping disabled steps. */
    private fun computeNext(from: Int): Int {
        var next = from + 1
        if (next == STEP_COEFFS && !isSmartSortEnabled()) next++
        if (next == STEP_FIELDS && !isCustomAssistance()) next++
        return next
    }

    private fun goToStep(step: Int) {
        if (step < 0 || step >= STEP_COUNT) return
        currentStep = step
        binding.onbFlipper.displayedChild = step
        binding.onbBtnBack.isInvisible = step == 0
        binding.onbBtnNext.text = getString(
            if (computeNext(step) >= STEP_COUNT) R.string.onb_finish else R.string.onb_next
        )
        var visibleCount = STEP_COUNT
        if (!isSmartSortEnabled()) visibleCount--
        if (!isCustomAssistance()) visibleCount--
        var visibleIndex = step
        if (!isSmartSortEnabled() && step > STEP_COEFFS) visibleIndex--
        binding.onbStepLabel.text = getString(R.string.onb_step_format, visibleIndex + 1, visibleCount)
        binding.onbProgress.setProgressCompat(((visibleIndex + 1) * 100) / visibleCount, true)
    }

    private fun isSmartSortEnabled() =
        prefs.getBoolean(KotaTaskApp.KEY_FEATURE_SMART_SORT, true)

    private fun isCustomAssistance() =
        prefs.getString(KotaTaskApp.KEY_ASSISTANCE_LEVEL, KotaTaskApp.DEFAULT_ASSISTANCE_LEVEL) ==
                KotaTaskApp.ASSISTANCE_CUSTOM

    // ─────────────────────────────────────────────────────────────────────
    // Step 2: System (theme + notifications)
    // ─────────────────────────────────────────────────────────────────────
    private fun bindSystemStep() {
        val s = binding.stepSystem

        // Theme
        val theme = prefs.getString(KotaTaskApp.KEY_THEME, "system")
        s.onbRgTheme.check(when (theme) {
            "light" -> s.onbRbThemeLight.id
            "dark"  -> s.onbRbThemeDark.id
            else    -> s.onbRbThemeSystem.id
        })
        s.onbRgTheme.setOnCheckedChangeListener { _, checkedId ->
            val mode = when (checkedId) {
                s.onbRbThemeLight.id -> "light"
                s.onbRbThemeDark.id  -> "dark"
                else                 -> "system"
            }
            prefs.edit().putString(KotaTaskApp.KEY_THEME, mode).apply()
            AppCompatDelegate.setDefaultNightMode(when (mode) {
                "light" -> AppCompatDelegate.MODE_NIGHT_NO
                "dark"  -> AppCompatDelegate.MODE_NIGHT_YES
                else    -> AppCompatDelegate.MODE_NIGHT_FOLLOW_SYSTEM
            })
        }

        // Notifications
        val notifOn = prefs.getBoolean(KotaTaskApp.KEY_NOTIF_ENABLED, false)
        val hour    = prefs.getInt(KotaTaskApp.KEY_NOTIF_HOUR,   KotaTaskApp.DEFAULT_NOTIF_HOUR)
        val minute  = prefs.getInt(KotaTaskApp.KEY_NOTIF_MINUTE, KotaTaskApp.DEFAULT_NOTIF_MINUTE)

        s.onbSwitchNotif.isChecked = notifOn
        s.onbRowNotifTime.isEnabled = notifOn
        s.onbTvNotifTime.text = formatTime(hour, minute)

        s.onbSwitchNotif.setOnCheckedChangeListener { _, isChecked ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_NOTIF_ENABLED, isChecked).apply()
            s.onbRowNotifTime.isEnabled = isChecked
        }
        s.onbRowNotifTime.setOnClickListener {
            val h = prefs.getInt(KotaTaskApp.KEY_NOTIF_HOUR,   KotaTaskApp.DEFAULT_NOTIF_HOUR)
            val m = prefs.getInt(KotaTaskApp.KEY_NOTIF_MINUTE, KotaTaskApp.DEFAULT_NOTIF_MINUTE)
            TimePickerDialog(this, { _, pickedH, pickedM ->
                prefs.edit()
                    .putInt(KotaTaskApp.KEY_NOTIF_HOUR,   pickedH)
                    .putInt(KotaTaskApp.KEY_NOTIF_MINUTE, pickedM)
                    .apply()
                s.onbTvNotifTime.text = formatTime(pickedH, pickedM)
            }, h, m, true).show()
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Step 3: Features
    // ─────────────────────────────────────────────────────────────────────
    private fun bindFeaturesStep() {
        val f = binding.stepFeatures
        f.onbSwitchSplitToday.isChecked = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_SPLIT_TODAY, true)
        f.onbSwitchCalendar.isChecked   = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_CALENDAR,    true)
        f.onbSwitchProjects.isChecked   = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_PROJECTS,    true)
        f.onbSwitchLocations.isChecked  = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_LOCATIONS,   true)
        f.onbSwitchTaskTypes.isChecked  = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_TASK_TYPES,  true)
        f.onbSwitchSmartSort.isChecked  = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_SMART_SORT,  true)
        f.onbSwitchDefer.isChecked      = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_DEFER,       false)

        // Отложенное планирование неактивно без разделения Сегодня/Стек
        onbUpdateDeferRow(f, f.onbSwitchSplitToday.isChecked)

        f.onbSwitchSplitToday.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FEATURE_SPLIT_TODAY, v).apply()
            onbUpdateDeferRow(f, v)
        }
        f.onbSwitchCalendar.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FEATURE_CALENDAR, v).apply()
        }
        f.onbSwitchProjects.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FEATURE_PROJECTS, v).apply()
        }
        f.onbSwitchLocations.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FEATURE_LOCATIONS, v).apply()
        }
        f.onbSwitchTaskTypes.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FEATURE_TASK_TYPES, v).apply()
        }
        f.onbSwitchSmartSort.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FEATURE_SMART_SORT, v).apply()
        }
        f.onbSwitchDefer.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FEATURE_DEFER, v).apply()
        }
    }

    /** Включает/выключает строку «Отложенное планирование» в зависимости от Split Today. */
    private fun onbUpdateDeferRow(
        f: com.mark.app.databinding.OnbStepFeaturesBinding,
        splitEnabled: Boolean
    ) {
        f.onbSwitchDefer.isEnabled = splitEnabled
        f.onbRowDefer.alpha = if (splitEnabled) 1.0f else 0.4f
    }

    // ─────────────────────────────────────────────────────────────────────
    // Step 4: Priority coefficients
    // ─────────────────────────────────────────────────────────────────────
    private fun bindCoeffsStep() {
        val c = binding.stepCoeffs
        c.onbSeekDeadline.progress   = (prefs.getFloat("coeff_deadline",   0.45f) * 100).toInt()
        c.onbSeekImportance.progress = (prefs.getFloat("coeff_importance", 0.35f) * 100).toInt()
        c.onbSeekDuration.progress   = (prefs.getFloat("coeff_duration",   0.10f) * 100).toInt()
        c.onbSeekAge.progress        = (prefs.getFloat("coeff_age",        0.10f) * 100).toInt()
        updateCoeffLabels()

        val listener = object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(s: SeekBar?, p: Int, fromUser: Boolean) = updateCoeffLabels()
            override fun onStartTrackingTouch(s: SeekBar?) {}
            override fun onStopTrackingTouch(s: SeekBar?) = saveCoeffs()
        }
        c.onbSeekDeadline.setOnSeekBarChangeListener(listener)
        c.onbSeekImportance.setOnSeekBarChangeListener(listener)
        c.onbSeekDuration.setOnSeekBarChangeListener(listener)
        c.onbSeekAge.setOnSeekBarChangeListener(listener)

        c.onbBtnResetCoeffs.setOnClickListener {
            c.onbSeekDeadline.progress   = 45
            c.onbSeekImportance.progress = 35
            c.onbSeekDuration.progress   = 10
            c.onbSeekAge.progress        = 10
            updateCoeffLabels()
            saveCoeffs()
        }

        // ── Overload section ──────────────────────────────────────────────
        val overloadOn = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_OVERLOAD, true)
        c.onbSwitchOverload.isChecked = overloadOn
        c.onbOverloadSettings.visibility = if (overloadOn) android.view.View.VISIBLE else android.view.View.GONE

        // Seek ranges: limit = (960-120)/10 = 84 steps; boost = 0..100
        val savedLimit = prefs.getInt("overload_limit_minutes", DEFAULT_OVERLOAD_LIMIT_MINUTES)
        c.onbSeekOverloadLimit.progress =
            (savedLimit - MIN_OVERLOAD_LIMIT_MINUTES) / OVERLOAD_STEP
        c.onbSeekOverloadBoost.progress =
            (prefs.getFloat("load_duration_boost", DEFAULT_LOAD_BOOST) * 100).toInt()
        updateOverloadLabels()

        c.onbSwitchOverload.setOnCheckedChangeListener { _, enabled ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FEATURE_OVERLOAD, enabled).apply()
            c.onbOverloadSettings.visibility =
                if (enabled) android.view.View.VISIBLE else android.view.View.GONE
        }

        val overloadListener = object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(s: SeekBar?, p: Int, fromUser: Boolean) = updateOverloadLabels()
            override fun onStartTrackingTouch(s: SeekBar?) {}
            override fun onStopTrackingTouch(s: SeekBar?) = saveOverload()
        }
        c.onbSeekOverloadLimit.setOnSeekBarChangeListener(overloadListener)
        c.onbSeekOverloadBoost.setOnSeekBarChangeListener(overloadListener)

        c.onbBtnResetOverload.setOnClickListener {
            c.onbSeekOverloadLimit.progress =
                (DEFAULT_OVERLOAD_LIMIT_MINUTES - MIN_OVERLOAD_LIMIT_MINUTES) / OVERLOAD_STEP
            c.onbSeekOverloadBoost.progress = (DEFAULT_LOAD_BOOST * 100).toInt()
            updateOverloadLabels()
            saveOverload()
        }
    }

    private fun updateCoeffLabels() {
        val c = binding.stepCoeffs
        c.onbTvDeadlineVal.text   = fmt(c.onbSeekDeadline.progress)
        c.onbTvImportanceVal.text = fmt(c.onbSeekImportance.progress)
        c.onbTvDurationVal.text   = fmt(c.onbSeekDuration.progress)
        c.onbTvAgeVal.text        = fmt(c.onbSeekAge.progress)
    }

    private fun updateOverloadLabels() {
        val c = binding.stepCoeffs
        val limitMin = MIN_OVERLOAD_LIMIT_MINUTES + c.onbSeekOverloadLimit.progress * OVERLOAD_STEP
        c.onbTvOverloadLimitVal.text = "$limitMin мин"
        c.onbTvOverloadBoostVal.text = fmt(c.onbSeekOverloadBoost.progress)
    }

    private fun saveCoeffs() {
        val c = binding.stepCoeffs
        prefs.edit()
            .putFloat("coeff_deadline",   c.onbSeekDeadline.progress   / 100f)
            .putFloat("coeff_importance", c.onbSeekImportance.progress / 100f)
            .putFloat("coeff_duration",   c.onbSeekDuration.progress   / 100f)
            .putFloat("coeff_age",        c.onbSeekAge.progress        / 100f)
            .apply()
    }

    private fun saveOverload() {
        val c = binding.stepCoeffs
        val limitMin = MIN_OVERLOAD_LIMIT_MINUTES + c.onbSeekOverloadLimit.progress * OVERLOAD_STEP
        prefs.edit()
            .putInt("overload_limit_minutes", limitMin)
            .putFloat("load_duration_boost",  c.onbSeekOverloadBoost.progress / 100f)
            .apply()
    }

    private fun fmt(progress: Int): String =
        String.format(Locale.US, "%.2f", progress / 100f)

    // ─────────────────────────────────────────────────────────────────────
    // Step 5: Calendar mode
    // ─────────────────────────────────────────────────────────────────────
    private fun bindCalendarStep() {
        val c = binding.stepCalendar
        val saved = prefs.getString(KotaTaskApp.KEY_CALENDAR_MODE, "range")
        c.onbRgCalendar.check(
            if (saved == "point") c.onbRbCalPoint.id else c.onbRbCalRange.id
        )
        c.onbRgCalendar.setOnCheckedChangeListener { _, checkedId ->
            val mode = if (checkedId == c.onbRbCalPoint.id) "point" else "range"
            prefs.edit().putString(KotaTaskApp.KEY_CALENDAR_MODE, mode).apply()
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Step 6: Assistance level
    // ─────────────────────────────────────────────────────────────────────
    private fun bindAssistanceStep() {
        val a = binding.stepAssistance
        val saved = prefs.getString(
            KotaTaskApp.KEY_ASSISTANCE_LEVEL,
            KotaTaskApp.DEFAULT_ASSISTANCE_LEVEL
        )
        a.onbRgAssistance.check(when (saved) {
            KotaTaskApp.ASSISTANCE_MINIMAL  -> a.onbRbAsstMinimal.id
            KotaTaskApp.ASSISTANCE_ADVANCED -> a.onbRbAsstAdvanced.id
            KotaTaskApp.ASSISTANCE_CUSTOM   -> a.onbRbAsstCustom.id
            else                            -> a.onbRbAsstStandard.id
        })
        a.onbRgAssistance.setOnCheckedChangeListener { _, checkedId ->
            val level = when (checkedId) {
                a.onbRbAsstMinimal.id  -> KotaTaskApp.ASSISTANCE_MINIMAL
                a.onbRbAsstAdvanced.id -> KotaTaskApp.ASSISTANCE_ADVANCED
                a.onbRbAsstCustom.id   -> KotaTaskApp.ASSISTANCE_CUSTOM
                else                   -> KotaTaskApp.ASSISTANCE_STANDARD
            }
            prefs.edit().putString(KotaTaskApp.KEY_ASSISTANCE_LEVEL, level).apply()
            // Refresh Next button text — it changes between "Далее" and "Готово"
            // depending on whether the custom step is now reachable.
            goToStep(currentStep)
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // Step 7: Task fields visibility + required fields
    // ─────────────────────────────────────────────────────────────────────
    private fun bindFieldsStep() {
        val f = binding.stepFields

        // ── Visibility toggles ──
        val durVisible  = prefs.getBoolean(KotaTaskApp.KEY_FIELD_DURATION,       true)
        val purVisible  = prefs.getBoolean(KotaTaskApp.KEY_FIELD_PURPOSE,        true)
        val projVisible = prefs.getBoolean(KotaTaskApp.KEY_FIELD_PROJECT,        true)
        val locVisible  = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_LOCATIONS,    true)
        val typeVisible = prefs.getBoolean(KotaTaskApp.KEY_FEATURE_TASK_TYPES,   true)

        f.onbSwitchFieldDuration.isChecked = durVisible
        f.onbSwitchFieldPurpose.isChecked  = purVisible
        f.onbSwitchFieldProject.isChecked  = projVisible

        // ── Required checkboxes: initial state from prefs ──
        f.onbCbReqDeadlineStart.isChecked = prefs.getBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_DEADLINE_START, false)
        f.onbCbReqDeadline.isChecked      = prefs.getBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_DEADLINE,       false)
        f.onbCbReqImportance.isChecked    = prefs.getBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_IMPORTANCE,     false)
        f.onbCbReqDuration.isChecked      = prefs.getBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_DURATION,       false)
        f.onbCbReqPurpose.isChecked       = prefs.getBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_PURPOSE,        false)
        f.onbCbReqProject.isChecked       = prefs.getBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_PROJECT,        false)
        f.onbCbReqLocation.isChecked      = prefs.getBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_LOCATION,       false)
        f.onbCbReqTaskType.isChecked      = prefs.getBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_TASK_TYPE,      false)

        // ── Initial enabled state for visibility-dependent checkboxes ──
        applyReqCheckboxState(f.onbCbReqDuration,  durVisible)
        applyReqCheckboxState(f.onbCbReqPurpose,   purVisible)
        applyReqCheckboxState(f.onbCbReqProject,   projVisible)
        applyReqCheckboxState(f.onbCbReqLocation,  locVisible)
        applyReqCheckboxState(f.onbCbReqTaskType,  typeVisible)

        // ── Visibility switch listeners (also update required checkboxes) ──
        f.onbSwitchFieldDuration.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FIELD_DURATION, v).apply()
            applyReqCheckboxState(f.onbCbReqDuration, v)
        }
        f.onbSwitchFieldPurpose.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FIELD_PURPOSE, v).apply()
            applyReqCheckboxState(f.onbCbReqPurpose, v)
        }
        f.onbSwitchFieldProject.setOnCheckedChangeListener { _, v ->
            prefs.edit().putBoolean(KotaTaskApp.KEY_FIELD_PROJECT, v).apply()
            applyReqCheckboxState(f.onbCbReqProject, v)
        }

        // ── Required checkbox listeners (save immediately) ──
        f.onbCbReqDeadlineStart.setOnCheckedChangeListener { _, v -> prefs.edit().putBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_DEADLINE_START, v).apply() }
        f.onbCbReqDeadline.setOnCheckedChangeListener      { _, v -> prefs.edit().putBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_DEADLINE,       v).apply() }
        f.onbCbReqImportance.setOnCheckedChangeListener    { _, v -> prefs.edit().putBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_IMPORTANCE,     v).apply() }
        f.onbCbReqDuration.setOnCheckedChangeListener      { _, v -> prefs.edit().putBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_DURATION,       v).apply() }
        f.onbCbReqPurpose.setOnCheckedChangeListener       { _, v -> prefs.edit().putBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_PURPOSE,        v).apply() }
        f.onbCbReqProject.setOnCheckedChangeListener       { _, v -> prefs.edit().putBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_PROJECT,        v).apply() }
        f.onbCbReqLocation.setOnCheckedChangeListener      { _, v -> prefs.edit().putBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_LOCATION,       v).apply() }
        f.onbCbReqTaskType.setOnCheckedChangeListener      { _, v -> prefs.edit().putBoolean(KotaTaskApp.KEY_CUSTOM_REQUIRE_TASK_TYPE,      v).apply() }
    }

    private fun applyReqCheckboxState(checkbox: CheckBox, isEnabled: Boolean) {
        if (!isEnabled) checkbox.isChecked = false
        checkbox.isEnabled = isEnabled
        checkbox.alpha = if (isEnabled) 1.0f else 0.38f
    }

    private fun finishOnboarding() {
        saveCoeffs()
        saveOverload()
        // commit() пишет на диск синхронно и попутно сбрасывает все предыдущие
        // apply()-изменения этого экземпляра SharedPreferences. Это гарантирует,
        // что все настройки онбординга попадут в файл до того, как activity
        // завершится и Android запустит Auto Backup.
        prefs.edit().putBoolean(KotaTaskApp.KEY_ONBOARDING_DONE, true).commit()

        // Если включили напоминания — запланируем
        if (prefs.getBoolean(KotaTaskApp.KEY_NOTIF_ENABLED, false)) {
            scheduleDaily(this)
        }

        startActivity(Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        })
        finish()
    }

    private fun formatTime(hour: Int, minute: Int): String =
        String.format(Locale.US, "%02d:%02d", hour, minute)

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (currentStep > 0) goToStep(currentStep - 1)
        else super.onBackPressed()
    }

    private companion object {
        const val KEY_CURRENT_STEP = "onb_current_step"
        const val STEP_COUNT = 7
        const val STEP_COEFFS = 3
        const val STEP_FIELDS = 6
        const val OVERLOAD_STEP = 10
        const val MIN_OVERLOAD_LIMIT_MINUTES = 120
        const val DEFAULT_OVERLOAD_LIMIT_MINUTES = 180
        const val DEFAULT_LOAD_BOOST = 0.2f
    }
}
