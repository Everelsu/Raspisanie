package com.example.raspisanie.view

import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.util.AttributeSet
import android.view.View
import android.view.animation.LinearInterpolator
import androidx.core.animation.doOnEnd
import kotlin.random.Random

class SnowfallView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
    defStyleAttr: Int = 0
) : View(context, attrs, defStyleAttr) {

    private val snowflakes = mutableListOf<Snowflake>()
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0xFFFFFFFF.toInt() // White
        style = Paint.Style.FILL
    }

    private var frameCallback: android.view.Choreographer.FrameCallback? = null
    private var isAnimating = false

    init {
        // Make view transparent so it doesn't block content
        setLayerType(LAYER_TYPE_HARDWARE, null)
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        if (w > 0 && h > 0) {
            createSnowflakes(w, h)
            startAnimation()
        }
    }

    private fun createSnowflakes(width: Int, height: Int) {
        snowflakes.clear()
        // Оптимизация: уменьшено количество снежинок для экономии ресурсов
        val count = (width * height / 15000).coerceIn(30, 60) // Уменьшено с 50-100 до 30-60
        
        val density = resources.displayMetrics.density
        
        repeat(count) {
            snowflakes.add(
                Snowflake(
                    x = Random.nextFloat() * width,
                    y = Random.nextFloat() * height,
                    size = (Random.nextFloat() * 4 + 1) * density, // 1-5 dp converted to pixels
                    speed = (Random.nextFloat() * 3 + 0.5f) * density, // 0.5-3.5 dp per frame
                    opacity = Random.nextFloat() * 0.5f + 0.5f, // 0.5-1.0 for better visibility
                    drift = Random.nextFloat() * 0.3f - 0.15f // Горизонтальный дрейф
                )
            )
        }
    }

    private fun startAnimation() {
        if (isAnimating) return
        isAnimating = true

        // Use Choreographer for smooth 60fps animation
        val choreographer = android.view.Choreographer.getInstance()
        frameCallback = object : android.view.Choreographer.FrameCallback {
            override fun doFrame(frameTimeNanos: Long) {
                if (isAnimating && visibility == View.VISIBLE) {
                    updateSnowflakes()
                    invalidate()
                    choreographer.postFrameCallback(this)
                }
            }
        }
        frameCallback?.let { choreographer.postFrameCallback(it) }
    }

    private fun updateSnowflakes() {
        val width = width.toFloat()
        val height = height.toFloat()
        
        snowflakes.forEach { flake ->
            // Move snowflake down
            flake.y += flake.speed
            
            // Add realistic horizontal drift with wind effect (как в exteraGram)
            val windEffect = (Math.sin((flake.y * 0.01 + System.currentTimeMillis() * 0.0001).toDouble()) * 0.8).toFloat()
            flake.x += flake.drift + windEffect
            
            // Reset if off screen
            if (flake.y > height) {
                flake.y = -flake.size * 2
                flake.x = Random.nextFloat() * width
            }
            
            // Wrap around horizontally
            if (flake.x < -flake.size) flake.x = width + flake.size
            if (flake.x > width + flake.size) flake.x = -flake.size
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        
        if (snowflakes.isEmpty()) return
        
        snowflakes.forEach { flake ->
            paint.alpha = (flake.opacity * 255).toInt()
            canvas.drawCircle(flake.x, flake.y, flake.size, paint)
        }
    }
    
    override fun onTouchEvent(event: android.view.MotionEvent?): Boolean {
        // Don't intercept touch events - let them pass through to views below
        return false
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        // Используем post для гарантии, что размеры view известны
        post {
            if (width > 0 && height > 0 && visibility == View.VISIBLE) {
                if (snowflakes.isEmpty()) {
                    createSnowflakes(width, height)
                }
                startAnimation()
            }
        }
    }

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        isAnimating = false
        frameCallback?.let {
            android.view.Choreographer.getInstance().removeFrameCallback(it)
        }
        frameCallback = null
    }

    fun pause() {
        isAnimating = false
        frameCallback?.let {
            android.view.Choreographer.getInstance().removeFrameCallback(it)
        }
    }

    fun resume() {
        if (visibility == View.VISIBLE && !isAnimating) {
            // Убеждаемся, что снежинки созданы
            if (width > 0 && height > 0) {
                if (snowflakes.isEmpty()) {
                    createSnowflakes(width, height)
                }
                startAnimation()
            } else {
                // Если размеры еще не известны, ждем
                post {
                    if (width > 0 && height > 0) {
                        if (snowflakes.isEmpty()) {
                            createSnowflakes(width, height)
                        }
                        startAnimation()
                    }
                }
            }
        }
    }

    private data class Snowflake(
        var x: Float,
        var y: Float,
        val size: Float,
        val speed: Float,
        val opacity: Float,
        val drift: Float // Горизонтальный дрейф для каждой снежинки
    )
}

