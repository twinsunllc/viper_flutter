package dev.twinsun.viper.example

import android.content.Context
import android.graphics.Color
import android.view.View
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // The example's native platform view, so captures and masking can be checked with one on
    // screen (D331, D338).
    flutterEngine.platformViewsController.registry.registerViewFactory("example/native", ExampleNativeFactory())
  }
}

class ExampleNativeFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
  override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
    val text = TextView(context).apply {
      text = "Native Android view"
      textSize = 18f
      setTextColor(Color.WHITE)
      setBackgroundColor(Color.rgb(140, 25, 150))
      setPadding(24, 24, 24, 24)
    }
    return object : PlatformView {
      override fun getView(): View = text
      override fun dispose() {}
    }
  }
}
