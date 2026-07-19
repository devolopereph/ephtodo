import 'dart:async';

import 'package:flutter/material.dart';
import 'package:multi_window_manager/multi_window_manager.dart';
import 'package:screen_retriever/screen_retriever.dart' as sr;

import '../foundation/foundation.dart';
import 'window_protocol.dart';

abstract interface class WindowCoordinator {
  Future<void> showSticky(WindowGeometry geometry);
  Future<void> showQuickNote(WindowGeometry geometry);
  Future<void> hideSticky();
  Future<void> hideQuickNote();
  Future<void> showMain();
  Future<void> broadcast(WindowEnvelope message);
}

abstract interface class SecondaryWindowClient {
  String get windowId;
  Stream<void> get geometryChanges;
  Stream<void> get closeRequests;
  Future<void> initializeSticky();
  Future<void> initializeQuickNote();
  Future<WindowGeometry> currentGeometry();
  Future<Object?> sendToMain(WindowEnvelope message);
  Future<void> setOpacity(double opacity);
  Future<void> setCompact(bool compact);
  Future<void> setBorderless(bool borderless);
  Future<void> hide();
  void dispose();
}

abstract interface class WindowCommandBus {
  Stream<WindowEnvelope> get messages;
  void dispose();
}

abstract interface class WindowGeometryStore {
  Future<WindowGeometry> load();
  Future<void> save(WindowGeometry geometry);
}

final class AppSupportWindowGeometryStore implements WindowGeometryStore {
  AppSupportWindowGeometryStore(this.store, {this.key = 'stickyGeometry'});
  final AppSupportStore store;
  final String key;

  @override
  Future<WindowGeometry> load() async {
    final values = await store.read();
    final raw = values[key];
    if (raw is Map<String, dynamic>) {
      try {
        return WindowGeometry.fromJson(raw);
      } on WindowProtocolException {
        // Use safe defaults after monitor/layout changes.
      }
    }
    return const WindowGeometry(x: 120, y: 120, width: 380, height: 540);
  }

  @override
  Future<void> save(WindowGeometry geometry) async {
    if (!geometry.isValid) return;
    final values = await store.read();
    await store.write({...values, key: geometry.toJson()});
  }
}

final class StickyPreferencesStore {
  StickyPreferencesStore(this.store);
  final AppSupportStore store;

  Future<StickyPreferences> load() async {
    final raw = (await store.read())['stickyPreferences'];
    return raw is Map<String, dynamic>
        ? StickyPreferences.fromJson(raw)
        : const StickyPreferences();
  }

  Future<void> save(StickyPreferences preferences) async {
    final values = await store.read();
    await store.write({...values, 'stickyPreferences': preferences.toJson()});
  }
}

final class MultiWindowCommandBus
    with WindowListener
    implements WindowCommandBus {
  MultiWindowCommandBus({this._handler}) {
    MultiWindowManager.current.addListener(this);
  }
  final Future<Map<String, Object?>> Function(WindowEnvelope message)? _handler;
  final _messages = StreamController<WindowEnvelope>.broadcast();

  @override
  Stream<WindowEnvelope> get messages => _messages.stream;

  @override
  Future<Object?> onEventFromWindow(
    String eventName,
    int fromWindowId,
    dynamic arguments,
  ) async {
    if (eventName != 'ephtodo.v1' || arguments is! String) {
      return _error(WindowErrorCode.malformed, 'Malformed event');
    }
    try {
      final message = WindowEnvelope.decode(arguments);
      _messages.add(message);
      final handler = _handler;
      if (handler != null) return handler(message);
      return {
        'ok': true,
        'requestId': message.requestId,
        'protocolVersion': windowProtocolVersion,
      };
    } on WindowProtocolException catch (error) {
      return _error(error.code, error.message);
    }
  }

  Map<String, Object?> _error(WindowErrorCode code, String message) => {
    'ok': false,
    'error': {'code': code.name, 'message': message},
    'protocolVersion': windowProtocolVersion,
  };

  @override
  void dispose() {
    MultiWindowManager.current.removeListener(this);
    unawaited(_messages.close());
  }
}

final class MultiWindowCoordinator implements WindowCoordinator {
  MultiWindowManager? _sticky;
  MultiWindowManager? _quickNote;

  @override
  Future<void> showSticky(WindowGeometry geometry) async {
    final existing = _sticky;
    if (existing != null) {
      await existing.show(inactive: true);
      return;
    }
    final window = await MultiWindowManager.createWindow([
      'sticky',
      geometry.x.toString(),
      geometry.y.toString(),
      geometry.width.toString(),
      geometry.height.toString(),
    ]);
    _sticky = window;
  }

  @override
  Future<void> hideSticky() async => _sticky?.hide();

  @override
  Future<void> showQuickNote(WindowGeometry geometry) async {
    final existing = _quickNote;
    if (existing != null) {
      await existing.show();
      return;
    }
    _quickNote = await MultiWindowManager.createWindow([
      'quickNote',
      geometry.x.toString(),
      geometry.y.toString(),
      geometry.width.toString(),
      geometry.height.toString(),
    ]);
  }

  @override
  Future<void> hideQuickNote() async => _quickNote?.hide();

  @override
  Future<void> showMain() => MultiWindowManager.current.show();

