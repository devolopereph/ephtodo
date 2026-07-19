import '../../../core/windowing/window_protocol.dart';
import '../../tasks/domain/task_models.dart';
import '../../tasks/domain/task_rules.dart';

final class StickySourceFilter {
  const StickySourceFilter();

  bool matches(Task task, StickyPreferences preferences, DateTime now) {
    final horizon = const HorizonEngine().classify(task, now);
    return switch (preferences.source) {
      StickySourceType.today =>
        horizon == TaskHorizon.today || horizon == TaskHorizon.overdue,
      StickySourceType.tomorrow => horizon == TaskHorizon.tomorrow,
      StickySourceType.thisWeek =>
        horizon == TaskHorizon.today ||
            horizon == TaskHorizon.tomorrow ||
            horizon == TaskHorizon.thisWeek,
      StickySourceType.project || StickySourceType.folderOrList =>
        task.projectNodeId == preferences.sourceId,
      StickySourceType.pinned => task.isPinned,
      StickySourceType.savedFilter => true,
    };
  }
}
