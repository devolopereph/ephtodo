import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/database/app_database.dart';
import '../core/foundation/foundation.dart';
import '../core/vault/vault_service.dart';
import '../core/windowing/multi_window_adapter.dart';

final bootstrapProvider = Provider<AppBootstrapState>(
  (ref) => throw StateError('Bootstrap provider was not overridden'),
);

final class AppBootstrapState {
  AppBootstrapState({
    required this.clock,
    required this.fs,
    required this.logger,
    required this.appSupport,
    required this.vaultService,
    required this.geometryStore,
    required this.quickNoteGeometryStore,
    required this.stickyPreferencesStore,
    required this.windowCoordinator,
    this.vault,
    this.database,
  });

  final Clock clock;
  final FileSystem fs;
  final StructuredLogger logger;
  final AppSupportStore appSupport;
  final VaultService vaultService;
  final WindowGeometryStore geometryStore;
  final WindowGeometryStore quickNoteGeometryStore;
  final StickyPreferencesStore stickyPreferencesStore;
  final WindowCoordinator windowCoordinator;
  final VaultHandle? vault;
  final AppDatabase? database;

  AppBootstrapState withVault(VaultHandle handle) {
    final database = AppDatabase.open(
      p.join(handle.root, 'database', 'ephtodo.sqlite'),
    );
    return AppBootstrapState(
      clock: clock,
      fs: fs,
      logger: logger,
      appSupport: appSupport,
      vaultService: vaultService,
      geometryStore: geometryStore,
      quickNoteGeometryStore: quickNoteGeometryStore,
      stickyPreferencesStore: stickyPreferencesStore,
      windowCoordinator: windowCoordinator,
      vault: handle,
      database: database,
    );
  }
}

Future<AppBootstrapState> bootstrapMainEngine({
  String? automationVaultParent,
  String? automationSupportPath,
}) async {
  const clock = SystemClock();
  const fs = LocalFileSystem();
  final logger = StructuredLogger();
  final supportDirectory = await getApplicationSupportDirectory();
  final appSupport = JsonAppSupportStore(
    automationSupportPath ?? p.join(supportDirectory.path, 'state.json'),
    fs,
  );
  final vaultService = VaultService(fs, clock);
  final geometryStore = AppSupportWindowGeometryStore(appSupport);
  final quickNoteGeometryStore = AppSupportWindowGeometryStore(
    appSupport,
    key: 'quickNoteGeometry',
  );
  var state = AppBootstrapState(
    clock: clock,
    fs: fs,
    logger: logger,
    appSupport: appSupport,
    vaultService: vaultService,
    geometryStore: geometryStore,
    quickNoteGeometryStore: quickNoteGeometryStore,
    stickyPreferencesStore: StickyPreferencesStore(appSupport),
    windowCoordinator: MultiWindowCoordinator(),
  );
  if (automationVaultParent != null) {
    await fs.createDirectory(automationVaultParent);
    return state.withVault(
      await vaultService.createInParent(automationVaultParent),
    );
  }
  Map<String, Object?> support;
  try {
    support = await appSupport.read();
  } on Object catch (error) {
    logger.log(
      LogLevel.warning,
      'app_support_unreadable',
      fields: {'type': error.runtimeType},
    );
    support = const {};
  }
  final lastVault = support['lastVaultPath'];
  if (lastVault is String) {
    try {
      state = state.withVault(await vaultService.open(lastVault));
    } on VaultException catch (error) {
      logger.log(
        LogLevel.warning,
        'vault_unavailable',
        fields: {'code': error.code.name},
      );
    }
  }
  return state;
}
