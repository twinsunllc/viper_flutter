// An unsent report's picture, kept on the phone (D165, D330): the panel keeps the words and sends
// again once Viper answers, even after the app was closed; the picture it names is kept here
// until it's sent, so the retry has the same picture, not the screen as it is by then.
import 'dart:convert';
import 'dart:io';

import 'package:viper_flutter/src/core/camera.dart';
import 'package:viper_flutter/src/core/environment.dart';

/// Pictures waiting for their report, one per send, by the panel's client id.
abstract interface class ShotStore {
  /// Keeps [shot] for [clientId].
  Future<void> save(String clientId, Shot shot);

  /// The picture kept for [clientId], or null.
  Future<Shot?> load(String clientId);

  /// Drops the picture for [clientId]: sent, or refused.
  Future<void> drop(String clientId);

  /// Drops pictures that waited too long.
  Future<void> prune(DateTime now);
}

/// [ShotStore] in memory, for tests.
class MemoryShotStore implements ShotStore {
  /// What's kept.
  final Map<String, Shot> shots = <String, Shot>{};

  @override
  Future<void> save(String clientId, Shot shot) async => shots[clientId] = shot;

  @override
  Future<Shot?> load(String clientId) async => shots[clientId];

  @override
  Future<void> drop(String clientId) async => shots.remove(clientId);

  @override
  Future<void> prune(DateTime now) async {}
}

/// [ShotStore] in files.
class FileShotStore implements ShotStore {
  /// Keeps pictures in [directory].
  FileShotStore(this.directory);

  /// Where they're kept: the app's temporary directory by default, which the OS may clear.
  final Directory directory;

  /// How long a picture waits for its report before it's dropped.
  static const Duration keep = Duration(days: 1);

  File _file(String clientId, String suffix) => File('${directory.path}/viper-${_safe(clientId)}.$suffix');

  static String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  @override
  Future<void> save(String clientId, Shot shot) async {
    final png = shot.png;
    if (png == null) return;
    await directory.create(recursive: true);
    await _file(clientId, 'png').writeAsBytes(png, flush: true);
    await _file(clientId, 'json').writeAsString(
      jsonEncode({'info': shot.info.toJson(), 'ms': shot.ms, 'thumb_type': shot.thumbType}),
      flush: true,
    );
  }

  @override
  Future<Shot?> load(String clientId) async {
    final png = _file(clientId, 'png');
    final meta = _file(clientId, 'json');
    if (!await png.exists() || !await meta.exists()) return null;
    try {
      final json = jsonDecode(await meta.readAsString()) as Map<String, Object?>;
      final info = json['info']! as Map<String, Object?>;
      return Shot(
        png: await png.readAsBytes(),
        thumb: null,
        thumbType: json['thumb_type'] as String? ?? 'image/jpeg',
        info: ScreenshotInfo(
          method: info['method'] as String? ?? 'native',
          platformViewsBlocked: info['platform_views_blocked'] == true,
          blocked: info['blocked'] as String?,
        ),
        ms: (json['ms'] as num?)?.toInt() ?? 0,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> drop(String clientId) async {
    for (final suffix in ['png', 'json']) {
      final file = _file(clientId, suffix);
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<void> prune(DateTime now) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.contains('/viper-')) continue;
      if (now.difference(await entity.lastModified()) > keep) await entity.delete();
    }
  }
}
