// An embedded web view, which every privacy level masks (D331): its passwords can't be found.
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A page with a web view in it.
class WebPageScreen extends StatefulWidget {
  /// The page.
  const WebPageScreen({super.key});

  @override
  State<WebPageScreen> createState() => _WebPageScreenState();
}

class _WebPageScreenState extends State<WebPageScreen> {
  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.disabled)
    ..loadHtmlString(_page);

  static const _page = '''
<!doctype html><meta name="viewport" content="width=device-width">
<body style="font: 16px system-ui; padding: 16px; background: #fdf6e3">
<h2>Call sheet</h2><p>Report at 6:00 a.m. to the Kakaako warehouse.</p>
<label>Portal password <input type="password" value="hunter2"></label>
</body>''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Web page')),
      body: WebViewWidget(controller: _web),
    );
  }
}
