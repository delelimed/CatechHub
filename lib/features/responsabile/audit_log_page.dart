// ══════════════════════════════════════════════════════════════════════════════
// audit_log_page.dart — CatechHub (Registro Trattamenti GDPR)
//
// Vista del Registro Trattamenti (GDPR Art. 30) riservata al Responsabile
// Catechistico. Elenca le voci immutabili e firmate HMAC dell'AuditLog,
// verifica in tempo reale l'integrità (anti-manomissione) ed evidenzia
// eventuali voci alterate o non firmate.
// ══════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/services/backup_encryption_service.dart';
import '../../features/gdpr/gdpr_export_service.dart';
import '../../shared/models/audit_log.dart';
import '../../shared/models/user_role.dart';
import '../../shared/widgets/app_scaffold.dart';
import 'audit_log_repository.dart';
import 'responsabile_providers.dart';

/// Pagina del Registro Trattamenti GDPR.
class AuditLogPage extends ConsumerStatefulWidget {
  const AuditLogPage({super.key});

  @override
  ConsumerState<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends ConsumerState<AuditLogPage> {
  final Set<String> _tamperedIds = {};

  @override
  Widget build(BuildContext context) {
    if (!RolePermissions.currentCan(RolePermission.manageAuditLog)) {
      return AppScaffold(
        title: 'Registro Trattamenti',
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Sezione riservata al Responsabile Catechistico.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return AppScaffold(
      title: 'Registro Trattamenti',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _intro(context),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final tampered =
                        await AuditLogRepository().findTampered();
                    if (!context.mounted) return;
                    setState(() {
                      _tamperedIds
                        ..clear()
                        ..addAll(tampered.map((l) => l.logId));
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          tampered.isEmpty
                              ? 'Registro integro: tutte le firme sono valide.'
                              : 'Attenzione: ${tampered.length} voce/i con firma '
                                  'non valida.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.shield_outlined, size: 18),
                  label: const Text('Verifica integrità del registro'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _exportAuditLogCsv(),
                  icon: const Icon(Icons.table_view_rounded, size: 18),
                  label: const Text('Esporta CSV'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _exportCompliancePackage(),
                  icon: const Icon(Icons.lock_outline_rounded, size: 18),
                  label: const Text('Backup conformità'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ref.watch(auditLogStreamProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Errore: $e')),
              data: (logs) {
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(auditLogStreamProvider.future),
                  child: ListView(
                    children: [
                      for (final log in logs) _logCard(log),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportAuditLogCsv() async {
    try {
      final csv = GdprExportService.buildAuditLogCsv();
      await _saveFile(
        bytes: Uint8List.fromList(utf8.encode(csv)),
        fileName: 'registro_trattamenti',
        extension: 'csv',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registro Trattamenti esportato.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Esportazione CSV fallita: $e')),
        );
      }
    }
  }

  Future<void> _exportCompliancePackage() async {
    final pin = await BackupEncryptionService.showBackupPinDialog(
      context: context,
      isExport: true,
    );
    if (pin == null || !mounted) return;
    try {
      final encrypted =
          GdprExportService.encryptParishConservationPackage(pin);
      await _saveFile(
        bytes: Uint8List.fromList(utf8.encode(encrypted)),
        fileName: 'conformita_parrocchia',
        extension: 'catechhub',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Backup di conformità salvato (crittato con PIN).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Salvataggio backup fallito: $e')),
        );
      }
    }
  }

  Future<void> _saveFile({
    required Uint8List bytes,
    required String fileName,
    required String extension,
  }) async {
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final fullName = '${fileName}_$timestamp.$extension';
    String? savedPath;
    var saved = false;
try {
      // file_picker 12: saveFile restituisce String?.
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Salva esportazione',
        fileName: fullName,
        bytes: bytes,
      );
      savedPath = uri;
      if (savedPath != null) saved = true;
    } catch (_) {
      savedPath = null;
    }
    if (!saved) {
      final directory = await FilePicker.getDirectoryPath(
        dialogTitle: 'Seleziona cartella di salvataggio',
      );
      if (directory != null) {
        await File('$directory/$fullName').writeAsBytes(bytes, flush: true);
      }
    }
  }

  Widget _intro(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF174A7E), Color(0xFF2368B1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Registro Trattamenti (GDPR, Art. 30)',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Ogni voce è immutabile e firmata HMAC. Modifiche posteriori ai '
            'dati invalideranno la firma. Le voci alterate vengono evidenziate.',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _logCard(AuditLog log) {
    final isTampered = _tamperedIds.contains(log.logId);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dt = log.timestamp.toLocal();
    final formatted = DateFormat('dd/MM/yyyy HH:mm').format(dt);
    final action = log.actionType.label;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context).colorScheme.surfaceContainer
            : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTampered
              ? Colors.red.shade400
              : isDark
                  ? Colors.grey.shade800
                  : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isTampered
                    ? Icons.gpp_bad_rounded
                    : Icons.verified_user_rounded,
                size: 20,
                color: isTampered ? Colors.red : Colors.green,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  action,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              Text(
                formatted,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey.shade400 : Colors.black54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Entità: ${log.affectedEntityType} · ${log.affectedEntityId}',
            style: TextStyle(
                fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.black54),
          ),
          Text(
            'Operatore: ${log.executedByCatechistName} '
            '(${log.executedByCatechistId})',
            style: TextStyle(
                fontSize: 11, color: isDark ? Colors.grey.shade500 : Colors.grey),
          ),
          if (isTampered)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'ATTENZIONE: firma HMAC non valida. Voce potenzialmente manomessa.',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}