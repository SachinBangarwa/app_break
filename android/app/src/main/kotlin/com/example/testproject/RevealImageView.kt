package com.example.testproject

import android.content.Context
import android.graphics.*
import android.util.AttributeSet
import android.view.View
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.random.Random

class RevealImageView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    // High density grid for extra-small micro-tile reveal effect (60x60 = 3600 tiny tiles)
    private val columns = 60
    private val rows = 60
    private val totalBoxes = columns * rows

    private val sequenceArray = IntArray(totalBoxes)
    private var sourceBitmap: Bitmap? = null
    private var scaledBitmap: Bitmap? = null

    private var currentProgress = 0f // 0.0 to 1.0

    // Reusable objects to eliminate GC allocations in onDraw
    private val srcRect = Rect()
    private val dstRect = RectF()
    private val clipPath = Path()
    private val containerRect = RectF()

    private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#141416") // Solid dark background without any lines or grid mesh
        style = Paint.Style.FILL
    }

    private val bitmapPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)

    init {
        // Deterministic reveal sequence with seed 42
        val shuffledList = (0 until totalBoxes).toList().shuffled(Random(42))
        for (i in 0 until totalBoxes) {
            sequenceArray[i] = shuffledList[i]
        }

        try {
            sourceBitmap = BitmapFactory.decodeResource(resources, R.drawable.reveal_image)
        } catch (e: Exception) {
            android.util.Log.e("RevealImageView", "Error loading reveal_image bitmap", e)
        }
    }

    fun setProgress(elapsedMs: Long, totalMs: Long) {
        val newProgress = if (totalMs > 0) {
            (elapsedMs.toFloat() / totalMs.toFloat()).coerceIn(0f, 1f)
        } else {
            0f
        }
        if (newProgress != currentProgress) {
            currentProgress = newProgress
            invalidate()
        }
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w > 0 && h > 0 && sourceBitmap != null) {
            scaledBitmap = Bitmap.createScaledBitmap(sourceBitmap!!, w, h, true)
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0 || h <= 0) return

        val cornerRadius = 16f * resources.displayMetrics.density

        // Round container clip path
        containerRect.set(0f, 0f, w, h)
        clipPath.reset()
        clipPath.addRoundRect(containerRect, cornerRadius, cornerRadius, Path.Direction.CW)

        canvas.save()
        canvas.clipPath(clipPath)

        // 1. Draw 100% solid flat dark background (ZERO grid lines, ZERO table mesh)
        canvas.drawRect(containerRect, bgPaint)

        val bmp = scaledBitmap
        if (bmp != null && !bmp.isRecycled) {
            val bmpW = bmp.width.toFloat()
            val bmpH = bmp.height.toFloat()

            val srcBoxW = bmpW / columns
            val srcBoxH = bmpH / rows

            val dstBoxW = w / columns
            val dstBoxH = h / rows

            val revealedCount = (currentProgress * totalBoxes).toInt().coerceIn(0, totalBoxes)

            // 2. Draw ONLY revealed image micro-tiles on top of solid background
            for (i in 0 until revealedCount) {
                val boxIndex = sequenceArray[i]
                val r = boxIndex / columns
                val c = boxIndex % columns

                val leftSrc = (c * srcBoxW).toInt()
                val topSrc = (r * srcBoxH).toInt()
                val rightSrc = ceil((c + 1) * srcBoxW).toInt()
                val bottomSrc = ceil((r + 1) * srcBoxH).toInt()

                srcRect.set(leftSrc, topSrc, rightSrc, bottomSrc)

                val leftDst = floor(c * dstBoxW)
                val topDst = floor(r * dstBoxH)
                val rightDst = ceil((c + 1) * dstBoxW)
                val bottomDst = ceil((r + 1) * dstBoxH)

                dstRect.set(leftDst, topDst, rightDst, bottomDst)

                canvas.drawBitmap(bmp, srcRect, dstRect, bitmapPaint)
            }
        }

        canvas.restore()
    }
}
