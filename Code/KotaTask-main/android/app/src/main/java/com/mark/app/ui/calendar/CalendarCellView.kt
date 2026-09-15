package com.mark.app.ui.calendar

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.util.AttributeSet
import android.view.View
import androidx.core.content.ContextCompat
import com.mark.app.R
import com.mark.app.data.Task

data class CalendarCell(
    val dayOfMonth: Int,
    val dateStr: String,
    val isCurrentMonth: Boolean,
    val isToday: Boolean,
    val tasks: List<Task>
)

/**
 * Calendar cell: radial task indicator (polar area chart).
 *
 * Visual design:
 *   - Each task occupies ONE sector with EQUAL angle: sectorAngle = 360 / taskCount
 *   - Angle never encodes any task attribute — all sectors are the same width
 *   - Radius encodes duration on a fixed global scale (MIN_RADIUS_RATIO → MAX_RADIUS_RATIO)
 *   - Dark stroke (#111111, strokeJoin=ROUND) on every sector gives clear visual separation
 *   - No ghost/shadow sectors
 *
 * Scale — ABSOLUTE, exponential saturation (independent of other tasks):
 *   visualProgress = 1 - exp(-duration / SCALE)
 *   radiusRatio    = MIN_RADIUS_RATIO + visualProgress * (MAX - MIN)
 *
 * Properties of this curve:
 *   - Steepest near zero: every minute of a short task adds more visible radius
 *     than every minute of a long one. Short tasks never disappear.
 *   - Asymptotically bounded: as duration → ∞, ratio → MAX_RADIUS_RATIO,
 *     so duration can be ANY positive integer without breaking the indicator.
 *   - Independent per task: a 4-hour task on the same day no longer shrinks
 *     a 15-min sibling. Each task has its own absolute radius.
 *
 * Approximate values at MIN=0.52, MAX=1.0, SCALE=60:
 *      0 min → 52 %         60 min → 82 %
 *     15 min → 63 %         90 min → 89 %
 *     30 min → 71 %        120 min → 94 %
 *                          240 min → ~99 %
 *                          480 min → ~100 %
 *
 * Colours (brand palette):
 *   status "Сегодня"      → #7FB5EC  Jordy Blue   (priority over importance)
 *   importance "Высокая"  → #F25757  Carnation
 *   importance "Средняя"  → #FDFF73  Paris Daisy
 *   importance "Низкая"   → #85EF82  Sulu
 *
 * Sort: today → high → medium → low → created asc (stable, no visual jumping).
 * cell.tasks already excludes Архив — filtered by CalendarFragment.groupTasksByDate().
 */
