import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class StickyGeometry {
  const StickyGeometry({
    this.x = 80,
    this.y = 80,
    this.width = 420,
    this.height = 640,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  Offset get position => Offset(x, y);
  Size get size => Size(width, height);

  Map<String, double> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  factory StickyGeometry.fromJson(Map<String, Object?> json) => StickyGeometry(
    x: (json['x'] as num?)?.toDouble() ?? 80,
    y: (json['y'] as num?)?.toDouble() ?? 80,
    width: (json['width'] as num?)?.toDouble() ?? 420,
    height: (json['height'] as num?)?.toDouble() ?? 640,
  );
}

class AppStateStore {
  AppStateStore._(this._file, this.geometry, this.vaultPath);

  final File _file;
  StickyGeometry geometry;
  String? vaultPath;

  static Future<AppStateStore> open() async {
    final root = await getApplicationSupportDirectory();
    final file = File(p.join(root.path, 'phase0-state.json'));
    if (!await file.exists()) {
      return AppStateStore._(file, const StickyGeometry(), null);
    }
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      return AppStateStore._(
        file,
        StickyGeometry.fromJson(
          (json['stickyGeometry'] as Map<Object?, Object?>).map(
            (key, value) => MapEntry(key.toString(), value),
          ),
        ),
        json['vaultPath'] as String?,
      );
    } on FormatException {
      return AppStateStore._(file, const StickyGeometry(), null);
    }
  }

  Future<void> save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert({'stickyGeometry': geometry.toJson(), 'vaultPath': vaultPath}),
      flush: true,
    );
  }
}
