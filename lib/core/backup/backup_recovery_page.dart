import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'vault_backup_service.dart';

final class BackupRecoveryPage extends StatefulWidget {
  const BackupRecoveryPage({super.key, required this.service});
  final VaultBackupService service;

  @override
  State<BackupRecoveryPage> createState() => _BackupRecoveryPageState();
}

final class _BackupRecoveryPageState extends State<BackupRecoveryPage> {
  bool _busy = false;
  String? _status;
  bool _statusIsError = false;

  Future<void> _createBackup() async {
    final l10n = AppLocalizations.of(context);
    final destination = await FilePicker.getDirectoryPath(
      dialogTitle: l10n.backupChooseExportFolder,
      lockParentWindow: true,
    );
    if (destination == null) return;
    await _run(() async {
      final result = await widget.service.createBackup(destination);
      return 'Backup verified • ${result.fileCount} files • '
          '${_formatBytes(result.totalBytes)}\n${result.path}';
    });
  }

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    final selection = await FilePicker.pickFiles(
      dialogTitle: l10n.backupChooseFile,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
      lockParentWindow: true,
    );
    final archive = selection?.files.single.path;
    if (archive == null || !mounted) return;
    final destination = await FilePicker.getDirectoryPath(
      dialogTitle: l10n.backupChooseRestoreParent,
      lockParentWindow: true,
    );
    if (destination == null || !mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.backupRestoreConfirmTitle),
        content: Text(l10n.backupRestoreConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: Text(l10n.backupValidateRestore),
          ),
        ],
      ),
    );
    if (approved != true) return;
    await _run(() async {
      final result = await widget.service.restoreIntoNewVault(
        archive,
        destination,
      );
      return 'Restore verified • ${result.fileCount} files • '
          '${_formatBytes(result.totalBytes)} • SQLite ${result.databaseIntegrity}\n'
          '${result.vault.root}';
    });
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _busy = true;
      _status = null;
      _statusIsError = false;
    });
    try {
      final status = await action();
      if (mounted) setState(() => _status = status);
    } on BackupException catch (error) {
      if (mounted) {
        setState(() {
          _status = error.message;
          _statusIsError = true;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _status = AppLocalizations.of(context).backupFailedGeneric;
          _statusIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 28, 40, 40),
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.shield_outlined, color: colors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.backupTitle,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(l10n.backupSubtitle),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _ActionCard(
              icon: Icons.archive_outlined,
              title: l10n.backupCreateTitle,
              body: l10n.backupCreateBody,
              buttonLabel: l10n.backupCreateButton,
              onPressed: _busy ? null : _createBackup,
            ),
            _ActionCard(
              icon: Icons.settings_backup_restore_rounded,
              title: l10n.backupRestoreTitle,
              body: l10n.backupRestoreBody,
              buttonLabel: l10n.backupRestoreButton,
              onPressed: _busy ? null : _restore,
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_busy)
          const LinearProgressIndicator(
            semanticsLabel: 'Backup operation in progress',
          ),
        if (_status != null) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (_statusIsError ? colors.error : colors.primary)
                    .withValues(alpha: 0.09),
                border: Border.all(
                  color: (_statusIsError ? colors.error : colors.primary)
                      .withValues(alpha: 0.35),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _statusIsError
                        ? Icons.error_outline_rounded
                        : Icons.verified_outlined,
                    color: _statusIsError ? colors.error : colors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: SelectableText(_status!)),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        _SafetyNote(text: l10n.backupSafetyNote),
      ],
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}

final class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String body;
  final String buttonLabel;
  final FutureOr<void> Function()? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 430,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(body),
            const SizedBox(height: 18),
            FilledButton.tonal(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ),
    ),
  );
}

final class _SafetyNote extends StatelessWidget {
  const _SafetyNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}
