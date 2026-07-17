import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/app_scaffold.dart';
import '../data/classic_sync_models.dart';
import '../domain/classic_sync_provider.dart';

/// Dashboard principale per la sincronizzazione Bluetooth Classico.
///
/// CONTESTO PROGETTO:
/// Pagina principale del feature di sincronizzazione. Mostra:
/// - Stato associazione (dispositivi fidati, count, scadenza chiavi)
/// - Selettore ruolo (Mio Dispositivo / Altro Catechista / Responsabile)
/// - Stato della sincronizzazione (inattivo, connessione, sync, errore)
/// - Pulsanti: Sincronizza (scan + sync), Aggiorna (force sync)
/// - Gestione dispositivi (elimina singolo device o tutti)
/// - Istruzioni per l'uso
///
/// Usa [ClassicSyncNotifier] via Riverpod per leggere e modificare
/// lo stato. Le azioni UI chiamano i metodi del notifier che a loro
/// volta usano [ClassicConnectionManager] e [ClassicSyncEngine].
///
/// Router: /ble-sync (dashboard), /classic-pairing (pairing)
class ClassicSyncDashboardPage extends ConsumerStatefulWidget {
  const ClassicSyncDashboardPage({super.key});

  @override
  ConsumerState<ClassicSyncDashboardPage> createState() =>
      _ClassicSyncDashboardPageState();
}

