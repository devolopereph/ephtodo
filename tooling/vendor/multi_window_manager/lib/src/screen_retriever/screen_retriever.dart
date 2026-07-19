import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'display.dart';
import 'screen_listener.dart';

export 'display.dart';
export 'screen_listener.dart';

class ScreenRetriever {
  ScreenRetriever._();

  static final ScreenRetriever instance = ScreenRetriever._();

  static const _methodChannel = MethodChannel(
    'multi_window_manager/screen_retriever',
  );

  static const _eventChannel = EventChannel(
    'multi_window_manager/screen_retriever_event',
  );

  StreamSubscription<dynamic>? _eventSubscription;
  final ObserverList<ScreenListener> _listeners =
      ObserverList<ScreenListener>();

  bool get hasListeners => _listeners.isNotEmpty;

  void _handleScreenEvent(dynamic event) {
    final type = (event as Map)['type'] as String;
    for (final listener in _listeners) {
      listener.onScreenEvent(type);
    }
  }

  void addListener(ScreenListener listener) {
    if (!hasListeners) {
      _eventSubscription =
          _eventChannel.receiveBroadcastStream().listen(_handleScreenEvent);
    }
    _listeners.add(listener);
  }

  void removeListener(ScreenListener listener) {
    _listeners.remove(listener);
    if (!hasListeners) {
      _eventSubscription?.cancel();
      _eventSubscription = null;
    }
  }

  Map<String, dynamic> get _defaultArguments {
    final mediaQueryData = MediaQueryData.fromView(
      WidgetsBinding.instance.platformDispatcher.views.single,
    );
    return {'devicePixelRatio': mediaQueryData.devicePixelRatio};
  }

  Future<Offset> getCursorScreenPoint() async {
    final result = await _methodChannel.invokeMethod<Map>(
      'getCursorScreenPoint',
      _defaultArguments,
    );
    if (result == null) throw Exception('Unable to get cursor screen point.');
    return Offset(
      (result['dx'] as num).toDouble(),
      (result['dy'] as num).toDouble(),
    );
  }

  Future<Display> getPrimaryDisplay() async {
    final result = await _methodChannel.invokeMethod<Map>(
      'getPrimaryDisplay',
      _defaultArguments,
    );
    if (result == null) throw Exception('Unable to get primary display.');
    return Display.fromJson(result.cast<String, dynamic>());
  }

  Future<List<Display>> getAllDisplays() async {
    final result = await _methodChannel.invokeMethod<Map>(
      'getAllDisplays',
      _defaultArguments,
    );
    if (result == null || result['displays'] == null) {
      throw Exception('Unable to get all displays.');
    }
    final displays = (result['displays'] as List)
        .map((item) => Display.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    if (displays.isEmpty) throw Exception('Unable to get all displays.');
    return displays;
  }
}

/// Global singleton accessor.
final screenRetriever = ScreenRetriever.instance;
