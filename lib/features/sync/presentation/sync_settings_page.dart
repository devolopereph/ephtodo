import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../application/sync_settings_controller.dart';
import '../domain/sync_models.dart';
import '../server/sync_server.dart';

final class SyncSettingsPage extends StatefulWidget {
  const SyncSettingsPage({super.key, required this.controller});

  final SyncSettingsController controller;

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

final class _SyncSettingsPageState extends State<SyncSettingsPage> {
  SyncSettingsSnapshot? _snapshot;
  StreamSubscription<SyncSettingsSnapshot>? _subscription;
  bool _busy = false;
  bool _persistOnLaunch = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.controller.snapshots.listen((snapshot) {
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _loadFailed = false;
        _persistOnLaunch = snapshot.persistentlyEnabled;
      });
    });
    unawaited(_refreshSafely());
  }

  Future<void> _refreshSafely() async {
    try {
      await widget.controller.refresh();
    } on Object {
      // Never leave the pane on an endless spinner when the controller
      // cannot produce a snapshot (e.g. secure storage failures).
      if (mounted && _snapshot == null) {
        setState(() => _loadFailed = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      if (_loadFailed) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sync_problem_outlined, size: 32),
                const SizedBox(height: 12),
                Text(AppLocalizations.of(context).syncLoadFailed),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {
                    setState(() => _loadFailed = false);
                    unawaited(_refreshSafely());
                  },
                  child: Text(AppLocalizations.of(context).retry),
                ),
              ],
            ),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final running = snapshot.server.state == SyncServerState.running;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).syncHeadline,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppLocalizations.of(context).syncHeadlineHint,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            _StatusPill(status: snapshot.server),
          ],
        ),
        const SizedBox(height: 22),
        _Section(
          title: AppLocalizations.of(context).syncSecureServer,
          subtitle: AppLocalizations.of(context).syncSecureServerHint,
          child: Column(
            children: [
              _SettingRow(
                icon: Icons.lan_outlined,
                title: running
                    ? AppLocalizations.of(context).syncServerAvailable
                    : AppLocalizations.of(context).syncServerOff,
                subtitle: running
                    ? '${snapshot.server.addresses.join(', ')}:${snapshot.port}'
                    : _serverMessage(snapshot.server),
                trailing: running
                    ? OutlinedButton.icon(
                        onPressed: _busy ? null : _confirmDisable,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: Text(AppLocalizations.of(context).syncStop),
                      )
                    : FilledButton.icon(
                        onPressed: _busy ? null : _enable,
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(AppLocalizations.of(context).syncEnable),
                      ),
              ),
              const Divider(height: 1),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                value: _persistOnLaunch,
                onChanged: running
                    ? (value) => setState(() => _persistOnLaunch = value)
                    : null,
                title: Text(AppLocalizations.of(context).syncRestoreOnLaunch),
                subtitle: Text(
                  AppLocalizations.of(context).syncRestoreOnLaunchHint,
                ),
              ),
              const Divider(height: 1),
              _SettingRow(
                icon: Icons.password_outlined,
                title: AppLocalizations.of(context).syncPassword,
                subtitle: AppLocalizations.of(context).syncPasswordHint,
                trailing: TextButton(
                  onPressed: _busy ? null : _setPassword,
                  child: Text(AppLocalizations.of(context).syncSetOrChange),
                ),
              ),
              const Divider(height: 1),
              _SettingRow(
                icon: Icons.settings_ethernet,
                title: AppLocalizations.of(context).syncPort(snapshot.port),
                subtitle: AppLocalizations.of(context).syncPortHint,
                trailing: TextButton(
                  onPressed: _busy ? null : () => _changePort(snapshot.port),
                  child: Text(AppLocalizations.of(context).syncChange),
                ),
              ),
              if (snapshot.server.fingerprint != null) ...[
                const Divider(height: 1),
                _SettingRow(
                  icon: Icons.fingerprint,
                  title: AppLocalizations.of(context).syncTlsFingerprint,
                  subtitle: snapshot.server.fingerprint!,
                  trailing: IconButton(
                    tooltip: AppLocalizations.of(context).syncCopyFingerprint,
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: snapshot.server.fingerprint!),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: AppLocalizations.of(context).syncPairing,
          subtitle: AppLocalizations.of(context).syncPairingHint,
          child: Column(
            children: [
              if (snapshot.pairing == null)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: running && !_busy
                          ? () => _run(widget.controller.beginPairing)
                          : null,
                      icon: const Icon(Icons.add_link),
                      label: Text(
                        AppLocalizations.of(context).syncCreatePairingCode,
                      ),
                    ),
                  ),
                )
              else
                _PairingCode(session: snapshot.pairing!),
              for (final pending in snapshot.pending) ...[
                const Divider(height: 1),
                _PendingDevice(
                  pending: pending,
                  onApprove: _busy
                      ? null
                      : () => _run(
                          () => widget.controller.approve(pending.requestId),
                        ),
                  onReject: _busy
                      ? null
                      : () => _run(
                          () => widget.controller.reject(pending.requestId),
                        ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: AppLocalizations.of(context).syncPairedDevices,
          subtitle: 'Normal clients receive sync read and write only.',
          child: snapshot.devices.isEmpty
              ? _EmptySetting(
                  icon: Icons.devices_other_outlined,
                  text: AppLocalizations.of(context).syncNoPairedDevices,
                )
              : Column(
                  children: [
                    for (
                      var index = 0;
                      index < snapshot.devices.length;
                      index++
                    ) ...[
                      if (index > 0) const Divider(height: 1),
                      _DeviceRow(
                        device: snapshot.devices[index],
                        onRevoke: snapshot.devices[index].revoked || _busy
                            ? null
                            : () => _confirmRevoke(snapshot.devices[index]),
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Redacted audit',
          subtitle: 'No request bodies, credentials, paths, or content.',
          child: snapshot.audit.isEmpty
              ? const _EmptySetting(
                  icon: Icons.shield_outlined,
                  text: 'No synchronization security events yet.',
                )
              : Column(
                  children: [
                    for (final event in snapshot.audit)
                      ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.check_circle_outline,
                          size: 18,
                        ),
                        title: Text(event.type.replaceAll('_', ' ')),
                        subtitle: Text(
                          '${event.resultCode} · '
                          '${event.at.toLocal().toIso8601String().split('.').first}',
                        ),
                        trailing: event.deviceIdSuffix == null
                            ? null
                            : Text('…${event.deviceIdSuffix}'),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Credential maintenance',
          subtitle:
              'Rotation disconnects clients. Reset revokes every paired device.',
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _confirmRotate,
                  icon: const Icon(Icons.autorenew),
                  label: const Text('Rotate certificate'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _confirmReset,
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Reset all credentials'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _serverMessage(SyncServerStatus status) => switch (status.state) {
    SyncServerState.error =>
      'Could not start securely (${status.errorCode ?? 'unknown error'}).',
    SyncServerState.starting => 'Starting secure listeners…',
    SyncServerState.stopping => 'Stopping listeners and clients…',
    _ => 'No network listener is active.',
  };

  Future<void> _enable() =>
      _run(() => widget.controller.enable(persist: _persistOnLaunch));

  Future<void> _confirmDisable() async {
    final clients = _snapshot?.server.connectedClients ?? 0;
    final confirmed = await _confirm(
      'Stop local sync?',
      clients == 0
          ? 'The HTTPS and WebSocket listeners will close immediately.'
          : '$clients connected client(s) will be disconnected immediately.',
      'Stop server',
    );
    if (confirmed) await _run(widget.controller.disable);
  }

  Future<void> _confirmRevoke(SyncDevice device) async {
    final confirmed = await _confirm(
      'Revoke ${device.name}?',
      'Its current access credential and event connection will stop working.',
      'Revoke device',
    );
    if (confirmed) {
      await _run(() => widget.controller.revoke(device.id));
    }
  }

  Future<void> _confirmRotate() async {
    final confirmed = await _confirm(
      'Rotate the TLS certificate?',
      'Connected clients will be disconnected and must verify the new fingerprint.',
      'Rotate',
    );
    if (confirmed) await _run(widget.controller.rotateCertificate);
  }

  Future<void> _confirmReset() async {
    final confirmed = await _confirm(
      'Reset all sync credentials?',
      'This stops the server, revokes every device, and removes the password '
          'verifier and TLS key from secure storage.',
      'Reset credentials',
    );
    if (confirmed) await _run(widget.controller.resetCredentials);
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _setPassword() async {
    final first = TextEditingController();
    final second = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set synchronization password'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Use at least 12 characters. The password cannot be recovered.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: first,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: second,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (first.text.length >= 12 && first.text == second.text) {
                Navigator.pop(context, first.text);
              }
            },
            child: const Text('Save securely'),
          ),
        ],
      ),
    );
    first.dispose();
    second.dispose();
    if (password != null) {
      await _run(() => widget.controller.setPassword(password));
    }
  }

  Future<void> _changePort(int current) async {
    final controller = TextEditingController(text: current.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change local sync port'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Port',
            helperText: '49152–65535',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text)),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) await _run(() => widget.controller.setPort(value));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on SyncApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object {
      // Plugin-level failures (secure storage, sockets) must not take down
      // the settings pane.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).syncLoadFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

final class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final SyncServerStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final (label, color, icon) = switch (status.state) {
      SyncServerState.running => (
        'Running · API v1',
        tokens.success,
        Icons.lock_outline,
      ),
      SyncServerState.error => (
        'Needs attention',
        tokens.danger,
        Icons.error_outline,
      ),
      SyncServerState.starting ||
      SyncServerState.stopping => ('Updating', tokens.warning, Icons.sync),
      _ => ('Disabled', tokens.secondaryText, Icons.sync_disabled),
    };
    return Semantics(
      label: 'Local sync status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          border: Border.all(color: color.withValues(alpha: .45)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}

final class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radius),
        boxShadow: [BoxShadow(color: tokens.shadow, blurRadius: 16)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }
}

final class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => ListTile(
    minLeadingWidth: 32,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    leading: Icon(icon, size: 20),
    title: Text(title),
    subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: trailing,
  );
}

final class _PairingCode extends StatelessWidget {
  const _PairingCode({required this.session});
  final PairingSession session;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Pairing code ${session.code}',
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              session.code,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 3,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Expires ${session.expiresAt.toLocal().toIso8601String().split('.').first}',
            ),
          ),
        ],
      ),
    ),
  );
}

