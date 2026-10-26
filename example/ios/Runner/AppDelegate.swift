import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The example's native platform view, so captures and masking can be checked with one on
    // screen (D331, D338).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ExampleNativeView") {
      registrar.register(ExampleNativeFactory(), withId: "example/native")
    }
  }
}

class ExampleNativeFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    ExampleNativeView(frame: frame)
  }
}

/// A UIKit view with a tab bar, like the native bars real apps put in Flutter screens.
class ExampleNativeView: NSObject, FlutterPlatformView {
  let root: UIView

  init(frame: CGRect) {
    root = UIView(frame: frame)
    super.init()
    root.backgroundColor = UIColor(red: 0.55, green: 0.1, blue: 0.6, alpha: 1)
    let label = UILabel(frame: CGRect(x: 12, y: 8, width: 300, height: 24))
    label.text = "Native UIKit view"
    label.font = .boldSystemFont(ofSize: 18)
    label.textColor = .white
    root.addSubview(label)
    let bar = UITabBar(frame: CGRect(x: 0, y: 40, width: 400, height: 70))
    bar.items = [
      UITabBarItem(title: "Today", image: UIImage(systemName: "sun.max.fill"), tag: 0),
      UITabBarItem(title: "Jobs", image: UIImage(systemName: "briefcase.fill"), tag: 1),
      UITabBarItem(title: "Network", image: UIImage(systemName: "person.2.fill"), tag: 2),
    ]
    bar.selectedItem = bar.items?.first
    bar.autoresizingMask = [.flexibleWidth]
    root.addSubview(bar)
  }

  func view() -> UIView { root }
}
