import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../shared/widgets/app_scaffold.dart';
import '../data/association_models.dart';
import '../p2p/p2p_security_service.dart';

/// Centro di controllo della Catena di Fiducia del Responsabile.
///
/// Due modalità d'uso:
///  1. Sul dispositivo del RESPONSABILE: genera il "QR di fiducia" (segreto
///     della parrocchia) da far scansionare UNA volta al dispositivo che
///     farà da PRIMARY, e approva/firma i dispositivi autorizzati a
///     sincronizzare le classi (generando per ognuno un QR di approvazione).
///  2. Su un dispositivo APPROVATO/VERIFICATORE: scansiona il QR di fiducia
///     (per importare il segreto) o il QR di approvazione del Responsabile
///     (per ricevere il certificato e poter sincronizzare).
class ApprovalCenterPage extends ConsumerStatefulWidget {
  const ApprovalCenterPage({super.key});

  @override
  ConsumerState<ApprovalCenterPage> createState() =>
      _ApprovalCenterPageState();
}

class _ApprovalCenterPageState extends ConsumerState<ApprovalCenterPage> {
  static const _trustQrPrefix = 'CatechHub_TRUST_v1|';
  static const _approvalQrPrefix = 'CatechHub_APPROVAL_v1|';

  final P2PSecurityService _security = P2PSecurityService();

  bool _isLoading = true;
  bool _responsabileMode = false;
  List<P2PDeviceAssociation> _associations = [];
  Map<String, dynamic>? _trustInfo;
  AssociatedDevice? _localApproval;

