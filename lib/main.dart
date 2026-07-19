import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/bootstrap.dart';
import 'app/ephtodo_app.dart';
import 'core/database/preferences_repository.dart';
import 'core/foundation/foundation.dart';
import 'core/theme/app_theme.dart';
import 'core/windowing/multi_window_adapter.dart';
import 'core/windowing/window_protocol.dart';
import 'l10n/app_localizations.dart';
import 'features/notes/presentation/quick_note_window.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = StructuredLogger();
  FlutterError.onError = (details) {
    logger.log(
      LogLevel.error,
      'flutter_error',
      fields: {
        'type': details.exception.runtimeType,
        'summary': details.summary.toString(),
        'library': details.library,
      },
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.log(
      LogLevel.error,
      'platform_error',
      fields: {
        'type': error.runtimeType,
        'summary': error.toString(),
      },
    );
    return true;
  };

  final windowId = args.isEmpty ? 0 : int.tryParse(args.first) ?? 0;
  final secondary = windowId != 0;
  final role = secondary && args.length > 1 ? args[1] : 'main';
  DatabaseOpenAudit.configure(role);
  final phase2Root = Platform.environment['EPHTODO_PHASE2_SMOKE_ROOT'];
  final phase34Root = Platform.environment['EPHTODO_PHASE34_SMOKE_ROOT'];
  final audioSmokeRoot = Platform.environment['EPHTODO_AUDIO_SMOKE_ROOT'];
  final phase2Smoke = phase2Root != null;
  final geometry = secondary && args.length >= 6
      ? WindowGeometry(
          x: double.tryParse(args[2]) ?? 120,
          y: double.tryParse(args[3]) ?? 120,
          width: double.tryParse(args[4]) ?? 380,
          height: double.tryParse(args[5]) ?? 540,
        )
      : null;

  try {
    await initializeWindowing(
      windowId: windowId,
      secondary: secondary,
      geometry: geometry,
      role: role,
    );
    if (secondary) {
      runApp(_SecondaryApp(role: role));
      return;
    }
    final bootstrap = await bootstrapMainEngine(
      automationVaultParent: phase2Root ?? phase34Root ?? audioSmokeRoot,
      automationSupportPath:
          phase2Root == null && phase34Root == null && audioSmokeRoot == null
          ? null
          : '${phase2Root ?? phase34Root ?? audioSmokeRoot}${Platform.pathSeparator}support.json',
    );
    if ((phase2Smoke || phase34Root != null || audioSmokeRoot != null) &&
        bootstrap.database != null) {
      await OnboardingRepository(
        DriftPreferencesRepository(bootstrap.database!, bootstrap.clock),
      ).save(const OnboardingSettings(step: 7, completed: true));
    }
    runApp(
      ProviderScope(
        overrides: [bootstrapProvider.overrideWithValue(bootstrap)],
        child: EphtodoApp(bootstrap: bootstrap),
      ),
    );
    if (phase34Root != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        await bootstrap.windowCoordinator.showSticky(
          const WindowGeometry(x: 100, y: 100, width: 380, height: 540),
        );
        await bootstrap.windowCoordinator.showQuickNote(
          const WindowGeometry(x: 520, y: 100, width: 620, height: 640),
        );
      });
    } else if (phase2Smoke ||
        args.contains('--phase1-native-verify') ||
        Platform.environment['EPHTODO_PHASE1_NATIVE_VERIFY'] == '1') {
      logger.log(LogLevel.info, 'native_verify_scheduled');
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(seconds: 2));
        try {
          await bootstrap.windowCoordinator.showSticky(
            const WindowGeometry(x: 120, y: 120, width: 380, height: 540),
          );
          logger.log(LogLevel.info, 'native_verify_sticky_created');
        } catch (error) {
          logger.log(
            LogLevel.error,
            'native_verify_sticky_failed',
            fields: {'type': error.runtimeType, 'error': error},
          );
        }
      });
    }
  } catch (error) {
    logger.log(
      LogLevel.error,
      'startup_failed',
      fields: {'type': error.runtimeType},
    );
    runApp(StartupFailureApp(error: error));
  }
}

/// Hosts the sticky or quick-note window and follows the language/theme the
/// main window broadcasts over IPC.
final class _SecondaryApp extends StatefulWidget {
  const _SecondaryApp({required this.role});
  final String role;

  @override
  State<_SecondaryApp> createState() => _SecondaryAppState();
}

final class _SecondaryAppState extends State<_SecondaryApp> {
  Locale? _locale;
  AppThemeId _theme = AppThemeId.obsidianBlack;

  void _onLocaleChanged(String code) {
    final locale = localeForCode(code);
    if (locale != _locale && mounted) setState(() => _locale = locale);
  }

  void _onThemeChanged(String themeId) {
    final matched = AppThemeId.values.where((value) => value.name == themeId);
    final next = matched.isEmpty ? AppThemeId.obsidianBlack : matched.first;
    if (next != _theme && mounted) setState(() => _theme = next);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: _locale,
    theme: buildAppTheme(_theme),
    builder: (context, child) {
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      return Theme(
        data: buildAppTheme(_theme, reducedMotion: reduceMotion),
        child: child ?? const SizedBox.shrink(),
      );
    },
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: widget.role == 'quickNote'
        ? QuickNoteWindow(
            clock: const SystemClock().now,
            onLocaleChanged: _onLocaleChanged,
            onThemeChanged: _onThemeChanged,
          )
        : StickyFoundationShell(
            clock: const SystemClock().now,
            onLocaleChanged: _onLocaleChanged,
            onThemeChanged: _onThemeChanged,
          ),
  );
}
