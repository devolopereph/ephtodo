import '../foundation/foundation.dart';
import 'app_database.dart';

enum CompletionPolicy { archive, trash, keepCompleted }

enum TrashRetentionPolicy { thirtyDays, never }

abstract interface class PreferencesRepository {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
}

final class DriftPreferencesRepository implements PreferencesRepository {
  DriftPreferencesRepository(this.database, this.clock);
  final AppDatabase database;
  final Clock clock;

  @override
  Future<String?> get(String key) async {
    final row = await (database.select(
      database.appPreferences,
    )..where((table) => table.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> set(String key, String value) => database.transaction(
    () => database
        .into(database.appPreferences)
        .insertOnConflictUpdate(
          AppPreferencesCompanion.insert(
            key: key,
            value: value,
            updatedAt: clock.now(),
          ),
        ),
  );
}

final class OnboardingSettings {
  const OnboardingSettings({
    this.step = 0,
    this.completed = false,
    this.completionPolicy = CompletionPolicy.keepCompleted,
    this.trashRetention = TrashRetentionPolicy.thirtyDays,
    this.themeId = 'obsidianBlack',
    this.localeCode = 'system',
  });

  /// 'system', or a supported language code such as 'en' or 'tr'.
  static const supportedLocaleCodes = {'system', 'en', 'tr'};

  final int step;
  final bool completed;
  final CompletionPolicy completionPolicy;
  final TrashRetentionPolicy trashRetention;
  final String themeId;
  final String localeCode;

  OnboardingSettings copyWith({
    int? step,
    bool? completed,
    CompletionPolicy? completionPolicy,
    TrashRetentionPolicy? trashRetention,
    String? themeId,
    String? localeCode,
  }) => OnboardingSettings(
    step: step ?? this.step,
    completed: completed ?? this.completed,
    completionPolicy: completionPolicy ?? this.completionPolicy,
    trashRetention: trashRetention ?? this.trashRetention,
    themeId: themeId ?? this.themeId,
    localeCode: localeCode ?? this.localeCode,
  );
}

final class OnboardingRepository {
  OnboardingRepository(this.preferences);
  final PreferencesRepository preferences;

  Future<OnboardingSettings> load() async => OnboardingSettings(
    step: int.tryParse(await preferences.get('onboarding.step') ?? '') ?? 0,
    completed: await preferences.get('onboarding.completed') == 'true',
    completionPolicy: CompletionPolicy.values.byName(
      await preferences.get('completion.policy') ??
          CompletionPolicy.keepCompleted.name,
    ),
    trashRetention: TrashRetentionPolicy.values.byName(
      await preferences.get('trash.retention') ??
          TrashRetentionPolicy.thirtyDays.name,
    ),
    themeId: await preferences.get('theme.id') ?? 'obsidianBlack',
    localeCode: switch (await preferences.get('locale.code')) {
      final String code
          when OnboardingSettings.supportedLocaleCodes.contains(code) =>
        code,
      _ => 'system',
    },
  );

  Future<void> save(OnboardingSettings settings) async {
    await preferences.set('onboarding.step', settings.step.toString());
    await preferences.set(
      'onboarding.completed',
      settings.completed.toString(),
    );
    await preferences.set('completion.policy', settings.completionPolicy.name);
    await preferences.set('trash.retention', settings.trashRetention.name);
    await preferences.set('theme.id', settings.themeId);
    await preferences.set('locale.code', settings.localeCode);
  }
}

DateTime? trashPurgeCutoff(TrashRetentionPolicy policy, Clock clock) =>
    policy == TrashRetentionPolicy.never
    ? null
    : clock.now().subtract(const Duration(days: 30));
