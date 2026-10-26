package dev.twinsun.viper.viper_flutter

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Viper's native side (D338): the screenshot and shake come in later slices. Registering does
 * nothing else (D336): no sensor listener or observer until Viper.start asks.
 */
class ViperFlutterPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private var channel: MethodChannel? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "viper_flutter").also { it.setMethodCallHandler(this) }
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    result.notImplemented()
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel?.setMethodCallHandler(null)
    channel = null
  }
}
