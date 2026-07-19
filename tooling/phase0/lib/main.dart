import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:multi_window_manager/multi_window_manager.dart';

import 'src/app_state_store.dart';
import 'src/main_screen.dart';
import 'src/sticky_screen.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('PHASE0_ARGS=$args');
  final windowId = args.isEmpty ? 0 : int.tryParse(args.first) ?? 0;
  final isSecondary = windowId != 0;
  final runSecondaryAutomation = isSecondary && args.contains('automation');
  final automatedVaultParent = isSecondary
      ? null
      : args
            .where((arg) => arg.startsWith('--phase0-auto='))
            .map((arg) => arg.substring('--phase0-auto='.length))
            .firstOrNull;

  if (isSecondary) {
    await MultiWindowManager.ensureInitializedSecondary(windowId);
  } else {
    await MultiWindowManager.ensureInitialized(windowId);
  }

  if (isSecondary) {
    final geometry = args.length > 2
        ? StickyGeometry.fromJson(
            (jsonDecode(args[2]) as Map<Object?, Object?>).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
        : const StickyGeometry();
    MultiWindowManager.current.waitUntilReadyToShow(
      WindowOptions(
        size: geometry.size,
        minimumSize: const Size(320, 320),
        alwaysOnTop: true,
        skipTaskbar: false,
        title: 'ephtodo Sticky PoC',
      ),
      () async {
        await MultiWindowManager.current.setPosition(geometry.position);
        await MultiWindowManager.current.show(inactive: true);
      },
    );
  } else {
    MultiWindowManager.current.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1050, 780),
        minimumSize: Size(760, 600),
        center: true,
        title: 'ephtodo Phase 0',
      ),
      () async => MultiWindowManager.current.show(),
    );
  }

  runApp(
    Phase0App(
      isSecondary: isSecondary,
      automatedVaultParent: automatedVaultParent,
      runSecondaryAutomation: runSecondaryAutomation,
    ),
  );
}

class Phase0App extends StatelessWidget {
  const Phase0App({
    super.key,
    required this.isSecondary,
    this.automatedVaultParent,
    this.runSecondaryAutomation = false,
  });

  final bool isSecondary;
  final String? automatedVaultParent;
  final bool runSecondaryAutomation;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ephtodo Phase 0',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff7c5cff),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff0b0c0e),
        useMaterial3: true,
      ),
      home: isSecondary
          ? StickyScreen(runAutomation: runSecondaryAutomation)
          : MainScreen(automatedVaultParent: automatedVaultParent),
    );
  }
}
