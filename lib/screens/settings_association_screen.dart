import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/providers/nearby_sync_provider.dart';
import '../features/sync/p2p/p2p_sync_service.dart';
import '../features/sync/p2p/p2p_security_service.dart';

class SettingsAssociationScreen extends ConsumerStatefulWidget {
  const SettingsAssociationScreen({super.key});

  @override
  ConsumerState<SettingsAssociationScreen> createState() =>
      _SettingsAssociationScreenState();
}

class _SettingsAssociationScreenState
    extends ConsumerState<SettingsAssociationScreen> {
  final P2PSecurityService _security = P2PSecurityService();

  List<P2PDeviceAssociation> _associations = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    try {
      final syncService = ref.read(nearbySyncServiceProvider);
      await syncService.init();
      final assocs = await _security.getAllAssociations();

      if (mounted) {
        setState(() {
          _associations = assocs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Errore caricamento: $e';
        });
      }
    }
  }

  Future<void> _refreshAssociations() async {
    final assocs = await _security.getAllAssociations();
    if (mounted) {
      setState(() => _associations = assocs);
    }
  }

  Future<void> _removeAssociation(P2PDeviceAssociation assoc) async {
    final syncService = ref.read(nearbySyncServiceProvider);
    await syncService.removeAssociationAndCleanup(assoc.deviceId);
    syncService.addLog('INFO', 'Dispositivo rimosso: ${assoc.deviceName}');
    await _refreshAssociations();
  }

  Future<void> _confirmRemoveAssociation(P2PDeviceAssociation assoc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovi dispositivo'),
        content: Text(
          'Rimuovere "${assoc.deviceName}" dalla lista dei dispositivi associati?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _removeAssociation(assoc);
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'mioDispositivo':
        return 'Registrato come: Mio Dispositivo';
      case 'altroCatechista':
        return 'Registrato come: Altro Catechista';
      default:
        return 'In attesa di sincronizzazione...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSyncEnabled = ref.watch(nearbySyncDaemonProvider);
    final syncState = ref.watch(nearbySyncStateProvider);

    final isSyncing = syncState.when(
      data: (state) =>
          state.status == P2PSyncStatus.discovering ||
          state.status == P2PSyncStatus.syncing,
      loading: () => false,
      error: (_, _) => false,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincronizzazione Nearby',
            style: TextStyle(color: Colors.white)),
        backgroundColor: colorScheme.primary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildBetaWarning(theme, colorScheme),
                  const SizedBox(height: 16),
                  _buildStatusLegend(theme, colorScheme),
                  const SizedBox(height: 12),
                  _buildSyncToggle(theme, colorScheme, isSyncEnabled),
                  const SizedBox(height: 12),
                  _buildManualSyncButton(theme, colorScheme, isSyncing),
                  const SizedBox(height: 20),
                  _buildAssociateButton(theme, colorScheme),
                  const SizedBox(height: 20),
                  _buildSectionHeader(theme, Icons.devices, 'Dispositivi associati'),
                  const SizedBox(height: 8),
                  _buildAssociatedDevicesSection(theme, colorScheme),
                  const SizedBox(height: 20),
                  _buildLogButton(theme, colorScheme),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    _buildErrorBanner(theme),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(
      ThemeData theme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(icon == Icons.devices
                ? context
                : context)
            .colorScheme
            .primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildBetaWarning(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.amber[800], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sync Nearby in fase beta',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber[900],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'La sincronizzazione Bluetooth è ancora in fase di sviluppo. '
                  'Per scambiare dati in modo affidabile, utilizza la scansione QR '
                  'o esporta un file di backup dalle impostazioni.',
                  style: TextStyle(fontSize: 13, color: Colors.amber[900]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusLegend(ThemeData theme, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text(
                'Legenda stato sincronizzazione',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _legendItem(Colors.red, 'Inattivo / nessun sync'),
              _legendItem(Colors.amber, 'Dispositivi vicini trovati'),
              _legendItem(Colors.green, 'Sync in corso'),
              _legendItem(Colors.cyan, 'Dati aggiornati'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildSyncToggle(
      ThemeData theme, ColorScheme colorScheme, bool isEnabled) {
    final daemonController = ref.read(nearbySyncDaemonProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isEnabled
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isEnabled ? Icons.sync : Icons.sync_disabled,
                color: isEnabled ? Colors.green : Colors.grey,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sincronizzazione automatica',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isEnabled
                        ? 'Attiva — ricerca dispositivi ogni 60s'
                        : 'Disattivata — nessuna sincronizzazione in background',
                    style: TextStyle(
                      fontSize: 12,
                      color: isEnabled ? Colors.green[700] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: isEnabled,
              activeTrackColor: Colors.green.withValues(alpha: 0.5),
              activeThumbColor: Colors.green,
              onChanged: (value) {
                daemonController.setSyncEnabled(value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualSyncButton(
      ThemeData theme, ColorScheme colorScheme, bool isSyncing) {
    final daemonController = ref.read(nearbySyncDaemonProvider.notifier);

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: isSyncing
            ? null
            : () async {
                await daemonController.triggerManualSync();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sincronizzazione manuale avviata'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
        icon: isSyncing
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.sync, size: 22),
        label: Text(
          isSyncing ? 'Sincronizzazione in corso...' : 'Avvia sincronizzazione manuale',
        ),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildAssociateButton(ThemeData theme, ColorScheme colorScheme) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => context.push('/settings/associate-device').then((_) {
          _refreshAssociations();
        }),
        icon: const Icon(Icons.qr_code_2, size: 20),
        label: const Text('Associa un nuovo dispositivo'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildLogButton(ThemeData theme, ColorScheme colorScheme) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => context.push('/settings/sync-log'),
        icon: const Icon(Icons.history, size: 20),
        label: const Text('Visualizza log di sincronizzazione'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          foregroundColor: colorScheme.primary,
          side: BorderSide(color: colorScheme.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _errorMessage = null),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildAssociatedDevicesSection(
      ThemeData theme, ColorScheme colorScheme) {
    if (_associations.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(Icons.link_off, size: 48, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              'Nessun dispositivo associato',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.grey[500],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Premi "Associa un nuovo dispositivo"\nper iniziare.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < _associations.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _buildAssociationCard(_associations[i], theme, colorScheme),
        ],
      ],
    );
  }

  Widget _buildAssociationCard(
      P2PDeviceAssociation assoc, ThemeData theme, ColorScheme colorScheme) {
    final daysLeft = assoc.daysRemaining;
    final isExpiring = daysLeft <= 5;
    final isExpired = daysLeft == 0;
    final assocDate = _formatDate(assoc.associatedAt);

    return Container(
      decoration: BoxDecoration(
        color: isExpired
            ? Colors.red.withValues(alpha: 0.05)
            : isExpiring
                ? Colors.orange.withValues(alpha: 0.05)
                : Colors.green.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isExpired
              ? Colors.red.withValues(alpha: 0.2)
              : isExpiring
                  ? Colors.orange.withValues(alpha: 0.2)
                  : Colors.green.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: isExpired
                  ? Colors.red.withValues(alpha: 0.15)
                  : isExpiring
                      ? Colors.orange.withValues(alpha: 0.15)
                      : Colors.green.withValues(alpha: 0.15),
              child: Icon(
                isExpired
                    ? Icons.block
                    : isExpiring
                        ? Icons.timer
                        : Icons.check_circle,
                color: isExpired
                    ? Colors.red
                    : isExpiring
                        ? Colors.orange
                        : Colors.green,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assoc.deviceName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        'Associato il $assocDate',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.hourglass_bottom,
                          size: 12,
                          color: isExpired
                              ? Colors.red[400]
                              : isExpiring
                                  ? Colors.orange[400]
                                  : Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        isExpired
                            ? 'Associazione scaduta'
                            : 'Scade tra $daysLeft giorni',
                        style: TextStyle(
                          fontSize: 12,
                          color: isExpired
                              ? Colors.red[600]
                              : isExpiring
                                  ? Colors.orange[700]
                                  : Colors.grey[600],
                          fontWeight:
                              isExpiring ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.sync,
                          size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        _roleLabel(assoc.remoteRole),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!isExpired)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _confirmRemoveAssociation(assoc),
                tooltip: 'Rimuovi',
              ),
          ],
        ),
      ),
    );
  }
}
