// A native platform view, registered by the example's AppDelegate and MainActivity, so the
// native screenshot and its masking can be checked with one on screen (D331, D338).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A page with a native view in it.
class NativeViewScreen extends StatelessWidget {
  /// The page.
  const NativeViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Native view')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Below is a view drawn by the platform, not by Flutter.'),
          ),
          SizedBox(
            height: 120,
            child: Platform.isIOS
                ? const UiKitView(viewType: 'example/native', creationParamsCodec: StandardMessageCodec())
                : const AndroidView(viewType: 'example/native', creationParamsCodec: StandardMessageCodec()),
          ),
          const Padding(padding: EdgeInsets.all(16), child: Text('And this is Flutter again.')),
        ],
      ),
    );
  }
}
