package dev.twinsun.viper.viper_flutter

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.webkit.MimeTypeMap
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
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
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream
import java.util.TimeZone

/**
 * Viper's native side (D338). Registering does nothing else (D336): no sensor listener or
 * observer until Dart asks for something.
 */
class ViperFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware, PluginRegistry.ActivityResultListener {
  private var channel: MethodChannel? = null
  private var activity: Activity? = null
  private var context: Context? = null
  private var shake: Shake? = null
  private var binding: ActivityPluginBinding? = null
  private var picking: MethodChannel.Result? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, "viper_flutter").also { it.setMethodCallHandler(this) }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    shake?.stop()
    shake = null
    channel?.setMethodCallHandler(null)
    channel = null
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    attach(binding)
  }

  override fun onDetachedFromActivityForConfigChanges() {
    detach()
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    attach(binding)
  }

  override fun onDetachedFromActivity() {
    // The activity is gone for good: a picker it opened will never answer, so answer it empty and
    // let the next pick open one.
    picking?.success(emptyList<String>())
    picking = null
    detach()
  }

  private fun attach(binding: ActivityPluginBinding) {
    activity = binding.activity
    this.binding = binding
    binding.addActivityResultListener(this)
  }

  private fun detach() {
    binding?.removeActivityResultListener(this)
    binding = null
    activity = null
  }

  /** The system file picker for the panel's file inputs (D235), answered with content URIs. */
  private fun pickFiles(call: MethodCall, result: MethodChannel.Result) {
    val current = activity
    if (current == null || picking != null) {
      result.success(emptyList<String>())
      return
    }
    val accept = (call.argument<List<String>>("accept") ?: emptyList()).flatMap { it.split(",") }.map { it.trim() }.filter { it.isNotEmpty() }
    val types = accept.map { if (it.startsWith(".")) MimeTypeMap.getSingleton().getMimeTypeFromExtension(it.drop(1)) ?: "*/*" else it }.distinct()
    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
      addCategory(Intent.CATEGORY_OPENABLE)
      type = "*/*"
      if (types.isNotEmpty() && "*/*" !in types) putExtra(Intent.EXTRA_MIME_TYPES, types.toTypedArray())
      putExtra(Intent.EXTRA_ALLOW_MULTIPLE, call.argument<Boolean>("multiple") == true)
    }
    picking = result
    current.startActivityForResult(intent, PICK_FILES)
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (requestCode != PICK_FILES) return false
    val result = picking ?: return true
    picking = null
    val uris = mutableListOf<String>()
    if (resultCode == Activity.RESULT_OK && data != null) {
      val clip = data.clipData
      if (clip != null) {
        for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri.toString())
      } else {
        data.data?.let { uris.add(it.toString()) }
      }
    }
    result.success(uris)
    return true
  }

  companion object {
    private const val PICK_FILES = 0x5649
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "capture" -> {
        val current = activity
        if (current == null) {
          result.error("no_window", "No activity to copy", null)
          return
        }
        // Masking guards privacy, so a box list that doesn't read is an error, never "no masks".
        val boxes = readBoxes(call.argument<Any>("boxes"))
        if (boxes == null) {
          result.error("bad_boxes", "The mask boxes didn't read", null)
          return
        }
        Screenshot(current, boxes, call, result).take()
      }
      "timezone" -> result.success(TimeZone.getDefault().id)
      "startShake" -> {
        val sensors = context?.getSystemService(Context.SENSOR_SERVICE) as SensorManager?
        if (sensors == null) {
          result.success(false)
          return
        }
        if (shake == null) shake = Shake(sensors) { channel?.invokeMethod("shake", null) }
        result.success(shake!!.start())
      }
      "pickFiles" -> pickFiles(call, result)
      "stopShake" -> {
        shake?.stop()
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  private fun readBoxes(raw: Any?): List<List<Double>>? {
    if (raw !is List<*>) return null
    return raw.map { box ->
      if (box !is List<*> || box.size != 4 || box.any { it !is Number }) return null
      box.map { (it as Number).toDouble() }
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
private class Screenshot(
  private val activity: Activity,
  private val boxes: List<List<Double>>,
  call: MethodCall,
  private val result: MethodChannel.Result,
) {
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

/**
 * A shake opens Viper (D335): the accelerometer through SensorManager, about 2.5 g at most once a
 * second. Listening starts only when Dart asks, after Viper.start and only where the project has
 * shake on; nothing at registration (D336).
 */
private class Shake(private val sensors: SensorManager, private val onShake: () -> Unit) : SensorEventListener {
  private var last = 0L
  private var listening = false

  fun start(): Boolean {
    if (listening) return true
    val accelerometer = sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return false
    listening = sensors.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_UI)
    return listening
  }

  fun stop() {
    if (listening) sensors.unregisterListener(this)
    listening = false
  }

  override fun onSensorChanged(event: SensorEvent) {
    val (x, y, z) = Triple(event.values[0], event.values[1], event.values[2])
    val g = Math.sqrt((x * x + y * y + z * z).toDouble()) / SensorManager.GRAVITY_EARTH
    val now = SystemClock.elapsedRealtime()
    if (g > 2.5 && now - last > 1000) {
      last = now
      onShake()
    }
  }

  override fun onAccuracyChanged(sensor: Sensor, accuracy: Int) {}
}
