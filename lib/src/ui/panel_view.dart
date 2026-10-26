// The panel in a web view (D328): the panel that ships, loaded top level from Viper's base URL in
// bridge mode, talking to Dart through the `ViperBridge` channel. The web view loads only Viper:
// every other URL goes to the system browser.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:viper_flutter/src/core/camera.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// The JavaScript channel the panel posts its messages through (flutter.md, the bridge).
const String bridgeChannel = 'ViperBridge';

/// The web view the panel lives in, made once and kept for the life of the app (the spike: a
/// second web view still took 0.85 s on the iOS simulator).
abstract interface class PanelView {
  /// Starts loading [url].
  Future<void> load(Uri url);

  /// Runs [javascript] in the panel.
  Future<void> run(String javascript);

  /// Loads the panel again, after a failed load.
  Future<void> reload();

  /// The widget that shows it.
  Widget build(BuildContext context);
}

/// Makes the [PanelView].
typedef PanelViewFactory =
    PanelView Function({
      required Uri base,
      required void Function(String message) onMessage,
      required void Function(Uri url) onExternal,
      required void Function(String description) onLoadError,
      required Color background,
    });

/// Whether a navigation may happen inside the web view: Viper's own pages, and frames that hold
/// no page of their own.
bool panelMayNavigate(Uri url, Uri base, {required bool mainFrame}) {
  if (url.scheme == base.scheme && url.host == base.host && url.port == base.port) return true;
  if (!mainFrame && const {'about', 'blob', 'data'}.contains(url.scheme)) return true;
  return url.toString() == 'about:blank';
}

/// [PanelView] over webview_flutter.
class WebPanelView implements PanelView {
  /// A web view for the panel on [base].
  WebPanelView({
    required this.base,
    required void Function(String message) onMessage,
    required void Function(Uri url) onExternal,
    required void Function(String description) onLoadError,
    required Color background,
  }) {
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(allowsInlineMediaPlayback: true)
        : const PlatformWebViewControllerCreationParams();
    _controller = WebViewController.fromPlatformCreationParams(params);
    unawaited(_controller.setJavaScriptMode(JavaScriptMode.unrestricted));
    unawaited(_controller.setBackgroundColor(background));
    unawaited(
      _controller.addJavaScriptChannel(bridgeChannel, onMessageReceived: (message) => onMessage(message.message)),
    );
    unawaited(
      _controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = Uri.tryParse(request.url);
            if (url != null && panelMayNavigate(url, base, mainFrame: request.isMainFrame)) {
              return NavigationDecision.navigate;
            }
            // Links leave for the system browser; nothing else loads in Viper's web view.
            if (url != null && request.isMainFrame && const {'http', 'https', 'mailto'}.contains(url.scheme)) {
              onExternal(url);
            }
            return NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? false) onLoadError(error.description);
          },
        ),
      ),
    );
    final platform = _controller.platform;
    if (platform is WebKitWebViewController) unawaited(platform.setInspectable(kDebugMode));
    if (platform is AndroidWebViewController) {
      unawaited(AndroidWebViewController.enableDebugging(kDebugMode));
      // The panel's file inputs (D235): Android's web view shows no picker on its own.
      unawaited(
        platform.setOnShowFileSelector(
          (params) => const ChannelNative().pickFiles(
            params.acceptTypes,
            multiple: params.mode == FileSelectorMode.openMultiple,
          ),
        ),
      );
    }
  }

  /// Viper's base URL.
  final Uri base;

  late final WebViewController _controller;

  /// The controller, for the platform-specific setup later slices add.
  WebViewController get controller => _controller;

  @override
  Future<void> load(Uri url) => _controller.loadRequest(url);

  @override
  Future<void> run(String javascript) => _controller.runJavaScript(javascript);

  @override
  Future<void> reload() => _controller.reload();

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

/// Makes a [WebPanelView]; the default [PanelViewFactory].
PanelView webPanelView({
  required Uri base,
  required void Function(String message) onMessage,
  required void Function(Uri url) onExternal,
  required void Function(String description) onLoadError,
  required Color background,
}) => WebPanelView(
  base: base,
  onMessage: onMessage,
  onExternal: onExternal,
  onLoadError: onLoadError,
  background: background,
);
