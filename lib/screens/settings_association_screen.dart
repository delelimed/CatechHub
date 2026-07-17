import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/storage/local_database.dart';
import '../models/association_models.dart';
import '../services/security_service.dart';
import '../services/nearby_sync_service.dart';

class SettingsAssociationScreen extends StatefulWidget {
  const SettingsAssociationScreen({super.key});

  @override
  State<SettingsAssociationScreen> createState() =>
      _SettingsAssociationScreenState();
}

class _SettingsAssociationScreenState
    extends State<SettingsAssociationScreen> {
  final AssociationSecurityService _security = AssociationSecurityService();
  final NearbySyncService _syncService = NearbySyncService();

  SyncRole _selectedRole = SyncRole.mioDispositivo;
  List<DeviceAssociation> _associations = [];
  bool _isLoading = true;
  bool _isPairingMode = false;
  bool _showScanner = false;
  String? _qrData;
  String? _errorMessage;
  MobileScannerController? _scannerController;
  StreamSubscription<NearbySyncState>? _syncStateSub;

  @override
  void initState() {
    super.initState();
    _initData();
    _syncStateSub = _syncService.onStateChanged.listen(_onSyncStateChanged);
    _startPairingMode();
  }

  @override
  void dispose() {
    _syncStateSub?.cancel();
    _stopPairingMode();
    _stopScanner();
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    try {
      await _syncService.init();
      final assocs = await _security.getAllAssociations();
      final qrData = await _generateQrData();

      if (mounted) {
        setState(() {
          _associations = assocs;
          _qrData = qrData;
          _selectedRole = _syncService.currentState.role;
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
    final deviceId = await _security.getOrCreateDeviceId();
    final deviceName = _getDeviceDisplayName();
    final publicKeyHex = await _security.getLocalPublicKeyHex();

    final handshake = QrHandshake(
      deviceId: deviceId,
      deviceName: deviceName,
      publicKeyHex: publicKeyHex,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    return handshake.encode();
  }

  String _getDeviceDisplayName() {
    try {
      final auth = LocalDatabase.auth();
      final name = auth.get('local_user_name', defaultValue: '') as String;
      if (name.trim().isNotEmpty) return name.trim();
    } catch (_) {}
    return 'Il mio CatechHub';
  }

  void _onSyncStateChanged(NearbySyncState state) {
    if (!mounted) return;

    if (state.status == NearbySyncStatus.completed && state.connectedDeviceName != null) {
      _refreshAssociations();
      setState(() {
        _isPairingMode = false;
        _errorMessage = 'Associazione completata con ${state.connectedDeviceName}';
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
    await _syncService.startPairingMode();
  }

  Future<void> _stopPairingMode() async {
    if (_isPairingMode) {
      await _syncService.stopPairingMode();
    }
  }

  void _showQrScanner() {
    setState(() {
      _showScanner = true;
      _errorMessage = null;
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

      final handshake = QrHandshake.decode(raw);
      if (handshake == null) {
        setState(() => _errorMessage = 'QR code non valido.');
        return;
      }

      if (!handshake.isFresh) {
        setState(() => _errorMessage = 'QR code scaduto. '
            'L\'altro dispositivo deve generarne uno nuovo.');
        return;
      }

      final existing = await _security.getAssociation(handshake.deviceId);
      if (existing != null) {
        setState(() => _errorMessage = 'Dispositivo già associato.');
        return;
      }

      try {
        final sharedSecret =
            await _security.computeSharedSecretHex(handshake.publicKeyHex);

        final association = DeviceAssociation(
          deviceId: handshake.deviceId,
          deviceName: handshake.deviceName,
          sharedSecretHex: sharedSecret,
          associatedAt: DateTime.now(),
        );

        await _security.saveAssociation(association);
        await _refreshAssociations();

        if (mounted) {
          setState(() {
            _errorMessage = 'Associazione completata con ${handshake.deviceName}';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() => _errorMessage = 'Errore associazione: $e');
        }
      }

      return;
    }
  }

  Future<void> _refreshAssociations() async {
    final assocs = await _security.getAllAssociations();
    if (mounted) {
      setState(() => _associations = assocs);
    }
  }

  Future<void> _removeAssociation(DeviceAssociation assoc) async {
    await _security.removeAssociation(assoc.deviceId);
    await _refreshAssociations();
  }

  Future<void> _confirmRemoveAssociation(DeviceAssociation assoc) async {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Associazione Dispositivi'),
        backgroundColor: colorScheme.primaryContainer,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildRoleSelector(theme, colorScheme),
                  const SizedBox(height: 16),
                  _buildQrSection(theme, colorScheme),
                  const SizedBox(height: 16),
                  _buildScannerSection(theme),
                  const SizedBox(height: 16),
                  if (_errorMessage != null) _buildErrorBanner(theme),
                  const SizedBox(height: 16),
                  _buildAssociatedDevicesSection(theme, colorScheme),
                ],
              ),
            ),
    );
  }

  Widget _buildRoleSelector(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ruolo del dispositivo',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            RadioGroup<SyncRole>(
              groupValue: _selectedRole,
              onChanged: (role) {
                if (role == null) return;
                setState(() => _selectedRole = role);
                _syncService.setRole(role);
              },
              child: Column(
                children: [
                  RadioListTile<SyncRole>(
                    title: const Text('Mio Dispositivo'),
                    subtitle: const Text('Sincronizzazione automatica'),
                    secondary: const Icon(Icons.sync),
                    value: SyncRole.mioDispositivo,
                  ),
                  RadioListTile<SyncRole>(
                    title: const Text('Altro Catechista'),
                    subtitle: const Text('Chiede conferma prima di sincronizzare'),
                    secondary: const Icon(Icons.how_to_reg),
                    value: SyncRole.altroCatechista,
                  ),
                  RadioListTile<SyncRole>(
                    title: Text(
                      'Responsabile',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                    subtitle: Text(
                      'Funzione Responsabile non ancora implementata',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                    secondary: Icon(Icons.admin_panel_settings, color: Colors.grey[500]),
                    value: SyncRole.responsabile,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrSection(ThemeData theme, ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.qr_code_2, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Il mio codice QR',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_qrData != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
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
                  size: 200,
                  backgroundColor: Colors.white,
                ),
              ),
            const SizedBox(height: 12),
            if (!_isPairingMode)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startPairingMode,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('Attendi associazione'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _stopPairingMode,
                  icon: const Icon(Icons.stop),
                  label: const Text('Ferma attesa'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            if (_isPairingMode) ...[
              const SizedBox(height: 12),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'In attesa di un dispositivo vicino...',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScannerSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.qr_code_scanner, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Scansiona QR partner',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_showScanner && _scannerController != null)
              SizedBox(
                height: 250,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: MobileScanner(
                    controller: _scannerController!,
                    onDetect: _onQrScanned,
                  ),
                ),
              )
            else if (_showScanner)
              const SizedBox(
                height: 250,
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 12),
            if (!_showScanner)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showQrScanner,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Scansiona QR code'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _stopScanner,
                  icon: const Icon(Icons.close),
                  label: const Text('Chiudi scanner'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
          ],
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Dispositivi associati',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_associations.length}',
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_associations.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.link_off,
                          size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text(
                        'Nessun dispositivo associato',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Scansiona il QR di un altro dispositivo\no mostralo per associarli.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _associations.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final assoc = _associations[index];
                  return _buildAssociationTile(assoc);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssociationTile(DeviceAssociation assoc) {
    final daysLeft = assoc.daysRemaining;
    final isExpiring = daysLeft <= 5;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: CircleAvatar(
        backgroundColor:
            isExpiring ? Colors.orange.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.15),
        child: Icon(
          isExpiring ? Icons.timer : Icons.check_circle,
          color: isExpiring ? Colors.orange : Colors.green,
        ),
      ),
      title: Text(
        assoc.deviceName,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            assoc.deviceId.length > 24
                ? '${assoc.deviceId.substring(0, 24)}...'
                : assoc.deviceId,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          Text(
            isExpiring
                ? 'Scade tra $daysLeft giorni'
                : '${assoc.daysRemaining} giorni rimanenti',
            style: TextStyle(
              fontSize: 12,
              color: isExpiring ? Colors.orange[700] : Colors.grey[600],
              fontWeight: isExpiring ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        onPressed: () => _confirmRemoveAssociation(assoc),
        tooltip: 'Rimuovi',
      ),
    );
  }
}
