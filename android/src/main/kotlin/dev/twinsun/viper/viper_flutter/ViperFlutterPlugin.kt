package dev.twinsun.viper.viper_flutter

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import io.flutter.embedding.android.FlutterImageView
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.TimeZone

/**
 * Viper's native side (D338). Registering does nothing else (D336): no sensor listener or
 * observer until Dart asks for something.
 */
class ViperFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
  private var channel: MethodChannel? = null
  private var activity: Activity? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "viper_flutter").also { it.setMethodCallHandler(this) }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel?.setMethodCallHandler(null)
    channel = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "capture" -> {
        val current = activity
        if (current == null) {
          result.error("no_window", "No activity to copy", null)
          return
        }
        Screenshot(current, call, result).take()
      }
      "timezone" -> result.success(TimeZone.getDefault().id)
      else -> result.notImplemented()
    }
  }
}

/**
 * The screenshot (D338, amended by the spike): the FlutterSurfaceView copied first; the window
 * when the surface has no data or Flutter is drawing through a FlutterImageView (a hybrid
 * composition view is on screen). Views are found by type, never by class name, since release
 * builds rename classes. A window with FLAG_SECURE gets no picture at all: the flag is read and
 * honored, not left to the copy failing (it doesn't). The picture is the FlutterView's area, and
 * the mask boxes are filled before the PNG is encoded (D331).
 */
private class Screenshot(private val activity: Activity, call: MethodCall, private val result: MethodChannel.Result) {
  private val boxes: List<List<Double>> = (call.argument<List<List<Number>>>("boxes") ?: emptyList()).map { box -> box.map { it.toDouble() } }
  private val thumbWidth: Double = call.argument<Number>("thumb_width")?.toDouble() ?: 360.0
  private val main = Handler(Looper.getMainLooper())
  private val started = SystemClock.elapsedRealtime()

  fun take() {
    val window = activity.window
    if (window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0) {
      result.success(mapOf("blocked" to "secure_window"))
      return
    }
    val views = mutableListOf<View>()
    collect(window.decorView, views)
    val flutter = views.firstOrNull { it is FlutterView }
    if (flutter == null || flutter.width == 0 || flutter.height == 0) {
      result.error("no_flutter_view", "No FlutterView on screen", null)
      return
    }
    val surface = views.firstOrNull { it is FlutterSurfaceView } as SurfaceView?
    val drawingThroughImage = views.any { it is FlutterImageView && it.visibility == View.VISIBLE }
    if (surface != null && !drawingThroughImage && surface.width > 0 && surface.height > 0) {
      val bitmap = Bitmap.createBitmap(surface.width, surface.height, Bitmap.Config.ARGB_8888)
      PixelCopy.request(surface, bitmap, { code ->
        if (code == PixelCopy.SUCCESS) finish(bitmap, "surface") else copyWindow(flutter)
      }, main)
    } else {
      copyWindow(flutter)
    }
  }

  private fun copyWindow(flutter: View) {
    val location = IntArray(2)
    flutter.getLocationInWindow(location)
    val area = Rect(location[0], location[1], location[0] + flutter.width, location[1] + flutter.height)
    val bitmap = Bitmap.createBitmap(area.width(), area.height(), Bitmap.Config.ARGB_8888)
    PixelCopy.request(activity.window, area, bitmap, { code ->
      if (code == PixelCopy.SUCCESS) finish(bitmap, "window") else result.error("copy_failed", "PixelCopy answered $code", null)
    }, main)
  }

  private fun collect(view: View, out: MutableList<View>) {
    out.add(view)
    if (view is ViewGroup) for (i in 0 until view.childCount) collect(view.getChildAt(i), out)
  }

  private fun finish(bitmap: Bitmap, copied: String) {
    val drawMs = SystemClock.elapsedRealtime() - started
    val density = activity.resources.displayMetrics.density.toDouble()
    // Encoding takes tens of milliseconds: off the main thread.
    val worker = HandlerThread("viper-screenshot").apply { start() }
    Handler(worker.looper).post {
      try {
        val canvas = Canvas(bitmap)
        val paint = Paint().apply { color = 0xFFD2D5DA.toInt(); isAntiAlias = true }
        val radius = (3 * density).toFloat()
        for (box in boxes) {
          if (box.size != 4) continue
          val rect = RectF((box[0] * density).toFloat(), (box[1] * density).toFloat(), ((box[0] + box[2]) * density).toFloat(), ((box[1] + box[3]) * density).toFloat())
          canvas.drawRoundRect(rect, radius, radius, paint)
        }
        val encodeStarted = SystemClock.elapsedRealtime()
        val png = ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        val encodeMs = SystemClock.elapsedRealtime() - encodeStarted
        val thumbW = minOf(bitmap.width, (thumbWidth * 2).toInt())
        val thumbH = (bitmap.height.toLong() * thumbW / bitmap.width).toInt()
        val thumb = ByteArrayOutputStream().also { Bitmap.createScaledBitmap(bitmap, thumbW, thumbH, true).compress(Bitmap.CompressFormat.JPEG, 70, it) }.toByteArray()
        val answer = mapOf(
          "png" to png, "thumb" to thumb, "width" to bitmap.width, "height" to bitmap.height,
          "draw_ms" to drawMs, "encode_ms" to encodeMs, "copied" to copied,
        )
        main.post { result.success(answer) }
      } catch (error: Throwable) {
        main.post { result.error("encode_failed", error.message, null) }
      } finally {
        worker.quitSafely()
      }
    }
  }
}