class _ClassicSyncDashboardPageState
    extends ConsumerState<ClassicSyncDashboardPage> {
  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(classicSyncProvider);

    return AppScaffold(
      title: 'Sincronizzazione Bluetooth',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildWorkInProgressBanner(),
            const SizedBox(height: 16),
            _buildPairingStatusCard(syncState),
            const SizedBox(height: 16),
            _buildRoleSelector(syncState),
            const SizedBox(height: 16),
            _buildSyncStatusCard(syncState),
            const SizedBox(height: 16),
            _buildControls(syncState),
            if (syncState.errorMessage != null) ...[
              const SizedBox(height: 16),
              _buildErrorMessage(syncState.errorMessage!),
            ],
            const SizedBox(height: 16),
            if (syncState.isPaired &&
                (syncState.keyExpiryDate != null ||
                    syncState.isKeyRenewalNeeded)) ...[
              _buildKeyExpiryCard(syncState),
              const SizedBox(height: 16),
            ],
            _buildInstructionsCard(syncState),
          ],
        ),
      ),
    );
  }

  Widget _buildPairingStatusCard(ClassicSyncUiState state) {
    final isPaired = state.isPaired;
    final deviceCount = state.trustedDevices.length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isPaired
            ? Colors.green.withValues(alpha: 0.08)
            : Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPaired
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isPaired
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPaired ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  color: isPaired ? Colors.green : Colors.orange,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPaired ? 'Dispositivi associati' : 'Nessun dispositivo associato',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isPaired ? Colors.green[800] : Colors.orange[800],
                      ),
                    ),
                    if (isPaired)
                      Text(
                        '$deviceCount ${deviceCount == 1 ? "dispositivo" : "dispositivi"} connesso${deviceCount == 1 ? "" : "i"}',
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (isPaired) ...[
            const SizedBox(height: 12),
            ...state.trustedDevices.map((device) => _buildDeviceTile(device, state)),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/classic-pairing'),
              icon: Icon(isPaired ? Icons.add : Icons.bluetooth_searching),
              label: Text(isPaired ? 'Aggiungi dispositivo' : 'Associa dispositivo'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(TrustedDevice device, ClassicSyncUiState state) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF174A7E).withValues(alpha: 0.1),
        child: const Icon(Icons.phone_android, color: Color(0xFF174A7E)),
      ),
      title: Text(device.cleanDisplayName),
      subtitle: Text(
        'Ultima sync: ${device.lastSyncedAt != null ? _formatDate(device.lastSyncedAt!) : 'Mai'}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        onPressed: () => _confirmDeleteDevice(device),
      ),
    );
  }

  Widget _buildRoleSelector(ClassicSyncUiState state) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: RadioGroup<ClassicSyncRole>(
        groupValue: state.role,
        onChanged: (value) {
          if (value != null) {
            ref.read(classicSyncProvider.notifier).setSyncRole(value);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ruolo del dispositivo',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildRoleOption(
              title: 'Mio Dispositivo',
              subtitle: 'Sincronizzazione automatica',
              icon: Icons.sync,
              role: ClassicSyncRole.mioDispositivo,
              currentRole: state.role,
            ),
            _buildRoleOption(
              title: 'Altro Catechista',
              subtitle: 'Chiede conferma prima di sincronizzare',
              icon: Icons.how_to_reg,
              role: ClassicSyncRole.altroCatechista,
              currentRole: state.role,
            ),
            _buildRoleOption(
              title: 'Responsabile',
              subtitle: 'Non ancora implementato',
              icon: Icons.admin_panel_settings,
              role: ClassicSyncRole.responsabile,
              currentRole: state.role,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleOption({
    required String title,
    required String subtitle,
    required IconData icon,
    required ClassicSyncRole role,
    required ClassicSyncRole currentRole,
  }) {
    final isSelected = currentRole == role;
    final isDisabled = role == ClassicSyncRole.responsabile;

    return RadioListTile<ClassicSyncRole>(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: isDisabled ? Colors.grey : null,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: isDisabled ? Colors.grey : Colors.grey[600],
        ),
      ),
      secondary: Icon(icon, color: isSelected ? const Color(0xFF174A7E) : Colors.grey),
      value: role,
    );
  }

  Widget _buildSyncStatusCard(ClassicSyncUiState state) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Stato sincronizzazione',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                _getStatusIcon(state.status),
                color: _getStatusColor(state.status),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  state.statusMessage,
                  style: TextStyle(
                    fontSize: 14,
                    color: _getStatusColor(state.status),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (state.lastSyncAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Ultima sincronizzazione: ${_formatDate(state.lastSyncAt!)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
          if (state.totalQueueSize > 1 && state.isBackgroundSyncActive) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (state.currentQueueIndex + 1) / state.totalQueueSize,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF174A7E)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildControls(ClassicSyncUiState state) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: state.isPaired && !state.isBackgroundSyncActive
                ? () => ref.read(classicSyncProvider.notifier).startScanAndSync()
                : null,
            icon: const Icon(Icons.sync),
            label: const Text('Sincronizza'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF174A7E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: state.isPaired
                ? () => ref.read(classicSyncProvider.notifier).forceSync()
                : null,
            icon: const Icon(Icons.refresh),
            label: const Text('Aggiorna'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorMessage(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.red),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildKeyExpiryCard(ClassicSyncUiState state) {
    final daysLeft = state.daysUntilKeyExpiry ?? 30;
    final needsRenewal = state.isKeyRenewalNeeded;
    final isExpired = state.isKeyExpired;

    final Color cardColor;
    final Color textColor;
    final IconData icon;

    if (isExpired) {
      cardColor = Colors.red;
      textColor = Colors.red[800]!;
      icon = Icons.timer_off;
    } else if (needsRenewal) {
      cardColor = Colors.orange;
      textColor = Colors.orange[800]!;
      icon = Icons.warning_amber;
    } else {
      cardColor = Colors.blue;
      textColor = Colors.blue[800]!;
      icon = Icons.timer;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cardColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: cardColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isExpired
                      ? 'Chiave scaduta!'
                      : needsRenewal
                          ? 'Rinnovo chiave consigliato'
                          : 'Scadenza chiave: $daysLeft giorni rimanenti',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
                if (needsRenewal && !isExpired)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Riesegui il pairing per rinnovare la chiave '
                      'prima della scadenza.',
                      style: TextStyle(fontSize: 11, color: textColor),
                    ),
                  ),
                if (isExpired)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'La chiave e scaduta. Riesegui il pairing '
                      'per continuare a sincronizzare.',
                      style: TextStyle(fontSize: 11, color: textColor),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsCard(ClassicSyncUiState state) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Come funziona',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildInstructionStep(1, 'Associa i dispositivi tramite QR code'),
          _buildInstructionStep(2, 'Scegli il ruolo (Mio Dispositivo / Altro Catechista)'),
          _buildInstructionStep(3, 'Avvia la sincronizzazione quando i dispositivi sono vicini'),
          _buildInstructionStep(4, 'I dati vengono scambiati automaticamente via Bluetooth'),
        ],
      ),
    );
  }

  Widget _buildInstructionStep(int step, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: const Color(0xFF174A7E),
            child: Text(
              '$step',
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteDevice(TrustedDevice device) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina dispositivo'),
        content: Text(
          'Vuoi eliminare "${device.cleanDisplayName}" dalla lista dei dispositivi associati?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref
                  .read(classicSyncProvider.notifier)
                  .deleteTrustedDevice(device.deviceId);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
  }

  IconData _getStatusIcon(ClassicSyncStatus status) {
    switch (status) {
      case ClassicSyncStatus.idle:
        return Icons.check_circle_outline;
      case ClassicSyncStatus.pairing:
        return Icons.link;
      case ClassicSyncStatus.scanning:
        return Icons.bluetooth_searching;
      case ClassicSyncStatus.connecting:
        return Icons.sync_problem;
      case ClassicSyncStatus.connected:
        return Icons.bluetooth_connected;
      case ClassicSyncStatus.syncing:
        return Icons.sync;
      case ClassicSyncStatus.completed:
        return Icons.check_circle;
      case ClassicSyncStatus.error:
        return Icons.error;
      case ClassicSyncStatus.keyExpired:
        return Icons.timer_off;
    }
  }

  Color _getStatusColor(ClassicSyncStatus status) {
    switch (status) {
      case ClassicSyncStatus.idle:
        return Colors.grey;
      case ClassicSyncStatus.pairing:
      case ClassicSyncStatus.scanning:
      case ClassicSyncStatus.connecting:
        return Colors.orange;
      case ClassicSyncStatus.connected:
      case ClassicSyncStatus.syncing:
        return const Color(0xFF174A7E);
      case ClassicSyncStatus.completed:
        return Colors.green;
      case ClassicSyncStatus.error:
        return Colors.red;
      case ClassicSyncStatus.keyExpired:
        return Colors.orange;
    }
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  Widget _buildWorkInProgressBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.construction_rounded, color: Colors.orange.shade700, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sincronizzazione Bluetooth in fase di implementazione. '
              'Al momento la funzionalità non è attiva.',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
