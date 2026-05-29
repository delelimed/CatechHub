import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../shared/widgets/app_scaffold.dart';
import '../../core/services/update_service.dart';

class UpdatePage extends ConsumerStatefulWidget {
  const UpdatePage({super.key});

  @override
  ConsumerState<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends ConsumerState<UpdatePage> {
  Map<String, dynamic>? _releaseInfo;
  bool _isLoading = true;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse(
          'https://api.github.com/repos/CatechHub-dev/CatechHub/releases/latest',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final latestVersion = (data['tag_name'] as String).replaceAll('v', '');

        if (UpdateService.isVersionNewerStatic(currentVersion, latestVersion)) {
          // Ottieni l'URL dell'APK
          final assets = data['assets'] as List<dynamic>;
          String? apkUrl;
          String? apkDigest;

          for (final asset in assets) {
            if (asset['name'] is String &&
                (asset['name'] as String).endsWith('.apk')) {
              apkUrl = asset['browser_download_url'] as String;
              apkDigest = asset['digest'] as String?;
              break;
            }
          }

          setState(() {
            _releaseInfo = {
              'version': latestVersion,
              'currentVersion': currentVersion,
              'name': data['name'] as String? ?? '',
              'body': data['body'] as String? ?? '',
              'html_url': data['html_url'] as String? ?? '',
              'apk_url': apkUrl,
              'apk_digest': apkDigest,
              'published_at': data['published_at'] as String? ?? '',
            };
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = 'Hai già l\'ultima versione ($currentVersion)';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage =
              'Impossibile controllare gli aggiornamenti (errore ${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Errore durante il controllo: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadAndInstall() async {
    final apkUrl = _releaseInfo?['apk_url'] as String?;
    final apkDigest = _releaseInfo?['apk_digest'] as String?;
    if (apkUrl == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('URL APK non disponibile')));
      return;
    }
    if (apkDigest == null || !apkDigest.startsWith('sha256:')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossibile verificare la firma del download'),
        ),
      );
      return;
    }

    // Richiedi permesso di installazione app
    if (!await Permission.requestInstallPackages.isGranted) {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permesso di installazione negato')),
        );
        return;
      }
    }

    // Scriviamo in una directory app-specific che non richiede permessi di storage
    // (evita problemi con Scoped Storage su Android 11+).
    Directory? directory;
    try {
      directory = await getExternalStorageDirectory();
    } catch (_) {
      directory = null;
    }
    if (directory == null) {
      directory = await getApplicationDocumentsDirectory();
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    File? downloadedFile;
    try {
      final response = await http.get(Uri.parse(apkUrl));

      if (response.statusCode != 200) {
        throw Exception('Download fallito: ${response.statusCode}');
      }

      final bytes = response.bodyBytes;
      final expectedDigest = apkDigest.substring('sha256:'.length);
      final actualDigest = sha256.convert(bytes).toString();
      if (actualDigest != expectedDigest) {
        throw Exception('Verifica integrita APK fallita');
      }

      // Simula progresso di download
      for (int i = 0; i <= 100; i += 10) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          setState(() {
            _downloadProgress = i / 100;
          });
        }
      }

      // Salva il file
      final path = '${directory.path}/catechhub_update.apk';
      downloadedFile = File(path);
      if (await downloadedFile.exists()) {
        await downloadedFile.delete();
      }
      await downloadedFile.writeAsBytes(bytes);

      setState(() {
        _isDownloading = false;
      });

      // Apri il file per l'installazione
      final result = await OpenFilex.open(path);

      if (result.type == ResultType.error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Errore nell\'apertura del file')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Errore download: $e')));
      }
    } finally {
      if (downloadedFile != null && await downloadedFile.exists()) {
        try {
          await downloadedFile.delete();
        } catch (_) {
          // Ignora se non è possibile cancellare il file.
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Aggiornamenti',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF174A7E)),
      );
    }

    if (_errorMessage != null) {
      return _ErrorCard(message: _errorMessage!, onRetry: _checkForUpdates);
    }

    if (_releaseInfo == null) {
      return const _ErrorCard(message: 'Nessun aggiornamento disponibile');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UpdateInfoCard(
          currentVersion: _releaseInfo!['currentVersion'],
          latestVersion: _releaseInfo!['version'],
          publishedAt: _releaseInfo!['published_at'],
        ),
        const SizedBox(height: 16),
        _ChangelogCard(
          title: _releaseInfo!['name'],
          body: _releaseInfo!['body'],
        ),
        const SizedBox(height: 20),
        if (_isDownloading)
          _DownloadingCard(progress: _downloadProgress)
        else
          _DownloadButton(onTap: _downloadAndInstall),
      ],
    );
  }
}

class _UpdateInfoCard extends StatelessWidget {
  final String currentVersion;
  final String latestVersion;
  final String publishedAt;

  const _UpdateInfoCard({
    required this.currentVersion,
    required this.latestVersion,
    required this.publishedAt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF174A7E), Color(0xFF2E5A8F)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.system_update_rounded,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(width: 12),
              const Text(
                'Nuovo aggiornamento!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _VersionInfo(
                  label: 'Versione attuale',
                  version: currentVersion,
                ),
              ),
              Container(width: 1, height: 40, color: Colors.white30),
              Expanded(
                child: _VersionInfo(
                  label: 'Nuova versione',
                  version: latestVersion,
                  isHighlighted: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Pubblicata: ${_formatDate(publishedAt)}',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }
}

class _VersionInfo extends StatelessWidget {
  final String label;
  final String version;
  final bool isHighlighted;

  const _VersionInfo({
    required this.label,
    required this.version,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          version,
          style: TextStyle(
            color: isHighlighted ? Colors.white : Colors.white70,
            fontSize: 18,
            fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _ChangelogCard extends StatelessWidget {
  final String title;
  final String body;

  const _ChangelogCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.description_rounded,
                color: const Color(0xFF174A7E),
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                title.isNotEmpty ? title : 'Note di rilascio',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF174A7E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            body.isNotEmpty ? body : 'Nessuna descrizione disponibile.',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DownloadingCard extends StatelessWidget {
  final double progress;

  const _DownloadingCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2,
                  color: const Color(0xFF174A7E),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: LinearProgressIndicator(
                  value: progress,
                  color: const Color(0xFF174A7E),
                  backgroundColor: Colors.blue.shade200,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                '${(progress * 100).toInt()}%',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF174A7E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Download in corso...',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  final VoidCallback onTap;

  const _DownloadButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF174A7E),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.download_rounded),
        label: const Text(
          'Scarica e installa',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ErrorCard({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: Colors.red.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.red.shade800, fontSize: 14),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Riprova'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
