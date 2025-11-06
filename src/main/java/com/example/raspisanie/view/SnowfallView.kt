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
        val count = (width * height / 15000).coerceIn(30, 60) // Adaptive count based on size
        
        val density = resources.displayMetrics.density
        
        repeat(count) {
            snowflakes.add(
                Snowflake(
                    x = Random.nextFloat() * width,
                    y = Random.nextFloat() * height,
                    size = (Random.nextFloat() * 3 + 1) * density, // 1-4 dp converted to pixels
                    speed = (Random.nextFloat() * 2 + 1) * density, // 1-3 dp per frame
                    opacity = Random.nextFloat() * 0.4f + 0.6f // 0.6-1.0 for better visibility
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
            
            // Add slight horizontal drift (wind effect)
            flake.x += (Math.sin(flake.y * 0.01) * 0.5).toFloat()
            
            // Reset if off screen
            if (flake.y > height) {
                flake.y = -flake.size
                flake.x = Random.nextFloat() * width
            }
            
            // Wrap around horizontally
            if (flake.x < 0) flake.x = width
            if (flake.x > width) flake.x = 0f
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
        if (width > 0 && height > 0) {
            startAnimation()
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
            startAnimation()
        }
    }

    private data class Snowflake(
        var x: Float,
        var y: Float,
        val size: Float,
        val speed: Float,
        val opacity: Float
    )
}

