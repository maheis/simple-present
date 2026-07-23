package be.heister.simplepresent

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import android.text.Layout
import android.text.StaticLayout
import android.text.TextUtils
import android.text.TextPaint
import androidx.core.content.res.ResourcesCompat

object WidgetTextRenderer {
    private const val DEFAULT_PADDING_DP = 2

    fun renderTextBitmap(
        context: Context,
        text: String,
        fontResId: Int,
        textSizeSp: Float,
        textColor: Int,
        maxWidthPx: Int,
        bold: Boolean = false,
    ): Bitmap {
        val metrics = context.resources.displayMetrics
        val paddingPx = (DEFAULT_PADDING_DP * metrics.density).toInt().coerceAtLeast(1)
        val width = maxWidthPx.coerceAtLeast(1)
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            color = textColor
            textSize = textSizeSp * metrics.scaledDensity
            typeface = loadTypeface(context, fontResId, bold)
        }

        val layout = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            StaticLayout.Builder
                .obtain(text, 0, text.length, paint, width)
                .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .setIncludePad(false)
                .setLineSpacing(0f, 1f)
                // single-line widget text with ellipsis at end
                .setMaxLines(1)
                .setEllipsize(TextUtils.TruncateAt.END)
                .build()
        } else {
            @Suppress("DEPRECATION")
            // For older APIs, pre-ellipsize the text to one line width
            val display = TextUtils.ellipsize(text, paint, width.toFloat(), TextUtils.TruncateAt.END).toString()
            StaticLayout(
                display,
                paint,
                width,
                Layout.Alignment.ALIGN_NORMAL,
                1f,
                0f,
                false
            )
        }

        val bmp = Bitmap.createBitmap(width, layout.height + paddingPx * 2, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        canvas.drawColor(Color.TRANSPARENT)
        canvas.save()
        canvas.translate(0f, paddingPx.toFloat())
        layout.draw(canvas)
        canvas.restore()
        return bmp
    }

    private fun loadTypeface(context: Context, fontResId: Int, bold: Boolean): Typeface {
        val base = try {
            ResourcesCompat.getFont(context, fontResId)
        } catch (_: Exception) {
            null
        }
        return when {
            base != null && bold -> Typeface.create(base, Typeface.BOLD)
            base != null -> base
            bold -> Typeface.DEFAULT_BOLD
            else -> Typeface.DEFAULT
        }
    }
}
