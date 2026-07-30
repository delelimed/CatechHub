import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pagina informativa che spiega che la funzionalità di esportazione
/// del report PDF è in fase di sviluppo e sarà disponibile in una
/// prossima versione dell'app.
class PdfReportPage extends ConsumerWidget {
  const PdfReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Esporta Report PDF'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.picture_as_pdf_rounded,
                size: 80,
                color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
              ),
              const SizedBox(height: 24),
              Text(
                'Funzione in arrivo!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? colorScheme.onSurface : const Color(0xFF174A7E),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'La generazione del report PDF è in fase di sviluppo '
                'e verrà resa disponibile nelle prossime versioni dell\'app.\n\n'
                'Presto potrai esportare un report completo con anagrafica, '
                'presenze, documenti e statistiche del tuo gruppo.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? colorScheme.primary : const Color(0xFF174A7E),
                  side: BorderSide(
                    color: isDark ? colorScheme.primary : const Color(0xFF174A7E),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Torna indietro',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
