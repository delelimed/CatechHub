/// Pagina "Informazioni e Licenze" che elenca le licenze open source delle
/// dipendenze utilizzate dall'app CateREG (CatechHub).
///
/// Mostra:
/// - Il testo integrale della licenza MIT dell'app stessa
/// - L'elenco di tutte le dipendenze runtime con versione e tipo di licenza
///   (BSD-3-Clause, MIT, Apache-2.0)
/// - Una nota di conformità che invita a verificare le licenze specifiche
///   su pub.dev prima del riutilizzo
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

class LicensesPage extends StatelessWidget {
  const LicensesPage({super.key});

  static const appLicense = 'MIT License';

  static const String licenseText = '''MIT License

Copyright (c) 2026 CatechHub

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
''';

  static const List<Map<String, String>> dependencies = [
    {'name': 'flutter', 'version': 'SDK', 'license': 'BSD-3-Clause'},
    {
      'name': 'flutter_localizations',
      'version': 'SDK',
      'license': 'BSD-3-Clause',
    },
    {'name': 'flutter_riverpod', 'version': '^3.3.2', 'license': 'MIT'},
    {'name': 'go_router', 'version': '^17.2.3', 'license': 'Apache-2.0'},
    {'name': 'local_auth', 'version': '^3.0.1', 'license': 'BSD-3-Clause'},
    {'name': 'hive_flutter', 'version': '^1.1.0', 'license': 'Apache-2.0'},
    {
      'name': 'flutter_secure_storage',
      'version': '^10.3.1',
      'license': 'BSD-3-Clause',
    },
    {'name': 'shared_preferences', 'version': '^2.3.0', 'license': 'BSD-3-Clause'},
    {'name': 'pointycastle', 'version': '^4.0.0', 'license': 'MIT'},
    {'name': 'crypto', 'version': '^3.0.3', 'license': 'BSD-3-Clause'},
    {'name': 'freerasp', 'version': '^8.0.0', 'license': 'Apache-2.0'},
    {
      'name': 'file_picker',
      'version': '^12.0.0-beta.7',
      'license': 'BSD-3-Clause',
    },
    {'name': 'archive', 'version': '^4.0.9', 'license': 'BSD-3-Clause'},
    {'name': 'qr_flutter', 'version': '^4.1.0', 'license': 'MIT'},
    {'name': 'mobile_scanner', 'version': '^7.0.0', 'license': 'BSD-3-Clause'},
    {'name': 'intl', 'version': '^0.20.2', 'license': 'BSD-3-Clause'},
    {'name': 'url_launcher', 'version': '^6.3.0', 'license': 'BSD-3-Clause'},
    {'name': 'http', 'version': '^1.2.0', 'license': 'BSD-3-Clause'},
    {
      'name': 'package_info_plus',
      'version': '^10.0.0',
      'license': 'BSD-3-Clause',
    },
    {
      'name': 'device_info_plus',
      'version': '^13.0.0',
      'license': 'BSD-3-Clause',
    },
    {
      'name': 'permission_handler',
      'version': '^12.0.0',
      'license': 'BSD-3-Clause',
    },
    {
      'name': 'flutter_local_notifications',
      'version': '^22.0.0',
      'license': 'BSD-3-Clause',
    },
    {'name': 'pdf', 'version': '^3.10.8', 'license': 'MIT'},
    {'name': 'printing', 'version': '^5.15.0', 'license': 'BSD-3-Clause'},
    {'name': 'cupertino_icons', 'version': '^1.0.8', 'license': 'MIT'},
    {'name': 'collection', 'version': '^1.18.0', 'license': 'BSD-3-Clause'},
    {'name': 'wiredash', 'version': '^2.6.1', 'license': 'MIT'},
    {'name': 'flutter_dotenv', 'version': '^5.1.0', 'license': 'MIT'},
    {'name': 'image_picker', 'version': '^1.2.2', 'license': 'BSD-3-Clause'},
    {'name': 'path_provider', 'version': '^2.1.0', 'license': 'BSD-3-Clause'},
    {'name': 'image', 'version': '^4.9.0', 'license': 'BSD-3-Clause'},
    {'name': 'open_filex', 'version': '^4.5.0', 'license': 'MIT'},
    {'name': 'share_plus', 'version': '^13.2.0', 'license': 'BSD-3-Clause'},
    {'name': 'state_notifier', 'version': '^1.0.0', 'license': 'MIT'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Informazioni e Licenze'),
        backgroundColor: const Color(0xFF174A7E),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final info = snapshot.data;
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
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
                            color: const Color(0xFF174A7E),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.menu_book_rounded,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CatechHub',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF174A7E),
                                ),
                              ),
                              Text(
                                info != null
                                    ? 'Versione ${info.version} (build ${info.buildNumber})'
                                    : 'Caricamento...',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'CatechHub è un\'app offline-first per la gestione dei '
                      'registri di catechismo, pensata da un catechista per '
                      'semplificare la gestione di presenze, documenti e '
                      'comunicazioni con le famiglie.',
                      style: TextStyle(fontSize: 14, height: 1.5),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text(
            'Licenza dell\'app',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  licenseText,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Dipendenze runtime',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: dependencies.map((dependency) {
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(
                    dependency['name']!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Versione: ${dependency['version']}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      dependency['license']!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF174A7E),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Nota di conformità',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Questo elenco riporta le licenze principali delle dipendenze usate. '
            'Verifica sempre la licenza specifica dei pacchetti su pub.dev o sul repository ufficiale prima di riutilizzare o distribuire il codice. '
            'Nel contesto non commerciale e open source, rispetta i termini di ciascuna licenza e conserva gli avvisi di copyright.',
            style: TextStyle(fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }
}
