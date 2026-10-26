// Opening links outside Viper's web view: the system browser for links (flutter.md, the bridge),
// and an in-app browser view for sign-in (D334: SFSafariViewController, a Custom Tab).
import 'package:url_launcher/url_launcher.dart';

/// Opens URLs outside the panel.
abstract interface class ViperOpener {
  /// The system browser, or the app that handles the link.
  Future<void> openExternal(Uri url);

  /// The in-app browser view, for signing in (D334).
  Future<void> openAuth(Uri url);

  /// Closes the in-app browser view where the OS allows it (iOS; a Custom Tab can't be closed).
  Future<void> closeAuth();
}

/// [ViperOpener] over url_launcher.
class LauncherOpener implements ViperOpener {
  /// The opener.
  const LauncherOpener();

  @override
  Future<void> openExternal(Uri url) async {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Future<void> openAuth(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.inAppBrowserView)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Future<void> closeAuth() async {
    if (await supportsCloseForLaunchMode(LaunchMode.inAppBrowserView)) await closeInAppWebView();
  }
}
