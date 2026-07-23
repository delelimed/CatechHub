import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
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

class _UpdatePageState extends ConsumerState<UpdatePage>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _releaseInfo;
  bool _isLoading = true;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  String? _errorMessage;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _checkForUpdates();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
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
          'https://api.github.com/repos/delelimed/CatechHub/releases/latest',
        ),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final latestVersion = (data['tag_name'] as String).replaceAll('v', '');

        if (UpdateService.isVersionNewerStatic(currentVersion, latestVersion)) {
          final assets = data['assets'] as List<dynamic>;
          String? apkUrl;
          String? apkDigest;

          for (final asset in assets) {
            if (asset['name'] is String &&
                (asset['name'] as String).endsWith('.apk')) {
              apkUrl = asset['url'] as String? ?? asset['browser_download_url'] as String;
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
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Nuova versione $latestVersion disponibile!'),
                backgroundColor: const Color(0xFF174A7E),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            );
          }
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
      ).showSnackBar(SnackBar(content: const Text('URL APK non disponibile')));
      return;
    }

    if (!await Permission.requestInstallPackages.isGranted) {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permesso di installazione negato')),
        );
        return;
      }
    }

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

    try {
      final path = '${directory.path}/catechhub_update.apk';
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }

      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(apkUrl));
        request.headers['Accept'] = 'application/octet-stream';
        final streamedResponse = await client.send(request).timeout(const Duration(seconds: 30));

        if (streamedResponse.statusCode != 200) {
          throw Exception('Download fallito (HTTP ${streamedResponse.statusCode})');
        }

        final contentLength = streamedResponse.contentLength ?? -1;
        var received = 0;
        final sink = file.openWrite();

        await for (final chunk in streamedResponse.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (contentLength > 0 && mounted) {
            setState(() {
              _downloadProgress = received / contentLength;
            });
          }
        }

        await sink.close();
        client.close();

        if (!await file.exists() || await file.length() == 0) {
          throw Exception('File scaricato vuoto o non valido');
        }

        if (apkDigest != null && apkDigest.startsWith('sha256:')) {
          final bytes = await file.readAsBytes();
          final expectedDigest = apkDigest.substring('sha256:'.length);
          final actualDigest = sha256.convert(bytes).toString();
          if (actualDigest != expectedDigest) {
            await file.delete();
            throw Exception('Verifica integrita APK fallita');
          }
        }

        final raf = await file.open(mode: FileMode.read);
        final header = await raf.read(4);
        await raf.close();
        if (header.length < 4 || header[0] != 0x50 || header[1] != 0x4B) {
          await file.delete();
          throw Exception('File APK non valido (formato corrotto)');
        }
      } finally {
        client.close();
      }

      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
      });

      try {
        await UpdateService.installApk(path);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Errore installazione: $e')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isDownloading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore download: $e')),
        );
      }
    } finally {
      await UpdateService.cleanupOldApks();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Aggiornamenti',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) return _LoadingSkeleton();

    if (_errorMessage != null) {
      final isLatest = _errorMessage!.startsWith("Hai già l'ultima versione");
      return _StatusCard(
        message: _errorMessage!,
        isLatest: isLatest,
        onRetry: isLatest ? null : _checkForUpdates,
      );
    }

    if (_releaseInfo == null) {
      return _StatusCard(
        message: 'Nessun aggiornamento disponibile',
        isLatest: true,
      );
    }

    return Column(
      children: [
        _LogoHeader(),
        const SizedBox(height: 24),
        _UpdateHeroCard(
          currentVersion: _releaseInfo!['currentVersion'],
          latestVersion: _releaseInfo!['version'],
          publishedAt: _releaseInfo!['published_at'],
        ),
        const SizedBox(height: 20),
        _ChangelogCard(body: _releaseInfo!['body']),
        const SizedBox(height: 24),
        if (_isDownloading)
          _DownloadProgressCard(progress: _downloadProgress)
        else
          _ActionButtons(
            onDownload: _downloadAndInstall,
            githubUrl: _releaseInfo!['html_url'],
          ),
      ],
    );
  }
}

// =========================
// LOGO HEADER
// =========================
class _LogoHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF174A7E), Color(0xFF2368B1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF174A7E).withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/images/logo.png',
              height: 64,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.system_update_rounded,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Aggiornamenti',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Mantieni CatechHub sempre aggiornato',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =========================
// LOADING SKELETON
// =========================
class _LoadingSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LogoHeader(),
        const SizedBox(height: 24),
        _ShimmerCard(height: 180),
        const SizedBox(height: 16),
        _ShimmerCard(height: 260),
      ],
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  final double height;
  const _ShimmerCard({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: CircularProgressIndicator(color: Colors.grey.shade400),
      ),
    );
  }
}

// =========================
// STATUS CARD (latest / error)
// =========================
class _StatusCard extends StatelessWidget {
  final String message;
  final bool isLatest;
  final VoidCallback? onRetry;

