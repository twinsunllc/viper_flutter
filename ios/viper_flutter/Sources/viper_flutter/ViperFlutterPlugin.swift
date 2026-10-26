import Flutter
import UIKit

/// Viper's native side (D338). Registering does nothing else (D336): no sensor listener,
/// responder hook or observer until Dart asks for something.
public class ViperFlutterPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "viper_flutter", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(ViperFlutterPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capture":
      let args = call.arguments as? [String: Any] ?? [:]
      DispatchQueue.main.async { result(Screenshot.take(args)) }
    case "timezone":
      result(TimeZone.current.identifier)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// The screenshot (D338): the key window drawn with drawViewHierarchyInRect, so native views and
/// Liquid Glass come out as they look. afterScreenUpdates false first (it reuses what's on
/// screen, about 7 ms in the spike), true when that draws nothing. Dart has hidden Viper's own
/// UI for the frame. The mask boxes are filled before the PNG is encoded, so nothing private
/// leaves the phone (D331).
enum Screenshot {
  static let fill = UIColor(red: 0xD2 / 255.0, green: 0xD5 / 255.0, blue: 0xDA / 255.0, alpha: 1)

  static func keyWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first
  }

  static func take(_ args: [String: Any]) -> Any {
    guard let window = keyWindow() else {
      return FlutterError(code: "no_window", message: "No window to draw", details: nil)
    }
    let boxes = (args["boxes"] as? [[Double]]) ?? []
    let thumbWidth = (args["thumb_width"] as? Double) ?? 360
    let format = UIGraphicsImageRendererFormat()
    format.scale = window.screen.scale
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
    let started = CFAbsoluteTimeGetCurrent()
    var afterUpdates = false
    var drew = false
    var image = renderer.image { _ in drew = window.drawHierarchy(in: window.bounds, afterScreenUpdates: false) }
    if !drew {
      afterUpdates = true
      image = renderer.image { _ in drew = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
    }
    if !drew {
      return FlutterError(code: "draw_failed", message: "drawViewHierarchyInRect drew nothing", details: nil)
    }
    let drawMs = (CFAbsoluteTimeGetCurrent() - started) * 1000
    let masked = renderer.image { ctx in
      image.draw(at: .zero)
      fill.setFill()
      for box in boxes where box.count == 4 {
        UIBezierPath(roundedRect: CGRect(x: box[0], y: box[1], width: box[2], height: box[3]), cornerRadius: 3).fill()
      }
      _ = ctx
    }
    let encodeStarted = CFAbsoluteTimeGetCurrent()
    guard let png = masked.pngData() else {
      return FlutterError(code: "encode_failed", message: "The PNG couldn't be encoded", details: nil)
    }
    let encodeMs = (CFAbsoluteTimeGetCurrent() - encodeStarted) * 1000
    // The composer's thumbnail (flutter.md: only a thumbnail crosses the bridge).
    let ratio = min(1, thumbWidth / window.bounds.width)
    let thumbSize = CGSize(width: window.bounds.width * ratio, height: window.bounds.height * ratio)
    let thumbFormat = UIGraphicsImageRendererFormat()
    thumbFormat.scale = 2
    let thumb = UIGraphicsImageRenderer(size: thumbSize, format: thumbFormat).image { _ in
      masked.draw(in: CGRect(origin: .zero, size: thumbSize))
    }.jpegData(compressionQuality: 0.7)
    return [
      "png": FlutterStandardTypedData(bytes: png),
      "thumb": FlutterStandardTypedData(bytes: thumb ?? Data()),
      "width": Int(masked.size.width * masked.scale),
      "height": Int(masked.size.height * masked.scale),
      "draw_ms": Int(drawMs),
      "encode_ms": Int(encodeMs),
      "after_screen_updates": afterUpdates,
    ]
  }
}
