import CoreMotion
import Flutter
import ObjectiveC
import UIKit

/// Viper's native side (D338). Registering does nothing else (D336): no sensor listener,
/// responder hook or observer until Dart asks for something.
public class ViperFlutterPlugin: NSObject, FlutterPlugin {
  let channel: FlutterMethodChannel

  init(channel: FlutterMethodChannel) {
    self.channel = channel
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "viper_flutter", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(ViperFlutterPlugin(channel: channel), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capture":
      let args = call.arguments as? [String: Any] ?? [:]
      DispatchQueue.main.async { result(Screenshot.take(args)) }
    case "timezone":
      result(TimeZone.current.identifier)
    case "startShake":
      Shake.start { [weak self] in self?.channel.invokeMethod("shake", arguments: nil) }
      result(true)
    case "stopShake":
      Shake.stop()
      result(nil)
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

  /// The FlutterViewController's view, wherever it sits in the window.
  static func flutterView(in window: UIWindow) -> UIView? {
    var queue: [UIViewController] = window.rootViewController.map { [$0] } ?? []
    while !queue.isEmpty {
      let controller = queue.removeFirst()
      if controller is FlutterViewController { return controller.view }
      queue.append(contentsOf: controller.children)
      if let presented = controller.presentedViewController { queue.append(presented) }
    }
    return nil
  }

  static func take(_ args: [String: Any]) -> Any {
    guard let window = keyWindow() else {
      return FlutterError(code: "no_window", message: "No window to draw", details: nil)
    }
    // Masking guards privacy, so a box list that doesn't read is an error, never "no masks".
    guard let raw = args["boxes"] as? [Any] else {
      return FlutterError(code: "bad_boxes", message: "The mask boxes didn't read", details: nil)
    }
    var boxes: [[Double]] = []
    for item in raw {
      guard let box = item as? [NSNumber], box.count == 4 else {
        return FlutterError(code: "bad_boxes", message: "A mask box didn't read", details: nil)
      }
      boxes.append(box.map { $0.doubleValue })
    }
    // Dart measures boxes in the FlutterView; the picture is the window. They're the same in an
    // app Flutter fills, and the offset covers one that embeds Flutter in a part of the window.
    let flutterOrigin = flutterView(in: window)?.convert(CGPoint.zero, to: window) ?? .zero
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
      for box in boxes {
        let rect = CGRect(x: box[0] + flutterOrigin.x, y: box[1] + flutterOrigin.y, width: box[2], height: box[3])
        UIBezierPath(roundedRect: rect, cornerRadius: 3).fill()
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

/// A shake opens Viper (D335): the accelerometer through CoreMotion on a phone, and the system's
/// shake gesture (UIWindow's motionEnded, which the simulator's Device > Shake sends). Started only
/// when Dart asks, after Viper.start and only where the project has shake on; nothing at
/// registration (D336).
enum Shake {
  static let motion = CMMotionManager()
  static var onShake: (() -> Void)?
  static var last = Date.distantPast
  static var swizzled = false

  static func start(_ handler: @escaping () -> Void) {
    onShake = handler
    if motion.isAccelerometerAvailable && !motion.isAccelerometerActive {
      motion.accelerometerUpdateInterval = 0.05
      motion.startAccelerometerUpdates(to: .main) { data, _ in
        guard let a = data?.acceleration else { return }
        // About 2.5 g: a deliberate shake, not a phone set down on a table.
        if sqrt(a.x * a.x + a.y * a.y + a.z * a.z) > 2.5 { fire() }
      }
    }
    swizzleMotionEnded()
  }

  static func stop() {
    onShake = nil
    if motion.isAccelerometerActive { motion.stopAccelerometerUpdates() }
  }

  static func fire() {
    guard let handler = onShake, Date().timeIntervalSince(last) > 1 else { return }
    last = Date()
    handler()
  }

  /// Adds Viper's motionEnded to UIWindow alone, calling on to what was there, so every other
  /// responder is untouched.
  static func swizzleMotionEnded() {
    guard !swizzled else { return }
    swizzled = true
    let original = #selector(UIResponder.motionEnded(_:with:))
    let replacement = #selector(UIWindow.viper_motionEnded(_:with:))
    guard let originalMethod = class_getInstanceMethod(UIWindow.self, original),
          let replacementMethod = class_getInstanceMethod(UIWindow.self, replacement) else { return }
    if class_addMethod(UIWindow.self, original, method_getImplementation(replacementMethod), method_getTypeEncoding(replacementMethod)) {
      class_replaceMethod(UIWindow.self, replacement, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
    } else {
      method_exchangeImplementations(originalMethod, replacementMethod)
    }
  }
}

extension UIWindow {
  @objc func viper_motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
    if motion == .motionShake { Shake.fire() }
    viper_motionEnded(motion, with: event)
  }
}