  @override
  Future<void> broadcast(WindowEnvelope message) async {
    final sticky = _sticky;
    if (sticky != null) {
      await MultiWindowManager.current.invokeMethodToWindow(
        sticky.id,
        'ephtodo.v1',
        message.encode(),
      );
    }
    final quickNote = _quickNote;
    if (quickNote != null) {
      await MultiWindowManager.current.invokeMethodToWindow(
        quickNote.id,
        'ephtodo.v1',
        message.encode(),
      );
    }
  }
}

final class MultiWindowSecondaryClient
    with WindowListener
    implements SecondaryWindowClient {
  MultiWindowSecondaryClient() {
    MultiWindowManager.current.addListener(this);
  }

  final _geometryChanges = StreamController<void>.broadcast();
  final _closeRequests = StreamController<void>.broadcast();

  @override
  String get windowId => MultiWindowManager.current.id.toString();

  @override
  Stream<void> get geometryChanges => _geometryChanges.stream;

  @override
  Stream<void> get closeRequests => _closeRequests.stream;

  @override
  Future<void> initializeSticky() async {
    await MultiWindowManager.current.setAlwaysOnTop(true);
    await MultiWindowManager.current.setPreventClose(true);
  }

  @override
  Future<void> initializeQuickNote() async {
    await MultiWindowManager.current.setAlwaysOnTop(false);
    await MultiWindowManager.current.setPreventClose(true);
  }

  @override
  Future<WindowGeometry> currentGeometry() async {
    final position = await MultiWindowManager.current.getPosition();
    final size = await MultiWindowManager.current.getSize();
    return WindowGeometry(
      x: position.dx,
      y: position.dy,
      width: size.width,
      height: size.height,
    );
  }

  @override
  Future<Object?> sendToMain(WindowEnvelope message) => MultiWindowManager
      .current
      .invokeMethodToWindow(0, 'ephtodo.v1', message.encode());

  @override
  Future<void> setOpacity(double opacity) =>
      MultiWindowManager.current.setOpacity(opacity.clamp(.65, 1));

  @override
  Future<void> setCompact(bool compact) async {
    final size = await MultiWindowManager.current.getSize();
    await MultiWindowManager.current.setSize(
      Size(size.width, compact ? 300 : 540),
    );
  }

  @override
  Future<void> setBorderless(bool borderless) =>
      MultiWindowManager.current.setTitleBarStyle(
        borderless ? TitleBarStyle.hidden : TitleBarStyle.normal,
      );

  @override
  Future<void> hide() => MultiWindowManager.current.hide();

  @override
  void onWindowMoved([int? windowId]) => _geometryChanges.add(null);

  @override
  void onWindowResized([int? windowId]) => _geometryChanges.add(null);

  @override
  void onWindowClose([int? windowId]) => _closeRequests.add(null);

  @override
  void dispose() {
    MultiWindowManager.current.removeListener(this);
    unawaited(_geometryChanges.close());
    unawaited(_closeRequests.close());
  }
}

Future<void> initializeWindowing({
  required int windowId,
  required bool secondary,
  WindowGeometry? geometry,
  String role = 'sticky',
}) async {
  if (secondary) {
    await MultiWindowManager.ensureInitializedSecondary(windowId);
    var value =
        geometry ??
        const WindowGeometry(x: 120, y: 120, width: 380, height: 540);
    try {
      final displays = await sr.screenRetriever.getAllDisplays();
      value = recoverWindowGeometry(
        value,
        displays
            .map(
              (display) => Rect.fromLTWH(
                display.visiblePosition?.dx ?? 0,
                display.visiblePosition?.dy ?? 0,
                (display.visibleSize ?? display.size).width,
                (display.visibleSize ?? display.size).height,
              ),
            )
            .toList(),
      );
    } on Object {
      value = const WindowGeometry(x: 120, y: 120, width: 380, height: 540);
    }
    MultiWindowManager.current.waitUntilReadyToShow(
      WindowOptions(
        size: Size(value.width, value.height),
        minimumSize: role == 'quickNote'
            ? const Size(420, 320)
            : const Size(280, 200),
        alwaysOnTop: role == 'sticky',
        title: role == 'quickNote' ? 'ephtodo quick note' : 'ephtodo sticky',
      ),
      () async {
        await MultiWindowManager.current.setPosition(Offset(value.x, value.y));
        await MultiWindowManager.current.setAlwaysOnTop(role == 'sticky');
        await MultiWindowManager.current.setPreventClose(true);
        await MultiWindowManager.current.show(inactive: true);
      },
    );
  } else {
    await MultiWindowManager.ensureInitialized(windowId);
    MultiWindowManager.current.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1100, 760),
        minimumSize: Size(760, 560),
        center: true,
        title: 'ephtodo',
      ),
      () => MultiWindowManager.current.show(),
    );
  }
}

WindowGeometry recoverWindowGeometry(
  WindowGeometry geometry,
  List<Rect> workAreas,
) {
  if (workAreas.isEmpty) {
    return const WindowGeometry(x: 120, y: 120, width: 380, height: 540);
  }
  final intersects = workAreas.any(
    (area) => area.overlaps(
      Rect.fromLTWH(geometry.x, geometry.y, geometry.width, geometry.height),
    ),
  );
  if (intersects) return geometry;
  final area = workAreas.first;
  return WindowGeometry(
    x: area.left + 24,
    y: area.top + 24,
    width: geometry.width.clamp(280, area.width),
    height: geometry.height.clamp(200, area.height),
  );
}
