import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/data_share_provider.dart';
import '../../core/services/data_export_service.dart';
import '../../core/services/qr_data_service.dart';
import '../../shared/widgets/app_scaffold.dart';

/// Pagina hub per la condivisione e il backup dei dati in CateREG.
///
/// Offre tre modalità di trasferimento dati:
/// 1. **Sincronizzazione nelle vicinanze** — associa e sincronizza con altri catechisti
/// 2. **Condivisione via QR** — invio/ricezione tramite codici QR animati
/// 3. **Backup cifrato** — esportazione e importazione di file di backup protetti
///
/// Mostra anche un'intestazione informativa che rassicura l'utente sulla
/// protezione e cifratura dei dati durante qualsiasi operazione di scambio.
/// Agisce come punto di smistamento verso i flussi di invio e ricezione.
class DataShareSelectionPage extends ConsumerWidget {
  const DataShareSelectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      title: 'Condivisione e backup',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF174A7E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.enhanced_encryption_rounded, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'I dati sono protetti e cifrati. '
                    'Puoi eseguire backup e ripristino dai file o tramite codici QR.',
                    style: TextStyle(color: Colors.white, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _ActionCard(
            icon: Icons.sensors_rounded,
            title: 'Sincronizzazione nelle vicinanze',
            subtitle: 'Associa e sincronizza con altri catechisti',
            color: Colors.teal,
            onTap: () => context.push('/settings/association'),
          ),
          const SizedBox(height: 16),
          _ActionCard(
            icon: Icons.qr_code_2_rounded,
            title: 'Condividi via QR',
            subtitle: 'Invia o ricevi dati tramite codici QR',
            color: const Color(0xFF174A7E),
            onTap: () => _showQrShareOptions(context, ref),
          ),
          const SizedBox(height: 16),
          _ActionCard(
            icon: Icons.backup_rounded,
            title: 'Backup cifrato',
            subtitle: 'Esporta o importa file di backup cifrati',
            color: Colors.teal,
            onTap: () => context.push('/backup'),
          ),
        ],
      ),
    );
  }

  void _showQrShareOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_rounded, color: Color(0xFF174A7E)),
              title: const Text('Invia dati'),
              subtitle: const Text('Mostra codici QR da scansionare'),
              onTap: () {
                Navigator.pop(ctx);
                _showDataSelectionDialog(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download_rounded, color: Colors.green),
              title: const Text('Ricevi dati'),
              subtitle: const Text('Scansiona codici QR per importare'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/data-share/receive');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDataSelectionDialog(BuildContext context, WidgetRef ref) {
    bool includeAnagrafica = true;
    bool includeAgenda = true;
    bool includeProgrammazione = true;
    bool includeDocumenti = true;
    bool includeContactNotes = false;
    bool includeCatechesi = false;
    bool includeAnnotazioni = false;
    bool _isPreparing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Row(
            children: [
              Icon(Icons.share_rounded, color: Color(0xFF174A7E)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Seleziona dati da inviare',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: _isPreparing
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF174A7E)),
                        SizedBox(height: 16),
                        Text('Preparazione dati in corso...'),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ModuleCheckbox(
                          label: 'Anagrafica ragazzi',
                          subtitle: 'Nomi, cognomi, contatti genitori',
                          icon: Icons.people_rounded,
                          value: includeAnagrafica,
                          onChanged: (v) => setDialogState(
                            () => includeAnagrafica = v,
                          ),
                        ),
                        _ModuleCheckbox(
                          label: 'Presenze',
                          subtitle: 'Registro presenze e assenze',
                          icon: Icons.fact_check_rounded,
                          value: includeAgenda,
                          onChanged: (v) => setDialogState(
                            () => includeAgenda = v,
                          ),
                        ),
                        _ModuleCheckbox(
                          label: 'Programmazione',
                          subtitle: 'Giornate e incontri programmati',
                          icon: Icons.calendar_month_rounded,
                          value: includeProgrammazione,
                          onChanged: (v) => setDialogState(
                            () => includeProgrammazione = v,
                          ),
                        ),
                        _ModuleCheckbox(
                          label: 'Documenti',
                          subtitle: 'Certificati, autorizzazioni, consegne',
                          icon: Icons.description_rounded,
                          value: includeDocumenti,
                          onChanged: (v) => setDialogState(
                            () => includeDocumenti = v,
                          ),
                        ),
                        _ModuleCheckbox(
                          label: 'Note di contatto',
                          subtitle: 'Comunicazioni con le famiglie',
                          icon: Icons.contact_mail_rounded,
                          value: includeContactNotes,
                          onChanged: (v) => setDialogState(
                            () => includeContactNotes = v,
                          ),
                        ),
                        _ModuleCheckbox(
                          label: 'Catechesi',
                          subtitle: 'Argomenti e contenuti delle catechesi',
                          icon: Icons.menu_book_rounded,
                          value: includeCatechesi,
                          onChanged: (v) => setDialogState(
                            () => includeCatechesi = v,
                          ),
                        ),
                        _ModuleCheckbox(
                          label: 'Annotazioni giornaliere',
                          subtitle: 'Note e osservazioni sui ragazzi',
                          icon: Icons.note_alt_rounded,
                          value: includeAnnotazioni,
                          onChanged: (v) => setDialogState(
                            () => includeAnnotazioni = v,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          actions: _isPreparing
              ? []
              : [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Annulla'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF174A7E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () async {
                      setDialogState(() => _isPreparing = true);
                      try {
                        final allData = await DataExportService.exportSelectiveData(
                          includeAnagrafica: includeAnagrafica,
                          includeAgenda: includeAgenda,
                          includeProgrammazione: includeProgrammazione,
                          includeDocumenti: includeDocumenti,
                          includeContactNotes: includeContactNotes,
                          includeCatechesi: includeCatechesi,
                          includeAnnotazioni: includeAnnotazioni,
                        );

                        final options = DataShareOptions(
                          includeAnagrafica: includeAnagrafica,
                          includeAgenda: includeAgenda,
                          includeProgrammazione: includeProgrammazione,
                          includeDocumenti: includeDocumenti,
                          includeContactNotes: includeContactNotes,
                          includeCatechesi: includeCatechesi,
                          includeAnnotazioni: includeAnnotazioni,
                        );

                        final shareData = QRDataService.prepareDataForShare(
                          options,
                          allData,
                        );

                        final pin = QRDataService.generatePin();

                        ref.read(dataShareDataProvider.notifier).state =
                            shareData;
                        ref.read(dataSharePinProvider.notifier).state = pin;

                        if (ctx.mounted) Navigator.pop(ctx);
                        if (context.mounted) {
                          context.push('/data-share/send');
                        }
                      } catch (e) {
                        setDialogState(() => _isPreparing = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Errore: $e')),
                          );
                        }
                      }
                    },
                    child: const Text('Invia'),
                  ),
                ],
        ),
      ),
    );
  }
}

class _ModuleCheckbox extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ModuleCheckbox({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Checkbox(
              value: value,
              activeColor: const Color(0xFF174A7E),
              onChanged: (v) => onChanged(v ?? false),
            ),
            const SizedBox(width: 8),
            Icon(icon, color: const Color(0xFF174A7E), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
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

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}
