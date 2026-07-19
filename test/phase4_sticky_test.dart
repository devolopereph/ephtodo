import 'package:ephtodo/core/theme/app_theme.dart';
import 'package:ephtodo/core/windowing/multi_window_adapter.dart';
import 'package:ephtodo/core/windowing/window_protocol.dart';
import 'package:ephtodo/features/sticky_window/domain/sticky_source.dart';
import 'package:ephtodo/features/tasks/domain/task_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sticky preferences persist sources and safe opacity bounds', () {
    final low = StickyPreferences.fromJson({
      'source': 'pinned',
      'sourceId': null,
      'opacity': .1,
      'compact': true,
      'showMetadata': false,
      'collapseCompleted': true,
      'borderless': false,
    });
    expect(low.source, StickySourceType.pinned);
    expect(low.safeOpacity, .65);
    expect(low.compact, isTrue);
    expect(
      StickyPreferences.fromJson({...low.toJson(), 'opacity': 2}).safeOpacity,
      1,
    );
  });

  test('monitor-aware restore recovers unavailable display geometry', () {
    final recovered = recoverWindowGeometry(
      const WindowGeometry(x: 9000, y: 9000, width: 380, height: 540),
      const [Rect.fromLTWH(0, 0, 1920, 1040)],
    );
    expect(recovered.x, 24);
    expect(recovered.y, 24);
    final retained = recoverWindowGeometry(
      const WindowGeometry(x: 100, y: 100, width: 380, height: 540),
      const [Rect.fromLTWH(0, 0, 1920, 1040)],
    );
    expect(retained.x, 100);
  });

  test('all production sticky command families validate', () {
    for (final envelope in [
      _message(WindowMessageType.stickyRefresh, const {}),
      _message(WindowMessageType.openMain, const {}),
      _message(WindowMessageType.openQuickNote, const {}),
      _message(WindowMessageType.taskOpen, const {'id': 't', 'revision': 1}),
      _message(WindowMessageType.stickySourceChanged, const {
        'source': 'tomorrow',
      }),
      _message(WindowMessageType.stickyPreferencesChanged, const {
        'source': 'today',
        'opacity': .8,
        'compact': false,
        'showMetadata': true,
        'collapseCompleted': false,
        'borderless': false,
      }),
    ]) {
      expect(WindowEnvelope.decode(envelope.encode()).type, envelope.type);
    }
  });

  test(
    'Today Tomorrow Week project and pinned sources filter deterministically',
    () {
      const filter = StickySourceFilter();
      final now = DateTime(2026, 7, 20, 12);
      final today = _task('today', due: DateTime(2026, 7, 20));
      final tomorrow = _task('tomorrow', due: DateTime(2026, 7, 21));
      final week = _task('week', due: DateTime(2026, 7, 22));
      final project = _task('project', projectId: 'project-1');
      final pinned = _task('pinned', pinned: true);
      expect(filter.matches(today, const StickyPreferences(), now), isTrue);
      expect(
        filter.matches(
          tomorrow,
          const StickyPreferences(source: StickySourceType.tomorrow),
          now,
        ),
        isTrue,
      );
      expect(
        filter.matches(
          week,
          const StickyPreferences(source: StickySourceType.thisWeek),
          now,
        ),
        isTrue,
      );
      expect(
        filter.matches(
          project,
          const StickyPreferences(
            source: StickySourceType.project,
            sourceId: 'project-1',
          ),
          now,
        ),
        isTrue,
      );
      expect(
        filter.matches(
          pinned,
          const StickyPreferences(source: StickySourceType.pinned),
          now,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'desktop visual system renders every theme with focus semantics',
    (tester) async {
      for (final theme in AppThemeId.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(theme),
            home: Scaffold(
              body: Focus(
                autofocus: true,
                child: Semantics(
                  button: true,
                  label: 'Fictional task',
                  child: const Text('Fictional task'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Fictional task'), findsOneWidget);
        expect(
          Theme.of(
            tester.element(find.text('Fictional task')),
          ).visualDensity.vertical,
          -2,
        );
      }
    },
  );

  testWidgets(
    'Windows reduced-motion preference zeros theme animation tokens',
    (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            theme: buildAppTheme(AppThemeId.obsidianBlack),
            builder: (context, child) {
              final reduceMotion = MediaQuery.disableAnimationsOf(context);
              return Theme(
                data: buildAppTheme(
                  AppThemeId.obsidianBlack,
                  reducedMotion: reduceMotion,
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const Scaffold(body: Text('Reduced motion')),
          ),
        ),
      );
      await tester.pump();
      final tokens = Theme.of(
        tester.element(find.text('Reduced motion')),
      ).extension<AppTokens>()!;
      expect(tokens.animationDuration, Duration.zero);
    },
  );
}

WindowEnvelope _message(WindowMessageType type, Map<String, Object?> payload) =>
    WindowEnvelope(
      type: type,
      requestId: 'fictional-request',
      sourceWindowId: 'sticky',
      payload: payload,
      timestamp: DateTime.utc(2026, 7, 19),
    );

Task _task(
  String id, {
  DateTime? due,
  String? projectId,
  bool pinned = false,
}) => Task(
  id: id,
  title: 'Fictional task',
  projectNodeId: projectId,
  status: TaskStatus.open,
  priority: TaskPriority.none,
  dueAt: due,
  sortOrder: 1,
  isPinned: pinned,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  revision: 1,
  originatingDeviceId: 'fictional',
);