class CalendarCellView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null
) : View(context, attrs) {

    // ── Brand colours ──────────────────────────────────────────
    private val colorToday  = Color.parseColor("#7FB5EC")
    private val colorHigh   = Color.parseColor("#F25757")
    private val colorMedium = Color.parseColor("#FDFF73")
    private val colorLow    = Color.parseColor("#85EF82")
    /** Отложенная задача в день откладывания. */
    private val colorDefer  = Color.parseColor("#8842B3")

    // ── Paints ────────────────────────────────────────────────
    /** Filled sector at actual task radius */
    private val paintFill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    /** Dark outline on every sector — provides visual separation without gaps */
    private val paintStroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style     = Paint.Style.STROKE
        color     = Color.parseColor("#111111")
        strokeJoin = Paint.Join.ROUND
        // strokeWidth is set dynamically in onDraw based on view size
    }

    /** White center hub — sits on top of all sectors, below day number */
    private val paintHub = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
        color = Color.WHITE
    }

    private val paintNumber = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        typeface  = Typeface.DEFAULT_BOLD
    }

    private val paintRing = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
    }

    private val paintBg = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.FILL
    }

    // Reuse Path / RectF to avoid allocations in onDraw
    private val path     = Path()
    private val fillOval = RectF()

    // ── Duration → radius scale (absolute, exponential saturation) ──
    /** Floor for any task ≥ 0 min — short tasks must stay clearly visible.
     *  Bump to 0.55 if 0-min/short tasks still feel too small. */
    private val MIN_RADIUS_RATIO = 0.52f
    /** Asymptotic ceiling — no task can ever exceed this radius, however long */
    private val MAX_RADIUS_RATIO = 1.0f
    /** Saturation rate (minutes). At d=SCALE the curve is at ~63 % of its range.
     *  Lower SCALE → faster saturation → bigger gap between 15 and 60 min.
     *  Try 50 if the 15-vs-60 difference still feels too small. */
    private val SCALE = 60f

    /** Hub circle size = 13 % of maxRadius — provides white backdrop for day number */
    private val HUB_RATIO = 0.13f

    // ── Public state ──────────────────────────────────────────
    var cell: CalendarCell? = null
        set(value) { field = value; invalidate() }

    var isDateSelected: Boolean = false
        set(value) { field = value; invalidate() }

    // ── Measure: square cell ──────────────────────────────────
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        setMeasuredDimension(w, w)
    }

    // ── Draw ─────────────────────────────────────────────────
    override fun onDraw(canvas: Canvas) {
        val c = cell ?: return
        val w  = width.toFloat()
        val cx = w / 2f
        val cy = w / 2f

        val maxRadius = w * 0.42f
        val numSize   = w * 0.28f

        // Stroke width scales with cell size (≈1.5 dp at typical grid density)
        paintStroke.strokeWidth = w * 0.025f

        val tasks = sortTasks(c.tasks)

        // 1 ── Selected-date highlight (behind everything)
        if (isDateSelected) {
            paintBg.color = ContextCompat.getColor(context, R.color.primary)
            paintBg.alpha = 30
            canvas.drawCircle(cx, cy, maxRadius + 5f, paintBg)
            paintBg.alpha = 255
        }

        // 2 ── Radial sectors or empty-ring placeholder
        if (tasks.isNotEmpty()) {
            drawSectors(canvas, tasks, cx, cy, maxRadius, c.dateStr)
        } else if (c.isCurrentMonth) {
            paintRing.color = ContextCompat.getColor(context, R.color.border_default)
            paintRing.strokeWidth = 2.5f
            paintRing.alpha = 80
            canvas.drawCircle(cx, cy, maxRadius * 0.68f, paintRing)
            paintRing.alpha = 255
        }

        // 3 ── Today: accent ring just outside the indicator
        if (c.isToday) {
            paintRing.color = ContextCompat.getColor(context, R.color.primary)
            paintRing.strokeWidth = 2.5f
            paintRing.alpha = 255
            canvas.drawCircle(cx, cy, maxRadius + 4f, paintRing)
        }

        // 4 ── Day number — always on top
        paintNumber.textSize = numSize
        when {
            !c.isCurrentMonth -> {
                paintNumber.color = ContextCompat.getColor(context, R.color.text_hint)
                paintNumber.clearShadowLayer()
            }
            tasks.isNotEmpty() -> {
                paintNumber.color = Color.WHITE
                paintNumber.setShadowLayer(6f, 0f, 2f, Color.argb(220, 10, 10, 10))
            }
            c.isToday -> {
                paintNumber.color = ContextCompat.getColor(context, R.color.primary)
                paintNumber.clearShadowLayer()
            }
            else -> {
                paintNumber.color = ContextCompat.getColor(context, R.color.text_primary)
                paintNumber.clearShadowLayer()
            }
        }
        val textY = cy - (paintNumber.descent() + paintNumber.ascent()) / 2f
        canvas.drawText(c.dayOfMonth.toString(), cx, textY, paintNumber)
    }

    // ─────────────────────────────────────────────────────────
    // Sector rendering — two-pass: fills first, strokes on top
    // ─────────────────────────────────────────────────────────

    private fun drawSectors(
        canvas: Canvas,
        tasks: List<Task>,
        cx: Float,
        cy: Float,
        maxRadius: Float,
        dateStr: String
    ) {
        val n    = tasks.size
        val hubR = maxRadius * HUB_RATIO

        // ── Single task: still uses its own absolute radius (no anchor coupling) ──
        if (n == 1) {
            val r = maxRadius * radiusRatio(tasks[0].duration)
            paintFill.color = taskColor(tasks[0], dateStr)
            canvas.drawCircle(cx, cy, r, paintFill)
            canvas.drawCircle(cx, cy, r, paintStroke)

            paintHub.alpha = 210
            canvas.drawCircle(cx, cy, hubR, paintHub)
            return
        }

        // Equal angle — stroke provides visual separation, no gap needed
        val sweep = 360f / n
        var angle = -90f   // start at 12 o'clock

        // ── Pass 1: fill each sector at its actual radius ──
        tasks.forEach { task ->
            val r = maxRadius * radiusRatio(task.duration)
            fillOval.set(cx - r, cy - r, cx + r, cy + r)
            path.reset()
            path.moveTo(cx, cy)
            path.arcTo(fillOval, angle, sweep)
            path.close()

            paintFill.color = taskColor(task, dateStr)
            canvas.drawPath(path, paintFill)

            angle += sweep
        }

        // ── Pass 2: stroke each sector on top of all fills ──
        // (separate pass ensures no fill from a later sector paints over an earlier stroke)
        angle = -90f
        tasks.forEach { task ->
            val r = maxRadius * radiusRatio(task.duration)
            fillOval.set(cx - r, cy - r, cx + r, cy + r)
            path.reset()
            path.moveTo(cx, cy)
            path.arcTo(fillOval, angle, sweep)
            path.close()

            canvas.drawPath(path, paintStroke)

            angle += sweep
        }

        // ── Hub: white circle on top so day number stays readable ──
        paintHub.alpha = 210
        canvas.drawCircle(cx, cy, hubR, paintHub)
    }

    // ─────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────

    /**
     * Stable sort: today-status first, then importance high→medium→low,
     * then by creation timestamp ascending.
     */
    private fun sortTasks(tasks: List<Task>): List<Task> =
        tasks.sortedWith(compareBy(
            { if (it.status == "Сегодня") 0 else 1 },
            { when (it.importance) { "Высокая" -> 0; "Средняя" -> 1; else -> 2 } },
            { it.created }
        ))

    /**
     * Absolute exponential-saturation scale.
     *
     *   visualProgress = 1 - exp(-duration / SCALE)     ∈ [0, 1)
     *   radiusRatio    = MIN + visualProgress * (MAX - MIN)
     *
     * No upper bound on durationMinutes is needed — the curve self-clamps:
     * the ratio asymptotically approaches MAX_RADIUS_RATIO but never exceeds it.
     * Negative inputs collapse to MIN_RADIUS_RATIO.
     */
    private fun radiusRatio(durationMinutes: Int): Float {
        val d = durationMinutes.coerceAtLeast(0).toFloat()
        val visualProgress = 1f - Math.exp((-d / SCALE).toDouble()).toFloat()
        return MIN_RADIUS_RATIO + visualProgress * (MAX_RADIUS_RATIO - MIN_RADIUS_RATIO)
    }

    /**
     * Colour priority: отложенная задача в день откладывания → фиолетовый;
     * иначе status "Сегодня" → blue; иначе по важности.
     */
    private fun taskColor(task: Task, dateStr: String): Int = when {
        task.deferredDate.isNotBlank() && task.deferredDate == dateStr -> colorDefer
        task.status == "Сегодня"     -> colorToday
        task.importance == "Высокая" -> colorHigh
        task.importance == "Средняя" -> colorMedium
        else                         -> colorLow
    }
}
