// Unsent pictures on the phone (D165): kept as files, read back the same, dropped when sent, and
// gone after a day.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:viper_flutter/src/core/camera.dart';
import 'package:viper_flutter/src/core/environment.dart';
import 'package:viper_flutter/src/core/shots.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('viper-shots-test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('keeps a picture as it was taken, and drops it once sent', () async {
    final store = FileShotStore(dir);
    final shot = Shot(
      png: Uint8List.fromList([137, 80, 78, 71, 9]),
      thumb: Uint8List(1),
      thumbType: 'image/jpeg',
      info: const ScreenshotInfo(method: 'flutter', platformViewsBlocked: true),
      ms: 42,
    );
    await store.save('send-1/x', shot);
    final back = await FileShotStore(dir).load('send-1/x');
    expect(back!.png, shot.png);
    expect(back.info.toJson(), {'method': 'flutter', 'platform_views_blocked': true});
    expect(back.ms, 42);
    await store.drop('send-1/x');
    expect(await store.load('send-1/x'), isNull);
    expect(dir.listSync(), isEmpty);
  });

  test('drops what waited more than a day', () async {
    final store = FileShotStore(dir);
    await store.save(
      'old',
      Shot(
        png: Uint8List(3),
        thumb: null,
        thumbType: 'image/jpeg',
        info: const ScreenshotInfo(method: 'native'),
        ms: 1,
      ),
    );
    await store.prune(DateTime.now().add(const Duration(days: 2)));
    expect(await store.load('old'), isNull);
  });
}
