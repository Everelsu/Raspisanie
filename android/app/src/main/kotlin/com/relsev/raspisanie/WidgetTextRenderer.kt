package com.relsev.raspisanie

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Typeface
import android.os.Build
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.util.TypedValue

// RemoteViews в лаунчере не резолвит android:fontFamily="@font/..." — рабочий
// способ показать кастомный TTF в домашнем виджете один: отрисовать текст в
// Bitmap через Canvas/StaticLayout и вставить через setImageViewBitmap на
// ImageView. Здесь же выполняется перенос/эллипсис — Android больше не
// пересчитывает их сам при ресайзе виджета, поэтому вызывающая сторона обязана
// передавать актуальный maxWidthPx (см. onAppWidgetOptionsChanged в
// ScheduleWidgetProvider).
object WidgetTextRenderer {

    fun typeface(context: Context, fontKey: String?, bold: Boolean): Typeface {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        }
        return try {
            when (fontKey) {
                "grotesk" -> context.resources.getFont(
                    if (bold) R.font.space_grotesk_bold else R.font.space_grotesk_regular
                )
                "ndot" -> context.resources.getFont(R.font.ndot77)
                "nunito" -> context.resources.getFont(
                    if (bold) R.font.nunito_bold else R.font.nunito_regular
                )
                "jost" -> context.resources.getFont(
                    if (bold) R.font.jost_bold else R.font.jost_regular
                )
                "manrope" -> context.resources.getFont(
                    if (bold) R.font.manrope_bold else R.font.manrope_regular
                )
                "robotoSlab" -> context.resources.getFont(
                    if (bold) R.font.roboto_slab_bold else R.font.roboto_slab_regular
                )
                else -> if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            }
        } catch (_: Exception) {
            if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        }
    }

    /// Рендерит [text] в Bitmap заданным шрифтом/цветом/размером. Bitmap
    /// обрезается по фактически использованной ширине (а не всегда maxWidthPx),
    /// чтобы ImageView с layout_width="wrap_content"/"0dp"+weight вело себя как
    /// обычный левовыровненный TextView.
    fun render(
        context: Context,
        text: String,
        typeface: Typeface,
        textSizeSp: Float,
        color: Int,
        maxWidthPx: Int,
        maxLines: Int = 1,
        fontScale: Float = 1f,
    ): Bitmap {
        val safeText = text.ifEmpty { " " }
        val safeWidth = maxWidthPx.coerceAtLeast(1)
        val paint = TextPaint(TextPaint.ANTI_ALIAS_FLAG).apply {
            this.typeface = typeface
            this.color = color
            textSize = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_SP,
                textSizeSp * fontScale,
                context.resources.displayMetrics,
            )
        }

        val layout = buildStaticLayout(safeText, paint, safeWidth, maxLines)

        var contentWidth = 0
        for (line in 0 until layout.lineCount) {
            contentWidth = maxOf(contentWidth, layout.getLineWidth(line).toInt())
        }
        contentWidth = contentWidth.coerceIn(1, safeWidth)
        val contentHeight = layout.height.coerceAtLeast(1)

        val bitmap = Bitmap.createBitmap(contentWidth, contentHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        layout.draw(canvas)
        return bitmap
    }

    private fun buildStaticLayout(
        text: String,
        paint: TextPaint,
        widthPx: Int,
        maxLines: Int,
    ): StaticLayout {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return StaticLayout.Builder
                .obtain(text, 0, text.length, paint, widthPx)
                .setMaxLines(maxLines)
                .setEllipsize(TextUtils.TruncateAt.END)
                .setIncludePad(false)
                .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .build()
        }
        @Suppress("DEPRECATION")
        return StaticLayout(
            text, paint, widthPx,
            Layout.Alignment.ALIGN_NORMAL, 1f, 0f, false,
        )
    }
}
