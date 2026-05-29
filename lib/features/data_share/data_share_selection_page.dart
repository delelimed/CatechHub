import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../core/services/qr_data_service.dart';
import '../../core/services/data_export_service.dart';
import '../../core/providers/data_share_provider.dart';

class DataShareSelectionPage extends ConsumerStatefulWidget {
  const DataShareSelectionPage({super.key});

  @override
  ConsumerState<DataShareSelectionPage> createState() =>
      _DataShareSelectionPageState();
}

class _DataShareSelectionPageState
    extends ConsumerState<DataShareSelectionPage> {
  bool _includeAnagrafica = true;
  bool _includeAgenda = true;
  bool _includeProgrammazione = true;
  bool _includeDocumenti = true;
  bool _includeContactNotes = false;
  bool _includeAnagraficaAttachments = true;
  bool _includeAgendaAttachments = true;

  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _startSharing() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Prepara i dati selezionati in base alle opzioni dell'utente
      final selectedData = await DataExportService.exportSelectiveData(
        _includeAnagrafica,
        _includeAgenda,
        _includeProgrammazione,
        _includeDocumenti,
        _includeContactNotes,
        _includeAnagraficaAttachments,
        _includeAgendaAttachments,
      );

      // Genera PIN
      final pin = QRDataService.generatePin();

      // Salva dati e PIN nei provider
      ref.read(dataShareDataProvider.notifier).state = selectedData;
      ref.read(dataSharePinProvider.notifier).state = pin;

      // Naviga alla pagina di invio
      if (mounted) {
        context.go('/data-share/send');
      }
    } catch (e, stack) {
      debugPrint('Errore durante l\'esportazione dei dati: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Impossibile preparare i dati per il QR: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _startReceiving() {
    // Naviga alla pagina di ricezione
    context.go('/data-share/receive');
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Condivisione Dati',
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF174A7E)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _InfoCard(),
                  const SizedBox(height: 24),
                  if (_errorMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  const _SectionTitle(
                    title: 'Seleziona contenuti da condividere',
                  ),
                  const SizedBox(height: 16),

                  _ShareOption(
                    icon: Icons.people_rounded,
                    title: 'Anagrafica',
                    subtitle: 'Studenti e classi',
                    value: _includeAnagrafica,
                    onChanged: (value) {
                      setState(() {
                        _includeAnagrafica = value ?? false;
                        if (!_includeAnagrafica) {
                          _includeAnagraficaAttachments = false;
                          _includeContactNotes = false;
                        }
                      });
                    },
                  ),

                  _ShareOption(
                    icon: Icons.attachment_rounded,
                    title: 'Allegati studenti',
                    subtitle: 'Includi i file collegati agli studenti',
                    value: _includeAnagraficaAttachments,
                    enabled: _includeAnagrafica,
                    onChanged: (value) {
                      if (!_includeAnagrafica) return;
                      setState(() {
                        _includeAnagraficaAttachments = value ?? false;
                      });
                    },
                  ),

                  _ShareOption(
                    icon: Icons.note_rounded,
                    title: 'Note contatto',
                    subtitle:
                        'Includi le note di contatto associate agli studenti',
                    value: _includeContactNotes,
                    enabled: _includeAnagrafica,
                    onChanged: (value) {
                      if (!_includeAnagrafica) return;
                      setState(() {
                        _includeContactNotes = value ?? false;
                      });
                    },
                  ),

                  _ShareOption(
                    icon: Icons.calendar_today_rounded,
                    title: 'Agenda',
                    subtitle: 'Presenze e incontri',
                    value: _includeAgenda,
                    onChanged: (value) {
                      setState(() {
                        _includeAgenda = value ?? false;
                        if (!_includeAgenda) {
                          _includeAgendaAttachments = false;
                        }
                      });
                    },
                  ),

                  _ShareOption(
                    icon: Icons.attachment_rounded,
                    title: 'Allegati agenda',
                    subtitle: 'Includi i file collegati agli incontri',
                    value: _includeAgendaAttachments,
                    enabled: _includeAgenda,
                    onChanged: (value) {
                      if (!_includeAgenda) return;
                      setState(() {
                        _includeAgendaAttachments = value ?? false;
                      });
                    },
                  ),

                  _ShareOption(
                    icon: Icons.event_note_rounded,
                    title: 'Programmazione',
                    subtitle: 'Pianificazione e allegati giornate',
                    value: _includeProgrammazione,
                    onChanged: (value) {
                      setState(() {
                        _includeProgrammazione = value ?? false;
                      });
                    },
                  ),

                  _ShareOption(
                    icon: Icons.folder_rounded,
                    title: 'Documenti',
                    subtitle: 'Documenti e consegne',
                    value: _includeDocumenti,
                    onChanged: (value) {
                      setState(() {
                        _includeDocumenti = value ?? false;
                      });
                    },
                  ),

                  const SizedBox(height: 32),

                  const _SectionTitle(title: 'Modalità di condivisione'),
                  const SizedBox(height: 16),

                  _ModeButton(
                    icon: Icons.qr_code_2_rounded,
                    title: 'Invia Dati',
                    subtitle: 'Genera QR code per la condivisione',
                    color: const Color(0xFF174A7E),
                    onTap: _startSharing,
                  ),

                  const SizedBox(height: 12),

                  _ModeButton(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Ricevi Dati',
                    subtitle: 'Scansiona QR code per ricevere dati',
                    color: Colors.green,
                    onTap: _startReceiving,
                  ),
                ],
              ),
            ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF174A7E), Color(0xFF2E5A8F)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.info_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Condivisione Offline Sicura',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Condividi i tuoi dati tra dispositivi in modo completamente offline e sicuro usando QR code animati. '
            'I dati sono protetti da un PIN di 8 cifre.',
            style: TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
        color: Colors.grey.shade600,
      ),
    );
  }
}

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool?> onChanged;

  const _ShareOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFF174A7E).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF174A7E)),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: enabled ? Colors.grey.shade600 : Colors.grey.shade400,
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeColor: const Color(0xFF174A7E),
          inactiveThumbColor: enabled ? null : Colors.grey.shade400,
          inactiveTrackColor: enabled ? null : Colors.grey.shade300,
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: color, size: 28),
          ],
        ),
      ),
    );
  }
}