  // Stato UI QR
  String? _trustQrData;
  String? _selectedApprovalQrData;
  bool _scanTrust = false;
  bool _scanApproval = false;
  MobileScannerController? _scannerController;
  bool _scanPaused = false;
  String? _scanMessage;
  bool _approvalInProgress = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    final mode = await _security.isResponsabileModeActive();
    final associations = await _security.getAllAssociations();
    final trustInfo = await _security.getResponsabileTrustInfo();
    final localApproval = await _security.getLocalApproval();
    if (!mounted) return;
    setState(() {
      _responsabileMode = mode;
      _associations = associations;
      _trustInfo = trustInfo;
      _localApproval = localApproval;
      _isLoading = false;
    });
  }

  Future<void> _refresh() async {
    await _initData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stato aggiornato.')),
      );
    }
  }

  Future<void> _generateTrustQr() async {
    final secret = await _security.getOrCreateParishApprovalSecret();
    final identity = await _security.getLocalIdentity();
    final payload = _trustQrPrefix +
        jsonEncode({
          'responsabileDeviceId': identity.deviceId,
          'responsabileName': identity.username,
          'approvalSecret': secret,
        });
    if (!mounted) return;
    setState(() {
      _trustQrData = payload;
      _scanTrust = false;
      _scanApproval = false;
    });
  }

  Future<void> _startScanTrust() async {
    setState(() {
      _scanTrust = true;
      _scanApproval = false;
      _trustQrData = null;
      _selectedApprovalQrData = null;
    });
    _ensureScanner();
  }

  Future<void> _startScanApproval() async {
    setState(() {
      _scanApproval = true;
      _scanTrust = false;
      _trustQrData = null;
      _selectedApprovalQrData = null;
    });
    _ensureScanner();
  }

  void _ensureScanner() {
    if (_scannerController != null) return;
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
    _scanPaused = false;
  }

  Future<void> _approveDevice(P2PDeviceAssociation assoc) async {
    if (_approvalInProgress) return;
    setState(() => _approvalInProgress = true);
    try {
      final cert = await _security.signDeviceApproval(
        deviceId: assoc.deviceId,
        catechistId: assoc.catechistId ?? '',
        publicKeyBase64: assoc.publicKeyBase64,
        deviceName: assoc.deviceName,
      );
      final updated = assoc.copyWith(
        authorizedByResponsabile: true,
        timestampApproval: cert.timestampApproval,
        approvedByDeviceId: cert.approvedByDeviceId,
        approvalSignature: cert.approvalSignature,
        approvalSignerPublicKey: cert.signerPublicKey,
      );
      await _security.saveAssociation(updated);

      if (!mounted) return;
      setState(() {
        _selectedApprovalQrData =
            _approvalQrPrefix + jsonEncode(cert.toJson());
        _scanApproval = false;
        _scanTrust = false;
        _trustQrData = null;
      });
      await _initData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${assoc.deviceName} approvato. Mostra il QR di approvazione '
            'al dispositivo per abilitarlo.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore approvazione: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _approvalInProgress = false);
    }
  }

  Future<void> _revokeApproval(P2PDeviceAssociation assoc) async {
    final updated = assoc.copyWith(clearApproval: true);
    await _security.saveAssociation(updated);
    await _initData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approvazione revocata per ${assoc.deviceName}.')),
      );
    }
  }

  Future<void> _onTrustQrScanned(String raw) async {
    if (_scanPaused) return;
    if (!raw.startsWith(_trustQrPrefix)) {
      setState(() => _scanMessage = 'QR non riconosciuto: non è un QR di fiducia.');
      return;
    }
    _scanPaused = true;
    try {
      final json = raw.substring(_trustQrPrefix.length);
      final data = jsonDecode(json) as Map<String, dynamic>;
      final secret = data['approvalSecret'] as String? ?? '';
      final respDeviceId = data['responsabileDeviceId'] as String? ?? '';
      final respName = data['responsabileName'] as String? ?? '';
      if (secret.isEmpty || respDeviceId.isEmpty) {
        setState(() => _scanMessage = 'QR di fiducia non valido.');
        _scanPaused = false;
        return;
      }
      await _security.storeResponsabileTrustInfo(
        responsabileDeviceId: respDeviceId,
        approvalSecret: secret,
        responsabileName: respName,
      );
      if (!mounted) return;
      setState(() {
        _trustInfo = {
          'responsabileDeviceId': respDeviceId,
          'approvalSecret': secret,
          'responsabileName': respName,
        };
        _scanTrust = false;
        _scanMessage = null;
      });
      await _initData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'QR di fiducia importato. Ora il dispositivo può verificare '
            'le approvazioni del Responsabile.',
          ),
        ),
      );
    } catch (e) {
      setState(() => _scanMessage = 'Errore import QR: $e');
      _scanPaused = false;
    }
  }

  Future<void> _onApprovalQrScanned(String raw) async {
    if (_scanPaused) return;
    if (!raw.startsWith(_approvalQrPrefix)) {
      setState(() => _scanMessage = 'QR non riconosciuto: non è un QR di approvazione.');
      return;
    }
    _scanPaused = true;
    try {
      final json = raw.substring(_approvalQrPrefix.length);
      final cert =
          AssociatedDevice.fromJson(jsonDecode(json) as Map<String, dynamic>);
      if (!cert.isApproved) {
        setState(() => _scanMessage = 'Certificato di approvazione non valido.');
        _scanPaused = false;
        return;
      }

      // Il dispositivo approvato memorizza il certificato locale.
      await _security.storeLocalApproval(cert);

      // Allega il certificato all'associazione verso il dispositivo del
      // Responsabile, se esiste.
      final assoc = await _security.getAssociation(cert.deviceId);
      if (assoc != null) {
        final updated = assoc.copyWith(
          authorizedByResponsabile: true,
          timestampApproval: cert.timestampApproval,
          approvedByDeviceId: cert.approvedByDeviceId,
          approvalSignature: cert.approvalSignature,
          approvalSignerPublicKey: cert.signerPublicKey,
        );
        await _security.saveAssociation(updated);
      }

      if (!mounted) return;
      setState(() {
        _localApproval = cert;
        _scanApproval = false;
        _scanMessage = null;
      });
      await _initData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Approvazione ricevuta: ora puoi sincronizzare le classi '
            'con il dispositivo del Responsabile.',
          ),
        ),
      );
    } catch (e) {
      setState(() => _scanMessage = 'Errore import approvazione: $e');
      _scanPaused = false;
    }
  }

  void _onQrDetected(BarcodeCapture capture) {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    if (_scanTrust) {
      _onTrustQrScanned(raw);
    } else if (_scanApproval) {
      _onApprovalQrScanned(raw);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppScaffold(
      title: 'Catena di fiducia',
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(4),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Aggiorna',
                    onPressed: _refresh,
                  ),
                ),
                _buildStatusBanner(theme, colorScheme),
                const SizedBox(height: 16),
                _buildResponsabileSection(theme, colorScheme),
                const SizedBox(height: 20),
                _buildVerificationSection(theme, colorScheme),
                const SizedBox(height: 20),
                _buildAssociationsSection(theme, colorScheme),
                if (_localApproval != null) ...[
                  const SizedBox(height: 20),
                  _buildLocalApprovalCard(theme),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _buildStatusBanner(ThemeData theme, ColorScheme colorScheme) {
    final active = _responsabileMode;
    final color = active ? Colors.green : Colors.blueGrey;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            active ? Icons.verified_user : Icons.info_outline,
            color: color,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active
                      ? 'Modalità Responsabile attiva'
                      : 'Modalità Responsabile disattivata',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  active
                      ? 'Ogni dispositivo deve essere approvato prima di '
                          'sincronizzare le classi.'
                      : 'Attiva la modalità Responsabile per gestire la '
                          'catena di fiducia.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey[700], height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsabileSection(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dispositivo del Responsabile',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (_trustQrData != null) ...[
          _buildQrCard(
            title: 'QR di fiducia',
            subtitle:
                'Scansionalo UNA volta dal dispositivo che farà da PRIMARY '
                '(o da ogni dispositivo che deve verificare le approvazioni).',
            data: _trustQrData!,
            color: Colors.teal,
          ),
          const SizedBox(height: 12),
        ],
        if (_selectedApprovalQrData != null) ...[
          _buildQrCard(
            title: 'QR di approvazione',
            subtitle:
                'Fallo scansionare dal dispositivo appena approvato per '
                'abilitarne la sincronizzazione.',
            data: _selectedApprovalQrData!,
            color: Colors.green,
          ),
          const SizedBox(height: 12),
        ],
        if (_scanTrust || _scanApproval) ...[
          _buildScannerCard(theme, colorScheme),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _generateTrustQr,
                icon: const Icon(Icons.qr_code_2, size: 20),
                label: const Text('Genera QR di fiducia'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.teal,
                  side: const BorderSide(color: Colors.teal),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Il QR di fiducia contiene il segreto che permette di verificare '
          'le approvazioni. Consegnane una copia (UNA volta) al dispositivo '
          'primario.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildVerificationSection(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Questo dispositivo',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (_trustInfo != null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.fact_check, color: Colors.teal),
              title: const Text('Fiducia del Responsabile configurata'),
              subtitle: Text(
                'Responsabile: ${_trustInfo!['responsabileName'] ?? '-'}\n'
                'Dispositivo: ${_trustInfo!['responsabileDeviceId'] ?? '-'}',
              ),
            ),
          )
        else ...[
          Card(
            child: ListTile(
              leading: Icon(Icons.help_outline, color: Colors.grey[500]),
              title: const Text('Nessuna fiducia configurata'),
              subtitle: const Text(
                'Scansiona il "QR di fiducia" del Responsabile per '
                'verificare le approvazioni. Senza di esso, un dispositivo '
                'approvato non potrà sincronizzare con questo.',
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _startScanTrust,
                icon: const Icon(Icons.qr_code_scanner, size: 20),
                label: const Text('Scansiona QR di fiducia'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.primary,
                  side: BorderSide(color: colorScheme.primary),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _startScanApproval,
                icon: const Icon(Icons.qr_code_2, size: 20),
                label: const Text('Ricevi approvazione'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green,
                  side: const BorderSide(color: Colors.green),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAssociationsSection(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dispositivi associati',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        if (_associations.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.link_off, size: 40, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text(
                  'Nessun dispositivo associato.',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          )
        else
          for (final assoc in _associations) ...[
            _buildAssociationCard(assoc, theme),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _buildAssociationCard(
      P2PDeviceAssociation assoc, ThemeData theme) {
    final approved = assoc.authorizedByResponsabile;
    final isDark = theme.brightness == Brightness.dark;
    final cardColor =
        isDark ? theme.colorScheme.surfaceContainer : Colors.white;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: approved
            ? Colors.green.withValues(alpha: isDark ? 0.12 : 0.05)
            : cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: approved
              ? Colors.green.withValues(alpha: 0.35)
              : (isDark
                  ? theme.colorScheme.outline.withValues(alpha: 0.2)
                  : Colors.grey.shade200),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                approved ? Icons.verified : Icons.radio_button_unchecked,
                color: approved ? Colors.green : Colors.grey,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  assoc.deviceName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (approved)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Approvato',
                    style: TextStyle(
                        color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            approved
                ? 'Approvato il ${_formatDate(assoc.timestampApproval)} '
                    'da ${assoc.approvedByDeviceId ?? '-'}'
                : 'Non ancora approvato dal Responsabile',
            style: TextStyle(
              fontSize: 12,
              color: approved ? Colors.green[700] : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!approved)
                FilledButton.tonalIcon(
                  onPressed: _approvalInProgress
                      ? null
                      : () => _approveDevice(assoc),
                  icon: const Icon(Icons.verified_user, size: 18),
                  label: const Text('Approva'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.withValues(alpha: 0.15),
                    foregroundColor: Colors.green[800],
                  ),
                )
              else ...[
                if (_responsabileMode)
                  TextButton.icon(
                    onPressed: () => _revokeApproval(assoc),
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Revoca'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedApprovalQrData = _approvalQrPrefix +
                          jsonEncode(
                            AssociatedDevice(
                              deviceId: assoc.deviceId,
                              catechistId: assoc.catechistId ?? '',
                              publicKey: assoc.publicKeyBase64,
                              authorizedByResponsabile: true,
                              timestampApproval: assoc.timestampApproval,
                              deviceName: assoc.deviceName,
                              approvedByDeviceId: assoc.approvedByDeviceId,
                              approvalSignature: assoc.approvalSignature,
                              signerPublicKey: assoc.approvalSignerPublicKey,
                            ).toJson(),
                          );
                    });
                  },
                  icon: const Icon(Icons.qr_code, size: 18),
                  label: const Text('Mostra QR'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocalApprovalCard(ThemeData theme) {
    final cert = _localApproval!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Text(
                'Questo dispositivo è stato approvato dal Responsabile',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green[800],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Approvato il ${_formatDate(cert.timestampApproval)}\n'
            'da ${cert.approvedByDeviceId ?? '-'}',
            style: TextStyle(fontSize: 13, color: Colors.green[700]),
          ),
        ],
      ),
    );
  }

  Widget _buildQrCard({
    required String title,
    required String subtitle,
    required String data,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4),
          ),
          const SizedBox(height: 12),
          QrImageView(
            data: data,
            version: QrVersions.auto,
            size: 210,
            backgroundColor: Colors.white,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() {
              _trustQrData = null;
              _selectedApprovalQrData = null;
            }),
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Chiudi QR'),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerCard(ThemeData theme, ColorScheme colorScheme) {
    final isTrust = _scanTrust;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isTrust ? Icons.fact_check : Icons.qr_code_2,
                size: 20,
                color: isTrust ? Colors.teal : Colors.green,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isTrust
                      ? 'Scansiona il QR di fiducia del Responsabile'
                      : 'Scansiona il QR di approvazione mostrato dal Responsabile',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _scanTrust = false;
                  _scanApproval = false;
                  _scanMessage = null;
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_scannerController != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 220,
                child: MobileScanner(
                  controller: _scannerController!,
                  onDetect: _onQrDetected,
                ),
              ),
            ),
          if (_scanMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _scanMessage!,
              style: TextStyle(
                color: _scanMessage!.contains('Errore') ||
                        _scanMessage!.contains('non')
                    ? Colors.red[700]
                    : Colors.grey[700],
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
