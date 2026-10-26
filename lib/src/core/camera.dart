// The phone's screenshot (D330, D338): the native picture first, so platform views appear;
// Flutter's own toImage when the native call fails, with platform views blocked and the capture
// saying so; none at all on a FLAG_SECURE window. Masked before it leaves the phone (D331).
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:viper_flutter/src/core/environment.dart';

/// A picture, ready to upload.
class Shot {
  /// The picture.
  const Shot({required this.png, required this.thumb, required this.thumbType, required this.info, required this.ms});

  /// No picture, and why.
  const Shot.none(this.info) : png = null, thumb = null, thumbType = 'image/png', ms = 0;

  /// The masked PNG at the phone's resolution, or null when none was taken.
  final Uint8List? png;

  /// The composer's thumbnail.
  final Uint8List? thumb;

  /// The thumbnail's type.
  final String thumbType;

  /// How it was taken, for the capture's `screenshot` field.
  final ScreenshotInfo info;

  /// How long it took, in whole milliseconds.
  final int ms;

  /// The thumbnail as a data URL for `viper:screenshot`.
  String? get thumbDataUrl {
    final bytes = thumb;
    if (bytes == null || bytes.isEmpty) return null;
    return Uri.dataFromBytes(bytes, mimeType: thumbType).toString();
  }
}

/// What the native side answered.
sealed class NativeAnswer {
  const NativeAnswer();
}

/// A picture.
final class NativePicture extends NativeAnswer {
  /// The picture.
  const NativePicture({required this.png, required this.thumb, required this.drawMs});

  /// The masked PNG.
  final Uint8List png;

  /// A JPEG thumbnail.
  final Uint8List thumb;

  /// How long the draw or copy took.
  final int drawMs;
}

/// The window is secure: no picture, on purpose (D338).
final class NativeSecure extends NativeAnswer {
  /// Secure.
  const NativeSecure();
}

/// The native call failed.
final class NativeFailed extends NativeAnswer {
  /// Why.
  const NativeFailed(this.message);

  /// What went wrong, for the log.
  final String message;
}

/// The plugin's native calls.
abstract interface class ViperNative {
  /// Draws the screen with [boxes] filled.
  Future<NativeAnswer> capture(List<ui.Rect> boxes, {double thumbWidth});

  /// The phone's time zone, `America/Chicago`, or null.
  Future<String?> timezone();

  /// Starts listening for a shake (D335), calling [onShake] each time; false where the phone
  /// can't tell.
  Future<bool> startShake(void Function() onShake);

  /// Stops listening.
  Future<void> stopShake();
}

/// [ViperNative] over the `viper_flutter` channel.
class ChannelNative implements ViperNative {
  /// The plugin.
  const ChannelNative();

  static const MethodChannel _channel = MethodChannel('viper_flutter');

  @override
  Future<NativeAnswer> capture(List<ui.Rect> boxes, {double thumbWidth = 360}) async {
    try {
      final answer = await _channel.invokeMapMethod<String, Object?>('capture', {
        'boxes': [
          for (final box in boxes) [box.left, box.top, box.width, box.height],
        ],
        'thumb_width': thumbWidth,
      });
      if (answer == null) return const NativeFailed('no answer');
      if (answer['blocked'] == 'secure_window') return const NativeSecure();
      final png = answer['png'];
      final thumb = answer['thumb'];
      if (png is! Uint8List || png.isEmpty) return const NativeFailed('no picture');
      return NativePicture(
        png: png,
        thumb: thumb is Uint8List ? thumb : Uint8List(0),
        drawMs: answer['draw_ms'] is int ? answer['draw_ms']! as int : 0,
      );
    } on PlatformException catch (error) {
      return NativeFailed('${error.code}: ${error.message}');
    } on MissingPluginException catch (error) {
      return NativeFailed('$error');
    }
  }

  @override
  Future<bool> startShake(void Function() onShake) async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shake') onShake();
      return null;
    });
    try {
      return await _channel.invokeMethod<bool>('startShake') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Android's system file picker for the panel's file inputs (D235): the chosen files' content
  /// URIs, empty when the person backs out.
  Future<List<String>> pickFiles(List<String> accept, {bool multiple = false}) async {
    try {
      final picked = await _channel.invokeListMethod<String>('pickFiles', {'accept': accept, 'multiple': multiple});
      return picked ?? const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<void> stopShake() async {
    try {
      await _channel.invokeMethod<void>('stopShake');
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  @override
  Future<String?> timezone() async {
    try {
      return await _channel.invokeMethod<String>('timezone');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// The phone's own picture of the app, as Flutter draws it (`toImage`): what's left when the native
/// call fails. Platform views come out blank, so they're blocked as well as masked (D338).
Future<Shot?> flutterShot(RenderRepaintBoundary boundary, List<ui.Rect> boxes, {required double pixelRatio}) async {
  final watch = Stopwatch()..start();
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(image, ui.Offset.zero, ui.Paint());
    final fill = ui.Paint()..color = const ui.Color(0xFFD2D5DA);
    for (final box in boxes) {
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(
            box.left * pixelRatio,
            box.top * pixelRatio,
            box.width * pixelRatio,
            box.height * pixelRatio,
          ),
          ui.Radius.circular(3 * pixelRatio),
        ),
        fill,
      );
    }
    final masked = await recorder.endRecording().toImage(image.width, image.height);
    final png = await masked.toByteData(format: ui.ImageByteFormat.png);
    final scale = 360 / (image.width / pixelRatio);
    final thumbRecorder = ui.PictureRecorder();
    ui.Canvas(thumbRecorder)
      ..scale(scale * 2 / pixelRatio)
      ..drawImage(masked, ui.Offset.zero, ui.Paint()..filterQuality = ui.FilterQuality.medium);
    final thumbImage = await thumbRecorder.endRecording().toImage(
      (image.width * scale * 2 / pixelRatio).round(),
      (image.height * scale * 2 / pixelRatio).round(),
    );
    final thumb = await thumbImage.toByteData(format: ui.ImageByteFormat.png);
    masked.dispose();
    thumbImage.dispose();
    if (png == null) return null;
    return Shot(
      png: png.buffer.asUint8List(),
      thumb: thumb?.buffer.asUint8List(),
      thumbType: 'image/png',
      info: const ScreenshotInfo(method: 'flutter', platformViewsBlocked: true),
      ms: watch.elapsedMilliseconds,
    );
  } finally {
    image.dispose();
  }
}
