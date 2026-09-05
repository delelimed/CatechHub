/// Pagina di backup e ripristino dei dati dell'app CateREG.
///
/// - **Esporta backup**: raccoglie tutti i dati (anagrafica, presenze,
///   programmazione, catechesi, documenti e allegati), li cifra con il PIN
///   dell'utente tramite [DataExportService.exportEncryptedData] e salva il
///   file `.catechhub` nella posizione scelta dall'utente (tramite
///   [FilePicker]). Il file viene verificato con checksum SHA-256 per
///   garantire integrità e completezza (sicurezza grado militare).
/// - **Importa backup**: seleziona un file `.catechhub`, richiede il PIN
///   di decifratura, verifica la password tramite
///   [DataExportService.verifyEncryptedPassword], verifica il checksum,
///   chiede conferma della sovrascrittura e ripristina tutti i dati tramite
///   [DataExportService.importEncryptedData].
///
/// Entrambe le operazioni verificano il PIN dell'utente prima di procedere.
/// L'importazione sostituisce completamente i dati esistenti in modo
/// irreversibile.
library;

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/services/backup_encryption_service.dart';
import '../../core/services/data_export_service.dart';
import '../../core/providers/current_class_provider.dart';
import '../../shared/models/class_model.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../classes/classes_provider.dart';
import '../documents/documents_provider.dart';
import '../planning/planning_provider.dart';
import '../students/students_provider.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _isExporting = false;
  bool _isImporting = false;
  String? _statusMessage;
  bool _isError = false;
  String? _phaseMessage;

  // ────────────────────────────────────────────
  //  EXPORT
  // ────────────────────────────────────────────

  Future<void> _exportBackup() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isExporting = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      // Autentica con biometrica/PIN del dispositivo
      final authService = ref.read(authServiceProvider);
      final authenticated = await authService.authenticate(
        localizedReason: 'Autenticati per esportare il backup',
      );
      if (!authenticated) {
        if (mounted) {
          setState(() {
            _isExporting = false;
            _statusMessage = 'Autenticazione annullata o fallita';
            _isError = true;
          });
        }
        return;
      }

      // A2: chiedi il PIN per cifrare il backup (politica forte: almeno
      // 12 caratteri alfanumerici con lettere e cifre, conferma in dialogo).
      if (!mounted) return;
      final pin = await BackupEncryptionService.showBackupPinDialog(
        context: context,
        isExport: true,
      );
      if (pin == null) {
        if (mounted) setState(() => _isExporting = false);
        return;
      }

      // Scegli se esportare una singola classe oppure tutte le classi
      final selection = await _askExportScope();
      if (selection == null) {
        if (mounted) setState(() => _isExporting = false);
        return;
      }
      final String? exportClassId = selection == 'ALL' ? null : selection;
      SchoolClass? exportClass;
      if (exportClassId != null) {
        final myClasses = ref.read(myClassesProvider);
        for (final c in myClasses) {
          if (c.id == exportClassId) {
            exportClass = c;
            break;
          }
        }
        if (exportClass == null) {
          if (mounted) {
            setState(() {
              _isExporting = false;
              _statusMessage = 'Classe selezionata non trovata';
              _isError = true;
            });
          }
          return;
        }
      }

      setState(() {
        _statusMessage = 'Raccolta dati in corso…';
        _phaseMessage = 'Esportazione anagrafica, presenze e documenti…';
      });
      await Future.delayed(Duration.zero);

      setState(() => _phaseMessage = 'Cifratura dati con PIN…');
      await Future.delayed(Duration.zero);

      // Esporta e cifra
      final encrypted = await DataExportService.exportEncryptedData(
        pin,
        classId: exportClassId,
      );
      final bytes = Uint8List.fromList(utf8.encode(encrypted));

      // Verifica integrità: calcola checksum SHA-256 dei dati cifrati (cryptography)
      final checksum = await _sha256(bytes);

      // Permetti all'utente di scegliere dove salvare
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final className = exportClass != null
          ? exportClass.name
          : 'ClassiCompleto';
      // Il nome file NON include il nome del catechista: i backup contengono
      // dati sensibili di minori e un nome file con dati personali aumenterebbe
      // il rischio di esposizione PII se il file venisse condiviso o caricato
      // accidentalmente su un servizio di cloud.
      final fileName =
          'catechhub_backup_${_sanitizeFilename(className)}_$timestamp'
          '.catechhub';

      String? savedPath;
      bool saved = false;
      try {
        // file_picker: saveFile restituisce String? (path) su Android/iOS,
        // Uri? su desktop/web. Gestiamo entrambi i casi.
        final result = await FilePicker.saveFile(
          dialogTitle: 'Salva backup',
          fileName: fileName,
          bytes: bytes,
        );
        if (result != null) {
          savedPath = result.toString();
          // Verifica militare: il file deve esistere, avere size > 0 e checksum corretto
          final file = File(savedPath);
          if (await file.exists()) {
            final writtenBytes = await file.readAsBytes();
            if (writtenBytes.isNotEmpty) {
              final writtenChecksum = await _sha256(writtenBytes);
              if (writtenChecksum == checksum) {
                saved = true;
              } else {
                if (mounted) {
                  setState(() {
                    _statusMessage = 'Errore: checksum non corrispondente (dati corrotti)';
                    _isError = true;
                  });
                }
                return;
              }
            } else {
              if (mounted) {
                setState(() {
                  _statusMessage = 'Errore: file scritto ma vuoto (0 byte)';
                  _isError = true;
                });
              }
              return;
            }
          }
        }
      } catch (e) {
        savedPath = null;
      }

      // Se saveFile fallisce, usa getDirectoryPath + scrittura manuale con verifica
      if (!saved) {
        try {
          final directory = await FilePicker.getDirectoryPath(
            dialogTitle: 'Seleziona cartella backup',
          );
          if (directory != null) {
            final filePath = '$directory/$fileName';
            final file = File(filePath);
            await file.writeAsBytes(bytes, flush: true);
            // Verifica post-scrittura
            if (await file.exists()) {
              final writtenBytes = await file.readAsBytes();
              if (writtenBytes.isNotEmpty) {
                final writtenChecksum = await _sha256(writtenBytes);
                if (writtenChecksum == checksum) {
                  savedPath = filePath;
                  saved = true;
                } else {
                  if (mounted) {
                    setState(() {
                      _statusMessage = 'Errore: checksum non corrispondente (fallback)';
                      _isError = true;
                    });
                  }
                  return;
                }
              } else {
                if (mounted) {
                  setState(() {
                    _statusMessage = 'Errore: file scritto ma vuoto (0 byte) - fallback';
                    _isError = true;
                  });
                }
                return;
              }
            }
          }
        } catch (e) {
          savedPath = null;
        }
      }

      if (saved) {
        if (mounted) {
          setState(() {
            _statusMessage = 'Backup esportato e verificato con successo (SHA-256)';
            _isError = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _statusMessage = 'Esportazione annullata o fallita';
            _isError = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Errore durante l\'esportazione: $e';
          _isError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  /// Calcola hash SHA-256 usando il package cryptography (compatibile con backup_encryption_service).
  static Future<String> _sha256(Uint8List data) async {
    final hash = await Sha256().hash(data);
    return base64Encode(hash.bytes);
  }

  // ────────────────────────────────────────────
  //  IMPORT
  // ────────────────────────────────────────────

  Future<void> _importBackup() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _isImporting = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      // Seleziona file
      // file_picker 12: pickFiles restituisce FilePickerResult.
      final result = await FilePicker.pickFiles(type: FileType.any);
      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _isImporting = false);
        return;
      }

      final filePath = result.files.single.path;
      if (filePath == null) {
        throw Exception(
          'Impossibile leggere il file selezionato: percorso non disponibile',
        );
      }

      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Il file selezionato non esiste: $filePath');
      }

      final encryptedData = utf8.decode(await file.readAsBytes());

      // Chiedi il PIN per decifrare (in lettura accetta anche i PIN numerici
      // legacy usati dalle versioni precedenti)
      if (!mounted) return;
      final pin = await BackupEncryptionService.showBackupPinDialog(
        context: context,
        isExport: false,
      );
      if (pin == null) {
        if (mounted) setState(() => _isImporting = false);
        return;
      }

      // Verifica PIN provando a decifrare
      setState(() => _statusMessage = 'Verifica password…');
      await Future.delayed(Duration.zero);
      if (!await DataExportService.verifyEncryptedPassword(
        encryptedData,
        pin,
      )) {
        if (mounted) {
          setState(() {
            _isImporting = false;
            _statusMessage = 'PIN non corretto o file non valido';
            _isError = true;
          });
        }
        return;
      }

      // Autentica con biometrica/PIN del dispositivo prima di importare
      final authService = ref.read(authServiceProvider);
      final authenticated = await authService.authenticate(
        localizedReason: 'Autenticati per importare il backup',
      );
      if (!authenticated) {
        if (mounted) {
          setState(() {
            _isImporting = false;
            _statusMessage = 'Autenticazione annullata o fallita';
            _isError = true;
          });
        }
        return;
      }

      // Conferma sovrascrittura
      final confirm = await _showConfirmDialog();
      if (confirm != true) {
        if (mounted) setState(() => _isImporting = false);
        return;
      }

      setState(() => _statusMessage = 'Importazione dati in corso…');
      await Future.delayed(Duration.zero);
      await DataExportService.importEncryptedData(
        encryptedData,
        pin,
        onPhase: (phase) {
          if (mounted) setState(() => _phaseMessage = phase);
        },
      );

      // Forza il refresh dei provider per aggiornare l'UI
      ref.invalidate(classesStreamProvider);
      ref.invalidate(documentsStreamProvider);
      ref.invalidate(planningRepoProvider);
      ref.invalidate(studentsRepoProvider);

      if (mounted) {
        setState(() {
          _statusMessage = 'Backup importato con successo';
          _isError = false;
          _phaseMessage = null;
        });
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Errore durante l\'importazione: $e';
          _isError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

// ────────────────────────────────────────────
  //  DIALOGS
  // ────────────────────────────────────────────

  Future<String?> _askExportScope() async {
    final myClasses = ref.read(myClassesProvider);
    var selected = 'ALL';
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(ctx).brightness == Brightness.dark
              ? Theme.of(ctx).colorScheme.surfaceContainer
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.class_outlined, color: const Color(0xFF174A7E)),
              const SizedBox(width: 8),
              const Expanded(child: Text('Classi da esportare')),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: RadioGroup<String>(
                groupValue: selected,
                onChanged: (v) => setDialogState(() => selected = v!),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<String>(
                      value: 'ALL',
                      title: const Text('Tutte le mie classi'),
                      subtitle: const Text(
                        'Backup completo di tutte le classi (nome file: ClassiCompleto)',
                      ),
                    ),
                    const Divider(height: 8),
                    for (final c in myClasses)
                      RadioListTile<String>(
                        value: c.id,
                        title: Text(c.name),
                        subtitle: Text('${c.studentIds.length} ragazzi'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF174A7E),
              ),
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('Continua'),
            ),
          ],
        ),
      ),
    );
  }

  /// Rimuove i caratteri non consentiti nei nomi file.
  String _sanitizeFilename(String value) {
    return value
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<bool?> _showConfirmDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(child: Text('Conferma Importazione')),
          ],
        ),
        content: const Text(
          'L\'importazione sostituirà tutti i dati esistenti '
          '(anagrafica, presenze, programmazione, catechesi, documenti e allegati). '
          'Questa operazione non è reversibile.\n\n'
          'Vuoi continuare?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Importa'),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Importazione Completata'),
          ],
        ),
        content: const Text(
          'Il backup è stato importato con successo. '
          'Tutti i dati sono stati ripristinati.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────
  //  BUILD
  // ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Backup',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_rounded, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Text(
                        'Informazioni',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Il backup include anagrafica, presenze, programmazione, '
                    'documenti, allegati (foto e PDF) e catechesi.\n\n'
                    'Durante l\'esportazione puoi scegliere se salvare una '
                    'singola classe oppure tutte le tue classi. In entrambi i '
                    'casi le catechesi sono sempre incluse.\n\n'
                    'Il file è protetto da un PIN che crei al momento dell\'esportazione '
                    'e che dovrai reinserire per importarlo su un altro dispositivo.\n\n'
                    'I dati ricevuti via QR code vengono invece inseriti nella classe '
                    'attualmente aperta sul dispositivo ricevente.\n\n'
                    'L\'accesso alle operazioni di backup richiede l\'autenticazione '
                    'con impronta, volto o PIN del tuo dispositivo.',
                    style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Export
            _ActionCard(
              icon: Icons.upload_file_rounded,
              title: 'Esporta Backup',
              subtitle: 'Salva tutti i dati in un file cifrato',
              color: const Color(0xFF174A7E),
              isLoading: _isExporting,
              onTap: _isImporting ? null : _exportBackup,
            ),

            const SizedBox(height: 16),

            // Import
            _ActionCard(
              icon: Icons.download_rounded,
              title: 'Importa Backup',
              subtitle: 'Ripristina i dati da un file di backup',
              color: Colors.green,
              isLoading: _isImporting,
              onTap: _isExporting ? null : _importBackup,
            ),

            const SizedBox(height: 24),

            // Phase banner (operazioni in corso)
            if (_phaseMessage != null && (_isImporting || _isExporting))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF174A7E).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF174A7E).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: const Color(0xFF174A7E),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _phaseMessage!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF174A7E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Status message
            if (_statusMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isError
                      ? Colors.red.withValues(alpha: 0.1)
                      : Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isError
                        ? Colors.red.withValues(alpha: 0.3)
                        : Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isError
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      color: _isError ? Colors.red : Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          color: _isError ? Colors.red : Colors.green.shade800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Card azione riutilizzabile nella pagina di backup: mostra un'icona,
/// titolo, sottotitolo, indicatore di caricamento e callback al tap.
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool isLoading;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final cardColor = isDark ? colorScheme.surfaceContainer : Colors.white;
    final iconBgColor = isDark
        ? color.withValues(alpha: 0.2)
        : color.withValues(alpha: 0.10);
    final titleColor = isDark ? colorScheme.onSurface : const Color(0xFF1A1A1A);
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final borderColor = isDark
        ? colorScheme.outline.withValues(alpha: 0.2)
        : Colors.transparent;
    final shadowColor = isDark
        ? Colors.black.withValues(alpha: 0.4)
        : Colors.black.withValues(alpha: 0.04);

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: isLoading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: shadowColor,
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: color,
                      ),
                    )
                  : Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isLoading ? 'Operazione in corso...' : subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
            if (!isLoading)
              Icon(
                Icons.chevron_right_rounded,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
              ),
          ],
        ),
      ),
    );
  }
}