final class _PendingDevice extends StatelessWidget {
  const _PendingDevice({
    required this.pending,
    required this.onApprove,
    required this.onReject,
  });

  final PendingPairing pending;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    leading: const Icon(Icons.phonelink_lock_outlined),
    title: Text(pending.deviceName),
    subtitle: Text('Pending explicit approval · ${pending.deviceId}'),
    trailing: Wrap(
      spacing: 8,
      children: [
        TextButton(
          onPressed: onReject,
          child: Text(AppLocalizations.of(context).syncReject),
        ),
        FilledButton(
          onPressed: onApprove,
          child: Text(AppLocalizations.of(context).syncApprove),
        ),
      ],
    ),
  );
}

final class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.onRevoke});
  final SyncDevice device;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
    leading: Icon(
      device.revoked ? Icons.mobile_off_outlined : Icons.phone_android_outlined,
    ),
    title: Row(
      children: [
        Flexible(child: Text(device.name)),
        const SizedBox(width: 8),
        Text(
          device.revoked ? 'Revoked' : 'Active',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    ),
    subtitle: Text(
      'Last seen ${device.lastSeenAt?.toLocal().toIso8601String().split('.').first ?? 'never'}'
      ' · ${device.scopes.map((scope) => scope.wireName).join(', ')}',
    ),
    trailing: TextButton(
      onPressed: onRevoke,
      child: Text(AppLocalizations.of(context).syncRevoke),
    ),
  );
}

final class _EmptySetting extends StatelessWidget {
  const _EmptySetting({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [Icon(icon, size: 18), const SizedBox(width: 9), Text(text)],
    ),
  );
}
