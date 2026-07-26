import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

  P2PSyncRole _selectedRole = P2PSyncRole.mioDispositivo;
  List<P2PDeviceAssociation> _associations = [];
  bool _isLoading = true;
  bool _isPairingMode = false;
  bool _showScanner = false;
  bool _showAssociationPanel = false;
  String? _qrData;
  String? _errorMessage;
  MobileScannerController? _scannerController;
  bool _qrScanJustCompleted = false;
  String? _lastScannedDeviceName;
  Timer? _reciprocalCheckTimer;

  @override
  void initState() {
    super.initState();
    _initData();

    ref.listen<AsyncValue<P2PSyncState>>(nearbySyncStateProvider,
        (previous, next) {
      next.whenData(_onSyncStateChanged);
    });
  }

  @override
  void dispose() {
    _stopPairingMode();
    _stopScanner();
    _reciprocalCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    try {
      final syncService = ref.read(nearbySyncServiceProvider);
      await syncService.init();
      final assocs = await _security.getAllAssociations();
      final qrData = await _generateQrData();

      if (mounted) {
        setState(() {
          _associations = assocs;
          _qrData = qrData;
          _selectedRole = syncService.currentState.role;
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

  Future<String> _generateQrData() async {
    return _security.generateQrPayload();
  }

  void _onSyncStateChanged(P2PSyncState state) {
    if (!mounted) return;

    if (state.status == P2PSyncStatus.completed &&
        state.connectedDeviceName != null) {
      _refreshAssociations();
      setState(() {
        _isPairingMode = false;
        _errorMessage =
            'Associazione completata con ${state.connectedDeviceName}';
      });
    }

    if (state.errorMessage != null) {
      setState(() => _errorMessage = state.errorMessage);
    }
  }

  Future<void> _startPairingMode() async {
    setState(() {
      _isPairingMode = true;
      _errorMessage = null;
    });
    final syncService = ref.read(nearbySyncServiceProvider);
    await syncService.startPairingMode();
  }

  Future<void> _stopPairingMode() async {
    if (_isPairingMode) {
      final syncService = ref.read(nearbySyncServiceProvider);
      await syncService.stopPairingMode();
    }
  }

  void _showQrScanner() {
    setState(() {
      _showScanner = true;
      _errorMessage = null;
      _qrScanJustCompleted = false;
      _lastScannedDeviceName = null;
    });
    _startScanner();
  }

  void _startScanner() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
    _scannerController!.start();
  }

  void _stopScanner() {
    try {
      _scannerController?.stop();
      _scannerController?.dispose();
    } catch (_) {}
    _scannerController = null;
    _showScanner = false;
  }

  Future<void> _onQrScanned(BarcodeCapture capture) async {
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;

      _stopScanner();

      final remoteIdentity = P2PSecurityService.parseQrPayload(raw);
      if (remoteIdentity == null) {
        setState(() => _errorMessage = 'QR code non valido.');
        return;
      }

      final existing = await _security.getAssociation(remoteIdentity.deviceId);
      if (existing != null) {
        setState(() => _errorMessage = 'Dispositivo già associato.');
        return;
      }

      try {
        final syncService = ref.read(nearbySyncServiceProvider);
        final localRole = syncService.currentState.role.name;

        final sharedSecret = await _security.computeStaticSharedSecret(
            remoteIdentity.publicKeyBase64,
            forDeviceId: remoteIdentity.deviceId);

        await _security.registerAndSaveAssociation(
          deviceId: remoteIdentity.deviceId,
          deviceName: remoteIdentity.deviceName,
          publicKeyBase64: remoteIdentity.publicKeyBase64,
          fingerprint: remoteIdentity.fingerprint,
          sharedSecretBase64: sharedSecret,
          localRole: localRole,
        );
        await _refreshAssociations();

        if (mounted) {
          setState(() {
            _qrScanJustCompleted = true;
            _lastScannedDeviceName = remoteIdentity.deviceName;
            _errorMessage = 'Associazione salvata: ${remoteIdentity.deviceName}';
          });
        }

        _startReciprocalCheck(remoteIdentity.deviceId);

        if (mounted) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Associazione salvata!'),
              content: Text(
                'Ora mostra il tuo QR all\'altro dispositivo (${remoteIdentity.deviceName}) '
                'affinché possa completare l\'associazione reciproca.\n\n'
                'L\'altro catechista deve scansionare il tuo QR usando il pulsante '
                '"Scansiona QR partner".',
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Ok, mostra il mio QR'),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          setState(() => _errorMessage = 'Errore associazione: $e');
        }
      }

      return;
    }
  }

  void _startReciprocalCheck(String scannedDeviceId) {
    _reciprocalCheckTimer?.cancel();
    final initialCount = _associations.length;
    _reciprocalCheckTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final current = await _security.getAllAssociations();
      if (current.length > initialCount) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _associations = current;
            _qrScanJustCompleted = false;
            _errorMessage = 'Associazione reciproca completata!';
          });
        }
      }
    });

    Future.delayed(const Duration(seconds: 30), () {
      _reciprocalCheckTimer?.cancel();
    });
  }

  Future<void> _refreshAssociations() async {
    final assocs = await _security.getAllAssociations();
    if (mounted) {
      setState(() => _associations = assocs);
    }
  }

  Future<void> _removeAssociation(P2PDeviceAssociation assoc) async {
    await _security.removeAssociation(assoc.deviceId);
    ref.read(nearbySyncServiceProvider).addLog(
        'INFO', 'Dispositivo rimosso: ${assoc.deviceName}');
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
                  _buildSectionHeader(theme, Icons.devices, 'Dispositivi associati'),
                  const SizedBox(height: 8),
                  _buildAssociatedDevicesSection(theme, colorScheme),
                  const SizedBox(height: 20),
                  _buildLogButton(theme, colorScheme),
                  const SizedBox(height: 16),
                  _buildAssociationExpandable(theme, colorScheme),
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

  Widget _buildAssociationExpandable(
      ThemeData theme, ColorScheme colorScheme) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: _showAssociationPanel,
        onExpansionChanged: (expanded) {
          setState(() => _showAssociationPanel = expanded);
        },
        leading: Icon(Icons.qr_code_2, color: colorScheme.primary),
        title: Text(
          'Associazione dispositivi',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'Associa un nuovo dispositivo via QR code',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                _buildRoleSelector(theme, colorScheme),
                const SizedBox(height: 12),
                _buildQrSection(theme, colorScheme),
                const SizedBox(height: 12),
                _buildScannerSection(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSelector(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ruolo del dispositivo',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        RadioGroup<P2PSyncRole>(
          groupValue: _selectedRole,
          onChanged: (role) {
            if (role == null) return;
            setState(() => _selectedRole = role);
            ref.read(nearbySyncServiceProvider).setRole(role);
          },
          child: Column(
            children: [
              RadioListTile<P2PSyncRole>(
                title: const Text('Mio Dispositivo'),
                subtitle: const Text('Sincronizzazione automatica'),
                secondary: const Icon(Icons.sync),
                value: P2PSyncRole.mioDispositivo,
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<P2PSyncRole>(
                title: const Text('Altro Catechista'),
                subtitle: const Text('Chiede conferma prima di sincronizzare'),
                secondary: const Icon(Icons.how_to_reg),
                value: P2PSyncRole.altroCatechista,
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<P2PSyncRole>(
                title: Text(
                  'Responsabile',
                  style: TextStyle(color: Colors.grey[500]),
                ),
                subtitle: Text(
                  'Funzione non ancora implementata',
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
                secondary: Icon(Icons.admin_panel_settings,
                    color: Colors.grey[500]),
                value: P2PSyncRole.responsabile,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQrSection(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _qrScanJustCompleted ? Icons.check_circle : Icons.qr_code_2,
              color: _qrScanJustCompleted ? Colors.green : colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'Il mio codice QR',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_qrScanJustCompleted && _lastScannedDeviceName != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700], size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hai salvato $_lastScannedDeviceName. Ora mostra questo QR all\'altro dispositivo.',
                    style: TextStyle(fontSize: 12, color: Colors.green[800]),
                  ),
                ),
              ],
            ),
          ),
        if (_qrData != null)
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: QrImageView(
                data: _qrData!,
                version: QrVersions.auto,
                size: 160,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (!_isPairingMode)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startPairingMode,
              icon: const Icon(Icons.wifi_tethering, size: 18),
              label: const Text('Attendi associazione'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _stopPairingMode,
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Ferma attesa'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        if (_isPairingMode) ...[
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text(
                'In attesa di un dispositivo vicino...',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildScannerSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(_qrScanJustCompleted
                ? Icons.check_circle_outline
                : Icons.qr_code_scanner,
                color: _qrScanJustCompleted ? Colors.green : theme.colorScheme.primary,
                size: 20),
            const SizedBox(width: 8),
            Text(
              'Scansiona QR partner',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_qrScanJustCompleted)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Chiedi all\'altro catechista di scansionare il tuo QR.',
                    style: TextStyle(fontSize: 12, color: Colors.blue[800]),
                  ),
                ),
              ],
            ),
          ),
        if (_showScanner && _scannerController != null)
          SizedBox(
            height: 200,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: MobileScanner(
                controller: _scannerController!,
                onDetect: _onQrScanned,
              ),
            ),
          )
        else if (_showScanner)
          const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          ),
        const SizedBox(height: 8),
        if (!_showScanner)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showQrScanner,
              icon: const Icon(Icons.camera_alt, size: 18),
              label: const Text('Scansiona QR code'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _stopScanner,
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Chiudi scanner'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
      ],
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
              'Espandi "Associazione dispositivi" qui sotto\nper associare un nuovo dispositivo.',
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
