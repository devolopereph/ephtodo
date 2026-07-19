import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:multi_window_manager/src/reuse_window_listener.dart';
import 'package:multi_window_manager/src/title_bar_style.dart';
import 'package:multi_window_manager/src/window_manager.dart';
import 'package:multi_window_manager/src/window_options.dart';

/// Root widget for windows that participate in the reuse cache.
///
/// Must be used as the `home` of a window launched with
/// `isEnabledReuse: true` in [MultiWindowManager.ensureInitializedSecondary].
///
/// Responsibilities:
/// - **Initial display**: calls [waitUntilReadyToShow] with [windowOptions].
/// - **Hide instead of close**: relies on the native [kWindowEventReuseClose]
///   mechanism. The native WM_CLOSE handler hides the window and emits
///   [kWindowEventReuseClose] globally so the registry is updated automatically
///   without touching [setPreventClose]. Inner widgets may still use
///   [setPreventClose] for their own "are you sure?" dialogs.
/// - **Reuse**: on [kWindowEventShowWindow] repositions/shows itself and
///   rebuilds [builder] with new args and a fresh content subtree.
///
/// Modal routes ([showDialog], etc.) live on the [MaterialApp] navigator above
/// this widget. On reuse-hide, [ReusableWindow] pops them and bumps an internal
/// session key so the next show starts from a clean stack.
///
/// ### Usage
/// ```dart
/// await MultiWindowManager.ensureInitializedSecondary(windowId, isEnabledReuse: true);
///
/// runApp(MaterialApp(
///   home: ReusableWindow(
///     initialArgs: args,
///     builder: (context, args) => MyPage(args: args),
///   ),
/// ));
/// ```
class ReusableWindow extends StatefulWidget {
  const ReusableWindow({
    required this.builder,
    this.loadingBuilder,
    this.initialArgs,
    this.windowOptions = const WindowOptions(
      center: true,
      size: Size(1440, 940),
      minimumSize: Size(1440, 940),
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    ),
    super.key,
  });

  final dynamic initialArgs;
  final WindowOptions windowOptions;
  final Widget Function(BuildContext context)? loadingBuilder;
  final Widget Function(BuildContext context, dynamic args) builder;

  @override
  State<ReusableWindow> createState() => ReusableWindowState();
}

class ReusableWindowState extends State<ReusableWindow>
    implements ReusableWindowListener {
  dynamic _currentArgs;
  bool _isInitialized = false;

  /// Bumped on every reuse-hide so [builder] subtree (and its State) is recreated.
  int _contentSession = 0;

  @override
  void initState() {
    super.initState();
    MultiWindowManager.current.addReuseListener(this);
    _currentArgs = widget.initialArgs;
    _showWindow();
  }

  @override
  void dispose() {
    MultiWindowManager.current.removeReuseListener(this);
    super.dispose();
  }

  /// Pops dialog and secondary routes from the root [MaterialApp] navigator.
  Future<void> _resetNavigationStack() async {
    final completer = Completer();
    if (!mounted) return;
    final navigator = Navigator.maybeOf(context, rootNavigator: true);

    Future.delayed(const Duration(milliseconds: 300), () {
      if (completer.isCompleted) return;
      Future.delayed(
          const Duration(
            //time to close dialog
            milliseconds: 220,
          ), () {
        completer.complete();
      });
    });
    do {
      if (!(navigator?.canPop() ?? false)) {
        if (completer.isCompleted) return;
        Future.delayed(
            const Duration(
              //time to close dialog
              milliseconds: 220,
            ), () {
          completer.complete();
        });
      } else {
        navigator?.pop();
      }
    } while (navigator?.canPop() ?? false);

    await completer.future;
  }

  /// Clears overlays/routes and invalidates cached page state before hide or show.
  Future<void> _prepareForReuseHide() async {
    await _resetNavigationStack();
    if (mounted) {
      setState(() => _contentSession++);
    }
  }

  Future<void> _showWindow() async {
    if (mounted && _isInitialized) setState(() => _isInitialized = false);
    await MultiWindowManager.current.waitUntilReadyToShow(
      widget.windowOptions,
      () async {
        await _resetNavigationStack();
        await MultiWindowManager.current.show();
        await MultiWindowManager.current.focus();
      },
    );

    if (mounted) setState(() => _isInitialized = true);

    if (Platform.isWindows) {
      _forceWindowsRepaint();
    }

    log(
      'ReusableWindow ${MultiWindowManager.current.id}',
      name: 'ReusableWindow',
    );
  }

  void _forceWindowsRepaint() {
    if (!Platform.isWindows) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final size = await MultiWindowManager.current.getSize();
      await MultiWindowManager.current.setSize(size + const Offset(0, 1));
      await MultiWindowManager.current.setSize(size);
    });
  }

  @override
  Future<void> onReuseClose() async {
    if (mounted) setState(() => _isInitialized = false);
    log(
      'ReusableWindow ${MultiWindowManager.current.id} hidden for reuse',
      name: 'ReusableWindow',
    );
  }

  @override
  Future<void> onConfirmReuseCloseWindow() async {
    // confirm-close -> (this) -> setConfirmClose -> close -> reuse-close ->[onReuseClose]
    await _prepareForReuseHide();
  }

  @override
  Future<void> onShowWindow(dynamic args) async {
    _currentArgs = args;
    await _showWindow();
  }

  @override
  Widget build(BuildContext context) => _isInitialized
      ? KeyedSubtree(
          key: ValueKey(_contentSession),
          child: widget.builder(context, _currentArgs),
        )
      : widget.loadingBuilder?.call(context) ??
          const Center(
            child: SizedBox(
              height: 60,
              width: 60,
              child: CircularProgressIndicator(),
            ),
          );
}
