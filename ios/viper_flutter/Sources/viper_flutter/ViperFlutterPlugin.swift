import Flutter
import UIKit

/// Viper's native side (D338): the screenshot and shake come in later slices. Registering does
/// nothing else (D336): no sensor listener, responder hook or observer until Viper.start asks.
public class ViperFlutterPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "viper_flutter", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(ViperFlutterPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result(FlutterMethodNotImplemented)
  }
}