  const _StatusCard({
    required this.message,
    required this.isLatest,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LogoHeader(),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: isLatest
                        ? [const Color(0xFF4CAF50), const Color(0xFF66BB6A)]
                        : [Colors.red.shade400, Colors.red.shade300],
                  ),
                ),
                child: Icon(
                  isLatest ? Icons.check_rounded : Icons.error_outline_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isLatest ? 'Tutto a posto!' : 'Qualcosa è andato storto',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF174A7E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF174A7E),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text(
                      'Riprova',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// =========================
// UPDATE HERO CARD
// =========================
class _UpdateHeroCard extends StatelessWidget {
  final String currentVersion;
  final String latestVersion;
  final String publishedAt;

  const _UpdateHeroCard({
    required this.currentVersion,
    required this.latestVersion,
    required this.publishedAt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF174A7E),
            const Color(0xFF2E5A8F),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF174A7E).withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.rocket_launch_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Nuova versione disponibile!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _VersionBadge(
                  label: 'Versione attuale',
                  version: currentVersion,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              Expanded(
                child: _VersionBadge(
                  label: 'Nuova versione',
                  version: latestVersion,
                  highlighted: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 14, color: Colors.white.withValues(alpha: 0.6)),
              const SizedBox(width: 6),
              Text(
                'Pubblicata il ${_formatDate(publishedAt)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return dateString;
    }
  }
}

class _VersionBadge extends StatelessWidget {
  final String label;
  final String version;
  final bool highlighted;

  const _VersionBadge({
    required this.label,
    required this.version,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: highlighted
            ? Colors.white.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            version,
            style: TextStyle(
              color: highlighted ? Colors.white : Colors.white.withValues(alpha: 0.7),
              fontSize: 22,
              fontWeight: highlighted ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// =========================
// CHANGELOG CARD
// =========================
class _ChangelogCard extends StatelessWidget {
  final String body;

  const _ChangelogCard({required this.body});

  @override
  Widget build(BuildContext context) {
    final sections = _parseChangelog(body);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF174A7E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Color(0xFF174A7E),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Novità di questa versione',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF174A7E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (sections.isEmpty)
            Text(
              body.isNotEmpty ? body : 'Nessuna descrizione disponibile.',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
                height: 1.5,
              ),
            )
          else
            ...sections.map((section) => _ChangelogSection(section: section)),
        ],
      ),
    );
  }

  List<_ChangelogSectionData> _parseChangelog(String text) {
    if (text.isEmpty) return [];

    final sections = <_ChangelogSectionData>[];
    _ChangelogSectionData? currentSection;
    final lines = text.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (trimmed.startsWith('## ')) {
        if (currentSection != null) {
          sections.add(currentSection);
        }
        currentSection = _ChangelogSectionData(
          title: trimmed.replaceFirst('## ', ''),
          items: [],
        );
      } else if (trimmed.startsWith('### ')) {
        if (currentSection != null) {
          sections.add(currentSection);
        }
        currentSection = _ChangelogSectionData(
          title: trimmed.replaceFirst('### ', ''),
          items: [],
          isSub: true,
        );
      } else if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        currentSection?.items.add(trimmed.substring(2));
      } else {
        currentSection?.items.add(trimmed);
      }
    }

    if (currentSection != null) {
      sections.add(currentSection);
    }

    return sections;
  }
}

class _ChangelogSectionData {
  final String title;
  final List<String> items;
  final bool isSub;

  _ChangelogSectionData({
    required this.title,
    required this.items,
    this.isSub = false,
  });
}

class _ChangelogSection extends StatelessWidget {
  final _ChangelogSectionData section;

  const _ChangelogSection({required this.section});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _iconForSection(section.title),
                size: 16,
                color: const Color(0xFF174A7E),
              ),
              const SizedBox(width: 8),
              Text(
                section.title,
                style: TextStyle(
                  fontSize: section.isSub ? 14 : 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF174A7E),
                ),
              ),
            ],
          ),
          if (section.items.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...section.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(left: 24, bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '•',
                      style: TextStyle(
                        color: const Color(0xFF174A7E).withValues(alpha: 0.5),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _iconForSection(String title) {
    final t = title.toLowerCase();
    if (t.contains('nuov') || t.contains('aggiunt')) return Icons.add_circle_rounded;
    if (t.contains('miglior') || t.contains('ottimiz')) return Icons.trending_up_rounded;
    if (t.contains('bug') || t.contains('fix') || t.contains('correz')) return Icons.bug_report_rounded;
    if (t.contains('rimoss') || t.contains('elimin')) return Icons.remove_circle_rounded;
    if (t.contains('sicur') || t.contains('security')) return Icons.shield_rounded;
    return Icons.circle_rounded;
  }
}

// =========================
// DOWNLOAD PROGRESS CARD
// =========================
class _DownloadProgressCard extends StatelessWidget {
  final double progress;

  const _DownloadProgressCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF174A7E).withValues(alpha: 0.05),
            Colors.blue.shade50,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFF174A7E).withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 4,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF174A7E)),
                    ),
                    Text(
                      '${(progress * 100).toInt()}%',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF174A7E),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Download in corso...',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF174A7E),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF174A7E)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _statusText,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String get _statusText {
    if (progress < 0.3) return 'Connessione al server...';
    if (progress < 0.7) return 'Scaricamento dati in corso...';
    if (progress < 0.95) return 'Quasi finito...';
    if (progress < 1.0) return 'Verifica integrità file...';
    return 'Download completato!';
  }
}

// =========================
// ACTION BUTTONS
// =========================
class _ActionButtons extends StatelessWidget {
  final VoidCallback onDownload;
  final String githubUrl;

  const _ActionButtons({
    required this.onDownload,
    required this.githubUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onDownload,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF174A7E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              elevation: 4,
              shadowColor: const Color(0xFF174A7E).withValues(alpha: 0.3),
            ),
            icon: const Icon(Icons.download_rounded, size: 22),
            label: const Text(
              'Scarica e installa',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              final uri = Uri.parse(githubUrl);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF174A7E),
              side: const BorderSide(color: Color(0xFF174A7E), width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
            label: const Text(
              'Visualizza su GitHub',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
